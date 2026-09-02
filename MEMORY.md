# DOS 6.22 memory model

This document records the durable HMA, UMB, XMS, and EMS constraints. Detailed
delivery history belongs in Git; current evidence belongs in the test manifests.

## Public behavior

The system reports DOS 6.22 consistently through `INT 21h/AH=30h`,
`AX=3306h`, system banners, and `COMMAND.COM VER`. It retains the `MSDOS5.0`
boot-sector OEM identifier used by retail MS-DOS 6.22. The existing
per-program fake-version hook affects the documented call but not the
true-version query.

The supported memory surface includes:

- allocation strategies `00h..02h`, `40h..42h`, and `80h..82h`;
- UMB link/query control through `INT 21h/58xxh`;
- `DOS=HIGH|LOW` and `DOS=UMB|NOUMB`;
- `DEVICEHIGH`, `INSTALLHIGH`, `LOADHIGH`/`LH`, and UMB-aware `MEM`;
- XMS 3.00 HMA, A20, extended-memory, and UMB functions, including the 32-bit
  free-memory, allocate, handle-information, and resize calls;
- EMM386 EMS-only default mode plus `RAM` and `NOEMS` UMB modes.

## Arena invariants

`src/DOS/ALLOC.ASM` owns allocation, resize, free, coalescing, and process cleanup.
`arena_head` remains the conventional arena head. `UmbArenaHead` identifies the
upper arena, `UmbLinkMcb` the conventional bridge, and `UmbLinked` only the
public link state—not whether UMB storage exists.

- Ordinary scans include UMBs only while the public chain is linked.
- Upper-only strategies never infer the arena from a segment threshold.
- Upper-then-low strategies retry conventional memory only after no upper block
  fits.
- Provider gaps are system-owned; allocation and coalescing cannot cross them.
- Process cleanup visits both arenas even when the public UMB link is off.
- Link changes validate the saved bridge and signatures before mutation.
- UMB acquisition and registration are transactional; any failure releases all
  acquired extents and exposes no partial arena.

SYSINIT alone uses the signed private `5804h` handoff to register the complete
validated map. Ordinary `5804h` calls retain the public invalid-function result.
Provider discovery, allocation, and release otherwise use standard XMS calls.

## HIMEM and EMM386 ownership

HIMEM owns the XMS entry point, HMA allocation, A20 nesting, extended-memory
handles, and the UMB allocation table. EMM386 obtains its backing pool through
XMS when the repository HIMEM peer is present. It removes UMB backing pages
from the EMS pool, installs stable mappings, and registers all extents
atomically.

The EMS and UMB ownership sets must stay disjoint. A committed UMB mapping must
remain stable across EMS map changes, DMA, alternate register sets, task
switches, failed initialization, and warm reboot. Page-frame windows, video
memory, option ROMs, explicit exclusions, and the system-ROM area are not UMB
candidates. `X=` exclusions override `I=` inclusions regardless of argument
order.

A third-party XMS provider remains valid for DOS. Repository EMM386 may decline
its UMB feature when its private HIMEM peer is absent, but must not replace or
damage the third-party manager.

## EMM386 footprint

Volkov Commander 4.05's `Alt+F5` MCB walk is the comparison oracle, using
identical 8 MiB QEMU hardware and startup files. Retail DOS 6.22 leaves a
618,736-byte largest conventional block. Before relocation was repaired, this
system left 455,984 bytes and a 128,688-byte low `system` block.

With HIMEM and `DOS=HIGH` alone the low block is 20,144 bytes. The former
EMM386-attributable increase was 108,544 bytes in both `NOEMS M5` and `RAM M5`;
`RAM` separately changes the upper arena, so that increase was not the EMS page
frame or UMB backing pool.

This build defines `NOHIMEM`, so `InitTab` uses the extended-buffer
`get_buffer`/`moveb` path before shrinking `driver_end`. The XMS allocator had
initialized only the EMS backing pool, leaving `get_buffer` unable to relocate
`PAGESEG` and `LAST`. It now reserves a relocation tail in the same locked XMS
handle. UMB mappings are committed before the initialization-only `LAST` state
is discarded, and the relocated page directory is installed in both the live
descriptor state and TSS.

The other large fixed cost was allocating maximum-capacity tables for all 255
handles and 255 fast register sets. These tables now occupy resident `VDATA`
according to the selected `H=` and `A=` capacities; the full option ranges are
unchanged.

Each fast register set formerly retained mapping slots for all 52 possible
windows even when the selected frame and banking layout exposed far fewer. The
runtime context size now determines the resident stride, while the maximum
`B=`/`A=` configuration still receives all 52 slots. Normal EMM386 residency
drops by 384 bytes without changing the public context size or option limits.
Saved page maps also use a byte owner: `H=255` exposes handles 0 through 254,
so `FFh` is an unambiguous unused marker. This removes another 64 bytes in the
normal `H=64` configuration without changing its four saved frame mappings.

The `P=` and `FRAME=` parser formerly kept its 20 page identifiers, 20 segment
values, and four frame candidates in resident DGROUP. Every consumer runs in
the discardable `LAST` initialization segment. Those 70 bytes now live beside
their consumers and use `CS`-relative references; paragraph rounding reduces
the installed EMM386 allocation by 64 bytes. Explicit frame selection,
individual page assignment, and EMS 4.0 alternate-register services remain
covered.

