# Repository UMB provider design

## Decision

The repository will use two cooperating drivers:

1. a repository-owned `HIMEM.SYS` is the single public XMS manager and owns
   extended-memory handles, the HMA, and A20;
2. `EMM386.SYS` remains the 386 paging and EMS owner, obtains its backing store
   from `HIMEM.SYS`, and registers safe UMA ranges and their permanently mapped
   backing pages with `HIMEM.SYS` through a private, versioned inter-driver
   call.

Applications and DOS see only the standard XMS discovery/control-entry and XMS
function interfaces. The private call is strictly between the two repository
drivers; it is not an alternative DOS UMB API.

This avoids three unsafe designs:

- two independent owners allocating the same extended memory;
- EMM386 advertising itself as an XMS manager while implementing only UMB
  calls;
- DOS depending on this EMM386's internal tables instead of the XMS contract.

The drivers may be delivered incrementally, but `HIMEM.SYS` must not report an
XMS version until every mandatory function for that reported version has exact
success and error behavior. Until then, provider tests use the existing
test-only XMS driver and production boot remains low-only.

## Existing EMM386 ownership model

The present source already contains the correct raw ingredients but does not
turn them into UMBs:

- `PPAGE.ASM` builds `mappable_segs`, excludes conventional RAM, video RAM,
  system ROM, discovered option ROMs, and command-line `X=` ranges, then picks
  an EMS page frame.
- `EMMINIT.ASM` converts the selected 16 KiB physical windows into
  `_mappable_pages`, `_page_frame_base`, and `_EMM_MPIndex`.
- `ALLOCMEM.ASM` currently claims extended memory by reducing the INT 15h
  report. This must become an XMS allocation when repository `HIMEM.SYS` is
  present; otherwise HIMEM and EMM386 would have overlapping ownership.
- `_pft386` identifies the backing physical page for each EMS logical page,
  while `_emm_free`, `_free_top`, and `_free_count` own the EMS free-page pool.

A mappable UMA window is not automatically a UMB. It becomes a UMB only after
EMM386 removes enough backing pages from the EMS free pool, permanently maps
them into the window, and successfully registers the resulting extent with
HIMEM. Page-frame windows are never candidates. An advertised UMB mapping must
not subsequently participate in EMS map operations.

## Public XMS boundary

`HIMEM.SYS` owns `INT 2Fh/4300h` and `4310h` and exposes one far-call control
entry. The initial production contract includes the complete function set for
the selected XMS version, not just the calls DOS happens to use. In particular:

- version and free-memory queries;
- HMA request/release;
- global and local A20 enable/disable and query;
- extended-memory allocate/free/move/lock/unlock/handle-information/reallocate;
- UMB request/release/reallocate (`10h`, `11h`, and `12h`).

The production target is XMS 2.00. A clean-room probe of the genuine reference
stacks found DOS 5 HIMEM 2.78 reporting XMS 2.00 and DOS 6.22 HIMEM 3.10
reporting XMS 3.00. The UMB/HMA contract needed here is fully representable by
2.00, and avoiding 3.00 means the driver does not make a false claim about the
32-bit-size functions and limits. DOS itself continues to depend only on
discovery plus UMB and HMA calls.

For XMS `10h`, HIMEM selects a registered free extent according to the XMS
specification, splits it when necessary, and returns the exact largest
available size and error code on failure. `11h` validates an exact allocation
start before release. Function `12h` returns error `80h`: both genuine DOS 5
and 6.22 reference stacks do so, despite the latter reporting XMS 3.00.
Registration is transactional: EMM386 submits a complete normalized extent
set, HIMEM either accepts all of it or none, and neither side exposes pages
until both ownership tables agree.

## Private HIMEM–EMM386 protocol

The private entry is discovered by a repository-specific multiplex identifier
that is documented as internal and collision-checked at installation. Every
request includes a structure size and protocol version. The first protocol
revision needs these operations:

- query capabilities and obtain the installed HIMEM instance identity;
- allocate an aligned, physically addressable backing block for EMM386;
- atomically register normalized UMB extents with their backing-page runs;
- unregister the entire map during initialization rollback;
- query committed extents for diagnostics and tests.

There is deliberately no run-time single-page handoff. Once committed, HIMEM
owns UMB allocation state and EMM386 owns stable translations until shutdown or
warm reboot. A generation cookie prevents either driver from accepting stale
state after a failed initialization or reinstallation.

## UMA construction

