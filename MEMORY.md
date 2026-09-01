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

## Open EMM386 footprint defect

Volkov Commander 4.05's `Alt+F5` MCB walk exposes a material conventional-memory
gap with identical 8 MiB QEMU hardware and startup files. Retail DOS 6.22 leaves
a 618,736-byte largest conventional block; this system leaves 455,984 bytes.
Exact addresses and small accounting differences are not parity requirements,
but losing roughly 163 KiB is.

The low `system` MCB beginning at `0C5Bh` is the main symptom. With HIMEM and
`DOS=HIGH` alone it is 20,144 bytes. Loading repository EMM386 increases it to
128,688 bytes in both `NOEMS M5` and `RAM M5`, an EMM386-attributable increase
of 108,544 bytes. `RAM` separately changes the upper arena, so the low-memory
increase is not the EMS page frame or UMB backing pool.

The leading source-level explanation is incomplete resident-image relocation.
`InitTab` in `src/MEMM/MEMM/INITTAB.ASM` can shrink `driver_end` only after
moving page tables and resident state through `HiSysAlloc`. That allocator in
`OEMPROC.ASM` depends on the historical high-system control words at
`F000:FFE0`; ordinary QEMU hardware does not provide that OEM facility. The
newer XMS path in `ALLOCMEM.ASM` allocates and locks the EMS backing pool but
does not provide an equivalent relocation destination for the resident image.
The size corroborates that path precisely: `INIT.ASM` initializes `driver_end`
to `seg LAST`, and the link map places `LAST` at relative segment `1A7Fh`.
Including the MCB paragraph gives `1A80h * 16 = 108,544` bytes, exactly the
observed increase. The first `HiSysAlloc` failure therefore leaves the initial
break address unchanged. What remains unproven is the correct replacement
relocation design; a future fix needs break-address tracing and must preserve
the existing EMS/UMB contracts.

## Evidence

The release suite covers allocator lifecycle and rollback, XMS transactions,
HMA residency and fallback, high loaders, MEM reporting, EMM386 modes and
mapping stability, A20 backends, filesystem/redirector traffic, interrupts,
warm reboot, and provider absence. The machine-readable inventories under
`tests/` and [tests/COVERAGE.md](tests/COVERAGE.md) are authoritative for
current test names and counts. These functional contracts do not yet enforce
retail-comparable EMM386 conventional-memory footprint.