The selected initial mode, `W=`, `RAM`/`NOEMS`, temporary page identifier, and
resident-break pointer are likewise needed only while `LAST` installs the
driver. Keeping these ten bytes with their initialization consumers removes one
more installed paragraph. Normal, `OFF`, `AUTO`, both `W=` forms, `RAM`, and
`NOEMS` startup paths remain covered.

The detected DOS version and the selected pool, `L=`, `D=`, and `B=` values are
also installation inputs rather than runtime state. Moving these nine bytes to
`LAST` removes another installed paragraph while keeping explicit XMS reserve,
DMA reserve, and banking-boundary configurations covered.

The candidates used to construct the DMA page list—high and extended starts,
counts, and the temporary ranges on either side of a 64 KiB boundary—are also
installation-only. Moving them beside `InitEPage` in `LAST` removes 14 resident
bytes and crosses an allocation boundary, reclaiming one 16-byte paragraph.
The final DMA page list remains resident. Accepted and rejected `D=` reserves
and the extended EMS 4.0 lifecycle remain covered.

Installation message flags and the 12-byte option-token buffer now live in
`LAST`; the parser writes and reads the latter explicitly through that segment.
The pool base and sizes, temporary availability totals, XMS entry and handle,
and relocation-tail size are likewise used only while allocation, table setup,
or failed-install cleanup is running. Moving those 19 bytes out of DGROUP with
the parser state removes 34 linked resident bytes after alignment and reduces
the installed allocation by 32 bytes. The complete option grammar, allocation
failure paths, and runtime command parser remain covered.

The physical address of the relocated text and the temporary stack, IDT, and
page-directory segment values are also consumed only during table setup. They
now live in `LAST`; the page-table segment deliberately remains resident
because split-UMB setup still consumes it during the transition. The unused
error-prefix word is gone. Return-to-real trapping now uses the saved port 84h
token itself as the pending-sequence state, invalidating it on any port 85h
output instead of retaining separate last-port and unread port-85 bytes. These
data and code reductions reclaim another 48 installed bytes while preserving
runtime `ON`/`OFF`/`AUTO`, split UMBs, and warm transitions.

The IDT and complete TSS, including its 8 KiB I/O bitmap, now follow `PAGESEG`
in the load image. Initialization builds them conventionally, then copies them
with the page tables into the locked XMS relocation tail and repoints their
descriptors. This preserves interrupt and I/O trapping while removing both
tables from the resident conventional span.

The NOHIMEM initialization stack retains its full 1 KiB depth but overlaps the
otherwise disposable 512-byte ring-stack template. `InitTab` rebases the live
ring-stack descriptor on dynamic resident storage before virtual mode starts.

The linker now places reflected EMS services and the real-mode transition path
before the protected-only trap engine. Initialization copies the complete
logical `_TEXT` to locked XMS, points the protected selectors at that copy,
then reuses the low protected suffix for the selected VDATA extent. Runtime
`ON`, `OFF`, and `AUTO` remain supported because DMA initialization, A20
control, interrupt masking, and the return path stay in the low prefix.

The transient `EMM386 ON`/`OFF`/`AUTO` parser now follows the protected-only
suffix boundary. Later command invocations execute their own loaded image, so
that parser need not remain in the installed driver. The comparison
configuration reports 14,320 installed bytes for EMM386, or 14,336 bytes
including its arena header. The exact paired measurement is recorded below.
The enforced normal EMM386 module budget is 14 KiB including that header.

HIMEM's UMB transaction table remains fixed-capacity, but its XMS handle table
now follows all other resident data. The initialization break includes only
the configured `/NUMHANDLES=` records and is rounded up to a paragraph so the
last record cannot be released partially. Parser, CPU detection, diagnostics,
and destructive memory-test code now follow the resident break. The normal
32-handle configuration stays within 3 KiB of conventional memory. The UMB
record count now also represents registration state: a valid registration is
never empty, and unregistering clears the count. Removing the redundant
committed flag and its writes crosses a paragraph boundary and saves 16 more
installed bytes. Each UMB record also stores its allocation state in the high
bit of its size: no valid UMB can approach the bit's 32,768-paragraph value.
This removes the former flag byte from all 32 records and simplifies their copy
loops, saving another 48 installed bytes. The complete 128-handle option remains
available and tested, as do all 32 UMB extents.

The XMS move engine formerly retained a word solely to recover its current
chunk length after BIOS `INT 15h/87h`, plus instructions to store and reload
it. Keeping that value on the active routine's stack removes the word and both
memory accesses. This moves the default resident break from `0BADh` to `0B9Dh`,
crossing a paragraph boundary and reclaiming 16 installed bytes without
changing the move descriptor, 64 KiB chunk limit, or maximum handle capacity.

HMA ownership now uses the high bit of `/HMAMIN=`. The accepted range is
`0..63`, so that bit cannot collide with a configured minimum and is masked
before the byte is converted to a request size. Global and local A20 operations
share their identical enable and reconciliation tails while retaining separate
nesting counters and local-underflow behavior. Together these changes cross the
next paragraph boundary, reducing HIMEM to 2,960 installed bytes. HMA ownership,
all A20 backends, XMS 3, 128 handles, 286 operation, UMB transactions, and the
EMM386 address-phase matrix remain covered.

## Memory-parity status

Use identical 8 MiB QEMU hardware, startup files, and VC 4.05 binaries for all
comparisons. Retail leaves a 618,736-byte largest conventional block; the
pre-compaction baseline leaves 558,240 bytes. The validated compacted build
with shared system-stack dispatch and the protected DMA trap engine leaves
593,616 bytes, a 25,120-byte gap.
Exact byte parity is not required, but a large unexplained loss is not
acceptable.

