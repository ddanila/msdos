# Emulator strategy

Use each emulator only for the hardware generation it models credibly. Local
test results are authoritative while CI is disabled; do not enable or require
CI until the maintainer requests it.

## Decision

- **86Box is the 80286 acceptance emulator.** It models complete period PCs,
  including the CPU, AT chipset, keyboard-controller A20 gate, and a real BIOS.
- **DOSBox-X remains a fast 8086/286 smoke-test backend.** Its 286 BIOS block
  move and protected-mode return behavior is synthesized, so a DOSBox-X-only
  failure is not evidence of a product defect.
- **QEMU remains the 80386-and-newer backend.** Its oldest selectable CPU is a
  486; it cannot validate 286-specific behavior.
- **MAME is an optional independent 286 oracle.** Add it only if a result is
  disputed or its stronger command-line automation becomes useful.
- Do not add PCem or Bochs. PCem offers no useful advantage over 86Box for this
  project, and Bochs does not target faithful 286 machine validation.

## Reference 286 machine

Keep one versioned 86Box VM configuration with:

- IBM PC/AT 5170;
- Intel 80286 at 8 MHz;
- 640 KiB conventional RAM and 2 MiB extended RAM on ISA expansion cards;
- IBM AT BIOS;
- standard AT keyboard controller and A20 gate;
- a 1.2 MiB floppy drive for generated test media;
- COM1 connected to the host process's standard output;
- host time synchronization disabled for deterministic NVRAM and diagnostics.

86Box and its ROMs are test prerequisites, not distributable product artifacts.
Do not commit BIOS ROMs, Microsoft binaries, NVRAM, writable disks, logs, or
other generated VM state. Commit only configuration templates and scripts.

## Test contract

An automated 286 test must:

1. build the normal product with the repository toolchain;
2. create a fresh bootable image in a temporary directory;
3. copy only the test payload and generated startup files onto that image;
4. clone the reference VM configuration into the temporary directory;
5. boot 86Box directly with explicit VM and ROM paths;
6. run without GUI input and emit a bounded, machine-readable result on COM1;
7. terminate on success, failure, or a host-side deadline;
8. preserve useful diagnostics after failure and remove ordinary temporary state;
9. skip with a precise prerequisite message when 86Box or ROMs are unavailable,
   and fail under the repository's strict no-skip mode;
10. leave source-controlled and user-owned disk images untouched.

The guest result must distinguish `PASS`, an asserted product failure, startup
failure, and timeout. The host script must not infer success from emulator exit
status alone.

## Implementation stages

Current status: Stages 1 through 3 are complete. The local suite covers clean
boot, BIOS block moves, the DOS 6.22 memory stack, AT hardware interfaces, and
pre-386 fallback on 86Box 6.0.

### 1. Prove the HIMEM path

- [x] Install the current stable 86Box locally on macOS ARM64.
- [x] Record the exact executable and ROM prerequisites in the test's skip message.
- [x] Create the reference IBM AT configuration and a minimal serial-output probe.
- [x] Add `tests/test_himem_286_86box.sh` using the existing forced-286 HIMEM build
  and full XMS move lifecycle.
- [x] Make a fresh IBM AT boot reach the standalone `INT 15h/AH=87h` probe
  reproducibly, then run the HIMEM lifecycle in a separate boot.
- [x] Compare the result with DOSBox-X; its 286 smoke test also passes with the
  current implementation.

Acceptance: repeated clean boots produce the same result, serial output is
captured without interaction, and the test has a bounded shutdown path.

Run `gmake test-286-acceptance` for the real-BIOS acceptance path and
`gmake test-himem-286-dosbox` for the faster synthesized-BIOS comparison.
DOSBox-X 2026.08.02 passes the focused HIMEM lifecycle but does not reach
AUTOEXEC in the broader HIMEM-plus-EMM386 pre-386 image; keep
`test-pre386-dosbox` diagnostic and non-blocking.

### Local prerequisites

Install 86Box itself with `brew install --cask 86box`. Obtain the official
86Box ROM set separately and place it in 86Box's normal ROM directory, or set
`BOX86_ROMS` to it. Set `BOX86_BIN` only when the executable is outside the
usual command path or macOS application bundle. The tests validate the exact
IBM 5170 ROM files they require and otherwise skip with a precise message.

### 2. Make the backend reusable

- [x] Factor image creation, VM cloning, launch, timeout, and serial parsing into a
  small helper shared by later 286 tests.
- [x] Add deterministic cleanup and retain-on-failure diagnostics.
- [x] Document installation without downloading or redistributing ROM material.
- [x] Add a local aggregate target for 286 acceptance tests.

Acceptance: a new test supplies only its DOS payload, startup files, expected
result, and timeout.

### 3. Expand 286 coverage

Goal: extend the real-BIOS IBM AT suite so every hardware-sensitive DOS 6.22
component has an explicit 80286 contract, and fix any incompatibilities it
finds. Keep 86Box authoritative for AT hardware behavior, DOSBox-X as the fast
comparison, and QEMU for 386-and-newer coverage.

- [x] Cover HIMEM A20 methods, HMA ownership, XMS moves, and `/TESTMEM`.
- [x] Prove that EMM386 rejects a 286 cleanly without leaving hooks or damaged
  DOS state.
- [x] Exercise CPU detection and unsupported-instruction paths.
- [x] Prove safe fallback for `DEVICEHIGH`, `LOADHIGH`, and MemMaker when 386 or
  UMB facilities are unavailable.
- [x] Cover startup selection, keyboard handling, disk geometry, and reboot on
  the reference IBM AT.
- [x] Include the completed contracts in `gmake test-286-acceptance` and update
  the gap and runtime-coverage manifests.

Acceptance: every test uses a fresh temporary image, emits a bounded result,
and leaves no 386-only instruction reachable on a supported 286 path. Keep pure
command parsing, filesystem logic, and fast smoke coverage on the existing
backends.

### 4. Add an independent oracle only when needed

Configure MAME's IBM 5170 with the same RAM, BIOS generation, and test image.
Use its timed execution and Lua support to reproduce only disputed 86Box results
or tests that require stronger automation. Agreement between 86Box and MAME is
strong evidence; disagreement requires a reduced probe or physical AT check.

## Result policy

- A real-machine result outranks every emulator result when the setup is known.
- Agreement between two full-machine emulators is sufficient for ordinary
  acceptance.
- One full-machine result outranks DOSBox-X for BIOS, A20, or protected-mode
  transitions.
- Emulator disagreement is recorded; it is never hidden by weakening a test.
- Physical timing, unusual BIOSes, and third-party chipsets remain validation
  targets, not release blockers unless the project explicitly claims them.
