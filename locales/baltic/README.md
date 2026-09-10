# Baltic locale inputs

[BALTIC.md](../../BALTIC.md) defines the Estonian, Latvian and Lithuanian
implementation and acceptance scope. This directory contains selected contracts
and focused country/font evidence. Complete installable language profiles
remain in progress.

[manifest.json](manifest.json) pins the Microsoft CP775 mapping and references
the existing local Cozette and 512_8 sources by path, revision and hash. Their
MIT, public-domain and Unicode license notices remain with the original inputs.
Builds and audits require no downloads. The [country contract](country-contract.json) selects national formatting and
explicit DOS sorting rules. The [keyboard contract](keyboard-contract.json)
selects the national input profiles. Unicode mapping alone defines neither.

Run `make test-baltic-font-sources` for independent encoding, language-letter,
candidate-coverage, retained-output and corruption checks. It is included in
`make test`. The shared auditor accepts an explicit locale directory:

```sh
python3 tools/audit_ru_fonts.py --locale locales/baltic
python3 tools/audit_ru_fonts.py --locale locales/baltic --check
```

[font-audit.json](review/font-audit.json) records every glyph's source, rows and
status. Candidate contact sheets are [8x8](review/contact-8x8.png),
[8x14](review/contact-8x14.png) and [8x16](review/contact-8x16.png). Missing glyphs
are marked rather than silently substituted. These unmodified candidates are
retained separately from the selected glyphs and their qualification below.
The Russian auditor's default invocation and retained outputs are preserved.

The [contract research record](contract-research.json) identifies candidate
keyboard references and the limitations of current country data. Selected
contracts and their pending runtime qualification are recorded separately.

[Foundation qualification](foundation-qualification.json) retains the command,
log and review hashes, including the existing Russian source/CPI regressions.

The [country contract qualification](country-contract-qualification.json) records
`make test-baltic-country-contract`. The [materialized expectations](review/country-expectations.json)
cover native CP775 and legacy CP437/850 modes. Formatting follows the pinned
historical DOSBox Staging parameter evidence; country identity to DOS 6.22 is
not claimed. Unicode CLDR national ordering informs explicitly listed DOS
letter groups. Lithuanian secondary distinctions become per-character weights;
this is not full Unicode word collation. Extra legacy-page letters have explicit
positions, and unrepresentable uppercase partners leave DOS bytes unchanged.

Run `python3 tools/baltic_country_contract.py --check` from the repository root
to verify the retained expectations. The materializer does not build COUNTRY.SYS;
production records and guest APIs are checked separately against its output.

[Keyboard contract qualification](keyboard-contract-qualification.json) records
`make test-baltic-keyboard-contract`. The pinned FreeDOS KEY sources and compiler
format documentation retain their GPL notices. A byte-preserving parser captures
CP775/common-table fallback, modifiers, composition pairs and explicit BIOS scan
remaps into [keyboard expectations](review/keyboard-expectations.json). It does
not emit resident code. ET/454, LV/default and LT/221 are the selected profiles;
other variants are deferred. Physical input and composition lifecycle still
require guest qualification.

[Country record qualification](country-record-qualification.json) records the
rebuilt COUNTRY.SYS and `make test-baltic-country-records`. The new Baltic objects
match retained expectations and every pre-Baltic object's contents are preserved,
including Russian. Case/collation corruption controls are included. Static
record correctness does not establish active CONFIG/NLSFUNC/CHCP behavior.

`make dev` builds EGA775.CPI using the shared font packer with explicit locale
inputs. [Font edits](font-edits.json) reuse the selected DOS control, border,
block and shade glyphs by Unicode identity, preserving their source licenses.
They do not copy CP866 byte positions into Baltic letter slots. Selected review
sheets are [8x8](review/selected-8x8.png), [8x14](review/selected-8x14.png) and
[8x16](review/selected-8x16.png); [selected-fonts.json](review/selected-fonts.json)
records glyph rows and hashes. The CP866 output remains byte-identical.

[Display qualification](display-qualification.json) records `test-baltic-cpi`
and the QEMU HIGH/LOW font matrix. The guest loads CP775 through DISPLAY/MODE,
checks memory-profile markers and captures the actual VGA font plane. The host
checks every glyph and strict completion/exit, retaining loaded bytes and screen
captures. A deliberately wrong o-with-tilde glyph must fail the same byte oracle.
Samples include all three languages. The Russian/existing EGA-page regression
matrix passes with the shared runner. Both new gates are included in `make test`.