The remaining difference is accounted for rather than treated as an
undifferentiated target:

| Status | Accounted difference | Measured effect or opportunity |
| --- | --- | ---: |
| Complete | DOS relocation hole fragmented below resident HIMEM | 32,928 bytes recovered |
| Open | Larger resident system components | 12,032 bytes |
| Open | Larger resident COMMAND | 3,360 bytes |
| Open | Retained DOS layout and conventional ceiling | 9,728 bytes |

The relocation row is closed. Remeasure the remaining rows after each retained
change instead of assuming that every byte is another oversized component.

## Road to retail-or-better conventional memory

The target is a largest conventional block of at least **618,736 bytes** in the
fixed VC 4.05 comparison, without reducing supported memory-manager options or
usable UMB space. The current result is 593,616 bytes, so 25,120 more bytes must
join the largest free block. Total free memory is supporting evidence, not a
substitute for this metric: saving bytes below a resident island may leave the
largest block unchanged.

The present accounting identifies the whole target but not yet every individual
symbol responsible for it:

| Workstream | Current excess or opportunity | Cumulative result if fully recovered |
| --- | ---: | ---: |
| EMM386 resident allocation | 10,192 bytes | 603,808 bytes |
| HIMEM resident allocation | 1,856 bytes | 605,664 bytes |
| COMMAND resident allocation | 3,360 bytes | 609,024 bytes |
| Layout and conventional ceiling | 9,728 bytes | 618,752 bytes |

The extra 16 bytes in the arithmetic are paragraph rounding. Matching only the
three measured component sizes recovers at most 15,408 bytes and therefore
cannot meet the goal; layout work is mandatory unless a component becomes
smaller than retail by the remaining amount.

### Success equation and critical path

Treat the 25,120-byte gap as a portfolio, not as four independent size targets.
For every retained change record:

```text
remaining gap = 25,120 - EMM386 gain - HIMEM gain - COMMAND gain
                         - DOS/layout gain - ceiling gain
```

Only growth of the largest VC block counts as a gain. Component shrinkage that
lands in a separate free island is pending layout work until that island is
joined to the largest block. No workstream is required to match retail's
private size: one may beat retail and cover an irreducible difference elsewhere.

The currently proved upper bound from matching the three named components is
15,408 bytes. Moving the 1 KiB EBDA without allocating a replacement block
raises that to 16,432 bytes, still leaving **8,688 bytes**. The final route must
therefore include at least one of these outcomes:

- recover at least 8,688 bytes from retained DOS/BIOS layout and fragmentation;
- make EMM386, HIMEM, or COMMAND collectively at least 8,688 bytes smaller than
  their retail counterparts; or
- combine smaller layout and better-than-retail component gains to the same
  total.

The critical path is:

1. make EMM386 independent of its load paragraph, because the present defect
   blocks even a proved one-paragraph HIMEM saving;
2. complete byte attribution and symbol censuses so safe compaction has a
   measured yield and destination;
3. take paragraph-scale HIMEM/EMM386 wins, then the bounded COMMAND wins, while
   updating the equation after every paired capture;
4. recover the EBDA ceiling paragraph only after identifying already-owned
   destination storage;
5. close the still-measured remainder through DOS layout compaction or the
   smallest necessary EMM386/COMMAND architectural split; and
6. defend retail-or-better memory with a local fixed-image regression floor.

This ordering is a dependency order, not a promise that the early inexpensive
work is sufficient. If the censuses show that safe compaction plus the EBDA and
layout work cannot close the then-current gap, proceed directly to the
architectural EMM386 gateway split; do not spend time chasing isolated bytes
that cannot reach the largest block.

### Complete improvement inventory

This is the backlog for reaching the target. An item is an opportunity, not an
assumed saving: retain it only when the paired capture shows that its bytes join
the largest conventional block. Estimates are deliberately ranges until a map
or A/B image measures them.

| Priority | Opportunity | Available evidence | Likely scale | Principal constraint |
| --- | --- | --- | ---: | --- |
| 1 | Compact EMM386 runtime-sized metadata and alignment | 10,192-byte component excess; initialization state and three tables reduced | tens to hundreds of bytes per item | Full `H=`/`A=` ranges and EMS 4.0 formats |
| 1 | Remove remaining HIMEM init-only state and padding | 1,856-byte component excess; resident break is explicit | tens to hundreds of bytes | 128 handles, 32 UMB extents, all A20 backends |
| 1 | Classify every byte below the first MCB | Current first system MCB begins at `0478h`; retail describes allocations from `0070h` | attribution first | Some low addresses are ABI or BIOS fixed |
| 2 | Move more EMM386 protected-only code/data to locked XMS | Low retained prefix dominates its allocation | low kilobytes | Real/virtual transitions, inactive `AUTO`, DMA and faults |
| 2 | Move COMMAND messages and rare resident services transient | 3,360-byte shell excess; resident messages occupy a material map range | low kilobytes | Reload, critical error, `INT 2Eh`, batch and pipe survival |
| 2 | Compact DOS-high low anchors and tables | Component parity alone remains 9,712 bytes short | low kilobytes | Real-mode near pointers and driver-visible internals |
| 3 | Relocate the EBDA into already-owned safe low storage | Exact 1,024-byte ceiling loss is measured | 1,024 bytes | Physical BIOS/DMA access; destination must not consume the gain |
| 3 | Remove MCB/alignment islands or change load order | Compare first-free and every allocation boundary | paragraphs to kilobytes | Identical startup files and stable ownership |
| 3 | Place eligible permanent allocations high | Local UMB advantage is only 1,216 bytes | at most 1,216 bytes without falling below retail UMB capacity | Must not disguise a conventional regression |
| 4 | Redesign EMM386's low entry/return architecture | Largest remaining single component opportunity | several kilobytes | High complexity and broad compatibility surface |
| 4 | Redesign COMMAND's resident/transient boundary | Map proves the tail is already cut correctly | up to 3,360 bytes to parity, possibly more | Shell state must survive transient overwrite |

