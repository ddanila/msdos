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
have separate records below; [RUSSIAN.md](../RUSSIAN.md) links the completed
locale qualification.

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
The profile gate below covers display planes; real-BIOS and end-to-end
evidence is linked below.

[RU packaging qualification](../locales/ru/packaging-qualification.json) records
disk hashes, available capacity and deployed optional-file hashes.

[RU profile qualification](../locales/ru/profile-qualification.json) covers
actual VGA font bytes and the NLS transition/rejection matrix on production
HIGH/UMB and LOW. `make test-ru-profiles-qemu`, included in `make test`, detects
the former generic-IOCTL segment error when preparing three DISPLAY pages.
The report retains its instruction trace and successful corrected-core runs.
The changed kernel has passed the [full release suite](../locales/ru/release-qualification.json).

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
actual event matrix and backend/core hashes. Separate records below cover XT-83 input, legacy reload/rejection and the
286 display/NLS matrix.

The [XT-83 input qualification](../locales/ru/xt83-qualification.json) selects
`--machine xt83` in the same runner. A private 360 KiB image boots the selected
core on the IBM XT BIOS and an 8088 with the PC/XT keyboard controller. The
guest asserts KEYB's XT type before running the same independent input oracle.
This adds BIOS and DOS input coverage; it does not establish XT font rendering
or replace the separate 286 display/NLS and end-to-end release gates.

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
286 font plane or replace the separate end-to-end and release gates.

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
changed COMMAND core is recorded in the [release report](../locales/ru/release-qualification.json).

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

The [Russian acceptance audit](../locales/ru/acceptance-audit.json) maps every
implementation-plan bullet to its retained evidence. It distinguishes focused
component results from current-core and full-release claims. The
[release record](../locales/ru/release-qualification.json) retains the successful
full suite and selected artifact hashes; the audit closes the Russian scope.

The [Baltic foundation qualification](../locales/baltic/foundation-qualification.json)
records `make test-baltic-font-sources`, included in `make test`. It checks the
pinned CP775 mapping against an independent codec, required national letters,
candidate glyph coverage, reproducible review artifacts and corrupted source/
mapping rejection. Shared-auditor changes also pass the existing Russian source
and CPI gates. This does not qualify Baltic keyboard, country or runtime support.

The [Baltic country contract qualification](../locales/baltic/country-contract-qualification.json)
records the selected per-country formatting, uppercase and collation expectations
for native and legacy code pages. `make test-baltic-country-contract`, included
in `make test`, checks DOS field encoding, independent national ordering examples,
case behavior and rejection of incomplete/ambiguous letter groups. This is a
reference-data gate; installed COUNTRY.SYS and guest API evidence is linked below.

The [Baltic keyboard contract qualification](../locales/baltic/keyboard-contract-qualification.json)
records `make test-baltic-keyboard-contract`, including pinned reference parsing,
fixed national scan/byte facts, composition pairs and byte-preserving handling
of CP775 values that Unicode treats as whitespace. The reference parser does
not emit keyboard driver data; physical BIOS/DOS qualification remains separate.

The [Baltic country record qualification](../locales/baltic/country-record-qualification.json)
records `make test-baltic-country-records`. It rebuilds COUNTRY.SYS, checks every
Baltic object against retained expectations, verifies all prior object contents
and detects incorrect case/collation bytes. Both targets are included in
`make test`. Country guest API and transition/rejection coverage is recorded below.

The [Baltic display qualification](../locales/baltic/display-qualification.json)
records `make test-baltic-cpi` and the shared QEMU display runner on HIGH/LOW.
Static checks cover the CPI structure, selected national glyph rows and supported
border edges. The guest prepares/selects CP775, captures actual VGA font bytes
and renders samples; completion, profile markers and process exit are required.
A wrong o-with-tilde slot is isolated through the same oracle. Existing Russian
and EGA-page display regressions pass. Real-BIOS, keyboard, country API and
installed-workflow qualification remain separate requirements.

The [Baltic country API qualification](../locales/baltic/country-qualification.json)
records `test-baltic-country-qemu`, included in `make test`. It requires matching
production-core hashes, HIGH/LOW profile markers, exact guest completion and
emulator exit. The matrix covers explicit/default CONFIG pages, DOS country,
external tables and uppercase APIs, NLSFUNC/CHCP transitions, unchanged-page
country switches, foreign-country queries and rejected page/country selections.
Private wrong-case and wrong-collation controls fail at expected stages. Existing
Russian country regressions pass; real-BIOS, resource and installation gates
remain separate requirements.

