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

## Stabilization subplan

The objective is to qualify one composed memory configuration for promotion
into the normal build. Start with the evidence audit and reboot checks below;
reuse applicable evidence before scheduling additional runs. Track the overall
open item in [TODO.md](TODO.md), and keep results in manifests or generated
reports rather than copying them here.

The [retained-image evidence audit](tests/memory_stabilization_audit.json)
identifies a frozen historical composition and records which existing results
match it. The [composed reboot qualification](tests/memory_stabilization_baseline.json)
records its rebuilt successor and the diagnostic/control pair. These records
qualify their exact inputs, not later builds or the entire stabilization plan.
Local artifacts and reproduction commands are linked from the records and
[composed memory diagnostics](tests/COVERAGE.md#composed-memory-diagnostics).

1. **Identify the candidate and audit existing evidence.** Freeze a matched
   image containing the intended BIOS and COMMAND relocations, paired
   HIMEM/EMM386 providers, and upper interrupt stack pool. Retain its binaries,
   hashes, maps, build options, and startup configuration. Compare these with
   the recorded [application comparisons](tests/DOS-APP-SMOKE.md) and focused
   memory tests. Reuse results only where the tested inputs and scope match;
   distinguish default-deployment results from composed-image qualification.
2. **Complete the reboot pair.** Run
   [test_bios_int19_qemu.py](tests/test_bios_int19_qemu.py) on the complete
   paired-provider and upper stack-pool composition, then run
   [test_software_reboot_qemu.py](tests/test_software_reboot_qemu.py) with the
   existing configuration on the same frozen base image as the unmodified
   bootstrap-chain control. Require the diagnostic's second boot, stack checks
   on both boots, and subsequent FCB operation, plus successful reboot through
   the control. Keep each run's mutations private; see
   [composed memory diagnostics](tests/COVERAGE.md#composed-memory-diagnostics).
3. **Qualify failure paths and memory ownership.** Use existing focused probes
   where applicable and add fixtures for concrete gaps. Exercise HIGH/LOW
   operation, allocation and publication failures, partial relocation, and
   usable low fallback. Check A20-off entry and return, interrupt handling,
   EMS mapping changes while UMB clients remain live, and process cleanup.
   Assert preserved ownership and data as well as successful execution.
4. **Qualify repeated application operations.** On the candidate image, cover
   child EXEC/exit cycles, COMMAND reload, pipes, disk/media I/O, and console
   editing. Reuse matching existing coverage and extend application scenarios
   where startup comparisons leave lifecycle behavior untested. Record the
   actual operations and assertions so startup success is not mistaken for
   full application qualification.
5. **Review promotion against the recorded scope.** Require the applicable
   [release gates](ARCHITECTURE.md#reproducibility-and-validation) and the checks
   above to pass for matched inputs, with discrepancies resolved or explicitly
   scoped. Record the decision on enabling the composition by default and
   retain reproducible qualification commands. Keep DBCS, external hooks,
   unusual hardware, and other untested contexts explicit; exhaustive coverage
   of every DOS program and machine is not the completion criterion. Further
   memory optimization remains deferred.

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