The following ideas are valid only behind explicit measurement and compatibility
gates:

- make fixed arrays dynamic only when their worst-case runtime growth remains
  possible; saving default-image bytes by silently reducing maximum capacity is
  not an improvement;
- share identical resident routines, strings, descriptors, scratch buffers, and
  error exits across modules where their lifetime and calling conventions match;
- replace word fields with bytes, bit sets, sentinels, or derived values only
  after proving every public numeric value still fits and unallocated states stay
  unambiguous;
- reorder resident segments to remove paragraph padding and place variable tails
  at the allocation break;
- copy immutable protected-mode tables to the existing locked EMM386 XMS image
  and keep only relocation-safe low gateways;
- use HMA space left after DOS only for data that is valid while A20 is enabled
  and whose ownership cannot collide with DOS, buffers, or third-party users;
- use UMBs for permanent state only when the fixed comparison remains
  deterministic and total usable UMB capacity remains at least retail's 47,888
  bytes; and
- become smaller than a retail component when that is simpler and safer than
  reproducing retail's private layout. The user-visible target is available
  memory and compatibility, not byte-for-byte internal identity.

These tempting shortcuts are excluded: falsifying `INT 12h` or the BDA size,
overwriting or page-mapping the live EBDA, reclaiming ROM/video/excluded ranges,
dropping supported option capacity, weakening rollback or warm-reboot behavior,
or consuming unreported UMB space merely to improve the conventional number.

### Actionable candidate register

This register turns the inventory into experiments. It is complete for the
currently known opportunities; new map evidence may add candidates. A candidate
is not an achievement until its focused compatibility tests and paired VC
capture pass.

| Order | Area | Experiment | Decision evidence |
| ---: | --- | --- | --- |
| 1 | Measurement | Add linker/map boundaries and paragraph deltas to the paired report; account for `0000h..0477h` and every gap between MCBs | Every byte of the 9,728-byte layout row has an owner or an explicitly unknown range |
| 2 | EMM386 | Keep installation and the first virtual-to-real continuation independent of the preceding driver's paragraph count | Passed across `/NUMHANDLES=24..32`; retain runtime-mode and warm-reboot coverage |
| 3 | HIMEM | Pack boolean HMA/A20 state into fields with proved spare bits, or derive it from existing nesting/ownership state | All A20 backends, nested local/global enable, HMA ownership, DOS-high and warm reboot |
| 4 | HIMEM | Audit duplicate error exits, request dispatch, range checks and paragraph-tail padding as one map-guided pass | Exact XMS error codes, XMS 2/3, 128 handles and legacy-driver bounce path |
| 5 | EMM386 | Produce a resident-symbol census grouped as real-only, protected-only, dual-mapped, mutable runtime, or initialization-only | No unclassified symbol in the 14,320-byte allocation; measured size per group |
| 6 | EMM386 | Compact remaining runtime arrays, descriptors, flags and alignment; size storage from selected options where maximum growth remains possible | Normal and maximum `H=`/`A=`/`B=`/`D=`/frame configurations and EMS 4.0 maps |
| 7 | EMM386 | Relocate the next self-contained protected-only table or routine into the existing locked XMS image | Fault, DMA, mapping, `ON`/`OFF`/`AUTO`, inactive query and warm-reboot paths |
| 8 | EMM386 | Replace the shared `RRProc` continuation with a small relocation-safe low gateway, allowing its transition module to move high | Repeated real/virtual transitions plus all runtime command modes |
| 9 | COMMAND | Generate a `CODERES`/`DATARES` symbol and string census; mark state that must survive transient overwrite | Every resident range has a survival reason and size |
| 10 | COMMAND | Move rare messages/formatting and reloadable services transient; merge scratch and descriptors whose lifetimes do not overlap | External-program reload, batch, pipe, `INT 2Eh`, Ctrl+C and critical-error tests |
| 11 | DOS/layout | Attribute retained low DOS/BIOS anchors and near-pointer tables, then move or compact only individually proved owners | Internal-structure and redirector suites plus a larger contiguous VC block |
| 12 | Ceiling | Relocate the 1 KiB EBDA into verified already-owned slack and update the BDA pointer atomically | BIOS users, DMA and warm reboot pass; `INT 12h` becomes 640 KiB without a new 1 KiB allocation |
| 13 | Placement | Remove alignment/MCB islands, adjust load order, or place eligible permanent state high | Largest conventional block grows and usable UMB remains at least 47,888 bytes |
| 14 | Regression | Enforce the fixed-image VC floor and retain component/UMB budgets locally | At least 618,736 bytes across clean rebuilds and the full release suite |

The EMM386 census is reproducible from a clean linker map:

```sh
python3 tests/report_emm386_residency.py --check \
  src/MEMM/MEMM/EMM386.MAP
```