EMM386 derives candidates from the post-parser, post-ROM-scan
`mappable_segs` map in 16 KiB units:

1. remove the selected EMS page frame and every explicit exclusion;
2. coalesce adjacent candidate pages, without crossing a nonmappable page;
3. reserve one EMS backing page per candidate page before changing a mapping;
4. program and verify identity-stable linear mappings for the complete run;
5. submit all runs to HIMEM in ascending segment order;
6. on any failure, restore page tables and return every reserved page to the
   EMS pool in reverse order;
7. expose the committed map only after HIMEM acknowledges the whole batch.

The DOS-side XMS acquisition remains separately transactional, so a later DOS
failure releases its XMS UMB allocations without destroying the provider's
underlying mappings.

`RAM` enables UMB construction. `NOEMS` suppresses the EMS page frame but still
permits paging-backed UMBs. `X=` always excludes a range. `I=` may include a
range only after the existing safety checks and reference behavior are made
explicit; it cannot override video or system ROM safety. Exact spelling,
defaults, diagnostics, and precedence remain Phase 0 reference gates.

## Concurrency and lifecycle invariants

- XMS calls and the private registration call serialize state changes with
  interrupts disabled only for the bounded table update; page copying and
  hardware waits occur outside that critical section.
- EMS and UMB ownership tables are disjoint and checked in both debug probes
  and production initialization.
- UMB physical translations are invariant across EMS mapping, alternate map
  register, DMA, and task-switch paths.
- Failure before device installation restores the prior INT 2Fh/INT 15h/A20
  state and releases all memory.
- Warm reboot restores a usable A20 state and cannot leave an old multiplex or
  XMS entry reachable.
- A third-party conforming XMS provider remains supported by DOS. Repository
  EMM386 may decline its UMB feature when the private peer protocol is absent;
  it must not corrupt or replace the third-party manager.

## Implementation and verification order

1. Extend the independent XMS conformance probe and freeze DOS 5/6.22 results
   for every XMS 2.00 success and error path the repository will expose.
2. Implement and unit-test the XMS handle allocator, move validation, and A20
   nesting logic without advertising the manager.
3. Install the public entry only when the selected-version conformance matrix
   passes, then verify third-party XMS clients and DOS's existing acquisition.
4. Change EMM386 backing allocation from direct INT 15h ownership to an XMS
   handle when the repository HIMEM peer is present.
5. Implement candidate coalescing, EMS-page reservation, stable mapping, and
   atomic registration; add rollback fault injection at every transition.
6. Test `RAM`, `NOEMS`, page-frame selection, `I=`, and `X=` against genuine
   reference configurations.
7. Stress EMS allocations and mappings while repeatedly writing and checking
   every UMB page, including warm reboot and failed initialization.

The Phase 3 exit gate is satisfied only when the production drivers—not the
test fixture—boot together, expose multiple safe extents through XMS, pass the
direct XMS and DOS allocator probes, and retain full EMS behavior concurrently.

## Current implementation status

The repository now contains an original clean-room HIMEM driver that exposes
the XMS 2.00 entry point, HMA ownership, A20 control, extended-memory handles,
moves, locking, resizing, and the optional XMS UMB request/release calls. Its
private transaction accepts or rejects a complete normalized UMB map, and
refuses unregistration while any advertised block remains allocated.

EMM386 now obtains its backing pool as a locked XMS allocation when the
repository HIMEM peer is present. After ROM and page-frame discovery, it takes
safe 16 KiB UMA windows out of the EMS mapping pool, reserves distinct backing
pages, installs permanent mappings, coalesces the resulting extents, and
registers the complete map atomically. Initialization failure reverses the
page mappings, returns every EMS page, unregisters the map, and releases the
XMS handle.

The combined QEMU test boots both production drivers with `DOS=UMB`, allocates
from every firmware-safe upper region exposed on that machine, and exercises
EMS in the same boot. A local QEMU map exposes two separated regions; the CI
firmware map exposes one. Deterministic synthetic coverage independently proves
normalization and allocation across multiple discontiguous extents.
This establishes the basic ownership split but does not close Phase 3:
remaining XMS edge cases and broader fault injection remain required. A
monitor-driven system-reset test now proves that HMA ownership, UMB allocation,
EMS isolation, and EMS allocation/mapping all work on two consecutive boots.
Physical A20 alias detection, fast-gate/BIOS/8042 backends, one
registration-rejection rollback, and live-UMB data stability during EMS
remapping are now covered. HIMEM is still omitted from published images until
the remaining gates pass.
