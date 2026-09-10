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

## Typed text workflows

[Text qualification](text-qualification.json) records physical COMMAND and
EDLIN workflows with CP775 files. The samples include every required national
letter in both cases, mixed ASCII and reference dead-key compositions where
available. Keys are injected physically; sample files are created by the guest.
The gate checks shell backspace editing, EDLIN insert/replacement/save/reopen,
redirection and a FIND pipeline. Saved file bytes and rendered glyph pixels
must agree with the expected text.

Run `make test-baltic-text-qemu` for the HIGH/LOW QEMU matrix. The wrapper also
accepts `--emulator`, `--roms` and `--qt-platform` for the real-BIOS LOW backend,
using the qualified VNC console. The record distinguishes backend results.

The workflow exposed FIND reading beyond a line whose last byte is a non-ASCII
single-byte character. It could match text on the following line and report
both lines. The corrected character-advance routine stops when no bytes remain.
`make test-find-sbcs-qemu` covers every high-byte line ending with ASCII and
national search strings, including inverted selection; the old executable is
a retained failure control. Existing native command tests and Russian text
workflows regress separately.

National filename/directory operations and fresh-boot reads have separate
filesystem qualification below. Installed-path workflows and final
source-matched release qualification remain open.

## National filenames and directories

[Filesystem qualification](filesystem-qualification.json) records CP775 short
names in COMMAND, MOVE and XCOPY on QEMU HIGH/LOW and real-BIOS 286 LOW.
The guest creates files with every required national letter, uses alternate
case for lookup, and exercises wildcard selection, name/extension sorting,
reverse name sorting, rename, recursive copying and empty directories.
Expected ordering comes from the frozen per-country collation tables.

The Estonian sample deliberately starts file and directory names with capital
O with tilde (CP775 byte E5). Raw FAT entries must use the live-name escape byte
05;
a deleted-entry marker cannot satisfy the directory oracle. Raw nested entries,
file contents and parent-cluster links are checked before reboot. A fresh boot
must read the saved data, preserve directory ordering and clean up both copied
trees successfully. The sample commands run from CP775 batch files; physical
keyboard input is covered separately by the text and keyboard gates.

Run `make test-baltic-files-qemu` for QEMU. The wrapper accepts `--emulator`,
`--roms` and `--qt-platform` for the real-BIOS LOW backend. This qualification
uses private floppy images and the recorded selected core. Installed hard-disk
paths and final source-matched release qualification remain separate work.

## Country resource headers

[Country resource qualification](country-resource-qualification.json) covers
NLSFUNC queries and country selection after the resident service has already
read a valid resource. Missing files, empty and short headers, damaged signature
bytes and an unsupported information type must be rejected. The full active
country/page/case/collation probe must still pass, and restoring the valid
resource must allow a query and successful country switch without reboot.

NLSFUNC now checks the returned header length and the COUNTRY signature before
using buffered offsets. Previously a damaged signature could be accepted.
The old executable is a failure control for the guest gate. Run
`make test-baltic-country-resources-qemu` for the per-language HIGH/LOW matrix.

This is runtime header validation. The control-block checks below extend it.
The directory scans below add record validation. Object data offsets and
bodies, transactional preservation after a later read fails, CONFIG.SYS boot
fallback, real-BIOS resource failures and installed-path failures remain open.


## Country control blocks

[Country directory qualification](country-directory-qualification.json)
extends runtime rejection to out-of-file directory/object-list pointers,
missing count bytes, empty or excessive object counts, incomplete lists and
object records with short, oversized or overflowing lengths. NLSFUNC records
the bytes actually read and validates the complete object list before it can
copy any table into DOS. Valid records may retain additional trailing bytes;
the check requires their mandatory fields to fit within the declared record.

Old-executable controls demonstrate accepted queries with an undersized record
and an accepted country switch with an object-list pointer at EOF. The guest
gate checks rejection, the complete prior active-country state and recovery
with a valid file. The record distinguishes the new HIGH/LOW language matrix,
the focused header regression, and existing country/legacy regressions.

The country-record scan below adds directory entry/count validation. Object
data checks are covered by the qualification below; later read-failure
transactions remain open. These control-block checks
do not qualify CONFIG.SYS boot fallback or real-BIOS/installed failure paths.


## Country-record scan

