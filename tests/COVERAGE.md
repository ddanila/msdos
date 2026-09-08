# Behavioral coverage

Coverage means a test asserts an externally visible result or state transition,
or a live source condition justifies excluding the interface. Source-line
execution alone is insufficient for DOS API, driver, and hardware contracts.

## Enforcement

`make test` runs source-derived manifest verifiers with `--require-complete`,
native checks, kvikdos tests, and selected QEMU suites. It does not run every
standalone emulator target. Build first; runtime prerequisites also trigger
build/deployment where declared. See the [Makefile](../Makefile) for the live
suite and [EMULATION.md](../EMULATION.md) for hardware-specific gates.

Use `FAIL_ON_SKIP=1 make test` to reject skips in tests that support this policy.
Automatic CI is paused. A manifest check validates evidence registration; it
does not execute every referenced test or prove retail parity.

Entries use these levels where supported:

- `contract`: focused assertions check the result or state transition;
- `excluded`: a source-backed condition makes direct runtime coverage inapplicable;
- `observed`: the path runs without an isolated assertion; rejected in strict mode;
- `uncovered`: acceptable evidence is absent; rejected in strict mode.

Verifiers reject missing/stale inventory rows and missing evidence files.
Runtime evidence must be wired into the Makefile or retained workflow graph.
Some diagnostics call that graph "CI" even though hosted execution is manual.
Use verifier output for current totals; do not copy inventories into Markdown.

The `*_coverage.json` manifests and their verifiers cover kernel dispatch and
errors, commands and parsers, CONFIG.SYS, runtime components, Help, interrupts,
public structures, EMS, and driver requests. Run individual checks through the
`test-*-coverage-manifest` targets; INT 21h dispatch uses
`test-coverage-manifest`.

## Oracle integrity

Tests must fail when the artifact or behavior they claim to validate is absent.
`oracle_mutation_coverage.json` records component-deletion results;
`audit_oracle_mutation.sh` reruns focused tests on private images with one
component removed. The normal verifier checks those records, rather than
performing the entire deletion audit on every run.

Serial batch tests disable echo before redirecting output to the serial device.
`test_batch_oracles.py` checks this so an echoed command cannot satisfy its own
pass marker. Add negative controls where a probe could otherwise pass without
exercising its claimed behavior.

Tests that mutate media must use private copies and honor `FLOPPY_IMAGE` where
the fixture supports it. Keep the deployed image immutable during a test run.

## Composed memory diagnostics

`make test-hma-qemu` checks low/high DOS operation and A20 recovery. Its
`hma_low_return_probe.asm` fixture also builds with `XMS3_RETURN` to check that
the ECX result survives a successful low dispatcher return and that failed
A20 restoration unwinds through the low frame. Each run keeps private artifacts
under `out/hma-qemu.*` and accepts `FLOPPY_IMAGE`.

Run `python3 tests/capture_emm_init_phases.py out/floppy.img --table-fallback allocation` and
the same command with `--table-fallback copy` to exercise high-table allocation
refusal and a partial destination copy. Both require the table owner to remain
low; the fault-injection defines are absent from the production build. Use
`--high-tables` without a fault option for the successful relocation control.
Build and deploy the baseline floppy before these captures.

`make test-bios-character-requests-qemu` compares actual installed low/high
character-device requests while deterministic firmware hooks disable A20.
`python3 tests/test_bios_character_requests_qemu.py --omit-keyboard-restore`
is a negative control and must fail. These tests use private floppy copies and
record request transcripts and input hashes in `out/bios-character-requests-*`.

`python3 tests/test_bios_int19_qemu.py IMAGE BIOS_BUILD_DIR` is a standalone
diagnostic for a frozen DOS=HIGH hard-disk composition with `STACKS=9,128`.
The image must contain the BIOS from that build directory and the current
kernel; retain its matching `low.json` and `msBIO.map`. The probe checks vector
restoration, then chains through the saved ROM bootstrap entry and requires a
second boot, stack checks on both boots, and a subsequent FCB operation. It
temporarily intercepts the saved INT 19h target to inspect the restored vectors;
use `test_software_reboot_qemu.py` for the unmodified bootstrap-chain control.
With EMM386 installed, pass `--emm-build EMM_BUILD_DIR` containing its matching
`EMM386.EXE` and `EMM386.MAP`. The diagnostic validates the installed manager
hook and its saved BIOS entry, enters through that hook, and requires real mode
at the restored-vector checkpoint. `--bad-emm-chain` corrupts the saved BIOS
entry in the private run and must fail before reboot. Passing with standalone
HIMEM does not qualify the paired-provider and upper stack-pool composition.

To rebuild the composed candidate, run `gmake -B -j4 all` and `gmake deploy`,
then create a non-faulted paired-provider fixture:

```sh
python3 tests/capture_emm_init_phases.py out/floppy.img \
  --common-xms-entry --reclaim-bootstrap --high-tables --fine-umbs --dos-high
```

