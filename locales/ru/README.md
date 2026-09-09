# Russian locale reference inputs

[manifest.json](manifest.json) pins the published CP866 mapping and candidate
font inputs, their source revisions, SHA-256 hashes and licenses. Vendored
files retain upstream bytes and notices. Normal builds and audits need no
network access. 512_8 remains public domain under its Unlicense notice;
Cozette remains MIT-licensed. The mapping has its Unicode license alongside it.

Run `python3 tools/audit_ru_fonts.py` from the repository root to regenerate
the [coverage audit](review/font-audit.json) and contact sheets. Run
`make test-ru-font-sources` to validate sources, mappings, placement, review
artifacts and corruption controls. `--check` on the audit command rejects
stale generated artifacts without rewriting them.

The manifest distinguishes text encoding from DOS display symbols in control
slots. Slot 00 is deliberately blank. Contact sheets run left to right, top
to bottom in byte order, starting at 00. Red dots mark cell origins; blue
diagonals identify missing or clipped glyphs. These are source-selection
prototypes, not CPI payloads or guest screenshots:

- [8x8 candidate](review/contact-8x8.png): 512_8 sans, using its Unicode alias
  table rather than assuming that the font indices equal CP866 bytes.
- [8x14 candidate](review/contact-8x14.png): Cozette, preserving its baseline
  in the taller DOS cell.
- [8x16 candidate](review/contact-8x16.png): the same Cozette glyphs with
  additional vertical padding, without rescaling or cropping.

The short font needs inverse smile, bullet and circle additions. Cozette
contains the required characters, but its advance is narrower than a DOS
cell and padding interrupts vertical strokes. Box drawing, blocks and shading
need explicit cell-filling edits before either tall candidate can qualify.
Unicode coverage alone does not prove glyph shape or connected borders.
The upstream short-font text sheet is retained for independent row review.

Open compatibility decisions remain in the manifest. Country formats,
collation and keyboard behavior must be resolved from DOS references before
implementation. The complete scope and guest acceptance gates remain in
[RUSSIAN.md](../../RUSSIAN.md).