Installed recipes and full release qualification remain separate open gates.
Physical input, real-BIOS country checks and rendering are recorded below. The font test's
Estonian COUNTRY selection does not establish country-API support for every
language, and rendered samples do not establish typed keyboard input.

[Country API qualification](country-qualification.json) records the full QEMU
HIGH/LOW CONFIG matrix and extended transition runs. Each language is tested
with explicit CP775/437/850 and default-page selection. Guest probes check
country formatting, external tables, far and INT 21h uppercase services,
filename rules and collation bytes. NLSFUNC/CHCP transitions verify active
DISPLAY and DOS page agreement. Country switches on CP775 must load the new
national tables; foreign-country queries and rejected selections must preserve
active state. Deliberate case and collation corruption fail at their expected
probe stages. Russian guest regressions pass with unchanged default probe bytes.

`make test-baltic-country-qemu` runs the matrix and is included in `make test`.
The Python runner accepts `--profile high|low` and `--case` for focused diagnosis.
Missing/malformed resource and installed-workflow checks remain open.
Real-BIOS country qualification is recorded below.

[Keyboard implementation qualification](keyboard-qualification.json) records
the generated supplemental library and focused physical BIOS/DOS input gates.
`make dev` builds KEYBRD2.SYS with ET (EE alias), LV and LT alongside the
unchanged Russian body. `make test-baltic-keyboard-records` checks generated
source, binary directories, common/page state boundaries, logic references and
allocation limits. Russian records retain their independent retail-table oracle
and a frozen hash of the original logic/common/page body.

`make test-baltic-keyboard-qemu` runs the retained key/plane and composition
expectations through physical QMP input, using private minimal-country boots
with the selected production core. It checks enhanced BIOS reads and DOS CON
reads separately. These are input-byte tests; they do not establish active font
selection or composed HIGH/LOW and installed profiles. Negative controls alter
a national translation, suppress nonbreaking space, and give a literal E0 byte
a scan code that DOS interprets as a special key.

DOS requires a zero scan code for literal E0; the generator applies that
transport rule while preserving explicit Lithuanian scan remaps. Latvian
nonbreaking space requires the new opt-in `LITERAL_FF` translation-table bit.
KEYB then uses its existing buffer routine that accepts FF characters. Tables
without this bit retain the original FF ignore behavior. The pack therefore
requires the matching project KEYB executable. The retained sources and their
notices remain linked from the selected keyboard contract.

Further keyboard profile and lifecycle qualification is recorded below.
Legacy BIOS input and complete language workflows remain open.
The Russian keyboard regression suite uses the same expanded library and
matching KEYB executable.

[Keyboard profile qualification](keyboard-profile-qualification.json) extends
the physical input matrix to HIGH/UMB and LOW with runtime profile probes
before and after input. `test-baltic-keyboard-qemu` now includes both profiles
for BIOS/DOS input and corruption controls. The selected library groups ET and
EE together for explicit ID lookup, allowing `EE /ID:454` to find the alias.
The record validator also rejects a regressed alias-group count.

`test-baltic-keyboard-lifecycle-qemu` checks grouped output for unmatched,
repeated and changed accents, pending accents followed by control/navigation
keys, cleanup after those sequences, modifier release and US/national hotkeys.
It runs BIOS and DOS reads on both memory profiles. Each group must leave the
keyboard queue empty and modifiers released.

`test-baltic-keyboard-selection-qemu` exercises defaults and explicit IDs,
Baltic/Russian/German transitions, unsupported pages, absent and mismatched
IDs, missing files, bad signatures and short headers. Each phase checks status
and physical input; rejected loads must preserve the active language. These
gates are included in `make test`.

Additional modifier and fallback edges, deeply malformed libraries, legacy
lifecycle checks, installation and complete language workflows remain open
requirements. Pending mode/reload boundaries are qualified below.

[Pending composition semantics](keyboard-pending-contract.json) define the
Baltic selection extension. Opted-in layouts cancel pending accents on US or
national selection and successful reloads. Entering Baltic from a legacy layout
also starts fresh. Rejected selections preserve pending composition; legacy
German self-reload retains its existing behavior.

[Pending-state qualification](keyboard-pending-qualification.json) records the
HIGH/LOW BIOS/DOS matrices and negative controls. A physical Caps transition,
acknowledged by the guest before the host releases it, lets the test arm an
accent without consuming it. Subsequent physical input proves either cancellation
or preservation. No host-written character substitutes for this input.