Use the printed fixture directory as `PAIRED_DIR` below. `BASE_HDD` is a private
FAT16 hard-disk baseline with the paired managers under `C:\DOS`, DOS=HIGH,UMB,
and existing startup/application files. The builder copies it, refreshes its
existing system tools from the deployed floppy, installs the composed owners,
checks shared kernel offsets, and adds explicit `STACKS=9,128`. The output
directory must not exist. Inputs and the deployed image remain unchanged.

```sh
python3 tests/build_memory_stabilization_image.py BASE_HDD PAIRED_DIR out/memory-candidate
python3 tests/test_bios_int19_qemu.py out/memory-candidate/candidate.img \
  out/memory-candidate/bios --emm-build out/memory-candidate/provider/MEMM/MEMM
python3 tests/test_software_reboot_qemu.py out/memory-candidate/candidate.img --profile existing
```

Build options, commands, maps, hashes, and provider evidence remain in the
private output directory. The [qualification record](memory_stabilization_baseline.json)
retains the tested identities and outcomes. Remaining stabilization work stays
in [TODO.md](../TODO.md).

The composed failure/ownership campaign uses private variants of that frozen
build, reconstructing the original provider and BIOS before introducing faults:

```sh
python3 tests/test_composed_memory_failures_qemu.py out/memory-candidate
python3 tests/test_composed_provider_cancel_qemu.py out/memory-candidate
python3 tests/test_command_upper_failure_qemu.py out/memory-candidate/candidate.img
python3 tests/test_command_upper_failure_qemu.py out/memory-candidate/candidate.img --policy-rejection
python3 tests/test_stack_pool_retirement_qemu.py out/memory-candidate/candidate.img \
  --shapes-bios out/memory-candidate/bios --async-timer --a20-off
```

The first runner accepts repeated `--case` selections. It checks BIOS table,
CDS and stack allocation fallback; EMM table allocation/partial-copy fallback;
and UMB rollback after mapping and before publication. Runtime assertions check
actual table/stack locations, EMS exhaustion and release, patterned UMB storage
during EMS remapping, and file operations. Child cleanup compares both the
largest free upper block and total free UMB space across repeated exits, with
the public arena alternately linked and unlinked. A deliberately retained child
must trigger the accounting failure, rather than merely fail a startup check.

The DOS=LOW variant removes the provider's HIGH-only diagnostic assertion and
independently verifies low kernel/stack operation. Its CDS and file tables may
still occupy UMBs. EMS rollback accounting excludes pages held by system handle
zero; it requires all other pages to be available, then exhausts and releases
them. The [failure qualification record](memory_failure_baseline.json) gives
the exact scope, input identities, positive results and negative controls.

## External DOS applications

The [DOS application startup comparison](DOS-APP-SMOKE.md) uses pinned archive.org
packages and a genuine DOS 6.22 image, compares application screen witnesses and
video attributes, and retains raw differences and binary hashes. Its manifest
lists selection rationale; it does not claim measured interrupt coverage or deep
application validation. The independent near-CALL probe checks the emulator
workaround needed for reliable comparisons. Both runners have optional Makefile
targets; external media is not required by the default test suite.

The [composed lifecycle campaign](DOS-APP-SMOKE.md#composed-application-lifecycle-qualification)
uses the frozen composition directly for repeated application jobs, forced shell
reloads, pipes, virtual-floppy round trips, and editor save/reopen operations.
Its [record](memory_application_baseline.json) includes per-cycle memory accounting
and corruption controls. It is separate from default-image startup comparisons.

The standalone EXEPACK loader regression (`gmake test-exepack-qemu`) uses a
synthetic compressed MZ and an unrecognized-decoder negative control under
HIMEM and EMM386. See [the application notes](DOS-APP-SMOKE.md#exepack-compatibility).

## Memory promotion review

The [review record](memory_promotion_review.json) distinguishes default-build
release gates from the opt-in composition's evidence. A passing default suite
cannot qualify different composed binaries. The profile audit changes only
startup configuration and its completion probe on private copies:

```sh
python3 tests/test_composed_promotion_profiles_qemu.py COMPOSITION_DIR \
  --record out/promotion-profiles.json
```

A profile counts as booted only when COMMAND emits the completion marker and
QEMU exits successfully. The runner returns failure if any profile does not
boot; recognizing the HMA diagnostic explains the blocker but does not waive it.
This audit checks startup, not complete HIGH/LOW or pre-386 compatibility.

## Promotion gate repairs

[Follow-up evidence](memory_gate_fixes.json) records repairs to failures found
during the promotion review. `gmake test-fc-qemu` checks FC version boundaries
and binary/text comparisons on the shipped kernel in LOW and HIGH operation.

`gmake test-command-shift-qemu` changes the maximum allocation available to a
child COMMAND and requires successful reload and parent resumption in LOW and
HIGH operation. Its negative control detects a shifted transient despite a
matching additive checksum.

[Residency budgets](memory_residency_budgets.json) retain explicit owner accounting
for the ordinary build. BIOS, COMMAND, and EMM386 reports and the MEM UMB gate
consume the same limits. Reproduce the live fixed-profile census with
`python3 tests/capture_emm_live_owners.py out/floppy.img --mem-umb-profile --require-compact`.
