# Upper Memory Block implementation plan

## Objective

Add Upper Memory Block (UMB) support to this MS-DOS 4 source tree with the
observable behavior of MS-DOS 6.22. The DOS-facing API is the DOS 5 interface
retained by 6.22: existing applications, drivers, and memory managers must see
the same calls, state transitions, allocation policies, fallbacks, and errors.

This is a compatibility implementation, not a new memory API. Existing DOS 4
behavior must remain unchanged when UMB support is unavailable or disabled.

## Compatibility boundary

### Required kernel API

Complete `INT 21h/AH=58h` as implemented by MS-DOS 5 through 6.22:

| Call | Input | Successful result | Required behavior |
| --- | --- | --- | --- |
| `AX=5800h` | none | `CF=0`, `AX=strategy` | Return the complete current strategy value. |
| `AX=5801h` | `BX=strategy`, with `BH=0` | `CF=0` | Validate and set the global allocation strategy. |
| `AX=5802h` | none | `CF=0`, `AL=0` or `1` | Return whether the UMB arena is linked into the DOS arena chain. |
| `AX=5803h` | `BX=0` or `1` | `CF=0` | Unlink or link the UMB arena without losing its contents. |

Invalid subfunctions, strategy values, and link values return `CF=1`, `AX=1`
(`ERROR_INVALID_FUNCTION`) and leave all state unchanged.

The supported strategy values are:

| Value | Placement |
| --- | --- |
| `0000h` | Low memory, first fit |
| `0001h` | Low memory, best fit |
| `0002h` | Low memory, last fit |
| `0040h` | UMB only, first fit |
| `0041h` | UMB only, best fit |
| `0042h` | UMB only, last fit |
| `0080h` | UMB first, then low memory; first fit |
| `0081h` | UMB first, then low memory; best fit |
| `0082h` | UMB first, then low memory; last fit |

Setting a high-memory strategy does not implicitly link the UMB arena. Linking
the arena does not implicitly select a high-memory strategy. Both settings are
global DOS state, survive child process execution, and remain the caller's
responsibility to restore.

`INT 21h/AH=48h`, `49h`, and `4Ah` must operate on UMB MCBs exactly as on
conventional MCBs, including owner PSP, name, split/coalesce behavior, maximum
available size on allocation/resize failure, arena-corruption detection, and
process-termination cleanup. `EXEC` must honor the current strategy while
preserving its existing overlay and environment behavior.

### Required CONFIG.SYS behavior

Implement the 6.22-facing forms relevant to UMBs:

- `DOS=UMB`, `DOS=NOUMB`, `DOS=LOW`, and comma-separated combinations such as
  `DOS=HIGH,UMB` and `DOS=UMB,LOW`, case-insensitively;
- multiple `DOS=` lines with the same effective state rules as 6.22;
- `DEVICEHIGH=driver [arguments]`, with conventional-memory fallback when no
  suitable UMB is available or UMB management is disabled;
- the DOS 5 compatibility spelling
  `DEVICEHIGH SIZE=hexsize driver [arguments]`;
- the 6.22 region form
  `DEVICEHIGH [/L:region[,minsize][;region[,minsize]...]] [/S]=driver
  [arguments]`;
- `INSTALLHIGH=program [arguments]` if reference testing confirms it is a
  6.22-supported public directive and establishes its precise fallback and
  error behavior.

`DOS=UMB` must be silent when no UMB provider is available, matching 6.22.
`DEVICEHIGH` then behaves like `DEVICE`. `DOS=` is valid anywhere in CONFIG.SYS,
so SYSINIT's pass ordering must make its settings effective as 6.22 does; the
UMB provider itself still has to be installed before a driver can load high.

### Required command behavior

Add the COMMAND.COM internal commands `LOADHIGH` and `LH` with 6.22 behavior:

- plain `LOADHIGH program [arguments]` tries the largest suitable UMB and falls
  back to conventional memory;
- `/L:region[,minsize][;...]` restricts the regions exposed to the child;
- `/S` is accepted only with `/L` and applies only to regions with a minimum
  size;