The current map divides `_TEXT` at `IOTrap_Tab`: 8,222 low bytes precede the
boundary and 9,379 protected-only bytes follow it. The map exposes 80 symbols
in the retained or dual-mode prefix, 100 in the protected-only suffix, and 67
in mutable runtime data, with no unclassified linker-visible symbol. This
completes the first EMM386 symbol-ownership pass, but not byte attribution:
local labels, padding, and the dynamically overlaid VDATA range still require
range-level accounting before selecting the next relocation.

### Decision gates

| Gate | Required evidence | Decision |
| --- | --- | --- |
| Address independence | Passed: EMM386 boots and completes the first continuation across `/NUMHANDLES=24..32` | Paragraph-changing HIMEM and linker work is unblocked |
| Attribution | All conventional ranges and every EMM386, HIMEM, and COMMAND resident symbol have an owner, lifetime, and size | EMM386 symbol ownership complete; range accounting plus HIMEM, COMMAND, DOS, and BIOS remain |
| Safe compaction exhausted | Every low-risk candidate has an A/B component delta and VC largest-block delta | Calculate the exact architectural/layout remainder |
| Layout route chosen | EBDA destination and all low islands are proved safe, or their gains are rejected explicitly | Implement only gains that join the largest block |
| Architecture required | Remaining gap exceeds the sum of proved safe layout candidates | Redesign EMM386's gateway first; redesign COMMAND only for the residual need |
| Target reached | VC reports at least 618,736 bytes and usable UMB capacity is at least 47,888 bytes | Run all compatibility gates and establish regression floors |

At each gate, update the baseline rather than carrying projected savings
forward. The roadmap is complete only when the equation reaches zero on a clean
build and the fixed comparison remains reproducible.

The immediate queue is deliberately conservative: finish attribution and
census EMM386 before changing another transition boundary. COMMAND and EBDA
work follow once their maps identify a destination rather than merely a source
of bytes. The architectural EMM386 and COMMAND changes remain available if
small compactions cannot close the gap.

Two HIMEM shortcuts have already been rejected and must not be retried without a
different design. Recovering saved caller registers from fixed stack offsets
passed narrow probes but hung the paired boot because the call depth is not a
stable ABI. Carrying source/destination move errors in `BL` corrupts the `BX`
handle consumed by endpoint resolution. The retained implementation therefore
keeps explicit caller state and move-error state until a reentrant replacement
has its own stable storage or calling convention.

Making `umb_count` byte-sized is also rejected on the 286 path: each consumer
would need an additional instruction to clear the high half of its loop count,
growing resident code by more than the one data byte recovered.

The next HIMEM paragraph exposed a separate EMM386 prerequisite. A prototype
packed HMA ownership into `/HMAMIN=`'s unused high bit and shared the identical
local/global A20 success tails. Focused HMA, A20, XMS 3, option-limit, and UMB
transaction/model tests passed, and the default HIMEM break moved from `0B9Dh`
to `0B8Bh`. The fixed hard-disk boot then stalled immediately after EMM386's
installation banner when DOS released the resulting paragraph. Diagnostic
padding and `/NUMHANDLES=` sweeps proved that the symptom followed the load
paragraph rather than the packed HIMEM state.

Historical A/B builds narrow the dependency to `1dec794`, which moved 19 bytes
of allocation state from DGROUP to LAST. Its parent `75aa2da` boots behind
stock HIMEM `/NUMHANDLES=29`; `1dec794` and later builds stall. Restoring those
variables to DGROUP fixes the shifted boot, but leaving them discardable and
adding an equal DGROUP pad also fixes it. A 12-byte pad moves `_TEXT` and all
later segments by one paragraph and exactly cancels HIMEM's one-paragraph load
shift; that configuration boots as well. The variables are therefore not live
after installation. The active defect is an absolute-address or page-boundary
assumption in the EMM386 protected-text/first-continuation layout.

The root cause was the final VDATA compaction, not the discarded variables.
`CompactVData` moved the dynamic arrays below `_TEXT` and lowered `driver_end`,
but left `VDMS_GSEL` pointing at the old ring-0 stack beyond that break. DOS was
therefore allowed to overwrite a live exception stack; the time and address of
the overwrite determined whether the first continuation survived. Compaction
now rebases `VDMS_GSEL` at the new rounded break and retains its complete
512-byte stack. The old extra guard paragraph is unnecessary because the base
and length are explicit. Hard-disk boots pass for `/NUMHANDLES=24..32`, spanning
the previously failing phases, and the runtime mode, EMS 4.0, capacity, UMB,
DMA, fault-rollback, and two-boot warm-reset paths remain required gates.

### Milestones to the target

The work proceeds by evidence, not by assuming all component excess is
recoverable:

1. **Finish attribution.** Extend the capture with retained boundaries from the
   DOS, BIOS, HIMEM, EMM386, and COMMAND maps. Explain the current `0000h..0477h`
   region, retail's `0070h..0252h` DOS/IO allocations, every paragraph between
   installed components, and the first-free difference `0EB4h` versus `08F0h`.
2. **Take safe component wins.** Finish table, field, duplicate-code, init-state,
   and alignment audits. Require an A/B result and focused maximum-option tests
   for every retained change.
3. **Reach component parity or document the irreducible difference.** Target
   HIMEM 1,104, EMM386 4,128, and COMMAND 2,960 bytes as comparison points, not
   hard implementation limits. If all three are matched, the projected largest
   block is 609,024 bytes.