[Country scan qualification](country-scan-qualification.json) records validation
of the complete declared country directory before using a matching record.
Zero counts, undersized records, incomplete trailing records, excessive counts
and missing record padding are rejected. The old scanner could accept a match
even when the directory declared no entries or the matching record was short.

The scanner uses a doubleword file cursor and validates record extents. It
preserves the first country/page match while checking the remaining directory.
Valid padded records crossing buffer and file-offset word boundaries must
still support queries and country switches. The qualification includes
negative controls, valid padding controls, prior resource regressions and
country/API regressions; its backend and profile scope is explicit.

The object-data qualification below extends these checks. Transactional
behavior on later media read failures remains open, along with boot fallback,
installed paths and final source-matched release qualification.


## Country object data

[Country data qualification](country-data-qualification.json) covers NLSFUNC
object signatures, declared payload lengths and actual read counts. The loader
preflights every declared object before writing DOS country tables, then repeats
the check when loading each object. A pointer at EOF previously passed an
external query; the retained old-executable control demonstrates that failure.

Known object sizes are bounded by the resident allocations in
[DOSMES.ASM](../../src/DOS/DOSMES.ASM), with exact limits recorded in the
qualification. The filename delimiter count must fit its payload; DBCS lengths
must be even and nonempty lists must end with a zero word. Unknown extension
IDs remain bounded by the external-query buffer.

The resource matrix checks truncation, signatures and invalid lengths for all
shipped object types, plus filename-list counts and DBCS termination, in
all three languages on HIGH and LOW. Each rejected query/switch is followed by
complete active-country checks and valid-resource recovery. The record also
includes earlier resource cases on ET LOW, Baltic/Russian country regressions,
legacy utilities and valid transitions on a real-BIOS 286. Fresh installation,
upgrade and installed language profiles were rerun with the current resources,
checking installed hashes, country state, physical input and rendered fonts.

`make test-nlsfunc-dbcs-query-qemu` verifies that the existing nonempty DBCS
records remain externally queryable from a Baltic HIGH/LOW environment, with
unchanged active Baltic state. This is a compatibility check for those records,
not qualification of installed DBCS environments. Preflight and repeated read
validation do not provide rollback for a media error after an earlier table
has already been copied. Installed failures and boot fallback have separate
qualification records below; final release gates remain open.


## Installed resource failures

[Installed resource qualification](installed-resource-qualification.json)
checks missing and malformed country/font resources through the shipped
`C:\DOS` startup paths. The gate uses private copies of completed installation
images and verifies their core, resource and documentation hashes against
current inputs before use. Its default invocation creates those installations;
`--installed-run` may reuse a completed, matching installation run.

Country queries and switches must reject invalid files with the expected DOS
error, preserve the active national tables and recover when the file is
restored. Font failures follow the documented DISPLAY behavior: a missing file
preserves active selection, while an opened invalid file leaves the requested
slot inactive until a valid prepare/select. The actual VGA font bytes remain
intact throughout. These checks use the shipped font height and both memory
profiles for every language.

Every profile finishes with physical national keyboard input and a check of
all restored installed payloads. The retained record links the installation
baseline, commands, exact mutation scope, memory/core identities, logs, startup
files and font captures. Boot fallback is covered below. Real-BIOS installed
failures and later media-error transactions remain separate gates. Installed
text/file workflows are qualified below; final source-matched release remains
open.


## Country boot fallback

[Country boot qualification](country-boot-qualification.json) covers BIOS
country loading in each Baltic HIGH/LOW profile. A truncated collation object
previously left the requested country/page and formatting installed alongside
default case tables. The boot loader now validates the complete control lists
and object data before writing DOS tables, then validates each object again
when loading it. It retains the boot loader's fixed-buffer directory limits;
NLSFUNC's wider runtime directory scan has separate qualification.

The boot oracle compares country/page identifiers and country-format,
uppercase, filename, collation and DBCS tables with a clean default boot.
Runtime pointer addresses are normalized. Each invalid-file case then restores
a valid resource and checks recovery to the requested Baltic profile. The
record retains the original partial-initialization failure and a valid-file
control that must fail the fallback comparison.

Both loaders accept the shipped `UCASE` and legacy `FUCASE` filename-uppercase
signatures. `make test-nlsfunc-filecase-qemu` checks external queries against the
retained legacy expectations and preserves the active Baltic state. Valid and
damaged alternative signatures also run through the resource gate. The earlier
NLSFUNC binary's rejected valid query is retained as a regression control.