- quoting, redirection, batch execution, `ERRORLEVEL`, Ctrl-C, environment
  ownership, and executable lookup remain consistent with normal execution;
- allocation strategy and link state are restored on every success and error
  exit.

Extend `MEM` to report conventional, upper, reserved, and total-under-1-MB
memory, the largest free UMB, module ownership, UMB region numbers, and free
regions through the applicable 6.22 switches (`/C`, `/D`, `/F`, and `/M`). This
is part of making UMB support observable and diagnosable, not an optional
presentation enhancement.

### UMB provider boundary

DOS must consume UMBs through the standard XMS discovery and service contract,
not a private EMM386-to-kernel entry point:

1. detect an XMS manager with `INT 2Fh/AX=4300h`;
2. obtain its control entry with `INT 2Fh/AX=4310h`;
3. request all available UMB extents through XMS function `10h`;
4. retain provider ownership while DOS represents the extents as MCB arenas;
5. release acquired extents with XMS function `11h` on rollback or when the
   boot-time acquisition cannot be completed safely;
6. support XMS function `12h` in the repository's provider if required for
   external 6.22 compatibility, although DOS need not depend on it internally.

The exact XMS error codes and largest-available-block results must follow the
XMS 3.0 specification. DOS must also work with a third-party conforming XMS/UMB
provider, which prevents the implementation from accidentally depending on
details of this repository's EMM386.

The current EMM386 predates this contract and exposes EMS 4.0 through `INT 67h`
but no XMS `INT 2Fh/43xxh` interface. Provider work therefore needs its own
design checkpoint. The preferred design is either:

- add a small, independently testable XMS manager/provider that owns A20,
  extended memory, HMA, and UMB services, then make EMM386 cooperate with it;
  or
- make EMM386 extend an already-installed XMS manager's UMB services in the
  standard manner, after the inter-driver protocol has been verified from
  specifications and black-box reference behavior.

EMM386 must identify safe UMA holes, exclude video RAM, option ROMs, system
ROM, EMS page-frame pages, explicitly excluded ranges, and its own resident
state. It must map backing RAM into each advertised range and keep those
mappings stable while DOS owns the UMBs. `RAM`, `NOEMS`, `I=`, `X=`, page-frame
selection, and unavailable-hardware fallbacks need 6.22-compatible semantics in
the portion exercised by UMB creation. Do not advertise an XMS version or
function set broader than the implementation actually supports.

## Current source baseline

The implementation should extend rather than replace these existing paths:

- `DOS/ALLOC.ASM` already implements first-, best-, and last-fit allocation and
  `5800h`/`5801h`, but accepts invalid values and scans a single arena;
- `DOS/MSCONST.ASM`, `DOS/STDDATA.ASM`, and `DOS/MS_TABLE.ASM` own allocator
  state and dispatch/error metadata;
- `DOS/MSINIT.ASM` creates the conventional arena;
- `BIOS/SYSINIT1.ASM`, `SYSINIT2.ASM`, and `SYSCONF.ASM` parse CONFIG.SYS,
  load drivers/programs, and allocate boot-time resident structures;
- `CMD/COMMAND` owns executable dispatch and is the correct home for `LH` and
  `LOADHIGH`;
- `CMD/MEM` is the user-visible arena diagnostic;
- `MEMM/MEMM` already provides EMS and 386 paging but not an XMS UMB-provider
  interface;
- `tests/emm386_probe.asm` and `tests/test_emm386_qemu.sh` provide an existing
  protected-mode/EMS test base;
- the INT 21, CONFIG.SYS, COMMAND, driver, process, and memory tests already
  provide places for focused UMB contracts.

Before coding, produce a symbol-and-call graph for these paths and record every
allocator entry that assumes one contiguous conventional arena. Audit direct
MCB traversal through the List of Lists as well as calls to `$ALLOC`, because
internal diagnostics and third-party tools observe arena layout directly.

## Arena design

Represent conventional memory and UMBs as two persistent arenas with explicit
heads and tails. Linking changes traversal visibility; it must not reconstruct,
move, free, or rename blocks.