KEYB now preserves its original resident allocation limit when copying rebuilt
tables. The previous temporary FFFF value could erase that limit, letting a
later smaller library redefine the capacity. The guest checks a valid limit
within the resident MCB and unchanged limits across selection phases. Negative
controls disable selection reset or restore the omitted capacity copy; each
must fail its corresponding guest oracle. `test-baltic-keyboard-pending-qemu`
is included in `make test`.

Pending-state preservation on additional load-failure and page-transition paths,
legacy BIOS, installed language profiles and complete text/filename workflows
remain open. The matching KEYB executable is required for the selection-reset
feature as well as literal FF input.

The resident buffer does not grow on reload. Start KEYB from KEYBRD2.SYS when
Baltic switching is required. A dedicated test starts from the smaller original
German allocation and requires an oversized Baltic load to fail while preserving
the German layout, pending accent and allocation limit.

[Legacy keyboard qualification](keyboard-legacy-qualification.json) records
physical Estonian, Latvian and Lithuanian BIOS/DOS input on real IBM AT and XT
BIOS with AT-84 and XT-83 keyboards and DOS LOW. The host filters unavailable
right Alt/Ctrl and the extra ISO key, uses left Ctrl+Alt for third level, and
moves navigation
to the physical keypad. It asserts that every required national letter in both
cases and every reference dead-key pair remains reachable. Guest byte checks
also cover applicable Caps/Shift, punctuation, controls and modifier release.
Country API probes check the national tables before and after DISPLAY/KEYB
activation. These checks do not capture or qualify actual font glyphs.
The existing Russian physical BIOS matrix passes through the same AT harness.

Run the private-image gate with the qualified VNC-enabled, loopback-only backend:

```sh
MEMORY_CORE_DIR=out/memory-production/files python3 tests/test_baltic_legacy_keyboard_86box.py \
  --emulator "$BOX86_BIN" --roms "$BOX86_ROMS" --qt-platform offscreen --machine at84
```

The runner accepts `--language et|lv|lt` and `--input bios|dos` for focused
checks. Use `--machine xt83` for the qualified XT matrix. Run these VNC cases
sequentially because the backend uses a fixed port. The shared
harness reconnects during an initial command wait to recover an emulator
startup pause race; it sends no keys until the guest requests input and still
requires guest completion and successful exit.

Legacy reload/pending-state failures, installed profiles, complete language
workflows and final release qualification remain open.

[Real-BIOS display qualification](display-286-qualification.json) records
`tests/test_baltic_display_86box.py` on IBM AT BIOS with DOS LOW. It selects
CP775 through DISPLAY/MODE at every supported font height, exports the actual
VGA font plane, and captures the rendered screen through the emulator's guest
Unit Tester interface. The host checks every glyph's loaded rows and every
grid pixel, including VGA ninth-column replication. The retained captures show
samples for Estonian, Latvian and Lithuanian, alongside DOS symbols and borders.
An altered o-with-tilde glyph must be the sole mismatched slot in the negative
control. Guest completion and successful emulator exit are mandatory.
The same runner also passes the CP866 height matrix, existing EGA pages and
the Russian wrong-glyph control with its default arguments.

Invoke the display gate with the same `--emulator`, `--roms` and `--qt-platform`
arguments as the keyboard gate. It uses private images and accepts `--jobs 2`;
its software renderer does not use the keyboard backend's VNC port. The setup
uses Estonian COUNTRY for a shared-font check. Country transitions are qualified
separately below; installed paths and complete typed workflows remain open.

[Real-BIOS country qualification](country-286-qualification.json) records
`tests/test_baltic_country_86box.py` on IBM AT BIOS with DOS LOW. Each language
passes explicit CP775/437/850 and default CONFIG selection. The transition
sequence switches national records while retaining CP775, cycles supported
pages, and checks that foreign queries and rejected country/page selections
preserve the active country and tables. The probes verify formatting, far
uppercase, extended country tables, character/string uppercase, filename rules,
collation and agreement between DOS and DISPLAY code pages.

Wrong case and collation data must fail their expected probe stages and exit
the emulator with failure status. Normal cases require complete marker counts
and successful guest-controlled exit. The QEMU and real-BIOS runners share the
same case plan and produce identical guest probes; the record includes plan
parity, the full QEMU HIGH/LOW rerun and the existing Russian real-BIOS suite.
Logs, configurations, input hashes and ROM identities are retained.

Invoke the country gate with `--emulator`, `--roms` and `--qt-platform` as above.
It accepts `--jobs 2` and repeated `--case` selectors. Missing or structurally
malformed resources, installed paths, complete text/filename workflows and final
release qualification remain open.