4. **Recover real layout bytes.** Safely relocating the EBDA raises that
   projection to 610,048 bytes. At least another 8,688 bytes must then come from
   DOS/BIOS low-layout compaction, fragmentation removal, safe high placement,
   or making one or more components smaller than retail.
5. **Cross and defend 618,736.** Once the fixed image reaches the retail floor,
   run the full local release suite, maximum-capacity configurations, warm
   reboot, and paired UMB comparison. Add a regression assertion for the largest
   conventional block and retain any margin rather than stopping at an
   alignment-sensitive exact tie.

After each milestone, update the table above with measured—not projected—bytes.
If a saving changes a component allocation but not the largest block, classify
the resulting island and keep it open as layout work.

### 1. Make each byte attributable

Before another structural change, turn the paired boot comparison into a
repeatable local measurement that records the VC largest block, `MEM /D` MCB
chain, component sizes, first free paragraph, conventional-memory ceiling, and
UMB regions for both systems. Keep the hardware, startup files, VC binary, and
environment size identical. Add retained-allocation boundaries from linker maps
or generated manifests for HIMEM, EMM386, COMMAND, DOS, and BIOS.

For each experiment, report both the allocation-size change and the largest-
block change. Classify any difference as resident code, resident data, alignment
or MCB overhead, an unavailable conventional range, or fragmentation. This is
the prerequisite for resolving the 9,728-byte layout row rather than moving it
between labels.

`tests/capture_vc_memory_comparison.py` implements the paired capture. It
rejects images whose `CONFIG.SYS` or VC binary differs, boots each private copy,
runs `MEM /D`, opens VC 4.05 Memory Info, and writes a Markdown comparison with
the raw conventional MCB rows. Its focused probe also records `INT 12h`, the
BIOS Data Area memory-size word, and the EBDA segment after CONFIG.SYS. Run it
against prepared current and retail hard disk images:

```sh
python3 tests/capture_vc_memory_comparison.py \
  CURRENT.IMG RETAIL-622.IMG out/vc-memory-comparison.md
```

The validated baseline reproduces 593,616 versus 618,736 bytes, the component
figures below, a conventional ceiling of `9FC0h` versus retail's `A000h`, and
the 1,216-byte local UMB advantage. This completes the repeatable measurement
foundation; generated reports remain build evidence rather than tracked
documentation.

### 2. Reduce EMM386's low allocation

EMM386 is the largest component opportunity: 14,320 bytes here versus 4,128 in
retail. Potential reductions, in preferred order, are:

- compact retained data and descriptor metadata, size every table from the
  selected `H=`, `A=`, frame, and DMA configuration, and remove paragraph or
  linker padding that is not an address-stability requirement;
- move additional protected-only code and immutable tables into the locked XMS
  image while retaining explicit low gateways for real-mode entry and return;
- redesign the EMS dispatcher so ordinary and mapping-sensitive functions can
  execute from the relocated image without losing inactive `AUTO` queries;
- replace the shared `RRProc`/return-to-real continuation with a relocation-safe
  gateway, then move the return trap module as one unit;
- separate installation and transient `ON`/`OFF`/`AUTO` command parsing from
  state genuinely needed by the installed driver; and
- audit low GDT, stack, DMA snapshot, exception diagnostics, and compatibility
  state for duplication with the relocated GDT, IDT, TSS, `_TEXT`, or VDATA.

This work must preserve EMS 3.2/4.0 services, non-empty function 56h maps,
alternate register sets, DMA, page frames, `RAM`/`NOEMS`, runtime
`ON`/`OFF`/`AUTO`, warm reboot, and maximum `H=`/`A=` capacities. Moving a
module solely because its normal path appears protected-only is unsafe; entry,
return, fault, inactive, and transition paths must all be identified first.

### 3. Reduce HIMEM's low allocation

HIMEM occupies 2,960 bytes versus retail's 1,104. Audit its resident break at
each `/NUMHANDLES=` capacity and distinguish fixed code/data from option-sized
records. Candidate work includes:

- pack UMB ownership records further where the full numeric ranges and
  transactional rollback can be retained;
- merge duplicate range validation, A20, request-header, and error paths;
- discard all detection, parser, diagnostic, and memory-test state after
  initialization, verifying the paragraph-rounded break directly;
- relocate immutable data or safe state into the HMA after DOS has reserved it,
  without consuming space needed by the DOS-high image and buffers; and
- reduce the permanent device stub only if the XMS entry point, request chain,
  third-party coexistence, and all A20 backends remain compatible.

The default and 128-handle configurations, all 32 UMB extents, XMS 2/3 calls,
HMA ownership, nested A20 state, transactional UMB behavior, and legacy-driver
bounce path are non-negotiable gates.

### 4. Reduce COMMAND's resident allocation

COMMAND occupies 6,320 bytes versus retail's 2,960. Its retained allocation
already ends at `DATARESEND`; the opportunity is inside resident code and data,
not an accidentally retained transient tail. Inspect `CODERES`, `DATARES`, the
resident message blocks, batch/environment bookkeeping, reload code, and their
alignment separately. Potential approaches are:

- move rarely used commands, messages, and error formatting to the reloadable
  transient part;
- consolidate resident message descriptors, duplicated strings, scratch areas,
  and compatibility variables;
- shrink reload, `INT 2Eh`, critical-error, pipe, batch, and termination paths
  after proving which portions must survive transient overwrite; and
- consider an optional UMB-resident permanent shell only after the identical
  comparison configuration can select it deterministically. It must not hide a
  regression by consuming UMBs or changing the public default.