The UMB arena must:

- represent discontiguous provider extents without exposing ROM/device holes as
  allocatable RAM;
- use system-owned MCBs for nonallocatable gaps where 6.22 does so;
- preserve correct `M`/`Z` signatures in both linked and unlinked states;
- never permit coalescing across a provider extent or reserved-hole boundary;
- preserve allocated UMBs across unlink/relink operations;
- keep conventional-only scans from crossing into UMBs even while linked;
- allow upper-only and upper-then-low scans to apply first/best/last fit within
  the intended domains;
- keep failed allocations' `BX` largest-block result compatible with the
  selected domain and fallback policy;
- remain valid when there are zero UMBs, one UMB, several adjacent UMBs, and
  fragmented UMBs.

Do not encode "upper" solely as a segment threshold. Keep arena identity in
kernel state so unusual machines and synthetic tests cannot confuse placement,
linking, or coalescing.

## Loading design

High-loading code should use a scoped allocator-state transaction:

1. save strategy and UMB link state;
2. link UMBs if available;
3. select upper-only or upper-then-low strategy according to the command;
4. constrain visible regions when `/L` is present;
5. load the driver, program, environment, and any requested auxiliary blocks;
6. apply `/S` shrinking rules only after the reference behavior is established;
7. restore region visibility, link state, and strategy on every path.

Share this state-management primitive between SYSINIT and COMMAND rather than
duplicating fragile save/restore sequences. Device initialization remains the
existing two-phase DOS driver protocol. A failed high attempt must leave no MCB,
device-chain, interrupt-vector, or provider allocation residue before falling
back low.

Region numbering is observable through `DEVICEHIGH /L`, `LOADHIGH /L`, and
`MEM`. Establish the exact 6.22 numbering and gap rules with a controlled
reference machine before selecting an internal representation. Region filters
must affect allocations performed by the loaded child as well as its initial
image where 6.22 does so.

## Delivery phases

### Phase 0: reference oracle and design evidence

- Create legally independent probes that run unchanged on genuine MS-DOS 5.0
  and 6.22 and on this tree.
- Capture all `58xxh` register/flag/error results, including invalid inputs.
- Capture MCB layouts before and after link, unlink, allocation, resize, free,
  process exit, and failed calls.
- Exercise multiple UMB regions, fragmentation, allocation strategies, nested
  EXEC, TSR termination, and arena corruption.
- Capture CONFIG/COMMAND syntax, diagnostics, fallback, exit codes, region
  numbering, `/S`, and directive-order behavior.
- Store probe source and normalized assertions, not proprietary binaries or
  copied code, in this repository.
- Freeze the resulting compatibility matrix before implementation begins.

Exit criterion: every required observable behavior is either backed by a
reference result or explicitly marked as a compatibility uncertainty.

### Phase 1: allocator and `INT 21h/58xxh`

- Add validated strategy constants and separate domain from fit policy.
- Introduce persistent conventional and UMB arena descriptors.
- Generalize scan, split, coalesce, free-process, resize, and signature checks
  across arena boundaries.
- Implement `5802h` and `5803h`, including exact errors and idempotence.
- Preserve DOS 4 low-only behavior and default strategy.
- Add assembly probes for all API and MCB invariants before connecting a real
  provider; use a deterministic synthetic UMB map in the test boot path.

Exit criterion: the kernel passes the complete `58xxh` matrix and memory
lifecycle tests with synthetic UMBs, while every pre-UMB memory test remains
green.

### Phase 2: standard provider discovery and acquisition

- Add boot-time XMS discovery and control-entry handling.
- Request provider UMB extents transactionally and build the UMB arena.
- Handle absent, partial, malformed, overlapping, or failing providers without
  destabilizing conventional memory.
- Add a tiny test-only XMS provider with configurable maps and failures.
- Verify interoperability against at least one independent conforming provider
  whose redistribution is not required for the tests.

Exit criterion: `DOS=UMB` works through the XMS boundary and silently remains
low-only when no valid provider exists.