The rebuilt private core includes existing repository kernel and HIMEM updates.
Its qualification retains build inputs, matching maps, the memory fault matrix,
country/API and legacy regressions, fresh/upgrade installation and installed
resource failures. Real-BIOS country boots/transitions require guest-triggered
emulator completion. The legacy memory-fallback harness instead checks guest
markers and a persisted result before stopping the backend; its scope is
recorded separately.

Earlier workflow records apply to their recorded cores. Installed text/file
workflows and real-BIOS resource failures are qualified below. Later media-error
rollback and full source-matched release/reproducibility remain open for this
core.

## Current-core workflow checks

[Current-core workflow qualification](current-workflows-qualification.json)
repeats the QEMU HIGH/LOW text and filesystem workflows with the private core
from country-boot qualification. Physical keyboard input creates and edits
each language's CP775 text in COMMAND and EDLIN; saved/reopened bytes,
redirection, FIND output and rendered glyphs must match the language samples.
National filename batch workflows check case lookup, wildcards, country DIR
ordering, copies and directory trees, followed by raw FAT inspection and a
fresh boot for reads and cleanup.

The record checks the core and utility bytes actually present in each image
and retains input events, text files, screenshots, directory captures and guest
logs. This refresh applies to QEMU HIGH/LOW. Real-BIOS workflow evidence must
also match the selected core. Installed text/file workflows are qualified
below; the final release/reproducibility gates remain open.

## Real-BIOS resource recovery gate

[Real-BIOS resource qualification](resources-286-qualification.json) retains
the country and font failure/recovery matrix with the rebuilt private core.
`tests/test_baltic_resources_86box.py` exercises country boot fallback, runtime
country rejection and CP775 font recovery on the IBM AT 286 VGA LOW profile.
Select the matching private core and supply the locally built emulator and
licensed ROM directory:

```sh
MEMORY_CORE_DIR=out/baltic-country-boot-core2/files \
python3 tests/test_baltic_resources_86box.py \
  --emulator /path/to/86Box --roms /path/to/roms \
  --qt-platform offscreen --jobs 2
```

The default run covers every Baltic language and supported font height.
`--language`, `--family` and `--height` select focused cases. The software
renderer permits isolated concurrent cases without a shared VNC port; each
guest must request a successful emulator exit within `--timeout` seconds.
The results record the exact mutation scope, core/resource hashes, startup
commands, guest markers, country snapshots and font-plane hashes. Country
fallback must match a clean default boot before restoring the national profile.
Font checks distinguish missing-file selection preservation from the inactive
slot after opened invalid data, and require valid-resource recovery.

This gate captures actual font bytes; physical typing, rendered application
text, installed paths and HIGH/UMB behavior have separate workflow gates.

## Installed application workflows

[Installed workflow qualification](installed-workflows-qualification.json)
exercises COMMAND/EDLIN text input and national filenames on private copies of
fresh/upgraded installations. `make test-baltic-installed-workflows-qemu`
creates the installations by default; `--installed-run` can reuse a completed
run whose core and complete installed payload hashes match current inputs.

Every language runs in HIGH/LOW with its installed CONFIG recipe and startup
commands. The test adds `PATH C:\DOS` for interactive utility lookup and rejects
root copies of EDLIN or FIND that could hide the installed versions. Physical
input exercises editing, save/reopen, redirection and pipes; exact CP775 bytes
and rendered glyphs must match the language samples. The filename gate uses
installed MOVE/XCOPY and checks national case, wildcards, country ordering,
directory trees, raw FAT16 entries and reads/cleanup after a fresh boot.

All installed payloads, the default root COMMAND and the baseline images must
remain intact. The record retains commands, input events, text and directory
bytes, screenshots and guest logs. This gate qualifies installed QEMU HIGH/LOW
workflows; real-BIOS workflow and final release/reproducibility gates must be
qualified against the selected core separately.

## Current-core real-BIOS workflows

[Current-core 286 workflow qualification](current-286-workflows-qualification.json)
repeats text and filename workflows with the rebuilt private core on IBM AT
BIOS in LOW memory. Every language passes physical COMMAND/EDLIN input,
save/reopen, redirection, FIND and rendered-glyph checks. National filenames
pass case lookup, wildcard and country ordering checks, directory tree
operations, raw FAT12 inspection and reads/cleanup after a fresh boot.

