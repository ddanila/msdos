# Baltic locale inputs

[BALTIC.md](../../BALTIC.md) defines the Estonian, Latvian and Lithuanian
implementation and acceptance scope. This directory currently contains pinned
encoding inputs and a candidate font audit, not an installable locale pack.

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
are marked rather than silently substituted. These unmodified candidates still
need explicit edits and visual/runtime qualification, including border geometry.
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