The [Baltic keyboard implementation qualification](../locales/baltic/keyboard-qualification.json)
records `test-baltic-keyboard-records` and `test-baltic-keyboard-qemu`, included
in `make test`. Static checks cover the expanded library and preservation of
the original Russian body. Physical QMP events exercise direct reference planes,
Caps, reachable dead-key pairs and control/navigation input through enhanced
BIOS and DOS CON reads. Corruption controls detect a wrong national letter,
suppressed FF and a scan-bearing E0 character. Russian physical/modifier/
resource regressions and expanded-library RU/GR reloads are retained separately.
The focused Baltic boots do not establish composed HIGH/LOW, legacy BIOS,
installed profiles or full pending-composition lifecycle behavior.

The [Baltic keyboard profile qualification](../locales/baltic/keyboard-profile-qualification.json)
records HIGH/LOW physical input and corruption gates, grouped composition
lifecycle checks, and layout/ID selection and rejection. Runtime memory probes
must pass before and after successful input. Selection phases check status,
physical bytes and guest completion; failed selections preserve the active
layout. The EE explicit-ID case guards the shared ET/EE directory group.
`test-baltic-keyboard-lifecycle-qemu` and `test-baltic-keyboard-selection-qemu`
are included in `make test`. Pending composition across mode/reload boundaries,
additional modifier/fallback edges, deep library validation and legacy BIOS
remain open; these gates do not establish installed or complete text workflows.

The [Baltic pending-state qualification](../locales/baltic/keyboard-pending-qualification.json)
records `test-baltic-keyboard-pending-qemu` and the extended mode lifecycle
matrix. Physical acknowledged Caps transitions arm accents without consuming
them. HIGH/LOW BIOS and DOS reads prove fresh state after Baltic mode/reload
selection and preserved state after missing-file/invalid-ID or insufficient-
capacity rejection. German
self-reload preserves its legacy pending state. Each selection probe also checks
that the resident limit is valid within its MCB and constant across reloads.
Private controls disable the reset feature or omit the capacity-preservation
store; both must fail. Further failure/page-transition cases and the remaining
real-BIOS, installation and release gates are separate requirements.

The [Baltic legacy keyboard qualification](../locales/baltic/keyboard-legacy-qualification.json)
records `tests/test_baltic_legacy_keyboard_86box.py` on real IBM AT and XT BIOS
with AT-84 and XT-83 keyboards and DOS LOW. Both BIOS and DOS reads cover each
language's reachable physical planes and every reference dead-key pair. The adapter
rejects loss of required national letters when filtering unavailable hardware
keys. It uses Ctrl+Alt for third level and keypad navigation with legacy scan
words. Guest probes check country tables before and after CP775 activation,
resident keyboard type, output bytes, empty input queue and modifier release.
Runs retain physical event oracles, expected bytes, logs, configurations and
core/resource/backend/ROM hashes, and require successful guest-controlled exit.
Legacy load failures, installed language profiles and complete workflows remain
open. The VNC backend requires sequential
runs and is invoked explicitly with `--emulator` and `--roms`.

The [Baltic real-BIOS display qualification](../locales/baltic/display-286-qualification.json)
records `tests/test_baltic_display_86box.py` on IBM AT BIOS with DOS LOW.
The guest selects CP775 at every supported height and exports the actual VGA
font plane and Unit Tester screen capture. The host compares all glyph rows
and rendered grid pixels, including VGA ninth-column replication. A damaged
o-with-tilde slot must be the only glyph mismatch in the negative control.
All three language samples appear in the retained, visually reviewed captures.
The gate requires guest completion and successful exit; Estonian COUNTRY setup
does not qualify national country transitions or installed workflows.
The record includes the shared runner's CP866 height matrix, preserved EGA
pages and Russian corruption-control regression.

The [Baltic real-BIOS country qualification](../locales/baltic/country-286-qualification.json)
records `tests/test_baltic_country_86box.py` on IBM AT BIOS with DOS LOW.
Every language passes explicit CP775/437/850 and default CONFIG selection.
The shared transition plan changes national records on CP775, cycles supported
pages, performs foreign queries and rejects absent country/page selections;
full probes verify the active state afterward. Case and collation corruption
must fail at the expected probe stages with guest-controlled failure exit.
The record retains the complete QEMU HIGH/LOW rerun, identical guest probes,
plan parity and Russian real-BIOS regressions. Missing or structurally malformed
resources and installed/complete language workflows remain separate open gates.