Each guest requests a successful emulator exit. The record retains screenshots,
keyboard events, file and directory bytes, startup configurations and logs,
and verifies core/resource hashes in each image. Input source snapshots preserve
the version used by the run. Installed paths and HIGH/UMB have their separate
qualification above; legacy keyboard reload/rejection/pending checks and final
release/reproducibility gates remain open.

## Pristine build comparison

[Pristine build qualification](pristine-qualification.json) compares independent
serial/parallel builds at the recorded source commit. All declared ordinary
artifacts and the composed core agree byte for byte. The composed core also
matches the candidate used by the Baltic runtime checks. Retained build logs,
tool hashes and linker maps preserve the build evidence.

The record distinguishes checkout line endings from source changes: affected
linker/control files differ only by CRLF versus LF. It also records the primary
checkout's different ordinary HIMEM binary; release runtime checks use the
pristine checkout. Full runtime, deployment/distribution and remaining legacy
keyboard acceptance must pass before the Baltic increment closes.

## Legacy keyboard lifecycle gate

`tests/test_baltic_legacy_lifecycle_86box.py` runs the Baltic mode, selection,
malformed-library and pending-accent plans on real IBM AT and XT BIOS. Run
one machine at a time because the physical VNC keyboard uses a shared loopback
port:

```sh
MEMORY_CORE_DIR=out/baltic-country-boot-core2/files \
python3 tests/test_baltic_legacy_lifecycle_86box.py \
  --emulator /path/to/86Box --roms /path/to/roms \
  --qt-platform offscreen --machine at84
```

Repeat with `--machine xt83`. The default runs BIOS and DOS input for every
family. `--family`, `--language`, `--scenario` and `--input` allow focused runs;
the language filter applies to the resource family. Legacy third-level input
uses left Ctrl+Alt, and navigation uses the keypad with Num Lock restored.
The selected hardware has no separate right Ctrl/Alt or ISO scan-86 key.

Every phase checks keyboard status and physical input against the independent
language oracle. Rejected loads must preserve the resident layout and pending
accent, and valid reloads must recover. A guest acknowledgment separates arming
a pending accent from releasing Caps Lock. Identical phase probes are shared
with a checked hexadecimal starting index so the complete resource matrix fits
on XT media. Command error checks and physical input checks remain per phase.

The [focused lifecycle qualification](legacy-lifecycle-focused-qualification.json)
retains the completed Estonian XT BIOS resource case, including guest logs,
physical events, core/resource hashes and startup files. During retention, the
current plans and compiled probes reproduce the actions and bytes in that
completed image. This is focused evidence; the full AT/XT BIOS/DOS matrices
remain open until their complete results are retained.


The [residency census audit](residency-qualification.json) records a release
preflight failure and its repair: the dispatcher expectation predated the
existing true-version HMA flag fix. Inspection of the linked instructions
accounts for the size change, and the complete DOS/BIOS residency target passes
with the corrected expectation. Production bytes are unchanged. The full
release suite still requires a successful rerun.


[Legacy cross-page selection qualification](legacy-selection-qualification.json)
retains the complete AT BIOS selection plan, including Baltic aliases/IDs,
rejected loads and Russian/German reloads. This plan prepares CP866 in a second
DISPLAY slot alongside CP775 before requesting a successful Russian reload.
The initial failure record shows why preparing only CP775 was insufficient.
The corrected complete selection image also fits XT media; actual XT execution
remains part of the full lifecycle gate.

Other legacy plans keep their single prepared page. Reconstructed Russian and
Baltic resource images preserve every guest payload and startup command from
their previously passed images byte for byte. The qualification distinguishes
these image checks from the completed physical AT selection run.


## Additional release gates

[Additional release qualification](extra-release-qualification.json) retains
the pristine ordinary-baseline IBM AT acceptance and historical memory/kernel
matrix, plus the Baltic and CP866 static contracts. All declared ordinary
artifacts still match the pristine build hashes. The record preserves commands,
source identity, backend hashes, logs and ordinary linker maps.

These baseline gates complement the composed-core country, memory and workflow
records. The historical 286 shell tests verify guest markers and persisted
results before host termination, using their documented private driver/probe
variants. They have a different scope from the composed-core workflows that
require guest-triggered emulator exit. Full default release and final
installation-media qualification remain separate requirements.
