# Russian / CP866 implementation plan

## Scope and decisions

Deliver an optional Russian DOS environment: CP866 text display, Russian and
Latin keyboard input, country services, and Cyrillic short filenames. Keep
English messages, Help, and the default installation language. Exact historical
font shapes are not an acceptance requirement; readability, correct mappings,
and connected box-drawing characters are.

Use the existing KEYB, DISPLAY, MODE, CHCP, COUNTRY and NLSFUNC interfaces.
Extend drivers or kernel code only where a focused test establishes a missing
contract. Windows CP1251, UTF-8 conversion, translated applications, printer and
LCD fonts, other Cyrillic locales, and full retail supplemental packs are outside
this increment.

Package the screen font as `EGA866.CPI` and the Russian layout as an initial
`KEYBRD2.SYS` containing RU only. This avoids changing the existing EGA.CPI and
KEYBOARD.SYS payloads and their historical regression contracts. Extend
COUNTRY.SYS with the required Russian records while preserving existing record
contents. Do not advertise the RU-only file as the complete retail KEYBRD2 pack.

## Implementation sequence

Each step ends with reviewable source and its focused validation. Keep inputs,
licenses, mappings, reference expectations and generated results in machine-
readable files; this document records scope and the order of work.

1. **Freeze the compatibility contract and font source.**
   - Add a locale manifest for CP866 with the published Unicode mapping,
     provenance, source revisions/hashes, and any applicable notices. Keep all
     build inputs local so normal builds require no downloads.
   - Resolve the Russian country identifier, period-appropriate date/time,
     currency and number formats, filename rules, case conversion, and
     collation from public DOS references. Record uncertainties explicitly;
     modern Russian locale defaults are not an automatic DOS oracle.
   - Specify a standard Russian JCUKEN layout, Latin mode, toggle shortcuts,
     Shift/Caps Lock behavior, punctuation, control keys, and supported PC
     keyboard variants. Verify historical identifiers and shortcuts before
     encoding them; phonetic and typewriter layouts are deferred.
   - Evaluate MIT-licensed Cozette for the taller screen fonts. Check every
     CP866 slot, including Yo/yo, the other encoded Cyrillic letters, symbols,
     DOS graphical control slots, and box drawing. Select a source for the
     short font as well; Cozette's native cell cannot simply be cropped into it.
     Original bitmap additions can be MIT-licensed. The public-domain 512_8
     font is an alternative if broader permissive licensing is acceptable,
     not a font to relabel as MIT.
   - Exit: a populated manifest, resolved behavioral tables, complete glyph
     coverage audit, and a contact sheet for each intended font height. Any
     deliberate compatibility differences are named before implementation.

2. **Build and load the CP866 screen fonts.**
   - Add reproducible conversion/packing tools and local bitmap inputs for
     the EGA/VGA font heights used by the existing CPI format. Preserve source
     attribution and record original glyph edits separately.
   - Build EGA866.CPI through `mk/dev.mk`; retain the existing CPI header and
     font-loading contracts rather than inventing a new format.
   - Add structural tests for offsets, sizes, character ordering, and complete
     glyph coverage. Compare representative glyphs to independently recorded
     expected rows, not only the generator's own output.
   - In a private QEMU image, load DISPLAY and prepare/select CP866 with MODE.
     Verify the active page and actual VGA font-plane bytes. Render Russian
     text, pseudographics, shading and mixed Latin/Cyrillic at each supported
     height; retain screenshots for visual acceptance.
   - Exit: CP866 loads, readable text and continuous borders are demonstrated,
     and existing EGA.CPI pages still load correctly. Serial text alone cannot
     establish font correctness.

3. **Implement country and NLS behavior.**
   - Extend `src/DEV/COUNTRY/MKCNTRY.ASM` and its includes using the manifest's
     Russian country and CP866 records. Derive character and filename uppercase
     tables explicitly, including the non-contiguous Cyrillic ranges and Yo.
     Do not equate Unicode byte mappings with DOS collation rules.
   - Extend country-record validation without replacing the existing historical
     assertions. Add guest probes for CONFIG.SYS country loading and the DOS
     country, extended-country, uppercase and code-page APIs.
   - Exercise NLSFUNC/CHCP transitions supported by the selected country
     records. Verify rejected combinations report failure and leave the
     previous usable state intact.
   - Exit: reported settings and conversion/collation behavior match the
     independent expectations; existing country records pass their regressions.