The shell must still reload after external programs, preserve batch and pipe
state, handle critical errors and Ctrl+C, maintain its environment and
`COMSPEC`, and support the complete internal-command surface.

### 5. Recover the layout and ceiling difference

After every component change, compare MCB start/end addresses rather than
inferring layout from component totals. The current 9,728-byte row may contain
several independent effects. Investigate:

- the top-of-conventional-memory value and every BIOS reservation below it;
- the location and order of DOS, device, shell, environment, and free MCBs;
- paragraph rounding, MCB headers, alignment gaps, and zero-sized or stranded
  blocks between resident allocations;
- whether DOS relocation leaves any additional low copy, compatibility anchor,
  transfer area, table, or arena bridge that can safely move to the HMA;
- whether eligible post-EMM386 allocations can use existing UMBs without
  reducing the largest UMB below retail or changing the startup files; and
- whether free blocks can be reordered or coalesced so recovered bytes actually
  extend the largest conventional block.

The ceiling probe explains the first item. This system leaves the QEMU EBDA at
`9FC0h`; both `INT 12h` and BDA word `40h:13h` therefore report 639 KiB. Retail
DOS 6.22 moves the EBDA pointer to `035Ch` and changes both reports to 640 KiB.
That accounts for exactly 1,024 bytes of the ceiling row, but changing the
reported values alone would corrupt the live EBDA. A retained implementation
must copy the EBDA into explicitly owned low memory, update `40h:0Eh` only after
the copy, preserve BIOS users of the area, and prove that its destination does
not consume the same 1 KiB from the largest block. Reusing verified slack in an
existing resident system allocation can yield the full gain; adding a new 1 KiB
allocation cannot.

Do not reclaim ROM, video, page-frame, exclusion, provider-gap, or real-mode
near-pointer space merely to improve the number. Preserve the current 1,216-byte
usable-UMB advantage unless an explicit trade yields a larger conventional
block and still leaves at least retail UMB capacity.

### 6. Lock in the target

Implement small, independently measured changes, starting with table and
alignment reductions before transition-path redesigns. After each retained
change, run the focused component suite and the paired memory capture; run the
full local release suite at workstream boundaries. Once the result reaches
618,736 bytes, add that value as a regression floor for the fixed comparison
image, retain the component ceilings, and record any margin above retail.

CI remains disabled by project decision. These gates run locally until CI is
explicitly restored.

Paired `MEM /D` captures account for the conventional system block as follows:

| Component | This system | Retail 6.22 | Excess |
| --- | ---: | ---: | ---: |
| HIMEM | 2,960 | 1,104 | 1,856 |
| EMM386 | 14,320 | 4,128 | 10,192 |
| FILES | 896 | 896 | 0 |
| FCBS | 256 | 256 | 0 |
| BUFFERS | 512 | 512 | 0 |
| LASTDRIVE | 2,288 | 2,288 | 0 |
| STACKS | 1,840 | 1,856 | -16 |
| Total | 23,072 | 11,040 | 12,032 |

`MEM` reports 23,184 and 11,168 bytes after each block's arena overhead. Both
systems use `BUFFERS=15` and now retain only one 512-byte conventional transfer
area. A direct retail probe found its buffer hash at `FFFF:B3D4`, confirming
that DOS 6.22 also places the normal buffer state in the HMA.

### Stage 1: HMA buffers with legacy-driver safety — complete

A retained implementation reserves the HMA before final-table construction and
packs the normal hash and buckets above the resident DOS image. Configured
sets that do not fit retain the original conventional allocation path, so the
supported `BUFFERS=` range is unchanged.

One maximum-sector transfer area is allocated through the normal SYSINIT layout.
After `RW_SC` has had the opportunity to select its own low cache, `DEVIOCALL`
redirects a remaining one-sector HMA read or write to that area. Writes are
copied down before the strategy/interrupt calls; successful reads are copied up
after the retained-low return trampoline has restored A20. The original request
pointer is restored before `VIRREAD` and before any outer critical-error retry.

The failed prototype used `SC_SECTOR_SIZE` as its copy length. That field belongs
to the optional secondary-cache path and may be zero even for a successful
ordinary buffer request, leaving stale HMA data after a driver returned `DONE`.
The retained path uses SYSINIT's maximum sector size, which is the allocation
bound shared by every HMA slot and the low transfer area.

Before relocation compaction, the DOS-high/A20 suite, INT 21h filesystem and
exhaustion suites, and MEM/UMB suite pass locally. The exact VC comparison gains
7,120 bytes in its largest block; the system component itself drops by the
expected 7,488 bytes, while the larger retained DOS path changes the surrounding
fragmented layout by 368 bytes.

### Stage 2: make the reclaimed DOS relocation hole safe — complete

The retained implementation relocates DOS into the HMA, synchronizes SYSINIT's
final exchange block to its low copy, publishes the reclaimed arena, and stores
up to six initial DPBs in resident BIOS memory. It boots the A/B/C comparison
image through `AUTOEXEC.BAT` and VC, recovering 32,928 bytes.

The retained-low driver trampoline forces A20 on after each native strategy
and interrupt entry point without changing public XMS nesting counts. The
focused probe sees A20 enabled after the calls.

