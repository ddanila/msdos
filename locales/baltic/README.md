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
production records are checked separately against its output. Guest API
qualification remains open.

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

Real-BIOS rendering, physical keyboard input, country APIs, installed recipes
and full release qualification remain separate open gates. The font test's
Estonian COUNTRY selection does not establish country-API support for every
language, and rendered samples do not establish typed keyboard input.
