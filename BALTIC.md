# Baltic / CP775 implementation plan

## Scope and decisions

Deliver optional Estonian, Latvian and Lithuanian DOS environments using CP775:
readable text, physical national keyboard input, country services and national
characters in short filenames. All three languages are acceptance requirements;
a font alone or an Estonian-only implementation does not complete this item.
Keep English messages, Help and the default installation configuration.

Use a shared `EGA775.CPI` screen font and separate language keyboard/country
profiles. Extend the supplemental `KEYBRD2.SYS` while preserving its existing RU
layout and invocation. Preserve `KEYBOARD.SYS`, existing EGA.CPI pages and the
qualified CP866 font. Extend COUNTRY.SYS without changing existing record
semantics. These scoped additions do not claim complete retail supplemental
packs. Keep exact KEYB identifiers, layout IDs and country numbers provisional
until supported by references; ISO language codes and telephone prefixes are
not sufficient evidence for DOS command arguments.

Reuse KEYB, DISPLAY, MODE, CHCP, COUNTRY and NLSFUNC. Share the Russian pack's
font tooling and test infrastructure where practical, with explicit page and
locale inputs. Require unchanged CP866 output when refactoring common code.
Change drivers or the kernel only when a focused test demonstrates a missing
contract. Store new manifests, reference tables and qualification records under
`locales/baltic/`, with distinct Estonian, Latvian and Lithuanian expectations.

Exact historical font shapes are not required. Legible diacritics, correct byte
mappings and connected supported box-drawing characters are required. Other
Baltic encodings, Windows code pages, UTF-8 conversion, translated applications,
printer/LCD fonts and additional national keyboard variants are outside this
increment. Modern euro-era formatting must not silently replace the selected
DOS-era country contract.

## Implementation sequence

1. **Freeze the shared encoding and each language contract.**
   - Pin the published Microsoft CP775 mapping, its provenance, hash and
     license locally. Distinguish text control codes from DOS screen symbols.
     Audit all encoded slots, including punctuation and pseudographics, rather
     than copying CP437 or CP866 slot positions.
   - Record required letters, uppercase/lowercase pairs and representative
     words independently for each language. Include Estonian tilde, diaeresis
     and caron letters; Latvian macron, cedilla and caron letters; and Lithuanian
     ogonek, dotted, macron and caron letters. Cover the full encoding even when
     a character is outside these language samples.
   - Select a reference-backed national keyboard layout for each language.
     Resolve KEYB codes/IDs, supported keyboard hardware, third-level modifiers,
     dead keys/composition where applicable, national/US switching and ordinary
     punctuation. Record omitted variants explicitly. Do not transplant RU
     toggle behavior without verifying the selected layout's contract.
   - Resolve DOS country identifiers, default/supported pages, date/time,
     currency/number formats, filename rules, uppercase and collation tables
     separately for Estonia, Latvia and Lithuania. Shared encoding does not
     imply shared national ordering. Where retail DOS evidence is unavailable,
     label the chosen extension and its reference instead of claiming retail
     parity or inventing table bytes.
   - Exit: manifests and independent expectations resolve these decisions
     before translation tables or country records are implemented. Record
     compatibility differences and unresolved evidence explicitly.

2. **Build and qualify CP775 screen fonts.**
   - Audit the already vendored Cozette and 512_8 sources for the required
     glyphs at every supported EGA/VGA height. Preserve MIT and public-domain
     attribution separately. Record any original glyph edits with provenance.
     Review diacritics at the short height rather than cropping taller glyphs.
   - Build EGA775.CPI through the existing device rules and CPI format. Keep
     normal builds offline and reproducible; add structural, mapping and
     independent representative-glyph checks and per-height contact sheets.
   - Load CP775 with DISPLAY/MODE in private guest images. Verify active page,
     actual VGA font-plane bytes and rendered text in all three languages.
     Review diacritics, spacing, supported borders, shading and DOS graphical
     control slots. Do not demand CP437 box characters absent from CP775.
   - Exit: each height is readable and byte-correct; a wrong diacritic glyph
     is detected by the guest/font oracle, and existing CP866/EGA pages pass.