The [Baltic installation qualification](../locales/baltic/installation-qualification.json)
records `test-baltic-install-qemu`, included in `make test`. Fresh installation
and upgrade verify all payload bytes, English defaults, preserved startup and
an unrelated file. Each installed language recipe boots in HIGH/UMB and LOW;
physical BIOS input, resident language/page/ID, country APIs, active code page,
font-plane bytes and rendered pixels must pass with guest-controlled exit.
The record retains deterministic distribution and developer-media checks,
Russian installation regression and unchanged default probe/grid behavior.
These selected-core results cover normal installed paths. Resource failures,
complete application/file workflows and the final source-matched release remain
open acceptance requirements.

The [Baltic keyboard resource qualification](../locales/baltic/keyboard-resource-qualification.json)
records `test-baltic-keyboard-resources-qemu`, included in `make test` for BIOS
and DOS input. Malformed outer records must be rejected without losing the
resident language, physical input, pending composition or allocation bound;
a valid reload follows each rejection. The inventory distinguishes pointer,
short-read and length-boundary cases. Deeper inner-table validation, other
directory/ID forms and installed/legacy failure workflows remain separate
acceptance work.

The [Baltic font resource qualification](../locales/baltic/font-resource-qualification.json)
records `test-baltic-font-resources-qemu`, included in `make test`. Each language,
HIGH/LOW profile and font height rejects missing/malformed CP775 resources.
The gate distinguishes unchanged selection after open failure from DISPLAY's
inactive prepared slot after bad data, then requires recovery through valid
PREPARE/SELECT. Actual VGA glyph rows, full plane identity and country services
are checked before/after errors and recovery. This qualifies QEMU resource
handling; installed paths, real-BIOS failure cases and application workflows
have separate qualification below.

The [Baltic text qualification](../locales/baltic/text-qualification.json)
records `test-baltic-text-qemu` and `test-find-sbcs-qemu`, included in `make test`.
Physical shell/editor input creates, edits, saves and reopens CP775 text, then
checks redirection, FIND filtering, exact file bytes and rendered glyph pixels.
The FIND regression covers high-byte line endings and detects the previous
cross-line match with the old executable. Backend and memory-profile scope,
Russian regressions and native command results are recorded explicitly.
Filename/directory and fresh-boot checks have separate qualification below;
installed workflows have separate qualification below.

The [Baltic filesystem qualification](../locales/baltic/filesystem-qualification.json)
records `test-baltic-files-qemu`, included in `make test`, and the real-BIOS
286 LOW matrix. It checks national short names, alternate case, wildcard and
country-specific DIR ordering, MOVE/XCOPY trees, raw FAT names and parent links,
then fresh-boot reads and deletion. Estonian names beginning with CP775 E5
exercise FAT's 05 escape. Russian filesystem regressions cover shared runner
changes; installed paths and source-matched release remain separate gates.

The [Baltic country resource qualification](../locales/baltic/country-resource-qualification.json)
records `test-baltic-country-resources-qemu`, included in `make test`. NLSFUNC
must reject missing files and invalid headers after a previous valid read,
preserve the active country state and recover when the valid file is restored.
The old executable demonstrates that the signature-corruption oracle detects
acceptance. Deeper directory/object validation, boot fallback, installed paths
and real-BIOS failure cases remain separate requirements.

The [country directory qualification](../locales/baltic/country-directory-qualification.json)
extends the same resource gate to missing count bytes and malformed object
lists. Actual read bounds, complete record extents and length overflow are
checked before any DOS table write. Old-executable controls detect an accepted
query and an accepted country switch. The scan qualification below covers
country-directory records; the data qualification below covers object data,
while later media read transactions remain open.

The [country scan qualification](../locales/baltic/country-scan-qualification.json)
adds complete directory-count/record validation to the resource gate. It
checks malformed records after a candidate match, valid padded records across
buffer/offset boundaries, rejection with prior-state preservation and recovery.
Old executables provide accepted-query controls. Backend/profile scope and
country, resource and legacy regressions are recorded explicitly.

The [country data qualification](../locales/baltic/country-data-qualification.json)
adds complete object reads, signatures, resident payload capacities, filename
counts and DBCS termination to the resource gate. It retains the old executable's
accepted EOF-data query and per-language HIGH/LOW rejection/state/recovery logs.
`test-nlsfunc-dbcs-query-qemu`, included in `make test`, checks the existing
nonempty DBCS query records and unchanged Baltic state in HIGH/LOW. This does
not qualify DBCS installations or rollback after later media errors.

