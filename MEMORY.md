# Memory maintenance

## Current priority

Stabilize the composed memory implementation. Further BIOS/COMMAND relocation,
HMA/UMB repacking, and EBDA recovery are deferred unless a correctness defect
requires them. More free conventional memory is not a promotion requirement.

The composed BIOS, shell, and paired-provider layouts are opt-in fixtures under
`tests/`; they are not all enabled by `make deploy`. Passing a default-image test
does not qualify a composed image. Keep its kernel, BIOS, COMMAND, HIMEM, EMM386,
shared-layout consumers, maps, and configuration matched.

Before promotion, qualify HIGH/LOW operation, allocation and publication
failures, A20-off entry/return, interrupts, disk/media I/O, console editing,
shell reload/EXEC/pipes, and software reboot on that same composition. DBCS,
external drivers and hooks, broader exception contexts, and hardware-specific
media/A20 behavior remain validation gaps. Scope these explicitly; a focused
passing probe does not establish full compatibility.

## Ownership constraints

- UMB storage ownership is independent of the public arena link state. Process
  cleanup must visit both arenas; allocation and coalescing must not cross
  provider gaps. Upper-only allocation must not fall back to conventional RAM.
- UMB acquisition and publication are transactional. Failed initialization must
  release reservations and expose no partial arena. The signed SYSINIT handoff
  is private; ordinary callers retain the public invalid-function result.
- HIMEM owns standalone XMS/HMA/A20 services. In paired-provider experiments,
  transfer allocator authority exactly once while preserving cached entries,
  live handles, locks, addresses, and data. An ambiguous publication result
  must not reactivate a stale bootstrap allocator.
- EMS pages and UMB backing remain disjoint. Published UMB mappings must survive
  EMS mapping changes and cannot disappear while clients still own them.
  Manager OFF/error continuation must respect live upper-memory and EMS owners.
- Keep standalone HIMEM, third-party XMS providers, and the 286 fallback usable.
  EMM386 requires a 386; it may decline its private UMB integration with an
  unfamiliar XMS provider but must not damage that provider.
- Relocation must preserve public far pointers and shared DOSGROUP offsets.
  Retain callable low entries, return frames, interrupt state, and DMA-safe
  buffers until every consumer can safely use its final owner. A copied or
  poisoned low body is not released memory.
- DOS, BIOS, cache, and shell share one HMA budget. Count alignment, entry gates,
  safety space, UMB allocation overhead, and locked XMS reservations once.
  Allocation or shrink failure must leave a coherent, callable low fallback.

## Validation and measurement

Use the [Makefile](Makefile) for maintained gates and each fixture's argument
parser for supported compositions. Rebuild matched inputs before testing; see
[EMULATION.md](EMULATION.md) for backend requirements.

Keep captures, hashes, maps, and measurements in ignored `out/` artifacts.
Compare matched hardware, startup files, requested resources, and binaries.
Report the largest contiguous conventional block, free UMBs, and application
XMS together; reconcile them with live ownership and linked boundaries.
Do not count a separate free hole or reduced resource capacity as an equivalent
gain.