### Phase 3: repository UMB provider

- Complete the provider design checkpoint described above.
- Implement safe UMA discovery, exclusions, backing-page ownership, stable
  mapping, and XMS UMB request/release behavior.
- Reconcile UMB pages with EMS page-frame and logical-page allocation.
- Extend EMM386 configuration only where required by the 6.22 compatibility
  matrix; retain existing working EMS behavior.
- Add direct XMS probes plus combined EMS/UMB stress tests.

Exit criterion: the repository boots under QEMU with its own provider, exposes
multiple safe UMBs, passes XMS and EMS probes concurrently, and survives warm
reboot and repeated allocation/free cycles.

### Phase 4: CONFIG.SYS and device/program high loading

- Add `DOS=` parsing and boot sequencing.
- Add `DEVICEHIGH`, legacy `SIZE=`, region `/L`, and `/S` behavior.
- Add `INSTALLHIGH` if confirmed by Phase 0.
- Add COMMAND `LOADHIGH` and `LH` using the shared scoped state primitive.
- Test fallback, rollback, ordering, driver chains, environments, TSRs,
  redirection, Ctrl-C, and nested execution.

Exit criterion: reference configuration files and batch files produce matching
placement and failure behavior on 6.22 and this tree.

### Phase 5: diagnostics and compatibility hardening

- Extend `MEM` with the required 6.22 UMB views and region numbering.
- Add long-running fragmentation/coalescing and repeated link-state stress.
- Test common third-party probes and loaders without bundling them.
- Test 8086/286/no-XMS/no-UMB behavior, 386 EMS-only behavior, and 386 UMB
  behavior.
- Measure conventional-memory savings and ensure enabling UMB support does not
  consume more low memory than the accepted budget.
- Document supported configuration, fallbacks, limitations, and API contracts
  in the lean public documentation after behavior is stable.

Exit criterion: all new compatibility tests and the complete existing suite pass
locally and in CI, with no unaccounted source or generated-file drift.

## Test matrix

### API and allocator

- every valid and invalid `5800h`-`5803h` input, flags, preserved registers,
  return values, and global-state transitions;
- all nine strategies with exact-fit, split, fragmented, and exhausted low/UMB
  pools;
- UMB-only failure versus upper-then-low fallback;
- `48h` largest-block reporting, `49h`, and every grow/shrink case of `4Ah`;
- unlink with live allocations, relink, process exit cleanup, TSR ownership,
  parent/child interaction, and corrupt signatures;
- repeated operations and randomized model-based arena sequences.

### Provider

- no XMS manager; XMS without UMB functions; no free UMB; one and multiple
  extents; provider partial failure; invalid or overlapping extents;
- ROM/video/page-frame/excluded-area safety;
- XMS functions `10h`, `11h`, and, if exposed, `12h`, including all errors;
- simultaneous EMS mapping and UMB access, DMA-sensitive paths, warm reboot,
  and provider activation modes.

### User-facing behavior

- every `DOS=` spelling, textual position, repetition, whitespace, case,
  invalid token, and absent-provider case;
- `DEVICEHIGH`, fallback to `DEVICE`, initialization failure rollback, multiple
  drivers, character/block drivers, and exact resident size;
- `LOADHIGH`/`LH` COM, EXE, batch, TSR, child allocations, environment,
  redirection, Ctrl-C, and exit status;
- `/L`, multiple regions, region 0, minimum sizes, `/S`, malformed syntax, and
  fragmented regions;
- `MEM` summary, classify, debug, free, and module views against known MCB maps.

### Regression and CI

- keep every existing low-memory, EXEC, CONFIG.SYS, device, EMM386, and INT 21h
  test enabled;
- run fast API/model probes under kvikdos where its memory model is sufficient;
- run paging, boot, device, and end-to-end placement tests under QEMU/KVM;
- add strict coverage manifests for the new API calls, directives, command
  switches, provider functions, and error paths;
- keep test images and serial channels isolated so the matrix remains parallel.

## Licensing and provenance