The [installed resource qualification](../locales/baltic/installed-resource-qualification.json)
records `test-baltic-installed-resources-qemu`, included in `make test`. It
exercises country/font rejection and recovery through installed paths in each
Baltic HIGH/LOW profile, checks actual VGA font bytes and active country state,
and finishes with physical national input and restored payload hashes. It
covers runtime failures at the shipped font height; boot fallback, real-BIOS
installed failures remain a separate gate; installed text/file workflows have
qualification below.

The [country boot qualification](../locales/baltic/country-boot-qualification.json)
records `test-baltic-country-boot-qemu` and `test-nlsfunc-filecase-qemu`, both
included in `make test`. Malformed-country boots must preserve the default
country/API table snapshot and recover to each Baltic profile. Legacy
filename-uppercase queries must accept both shipped signatures. Retained
controls expose partial boot initialization, rejection of valid legacy data,
and a deliberately non-default snapshot. The rebuilt private core has matched
memory, installation and country regressions with explicit backend scopes;
full workflow and release qualification remain separate gates.

The [current-core workflow qualification](../locales/baltic/current-workflows-qualification.json)
repeats the existing Baltic text and filesystem gates in QEMU HIGH/LOW with
the rebuilt country-boot core. It checks the actual core and utility hashes
in every image, physical text input, saved/reopened CP775 bytes, rendered
glyphs, national short-name operations and fresh-boot reads/cleanup. Retained
events, screenshots, raw directory captures and guest logs establish this
backend scope. Installed and real-BIOS workflows have matching-core
qualification below; final release gates remain open.

The [installed workflow qualification](../locales/baltic/installed-workflows-qualification.json)
records `test-baltic-installed-workflows-qemu`, included in `make test`. Its
default run creates fresh/upgraded installations and then exercises physical
text editing and national filename workflows through installed paths in each
language's HIGH/LOW profile. It checks all installed payloads, the root shell,
startup recipes, rendered text, saved bytes and FAT16 directory data, including
a fresh boot for filename reads and cleanup. Root utilities that could hide
the installed EDLIN or FIND are rejected before boot. `--installed-run` can
reuse a completed installation only when its payload hashes match current
inputs. Real-BIOS workflow and release scopes remain separate requirements.

The [real-BIOS resource qualification](../locales/baltic/resources-286-qualification.json)
records the manual `tests/test_baltic_resources_86box.py` gate. On the IBM AT
286 VGA LOW profile, failed country boots must match the clean default table
snapshot before recovery. Runtime country failures must preserve the active
national tables and recover after restoring the resource. Each supported font
height must reject malformed CPI data, preserve actual VGA glyph bytes and
recover through valid preparation/selection. Every case requires guest-requested
emulator exit zero. The record includes exact mutations, startup files, logs,
font and country captures, selected core/resource hashes and backend identities.
Physical input, rendered application text and installed paths have separate
workflow gates; this suite does not replace the full release requirements.

The [current-core 286 workflow qualification](../locales/baltic/current-286-workflows-qualification.json)
repeats the Baltic text and filename workflows on real IBM AT BIOS with the
rebuilt core. Physical input, saved/reopened CP775 bytes and actual rendered
text are checked for every language. Filename operations include raw FAT12
entries and reads/cleanup after a fresh boot. All guests must request emulator
exit zero. The record preserves the exact input sources used by this run,
backend/core/resource identities, keyboard events, screenshots and directory
captures. Legacy keyboard lifecycle and final release gates remain separate.

The [Baltic pristine build qualification](../locales/baltic/pristine-qualification.json)
records independent `make -j1`, `-j4` and `-j8` builds of the declared artifacts
and composed production core with identical pinned host tools. Core hashes
match the Baltic runtime-qualified candidate; build logs, source identities
and linker maps are retained. Full `FAIL_ON_SKIP=1 make test`, deployment and
distribution checks remain separate release gates. The pristine checkout is
used for those checks because the primary checkout's ordinary HIMEM artifact
differs from the pristine output; the selected composed HIMEM matches.

## External DOS API suite

`make test-dosemu2-qemu` runs selected upstream DOSEMU2 FAT tests against the
matched guest DOS in LOW and HIGH/UMB modes. This is an independent optional
gate, not a replacement for the maintained contract inventories. See
[setup, licensing, and scope](DOSEMU2.md).

