# Behavioral coverage

The optional Russian increment has source, reference and CPI gates:
`make test-ru-font-sources test-ru-contract test-ru-cpi`. The
[locale manifest and font audits](../locales/ru/README.md) pin inputs and
independent glyph/box-edge expectations. `make test-ru-display-qemu` verifies
DISPLAY/MODE selection, every loaded VGA glyph, guest completion and emulator
exit, including a wrong-slot control and existing EGA-page regressions.
[Display qualification](../locales/ru/display-qualification.json) retains
the focused results and screenshots. `make test-ru-country-records test-ru-country-qemu`
checks all prior country payloads, the new Russian records, DOS country/case
APIs, external table queries, CHCP/DISPLAY agreement and rejected selections.
[Country qualification](../locales/ru/country-qualification.json) records the
guest results, including detection of a corrupted case entry and the NLSFUNC
fixes established by the new tests. Older keyboard variants, installation,
HIGH/UMB/LOW/286 and end-to-end qualification remain in [the plan](../RUSSIAN.md).

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

The [review record](memory_promotion_review.json) links the matched production
release evidence and retains the scope of historical baseline checks. A passing
suite cannot qualify different composed binaries. The profile audit changes only
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

The Russian keyboard table gate, `make test-ru-keyboard-records`, checks the
separate RU library against the independently captured DOS reference and
rejects wrong translations and malformed records.
[Keyboard qualification](../locales/ru/keyboard-qualification.json) records its
results and before/after physical-input evidence. `make test-ru-keyboard-qemu`
checks enhanced-keyboard BIOS/DOS bytes, mode selections, case, punctuation,
third shift, controls, navigation, keypad and released modifiers. It detects
a wrong Yo byte and verifies typed RU/GR/RU reloads. Older keyboard variants
and complete locale qualification remain open in
[RUSSIAN.md](../RUSSIAN.md).

[Modifier qualification](../locales/ru/modifier-qualification.json) extends the
physical keyboard gate with BIOS/DOS checks of Caps punctuation, both Shifts,
right Ctrl, Alt-letter passthrough, third-shift priority and overlapping
language selections. These cases verify released flags and empty input queues.

The RU keyboard guest gate also rejects missing/invalid libraries and
unsupported page, identifier and layout selections, then verifies typed input
in the prior Russian mode. It executes the startup sections from the shipped
[RUSSIAN.TXT](../locales/ru/RUSSIAN.TXT) with paths adapted to its private
floppy and checks DOS/DISPLAY code-page agreement. The distribution gate
compares decompressed locale resources and font licenses with their sources.
`make test-ru-install-qemu` checks fresh/upgrade payload hashes and startup
preservation, then boots the installed recipe in HIGH/UMB and LOW profiles.
It requires emulator exit plus country, code-page and physical-key completion;
the HIGH case proves HMA residency and a usable UMB allocation. See
[installation qualification](../locales/ru/installation-qualification.json).
The profile gate below covers display planes; real-BIOS 286/end-to-end gates
remain open in the plan.

[RU packaging qualification](../locales/ru/packaging-qualification.json) records
disk hashes, available capacity and deployed optional-file hashes.

[RU profile qualification](../locales/ru/profile-qualification.json) covers
actual VGA font bytes and the NLS transition/rejection matrix on production
HIGH/UMB and LOW. `make test-ru-profiles-qemu`, included in `make test`, detects
the former generic-IOCTL segment error when preparing three DISPLAY pages.
The report retains its instruction trace and successful corrected-core runs.
The changed kernel still requires full release qualification.

The [legacy backend bootstrap](../locales/ru/legacy-backend-qualification.json)
records `tests/test_86box_guest_exit.py` with a selected production core. It
requires DOS completion and guest-requested success/failure process statuses
on the real-BIOS IBM AT. This establishes the exit mechanism for forthcoming
Russian 286 gates; it does not qualify their country, keyboard or display
behavior. The record pins the emulator build, BIOS ROMs and retained logs.

[Probe ISA qualification](../locales/ru/legacy-probe-qualification.json) records
why locale probes explicitly target 8086: NASM's default 386-only conditional
near jumps prevented the country probe from running on a 286. The corrected
probes pass the initial real-BIOS AT-84 country/input check and the selected
HIGH/LOW QEMU regressions. The expanded AT-84 input gate below adds coverage;
286 font-plane/transition matrices remain required by the Russian plan.

The [AT-84 input qualification](../locales/ru/at84-qualification.json) runs
`tests/test_ru_legacy_keyboard_86box.py` against a VNC-enabled, loopback-only
86Box backend. It verifies the resident AT keyboard type and reuses the
independent Russian byte oracle through BIOS and DOS input. Separate enhanced
navigation keys become physical keypad events; unavailable right Alt/Ctrl
cases are excluded. Guest completion, exact process status, released modifier
bits and an empty input queue are required. The retained record includes the
actual event matrix and backend/core hashes. XT-83 input, legacy reload and
rejection cases, and the complete 286 display/NLS matrix remain open.