3. **Implement and qualify country/NLS records.**
   - Extend the country builder using the frozen language contracts. Share
     tables only where their independently established bytes agree. Derive
     character and filename uppercase explicitly; Unicode mappings alone are
     not a DOS collation oracle.
   - Test structural records and guest CONFIG loading, country and extended
     country APIs, uppercase, active-page queries and NLSFUNC/CHCP transitions
     for each national profile. Check COUNTRY ordering against the shipped
     HIGH/LOW startup recipe, including multi-page DISPLAY preparation.
   - Exercise supported country/page combinations and rejection of unsupported
     combinations. Require the prior usable state after rejection. Test
     switching national records while retaining CP775, so stale country or
     collation state cannot hide behind an unchanged page number.
   - Exit: independent per-country expectations pass, deliberate case and
     collation corruption is detected, and existing country records regress
     cleanly, including Russian.

4. **Implement and qualify all three keyboards.**
   - Add separate translation data using the existing keyboard macros and
     supplemental library build. Validate directory records, offsets, loader
     limits and exact supported page/layout combinations as the library grows.
   - Physically inject keys and compare BIOS/DOS input bytes to independent
     per-layout oracles. Cover every national letter in both cases, Shift/Caps,
     third-level modifiers, applicable dead-key sequences, literal accents,
     punctuation, control/navigation keys and released modifier state.
   - Verify status, US/national switching, switching among the Baltic layouts,
     RU reloads and existing-layout regressions. Exercise supported legacy
     keyboards on real BIOS; document hardware-specific exclusions explicitly.
   - Exit: each language can be typed without serial text injection or host
     file substitution. Missing/truncated/malformed libraries, unsupported
     selections and a wrong national-letter translation are detected; failed
     loads preserve the resident usable layout.

5. **Ship and test the optional pack.**
   - Add resources and notices to device builds, artifact/deployment/clean
     lists and distribution inventory. Verify media capacity and deterministic
     packaging. Update runtime and mutation coverage manifests together with
     the new artifacts, retaining coverage of the expanded KEYBRD2 library.
   - Ship `BALTIC.TXT` with tested CONFIG.SYS/AUTOEXEC.BAT recipes for each
     language and exact identifiers, paths, startup order and switching steps.
     Preserve the Russian recipe and English default boot.
   - Test fresh installation and upgrade copying, then boot installed HIGH/UMB
     and LOW configurations for each language. Verify selected resource hashes,
     country/page/layout, actual font bytes and physical input from installed
     paths. Include resource failure cases in private media.
   - Exit: users can enable any of the three languages entirely from the
     shipped distribution, without replacement drivers or downloaded fonts.

6. **Qualify complete workflows and close the Baltic increment.**
   - For each language, physically type, edit, save and reopen text in COMMAND
     and EDLIN. Check exact CP775 file bytes and actual rendered glyphs; include
     mixed ASCII, pipes, redirection and characters requiring composition.
   - Exercise national 8.3 file and directory names, alternate-case lookup,
     wildcards, DIR name/extension and reverse ordering, COPY, rename, MOVE,
     recursive XCOPY and deletion. Verify raw directory names and file contents
     after reboot. Use each country's independent ordering expectations.
   - Run on the composed HIGH/UMB profile, LOW/fallback and real-BIOS 286.
     Keep images private; require guest completion and successful emulator
     exit. Include missing/malformed font and country resources, unsupported
     selections and corruption controls for glyphs, keys, case and collation.
   - Run existing Russian and legacy locale regressions, installation gates,
     full release tests and pristine serial/parallel reproducibility checks.
     Compare selected core and resource hashes before reusing prior evidence;
     requalify changed memory compositions with matching maps and artifacts.
   - Retain commands, hashes, machine/profile identities, logs, font captures
     and results in qualification JSON linked from tests/COVERAGE.md. Audit
     acceptance separately for every language. Close this TODO only when all
     three profiles and the shared release gates pass; leave other locale
     packs as independent work.