`make test-compat-bpb-qemu` checks true-version HMA flags in LOW, HIGH/UMB,
and no-HIMEM fallback, then verifies guest BPBs and file read/write against
private mtools FAT12/FAT16 disks. Malformed BPBs must retain the legacy fallback
without adopting invalid fields. Optional external Microsoft inputs characterize
retail differences; expected DPB mismatches are recorded explicitly. See the
[qualification record](compat_bpb_qualification.json) for cases, controls,
matched memory regressions, and scope.


The [focused Baltic legacy lifecycle qualification](../locales/baltic/legacy-lifecycle-focused-qualification.json)
records `tests/test_baltic_legacy_lifecycle_86box.py` for the Estonian XT BIOS
malformed-library family. The manual gate reuses independent mode, selection,
resource and pending-accent oracles with physical legacy-key adaptations.
It checks per-phase status, resident keyboard type, exact BIOS/DOS bytes,
command rejection, pending-accent preservation and valid reload recovery.
Cached guest probes retain per-phase indices and fit the full malformed-library
set on XT media. The default gate covers both input interfaces and every family;
AT and XT runs must be sequential because they use the VNC keyboard port.
Full lifecycle qualification remains pending; the linked record claims only
the completed focused case and verifies its probes against the retained image.


The [Baltic release residency audit](../locales/baltic/residency-qualification.json)
retains the stale dispatcher-size failure from the pristine full suite, the
linked instruction audit and the passing `test-dos-bios-residency` rerun.
The assertion includes the existing true-version HMA flag instructions and
continues to require the exact audited size and valid relocation boundaries.
This focused repair does not qualify the full release suite.


The [legacy cross-page selection qualification](../locales/baltic/legacy-selection-qualification.json)
records the corrected AT BIOS selection run. Successful CP866 reloads require
a second prepared DISPLAY slot; the gate derives additional font pages from
its phase plan and records the prepared pages. It retains the original
unprepared-page failure, passing physical selection/rejection/reload results,
XT media-capacity check and byte-identical ordinary guest payload regressions.
Full AT/XT BIOS/DOS lifecycle completion remains a separate requirement.


The [additional Baltic release qualification](../locales/baltic/extra-release-qualification.json)
records pristine ordinary-baseline `test-286-acceptance`, the historical baseline
memory/kernel matrix and Baltic/CP866 static contracts. The runtime commands
use `MEMORY_PROFILE=baseline` and `FAIL_ON_SKIP=1`. All declared ordinary
artifacts still match the pristine build record. Logs, linker maps and backend
identities are retained; historical 286 marker/persisted-result checks are
scoped separately from composed-core guest-exit workflows. Full default release
and final deployment/distribution remain independent gates.

The [Baltic default release qualification](../locales/baltic/release-qualification.json)
retains the complete pristine `FAIL_ON_SKIP=1 make -k -j1 test` log and the
subsequent `make -j1 deploy distribution` log, with matching composed-core,
deployed-resource and installation-disk hashes. Its source revision and later
manual legacy-helper changes are recorded separately; this run does not replace
the dedicated AT/XT lifecycle matrices or final acceptance audit.

The [current-core Baltic display comparison](../locales/baltic/current-display-qualification.json)
retains the full release suite display results and records exact font-plane and
screen-hash agreement with the previously reviewed HIGH/LOW captures at every
height, including the wrong-glyph controls.

The [complete Baltic AT lifecycle qualification](../locales/baltic/legacy-lifecycle-at84-qualification.json)
checks BIOS/DOS mode switching, aliases/IDs, reloads, malformed-library
preservation and pending accents. German pending tests use physical Caps Lock
to clear the legacy BIOS flag; Shift clears it only on enhanced keyboards.
Retained component runs distinguish the initial barrier failure from corrected
German runs and unchanged successful cases. Every completed probe, phase action
and resource is checked against its actual guest image.

The [XT test-media capacity record](../locales/baltic/legacy-media-qualification.json)
checks complete Latvian/Lithuanian mutation payloads and batch files on 360 KiB
images, with unchanged guest files across the checked FAT cluster layouts.
The host capacity checks intentionally stop before emulator launch. The same
record separately retains passing Lithuanian BIOS/DOS resource-recovery runs
on the corrected images, with every mutant and compiled probe checked against
the actual media.

The [complete Baltic AT/XT lifecycle qualification](../locales/baltic/legacy-lifecycle-qualification.json)
retains all 36 mode, selection, resource and pending-accent cases per machine,
covering both BIOS and DOS input with successful emulator exits. Retention
rebuilds probes and checks phase actions and resource bytes against each actual
guest image. Composite results retain the earlier media-creation failures and
the successful component runs; they do not claim a single uninterrupted run.