External hardware-breakpoint traces reject an allocation-overlap explanation.
The HMA-buffer callback publishes an active 512-byte low transfer area at
`0571:0000`; its device mark extends through `0591`, while the preceding test
driver remains intact at `053A`. A no-op `REM` line after HIMEM is sufficient
to trigger the same failure, so another driver's behavior is not required.
The first failing-operation FAT read and root-directory `GETBUFF` were correct.
The actual mismatch was `THISCDS`: path parsing updated the retained-low SDA to
`0588:0000`, while `TestNet` used an implicit `CS:` override and read the stale
HMA duplicate `0000:043C`. Reading this mutable state through `SS:` gives it one
owner and restores directory, file, and free-space operations after any
post-HIMEM CONFIG line.

The DOS-high/A20, filesystem and exhaustion, internal-structure, HIMEM-option,
and MEM/UMB suites pass locally. A VC 4.05 capture before Stage 3 left 590,768
bytes in the largest conventional block, confirming the reclaimed 32 KiB
remains usable.
CI remains disabled until explicitly restored.

Structures addressed by real-mode near offsets must remain below 1 MiB. Do not
use broad pointer scans or heuristic segment rewriting; every new ownership
transition needs a focused regression.

### Stage 3: reduce and account for resident components — complete

The measured system-component excess is 12,032 bytes. The current paired VC
capture reports COMMAND at 6,320 bytes versus retail's 2,960, a separate
3,360-byte excess. The retained boundaries are:

- narrow the EMM386 low/high split only at entry points whose reflected,
  protected-only, or dual-mapped ownership is understood. EMS function 56h
  now uses the retained-low `_TEXT` segment for its real-mode return gateway
  rather than truncating the relocated protected-code address. Its physical-
  and segment-map call paths are regression-tested with non-empty maps. The
  `ARPL` gateway still resumes at the same logical offset in the high copy, so
  moving the complete EMS library remains a code-transition redesign rather
  than a linker-only change. Ordinary EMS calls also enter `int67_Entry` in
  the retained real/virtual copy, while only mapping-sensitive calls use the
  protected dispatcher. Moving even the C-only services therefore reclaims
  live code. A future split must preserve inactive `AUTO` queries and activate
  virtual mode only when allocation requires it;
- keep the DMA register snapshot in the retained prefix, but keep the DMA trap
  engine protected-only. This retained split saves 1,072 conventional bytes
  and passes normal, `ON`/`OFF`/`AUTO`, EMS 4.0, frame, `D=`, and capacity
  coverage;
- keep `RRProc` and its return-to-real trap module together until their shared
  virtual-mode continuation is replaced; moving only the handler prevents the
  first runtime `OFF` transition from completing;
- investigate the remaining 1,856-byte HIMEM excess without reducing supported
  option capacity. HIMEM's 32 UMB records have no pad or allocation byte; the
  allocation state uses the otherwise impossible high bit of their paragraph
  size. XMS handle records contain only their active flag, lock count, base, and
  size, removing two unused bytes per configured handle. HMA ownership likewise
  uses `/HMAMIN=`'s unavailable high bit, and the global/local A20 paths share
  identical success tails. Together these retain the full extent and 128-handle
  limits while reducing the normal HIMEM allocation by 160 bytes;
  STACKS now uses one nested-safe common dispatcher while each
  vector retains its compatibility header and successor pointer; the default
  9-by-128 pool occupies 1,840 bytes, 16 fewer than retail, and is budget-gated;
- COMMAND's 6,320-byte footprint remains above retail's 2,960 bytes. Its map
  ends the resident allocation exactly at `DATARESEND` (6,112 program bytes),
  so this is resident code/data rather than an incorrectly retained transient
  tail. Closing the final 3,360 bytes would require a targeted resident-shell
  redesign, not correcting retained transient data.

Retain the full documented option ranges. Each footprint reduction needs a
component budget assertion and the relevant maximum-capacity test.

Stage 3 evidence is complete:

- EMS functions, including function 56h, pass after any EMM386 split change;
- the normal EMM386 and HIMEM footprints remain budget-gated without reducing
  maximum supported capacities;
- COMMAND's resident excess is explained; and
- the fresh paired VC and `MEM /D` captures provide the figures above.

### Stage 4: reconcile UMB reporting — complete

Goal: explain the remaining arena-layout and reporting differences after the
large conventional losses have been removed.

With the public UMB chain linked, this system exposes free regions of 16,352
bytes at `CC00h` and 32,752 bytes at `E000h`. Retail exposes 15,152 bytes near
`CC4Bh` and 32,736 bytes near `E002h`, so this system provides 1,216 more usable
upper-memory bytes. VC hides the first local region only while the public chain
is unlinked; this is reporting state, not lost memory.

The current 593,616-byte largest block is 25,120 bytes (4.1%) below retail and
every material difference is assigned to a measured component or layout
workstream above. This is an explained baseline, not completion: the fixed
comparison must reach at least 618,736 bytes without reducing option capacity
or retail-equivalent usable upper memory. After every retained-memory change,
repeat the paired VC capture and relevant local suites. CI stays disabled during
active development; local tests remain authoritative until it is restored.

## Evidence

The release suite covers allocator lifecycle and rollback, XMS transactions,
HMA residency and fallback, high loaders, MEM reporting, EMM386 modes and
mapping stability, A20 backends, filesystem/redirector traffic, interrupts,
warm reboot, and provider absence. The machine-readable inventories under
`tests/` and [tests/COVERAGE.md](tests/COVERAGE.md) are authoritative for
current test names and counts. `test_mem_umb_qemu.sh` enforces the 14 KiB
EMM386 and 3 KiB HIMEM conventional-memory budgets. Load-option tests cover
the maximum EMM386 `H=`/`A=` and HIMEM `/NUMHANDLES=` capacities.