The [XT-83 input qualification](../locales/ru/xt83-qualification.json) selects
`--machine xt83` in the same runner. A private 360 KiB image boots the selected
core on the IBM XT BIOS and an 8088 with the PC/XT keyboard controller. The
guest asserts KEYB's XT type before running the same independent input oracle.
This adds BIOS and DOS input coverage; it does not establish XT font rendering
or replace the remaining 286 display/NLS and end-to-end release gates.

The [legacy load-state qualification](../locales/ru/legacy-load-qualification.json)
selects `--suite lifecycle` with either legacy machine. Each BIOS/DOS run
requires errors for missing, bad-signature and truncated files, unsupported
page, ID and layout; verifies preserved Russian input and both language
shortcuts after every rejection; and checks German and reloaded Russian
physical input. Resident keyboard type, released modifiers, empty queues,
all phase markers and a guest-requested successful exit are required.

The [286 country qualification](../locales/ru/country-286-qualification.json)
runs `tests/test_ru_country_86box.py` on the IBM AT BIOS with the selected
production core and DOS=LOW. It covers explicit and default CONFIG country
pages, CHCP transitions, external-page queries, rejected selections and a
corrupted case-table control. Positive cases require every expected probe
marker and guest-requested status zero; corruption must fail at the expected
case-table stage with guest-requested status one. This does not qualify the
286 font plane or replace the remaining end-to-end and release gates.

The [backend exit record](../locales/ru/backend-exit-qualification.json)
retains the Qt crash stack and private Unit Tester exit patch used by the
286 country run. It separately verifies guest-requested statuses zero and
one; a DOS completion marker alone never makes a host crash pass.

The [286 display qualification](../locales/ru/display-286-qualification.json)
runs `tests/test_ru_display_86box.py` against real IBM AT BIOS. The BOX86
probe option exports the loaded VGA plane and a Unit Tester screen snapshot
before guest completion; it does not synthesize a screen from font data.
The host compares all glyph slots to the font oracle and every grid pixel
to the loaded bitmap, including VGA ninth-column line-graphics replication. CP866 height variants, preserved old pages
and the wrong-yo-slot control require exact completion and status zero.
The default QEMU probe remains byte-identical with BOX86 undefined.

The [Russian text workflow](../locales/ru/text-qualification.json) runs
`tests/test_ru_text_qemu.py` on the selected HIGH/UMB and LOW core. It types
physical JCUKEN/Latin keys, corrects a shell line with Backspace, creates and
edits text in EDLIN, saves and reopens it, and exercises TYPE redirection and
a FIND pipe. Exact CP866 files, fresh-screen text, screenshots, runtime
profile evidence and guest completion/status are required.

The [Russian filesystem qualification](../locales/ru/filesystem-qualification.json)
runs `tests/test_ru_files_qemu.py` on HIGH/UMB and LOW. CP866 batch commands
exercise alternate-case paths, copy/rename/delete, Cyrillic 8.3 extensions,
nested directories, padded-field wildcards, collation ordering and reverse
ordering. A guest marker selects verification on a fresh boot of the same
image, with no host edits between boots. The host parses FAT directory bytes,
checks file contents and verifies final removal. The test exposed raw-byte
DIR sorting; COMMAND now caches active DOS weights for name/extension keys.
The record includes existing command regressions, a kvikdos NLS/BDA isolation
fix and matched text-workflow evidence. Full release qualification of the
changed COMMAND core remains required.

The [286 filesystem qualification](../locales/ru/filesystem-286-qualification.json)
uses the same runner with `--emulator` and `--roms` on IBM AT BIOS and DOS LOW.
It creates a private boot image from the selected core and requires guest
completion, exact backend exit status, raw FAT names and file bytes on both
boots. Commands arrive from a CP866 batch file; this gate does not exercise
physical keyboard input or rendered Cyrillic text.

The [286 text qualification](../locales/ru/text-286-qualification.json) runs
the same physical shell/editor workflow through VNC on IBM AT BIOS and an
AT-84 keyboard. Captures compare actual rendered glyph masks with CP866 font
rows; saved files require exact bytes. The runner waits for editor prompts and
for an empty shell prompt on the last occupied row around checkpoints, so
floppy I/O cannot overflow the BIOS key buffer. The record includes the VNC
resize correction, retained timing diagnostics and QEMU profile regressions.

The [Russian directory qualification](../locales/ru/directory-qualification.json)
extends the filesystem gate with MOVE directory rename and recursive XCOPY,
including an empty directory. It checks exact short names, nested content and
FAT parent links before fresh-boot reads and cleanup on QEMU HIGH/UMB, LOW and
IBM AT BIOS. `make test` includes both `test-ru-files-qemu` and
`test-ru-text-qemu`; their media remain private to each run.

The [Russian pristine build qualification](../locales/ru/reproducibility-qualification.json)
compares every declared Makefile artifact and the composed production memory
core from independent detached worktrees at serial and parallel job counts.
The tool binaries, commands and complete logs are retained. Both the ordinary
and composed outputs also match the active release artifacts. This evidence
does not replace the full runtime release suite.

[Russian memory requalification](../locales/ru/memory-requalification.json)
uses a frozen candidate containing the current production kernel and COMMAND.
It repeats the composed failure matrix and reboot/application/cancellation/A20
campaign, including COMMAND fallback and startup profiles. Ordinary baseline
map-sensitive gates are separate from this composed-core evidence.
