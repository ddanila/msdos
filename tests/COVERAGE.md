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
Passing with standalone HIMEM does not qualify the paired-provider and upper
stack-pool composition. Keep that qualification in [TODO.md](../TODO.md).

## External DOS applications

The [DOS application startup comparison](DOS-APP-SMOKE.md) uses pinned archive.org
packages and a genuine DOS 6.22 image, compares application screen witnesses and
video attributes, and retains raw differences and binary hashes. Its manifest
lists selection rationale; it does not claim measured interrupt coverage or deep
application validation. The independent near-CALL probe checks the emulator
workaround needed for reliable comparisons. Both runners have optional Makefile
targets; external media is not required by the default test suite.