## Starting points and evidence boundaries

- [Microsoft CP775 mapping published by Unicode](https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/PC/CP775.TXT)
  defines the byte-to-Unicode mapping. It does not define keyboard layouts,
  national formatting or DOS sorting rules.
- [Russian plan and qualification](RUSSIAN.md),
  [locale tooling and records](locales/ru/README.md), and
  [font packer](tools/build_ru_cpi.py) provide reusable implementation patterns.
- [Device rules](mk/dev.mk), [country builder](src/DEV/COUNTRY/MKCNTRY.ASM),
  [keyboard macros](src/DEV/KEYBOARD/KEYBMAC.INC), and
  [distribution inventory](distribution/files.json) are integration points.
- [Coverage contracts](tests/COVERAGE.md), [emulator roles](EMULATION.md), and
  [release gates](ARCHITECTURE.md) define qualification requirements.

The [Baltic implementation records](locales/baltic/README.md) contain pinned
encoding/font inputs and selected national country and keyboard contracts.
COUNTRY.SYS includes the Baltic records with static checks against retained
expectations and preservation of prior records. EGA775.CPI passes the shared
font build and QEMU HIGH/LOW font-plane/rendering gates. Baltic country APIs
and NLS transitions pass the QEMU HIGH/LOW matrix. KEYBRD2.SYS includes all
three Baltic layouts, with focused BIOS/DOS physical-input and corruption
checks on HIGH/LOW profiles. Selection, alias/ID, failed-load preservation
and composition tests also pass, including pending accents across mode/reload
changes. Real-BIOS country, display and legacy keyboard matrices have separate
retained qualification records. The optional resources, notices and startup
recipes are packaged; fresh/upgrade installation and installed HIGH/LOW language
profiles are covered by the [installation qualification](locales/baltic/installation-qualification.json).
[Keyboard resource qualification](locales/baltic/keyboard-resource-qualification.json)
covers rejected outer-record pointers, short reads and section lengths.
[Font resource qualification](locales/baltic/font-resource-qualification.json)
covers missing/malformed CPI rejection and documented recovery in QEMU.
[Text workflow qualification](locales/baltic/text-qualification.json) covers
physical COMMAND/EDLIN editing, saving and reopening, rendered CP775 glyphs,
redirection and FIND pipes in each language on QEMU HIGH/LOW and real-BIOS 286.
The workflow exposed a FIND line-boundary error, now covered by a focused
high-byte regression and an old-binary failure control.
[Filesystem qualification](locales/baltic/filesystem-qualification.json) covers
national short names, alternate-case lookup, wildcard and country-specific DIR
ordering, MOVE/XCOPY trees, raw FAT entries and fresh-boot reads/cleanup on
QEMU HIGH/LOW and real-BIOS 286 LOW.
[Country resource qualification](locales/baltic/country-resource-qualification.json)
covers NLSFUNC runtime header rejection, active-state preservation and recovery.
[Country directory qualification](locales/baltic/country-directory-qualification.json)
extends rejection to short control reads and malformed object lists before
DOS table writes.
[Country scan qualification](locales/baltic/country-scan-qualification.json)
covers declared directory counts, record extents and valid padded records
before the selected country data is used.
[Country data qualification](locales/baltic/country-data-qualification.json)
covers object signatures, complete payload reads, resident table capacities,
filename-list bounds and DBCS termination before country-table writes.
Deeper malformed-resource cases, legacy lifecycle failures, installed text and
file workflows, and final source-matched release/reproducibility gates remain
open. Existing Russian evidence does not establish Baltic support.