4. **Implement Russian keyboard input.**
   - Add RU translation logic/data and a supplemental keyboard-library build
     under `src/DEV/KEYBOARD/`, using the existing macros and KEYB loader.
   - Test loading via `KEYB RU,866,...`, status reporting, Latin/Russian
     switching, lowercase/uppercase, Yo, punctuation, modifiers, held-key
     release, and ordinary navigation/control keys.
   - Inject keyboard scan codes through QEMU and capture BIOS/DOS input bytes;
     a successful KEYB command or injected serial string is insufficient.
     Use an independently specified key-to-byte oracle.
   - Exit: typed bytes match CP866 expectations, toggles do not leave modifiers
     stuck, and switching back to existing layouts passes regression checks.

5. **Integrate the optional pack into installation media.**
   - Add the files to `distribution/files.json`, Makefile artifact/deployment
     lists and clean rules. Verify disk capacity and installed paths.
   - Provide a tested CONFIG.SYS/AUTOEXEC.BAT recipe for COUNTRY, DISPLAY,
     NLSFUNC, MODE and KEYB, with the exact order established by guest tests.
     Include the recipe and required attribution in installed documentation.
     Keep initial boot in the existing English configuration.
   - Test installation and upgrade copying, then boot an installed disk using
     the recipe. Verify file hashes and active country/code page/layout.
   - Exit: a user can enable Russian from the shipped files without downloading
     additional data or substituting third-party drivers.

6. **Qualify end-to-end behavior and close the scoped item.**
   - Type, edit, save and reload Russian text using the existing shell/editor;
     compare file bytes and screen output. Include pipes and redirection.
   - Create, find with alternate case, rename, copy and delete Cyrillic 8.3
     filenames and directories. Exercise wildcard matching and ordering using
     the defined DOS rules; verify persisted directory bytes after reboot.
   - Run the focused locale suite on the default composed HIGH/UMB profile,
     LOW/fallback configurations and a real-BIOS 286 backend. Keep media private
     and require guest completion plus successful emulator exit. Test missing
     or malformed locale resources and unsupported page/layout selections.
   - Add negative controls for a wrong glyph slot, key translation and case
     table entry so the new tests demonstrate that they detect corruption.
   - Run relevant existing country/keyboard/display and installation tests, the
     full release suite, and pristine serial/parallel reproducibility checks.
     Investigate any changed memory-core bytes before reusing memory evidence.
   - Record selected artifact hashes, commands, results and remaining scope in
     a locale qualification JSON file linked from tests/COVERAGE.md. Close only
     the Russian increment; other locale packs remain separate open work.

## Starting point

Pinned inputs, selected compatibility tables and complete font coverage live in
[locales/ru](locales/ru/README.md). The CP866 CPI build and focused display gate
are implemented; [display qualification](locales/ru/display-qualification.json)
records actual VGA bytes, screenshots and corruption detection.
[Country qualification](locales/ru/country-qualification.json) covers the new
country records, DOS/NLSFUNC APIs, CHCP transitions and rejection tests. Russian
keyboard implementation is next. The manifest keeps the keyboard modifier and
variant checks visible, and installation/end-to-end gates remain open.

Existing implementation and test entry points:

- [Device build rules](mk/dev.mk) and [distribution inventory](distribution/files.json).
- [Keyboard data/macros](src/DEV/KEYBOARD/KEYBMAC.INC) and
  [keyboard record tests](tests/test_keyboard_records.py).
- [Country builder](src/DEV/COUNTRY/MKCNTRY.ASM),
  [country record tests](tests/test_country_records.py), and
  [guest country matrix](tests/test_country_matrix_qemu.sh).
- [CPI header](src/DEV/DISPLAY/EGA/CPI-HEAD.ASM) and
  [supplemental locale smoke tests](tests/test_supplemental_locale_qemu.sh).
  The new acceptance tests must add byte-level oracles and strict completion;
  the existing smoke markers alone do not prove the Russian contracts.

Public starting references:

- [Microsoft CP866 mapping published by Unicode](https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/PC/CP866.TXT).
- [FreeDOS localization interfaces](https://help.freedos.org/docs/howto/local.html),
  useful as an interoperability reference, not proof of Microsoft table bytes.
- [Cozette source](https://github.com/the-moonwitch/Cozette) and
  [MIT license](https://github.com/the-moonwitch/Cozette/blob/main/LICENSE).
- [512_8 source, coverage and public-domain terms](https://github.com/alexfru/512_8).