Implementation may be original work based on public interface documentation and
black-box observations, or reuse code only after an explicit per-file license
review. Pre-approved "MIT-like" licenses should be limited to MIT, BSD-2-Clause,
BSD-3-Clause, ISC, and zlib unless the owner chooses a different allowlist.

Do not copy from GPL, LGPL, AGPL, MPL, CDDL, proprietary, source-available,
decompiled, leaked, or license-unclear implementations. Documentation may define
behavior but does not authorize copying its implementation or expressive text.
For every reused contribution, record project URL, exact revision, file paths,
license/SPDX identifier, copyright notice, local modifications, and the review
decision. Preserve all required notices. A clean-room implementation remains the
default because the present Microsoft MS-DOS 4 sources are MIT-licensed while
most readily available later DOS and memory-manager sources are not permissive.

## Compatibility evidence

The initial contract is based on:

- the Microsoft *MS-DOS 5.0 Programmer's Reference*, especially the UMB
  overview and `INT 21h/58xxh` calls:
  <https://ftpmirror.your.org/pub/misc/bitsavers/pdf/microsoft/msdos_5/Microsoft_-_MS-DOS_Programmers_Reference_1991.pdf>;
- Microsoft MS-DOS 6.22 Help for
  [DOS](https://www.infania.net/misc/dos622help/dos.html),
  [DEVICEHIGH](https://www.infania.net/misc/dos622help/devicehigh.html),
  [LOADHIGH](https://www.infania.net/misc/dos622help/loadhigh.html),
  [MEM](https://www.infania.net/misc/dos622help/mem.html),
  [HIMEM.SYS](https://www.infania.net/misc/dos622help/himem.sys.html), and
  [EMM386.EXE](https://www.infania.net/misc/dos622help/emm386.exe.html);
- Microsoft's XMS 3.0 specification:
  <https://ps-2.kev009.com/basil.holloway/ALL%20PDF/Microsoft_XMS_3%5B1%5D.0_Specification.pdf>;
- Ralf Brown's Interrupt List as a secondary cross-check for strategy values
  and undocumented edge cases:
  <https://fd.lod.bz/rbil/interrup/dos_kernel/2158.html>.

Reference-machine probes take precedence where documentation is ambiguous.
Before implementation, cite the exact reference result beside each ambiguity in
the compatibility matrix.

## Decisions required before implementation

1. **Version reporting.** Recommended: retain the product's DOS 4.0 identity but
   implement the later calls, and document that applications which gate UMB use
   on `INT 21h/AH=30h >= 5` need an explicit compatibility mechanism. Alternative:
   report 5.0 or 6.22 globally, which broadens the compatibility promise far
   beyond UMBs and is therefore not recommended.
2. **HMA scope.** Recommended: make UMBs the first deliverable and treat
   `DOS=HIGH` plus full HIMEM/HMA support as a separately gated phase. During the
   UMB deliverable, parse `HIGH` compatibly and follow the 6.22 low-memory
   fallback when HMA is unavailable. If the goal is specifically the canonical
   `DOS=HIGH,UMB` outcome and its conventional-memory savings, HMA must be in
   scope from the start.
3. **6.22 loader breadth.** Recommended: include `/L`, `/S`, legacy `SIZE=`,
   `INSTALLHIGH` if confirmed, and the relevant `MEM` views. Omitting them gives
   DOS 5-like basic UMB support, not the requested 6.22 user-facing contract.
4. **Permissive-license allowlist.** Recommended: approve MIT, BSD-2-Clause,
   BSD-3-Clause, ISC, and zlib; require an explicit decision for any other
   license.
5. **Hardware acceptance target.** Recommended: require correct fallback on
   8086/286, functional UMBs on 386+ under QEMU, and provider interoperability
   on at least one real or cycle-accurate PC-compatible environment before the
   feature is called complete.
6. **Reference media.** Genuine MS-DOS 5.0/6.22 binaries are useful only as
   external black-box oracles. Confirm that the test operator may use locally
   owned media; no proprietary binary or derived binary data will be committed.