## Optional distribution and installed profiles

[BALTIC.TXT](BALTIC.TXT) supplies the per-language CONFIG.SYS/AUTOEXEC.BAT
recipes. Distribution media and developer deployment include the shared CP775
font, keyboard attribution and upstream license notices. The supplemental
keyboard library and country records retain their existing distribution paths.

[Installation qualification](installation-qualification.json) records fresh
SETUP, upgrade over stale Baltic resources and boots using recipes read from
the installed document. The gate checks all installed payloads against their
selected sources, preserves English defaults and user startup files during
upgrade, and exercises each language in HIGH/UMB and LOW configurations.
Physical keyboard input, resident layout identity, country APIs, DOS/DISPLAY
page agreement, VGA font bytes and rendered grid pixels are checked together.
The font capture contains generated language samples; it does not establish
interactive COMMAND/EDLIN workflows. The shared Russian installation regression
and deterministic distribution checks are retained with the same record.

Run `make test-baltic-install-qemu` after selecting the production core through
the normal build. For an already built, explicitly selected core:

```sh
MEMORY_CORE_DIR=out/memory-production/files python3 tests/test_baltic_install_qemu.py
```

The screen oracle accepts an explicit backend ninth-column range. QEMU captures
use B0-DF; the existing real-BIOS oracle retains its C0-DF default. The record
includes the renderer reference, default probe binary parity and retained
real-BIOS grid regression. The installed probe hides the cursor for stable
captures and checks resident identity even when KEYB omits Latvian's default
ID zero from its status text.

These results qualify normal installed profiles on the recorded selected core.
They supersede the earlier installed-path gaps above. Installed resource-failure
cases, legacy lifecycle failures, complete text/filename workflows and final
source-matched release and reproducibility checks remain open.

## Keyboard resource rejection

[Keyboard resource qualification](keyboard-resource-qualification.json) covers
out-of-file directory/logic/page pointers, truncated headers and bodies, and
invalid logic, section and state lengths. The loader now checks short reads
before interpreting headers, bounds state traversal by its declared section,
and propagates common-section construction errors. Failed construction keeps
the resident tables intact; subsequent valid reloads must still work.

`make test-baltic-keyboard-resources-qemu` exercises ET, EE, LV and LT in
HIGH/LOW profiles through physical BIOS and DOS input. Each rejected load is
followed by input and resident-capacity checks. ET/EE and LV additionally arm
a reference dead key before rejection and require its composition afterward.
LT has no dead accents in the selected layout. The record separates this
focused pending-state check from the existing full accent matrix.

The same executable passes the full Baltic HIGH/LOW BIOS/DOS input matrices,
wrong-character controls and the Russian keyboard suite. All national layouts
also pass physical input on real XT BIOS. A retained old/new comparison checks
original-library command output and rejections across its language defaults and
identifier-directory selections. It preserves existing unsupported forms;
record presence alone does not establish that every command form is accepted.

This gate covers the outer record boundaries and read failures listed in its
mutation inventory. Inner logic opcodes and translation-table structure,
allocation-header arithmetic, additional directory/ID variants, installed
resource failures and legacy pending/rejection paths remain open. Existing
installation results predate this loader change and require a final rerun with
the release composition.

## Font resource errors and recovery

[Font resource qualification](font-resource-qualification.json) records missing,
empty, bad-signature and truncated CP775 files, out-of-file directory/font
pointers and an absent requested page. `make test-baltic-font-resources-qemu`
runs the cases for each language, HIGH/LOW profile and supported font height.
The probe reads the actual VGA font plane before rejection, after rejection
and after restoring the correct resource; every active glyph row must match
the shared CPI, and the entire plane must remain unchanged through recovery.
Country services are checked throughout.

The contract follows DISPLAY's existing distinction between opening a missing
file and failing a started preparation. A missing file leaves the selected
page intact. Bad font data invalidates the requested prepared slot; querying
DISPLAY returns its inactive status, and selecting that slot must fail. DOS
country state and the visible glyphs remain intact. Repeating valid MODE
PREPARE and SELECT restores prepared-font availability and DOS/DISPLAY page
agreement without rebooting. [BALTIC.TXT](BALTIC.TXT) documents this recovery.
An unchanged screen alone does not prove that DISPLAY still has a valid slot.

The dump-only and inactive-page probe options leave existing default probe
binaries unchanged. These QEMU checks do not replace rendered-font evidence,
real-BIOS resource-failure cases, installed-path failure tests or complete
application/file workflows. The shared driver behavior is unchanged.
