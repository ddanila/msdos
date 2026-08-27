# PLAN: Full open-source toolchain for MS-DOS 4.0

Goal: build the complete MS-DOS 4.0 image with a **100% open-source, no-cost,
copyright-preserving** toolchain -- no proprietary Microsoft binaries and no
emulator (kvikdos) anywhere in the build path. This file is the strategic
roadmap: decisions and unlocks. The running technical log stays in `TODO.md`;
deep notes in `docs/agent-notes/`.

Last updated: 2026-08-28.

---

## Where we are

All production tool layers are now open-source and native-hosted. The committed
result passes the full Linux CI and QEMU matrix.

| Layer | Tool today | Open source? | Status |
|-------|-----------|--------------|--------|
| Assembler (all `.ASM`) | JWasm `-Zm` (`bin/jwasm-masm`) | Yes (SOWPL) | **DONE** -- 0 errors tree-wide |
| Linker (kernel, drivers, all 38 commands) | Open Watcom `wlink` (`bin/wlink`) | Yes (SOWPL) | **DONE** |
| C compiler (all C-hybrids) | Open Watcom `wcc` | Yes (SOWPL) | **DONE** |
| Library manager | Open Watcom `wlib` (`bin/wlib`) | Yes (SOWPL) | **DONE** |
| Proprietary build utilities (9 tools) | Native Python wrappers | Yes | **DONE -- 9 of 9 native** |

Every `.ASM` is assembled by JWasm, every C source is compiled by Open Watcom,
and all libraries and executables are produced by Open Watcom tools. The nine
formerly proprietary build utilities have native replacements. `make deploy`
therefore creates the complete boot floppy without executing DOS code during
the build.

MEMM/EMM386 was the final island. Its C sources now compile with `wcc`, EMMLIB
is created by `wlib`, and EMM386 links with `wlink`. The link explicitly disables
far-data packing because the original protected-mode code requires GDT, IDT,
TSS, PAGESEG, and LAST to have independent `SEG:0000` addresses. Its QEMU probe
enters virtual-8086 mode and validates INT 67h allocation, dual-window mapping,
memory aliasing, and release.

Two clean macOS builds established repeatability before the final tool refresh.
The WLIB wrapper removes wall-clock DOS timestamps from library members while
preserving valid OMF checksums, and Linux CI now reproduces all 59 refreshed
golden artifacts. Both the complete local QEMU matrix and the 23-job GitHub
Actions matrix are green.

---

## The toolchain decision: is JWasm+Watcom the right base?

Deep survey of the mid-2026 landscape (see `docs/agent-notes/` and the research
that fed this plan) confirms **JWasm + Open Watcom is the correct base** and
there is no materially better alternative to switch to. Summary of what exists:

**Assemblers (MASM 5.1-compatible, OMF output):**
- **JWasm** (Baron-von-Riedesel) -- SOWPL. What we use. Active through 2026,
  proven on the entire tree. macOS arm64 host works (one-line `alloca.h` patch).
- **UASM** (Terraspace) -- SOWPL. JWasm-derived, adds native **Mach-O** output
  and first-class macOS build. A drop-in-ish fallback if JWasm stalls.
- **Asmc** (nidud) -- **GPL** (FSF-clean), very active (2.39, Jul 2026). The
  only FSF-free MASM-compatible assembler. Relevant only if we adopt a hard
  "FSF-free" license bar (see license section).

**Linkers (16-bit OMF -> MZ/COM):**
- **wlink** (Open Watcom) -- SOWPL. What we use; byte-identical to MS LINK here.
- **JWlink** (japheth fork) -- SOWPL, macOS-buildable since Jan 2026, but nearly
  unmaintained (6 commits in 12 years). Useful as a *diagnostic* (its non-quiet
  mode named the `.ALPHA` OMF bug) but not as a primary linker.
- **No FSF-free 16-bit OMF->MZ linker exists.** The linker slot is unavoidably
  SOWPL short of writing a new one.

**16-bit real-mode C compilers:**
- **Open Watcom `wcc`** -- SOWPL. Incumbent for Stage B. Emits OMF, links with
  our JWasm objects, small-model/cdecl/far-pointer capable.
- **Digital Mars C (DMC)** -- Boost license (permissive, FSF-clean!), targets
  16-bit DOS -- but **Win32-host only**, no native Linux/macOS, so it needs
  Wine/DOSBox, i.e. it reintroduces an emulator. Disqualified.
- **gcc-ia16** (tkchia) -- GPL, cross-hostable -- but targets ELF/a.out, not
  OMF, and a very different ABI from MS C 5.x. Porting the MS-C-ABI utilities to
  it is *more* work than the wcc port, not less. Disqualified for this codebase.
- No open-source reimplementation of the **MS C 5.x runtime (SLIBCE)** or the
  **DOS family API** exists. This is the actual root blocker for the C-hybrids
  under any open compiler -- confirmed gap, not a tooling choice.

**Conclusion:** keep JWasm (assembler) + wlink (linker) + wcc (C compiler).
No alternative removes work; some add it. The remaining effort is *integration
and reimplementation*, not picking a different compiler.

---

## License posture (decide once)

The user's stated aim is "no commercial value, preserve original-author
copyrights, pure open source." Two tiers of "open source" are in play:

- **OSI-approved:** SOWPL 1.0 **is** OSI-approved. JWasm, UASM, wlink, JWlink,
  wcc all qualify.
- **FSF-free / Debian DFSG:** SOWPL is **not** FSF-free and **not** DFSG-free
  (its "Deploy" clause forces source publication; Debian excludes it from main).
  Only **Asmc** (GPL) and **DMC** (Boost) clear this bar -- and only for the
  assembler / C-compiler slots, never the linker.

**Recommendation: target the OSI-approved tier, not the FSF-free tier.** For a
hobby project that vendors build-tool *binaries* (never links them into the
shipped DOS image), SOWPL's obligations are immaterial -- the tool sources are
public, copyrights are intact, and nothing proprietary ships. Chasing FSF-free
would force an Asmc re-validation of the whole tree and *still* leave the linker
SOWPL, so it buys nothing. **This is a decision to confirm with the user** -- if
a hard FSF-free bar is required, WS3 changes materially (Asmc migration + a
new-linker question). Absent that, the plan proceeds on the OSI tier.

Copyright hygiene (applies regardless): keep Microsoft's copyright headers on
all MS-DOS sources intact; our fork LICENSE is MIT over the MIT-licensed MS
release; vendored tool binaries retain their upstream licenses in `watcom/`,
`jwasm/`. Toolchain bug fixes go to the user's forks, never upstream.

---

## Workstreams to 100%

Ordered by ROI. WS1 is the big, clean, well-scoped win; WS2 is the hard long
tail; WS3/WS4 are hygiene that de-risk the milestone.

### WS1 -- Replace the 9 proprietary build utilities (DONE)

This removes kvikdos from the build entirely for pure-asm targets and is
**purely additive, low-risk, MIT-clean** (our own Python, no license question).
These tools are deterministic file transformers with checked-in
input/output pairs, so each can be verified by byte-diff against the current
kvikdos output. Full per-tool analysis already exists in `TODO.md` Phase 6.

Implementation order:
1. **DBOF + BUILDIDX (DONE)** -- binary->INC hex dump; MSG
   index builder. Byte-diff vs `BOOT.INC`/`USA-MS.IDX`.
2. **EXE2BIN (DONE)** -- native MZ-to-binary conversion, including the
   `<LOCSCR` / `<ZERO.DAT` stdin load-segment cases used by MSBIO, PRINTER,
   and DISPLAY.
3. **NOSRVBLD + MENUBLD (DONE)** -- kernel message class generator; FDISK
   menu-to-C.
4. **CONVERT (DONE)** -- EXE->COM with a relocating stub; hand-write the
   ~80-byte stub once, embed as a blob, verify FORMAT.COM/CHKDSK.COM boot.
5. **BUILDMSG (DONE)** -- native message compiler, byte-exact across all 43
   production skeletons and all 204 generated CL/CTL files.
6. **ASC2HLP + COMPRESS (DONE)** -- native SELECT help and panel-data
   compilers, byte-exact for both production outputs.

Current state: no proprietary helper utility remains and the source-built
MKCNTRY generator no longer executes under DOS. DOS emulation is now confined
to the C-hybrid compiler/linker and library-manager steps.

### WS2 -- Migrate the C-hybrids off MS CL/LINK (DONE)

The wcc port of ATTRIB now proves the pattern end-to-end: production builds it
with wcc+JWasm+wlink, all eight focused host behaviors pass, and QEMU validates
its FAT attribute changes through BACKUP/RESTORE. Its final blocker exposed a
reusable ABI rule: `-Zp` structures stay byte-packed, while SAL message
substitution records require an explicit 12-byte stride. There is still **no
systematic silver bullet** for all remaining utilities. Root cause is the missing open **SLIBCE /
DOS-family-API runtime**, not the compiler.

Strategy -- treat it as a runtime project, not a per-file grind:
1. **Build a shared OW-based compat runtime module** ("open-slibce"): the
   `getpspbyte`/`putpspbyte` shims, the `ES=DGROUP` asm-interface fix in
   `_PARSE.ASM`/`_MSGRET.ASM`, the OW-`cstart` entry recipe (`pspbyte.c`
   `main()` + `criterr.asm`), and the message-substitution (`sysdispmsg`
   `m_sublist`) contiguity fix -- factored out of ATTRIB into one reusable unit.
   The banked ATTRIB groundwork is the seed.
2. **Nail ONE utility fully working (DONE: ATTRIB).** The first genuinely
   running C-hybrid validates OW startup, PSP access, assembler interfaces,
   packing, and SAL message substitution.
3. **Templatize across the remaining targets.** FC, FILESYS, REPLACE, JOIN,
   SUBST, BACKUP, RESTORE, MEM, and FDISK are complete; continue with the
   library-heavy ones (SELECT/SERVICES.LIB and EMM386).
4. **Switch LIB.EXE -> `wlib`.** MAPPER is complete with identical exports and
   full QEMU coverage. Apply the proven wrapper to EMMLIB and SERVICES.
   COMSUBS has no source in this tree and must instead be replaced by source
   implementations of the entry points actually used by migrated utilities.

Reality check: this is a multi-week effort with diminishing per-utility returns.
Gate it behind WS1 (which delivers most of the "no proprietary tools" value at a
fraction of the cost) and behind a real qemu validation environment (see WS4).

### WS3 -- Assembler/linker robustness + upstream fixes (de-risk)

- File the banked toolchain bugs against the user's forks
  (`ddanila/open-watcom-v2`, `ddanila/JWasm`): the `.ALPHA` OMF seg-index bug
  (worked around source-side via `.SEQ`; the engine fix -- renumber `seg_idx`
  after sort + remap fixups -- would let `.ALPHA` work), and a defensive
  bounds-check in the wlink OMF loader (segfault-on-bad-fixup hardening).
- Keep `bin/wlink`'s MS-LINK-syntax shim as the compatibility layer; it is the
  load-bearing adapter and byte-parity is the validation of record.
- Re-confirm JWasm/Asmc native macOS-arm64 hosting if a CI matrix expands.

### WS4 -- Toolchain compatibility-layer cleanup (finish line)

The production build is native and uses no DOS emulator. Custom JWasm consumes
the checked-in assembly sources directly, while Open Watcom provides the C
compiler, linker, and library manager. The completed audit below records the
transformations that were retired and the narrow compatibility adapters that
remain intentionally.

#### WS4.1 -- Characterize behavior before removing it (DONE)

Focused contracts now accompany the retained transformations instead of relying
only on final artifact checksums and broad QEMU coverage:

- custom JWasm regression tests cover structured-macro whitespace arguments and
  case-insensitive include lookup; the root suite assembles the same contract
  through `bin/jwasm-masm` directly from its real source directory.
- raw native BUILDMSG output for COMMAND, SYS, and FORMAT is assembled and
  linked without a post-generation rewriter during the normal build.
- `bin/wlink` option validation covers accepted and rejected compatibility
  options; compact MZ input is exercised through native `exe2bin`.
- Kernel layout is emitted directly from custom JWasm's historical segment
  order; the resulting unpatched image begins with the source `JMP DOSINIT`,
  while shared DOSGROUP offsets remain identical in resident utilities.
- `fix-exepack` and `exefix`: assert which artifacts are changed, their exact
  header/stub contracts, idempotence, and real-DOS/QEMU behavior.

Removal gate: a compatibility pass is retired only after a focused test first
captures its current contract and the full deterministic-build and QEMU suites
remain green without it.

#### WS4.2 -- Retire assembly source rewriting (DONE)

The retired shadow preprocessor used to change 380 of 1,111 eligible source-like
files: 64 files contained 2,091 structured-directive invocations and 379 files
contained 1,221 concrete mixed/uppercase `INCLUDE` operands.

Custom JWasm `4c2f0a2f7440ca40a8cfa6718ac3ffd74ca1f9d9` implements MASM 5.10
structured-macro whitespace arguments and case-insensitive include resolution
in M510 mode. `bin/jwasm-masm` now assembles the real source path directly, and
`bin/preprocess-jwasm` has been deleted. Linux CI remains the case-sensitive
host gate.

#### WS4.3 -- Revalidate the generated-message workaround (DONE)

The workaround described old WASM single-pass limitations. Current custom JWasm
assembles and links raw BUILDMSG output for COMMAND, SYS, and FORMAT, so all
three recipe hooks and `fix_cl_forward_refs.py` have been deleted.

#### WS4.4 -- Remove linker-layout and blanket EXE-header patches (DONE)

1. Custom JWasm emits the historical `START, CONST, DATA, TABLE, CODE, LAST`
   order, causing the source START segment and its `JMP DOSINIT` to occupy
   offset zero naturally. The inline post-EXE2BIN byte patch has been deleted.
   An explicit `/ORDER:START,CODE` was rejected by runtime validation because
   it moved shared DOSGROUP data behind CODE and broke resident utilities.
2. Native `exe2bin` already accepts arbitrary valid MZ header sizes. WLINK's
   blanket 512-byte MS-LINK-style header rewrite has therefore been deleted.
3. `nofarcalls`, case mapping, `/ORDER`, `/PACKDATA`, and `/DOSSEG` remain
   explicit translated Microsoft LINK semantics.

#### WS4.5 -- Harden and document the adapters we retain

- `bin/wcc` and `bin/wlink` now reject unknown options. Their explicitly
  supported Microsoft-option surfaces include documented no-ops, and `-Os` and
  `/DOSSEG` are translated rather than silently discarded.
- Retain WCC's ABI/memory-model translation and temporary case-insensitive
  include mirror until the underlying tools provide equivalent behavior.
- Retain WLIB timestamp normalization as an explicit reproducibility step.
- Retain native historical build-tool replacements (`buildmsg`, `buildidx`,
  `exe2bin`, `convert`, `dbof`, `nosrvbld`, `menubld`, `asc2hlp`, `compress`,
  and `mkcntry`) subject to their byte-parity tests; these are implementations
  of required build operations, not hidden preprocessors.
- Retain the floppy BPB patch as explicit image construction, and retain the
  fixed EXEPACK stub while affected packed binaries need it on real DOS/QEMU.
- Keep the `kvikdos-soft` compatibility header classified as test-only. It must
  never become a production-build dependency.

#### WS4.6 -- Documentation and CI completion

- The assembler documentation now accurately describes direct source assembly,
  and the stale Microsoft C 5.10/kvikdos statement has been removed.
- Document each retained transformation beside its rule, its compatibility
  reason, its focused test, and its eventual removal condition.
- Keep macOS and Linux on the same production path; Homebrew should provide
  only ordinary host dependencies, never a separate source-transformation
  path.
- **Keep the complete QEMU suite green.** The boot/serial harness and all QEMU
  Make targets passed the August 26 merge gate, including parallel FORMAT
  groups. Extend those tests as each native replacement lands.
- **CI**: add an explicitly kvikdos-free native-toolchain job as WS1 lands;
  retain reference jobs only while they prove parity with a tool being replaced.
- **Host MKCNTRY natively (DONE).** Its JWasm/wlink-built executable contains
  the complete COUNTRY.SYS payload; the native extractor writes that payload
  byte-for-byte without executing DOS code.

Local cleanup validation (2026-08-27): focused native contracts pass; the fast
kvikdos suite passes 389/389; all 60 golden artifacts are identical across
clean `-j1`, `-j4`, and `-j8` builds; deployment succeeds; and the complete
QEMU target matrix passes, including all seven parallel FORMAT groups. Enabling
the formerly ignored `-Os` exposed FC's unsafe function-pointer dispatch for
`/T`; `ddanila/MS-DOS` commit `50daf26626cad4cadd3cc465a032227f1861f9cc`
replaces it with explicit tab-preserving input and is covered by the existing
FC `/T` runtime contract. GitHub Actions run
[`33117104290`](https://github.com/ddanila/msdos/actions/runs/33117104290)
passed the complete Linux build and QEMU matrix for cleanup commit `953332b`.

#### WS4.7 -- Cleanup execution checklist (DONE)

The audit identified the complete cleanup scope below. All items and their
validation gates are complete in `master`; the checklist remains the record of
what was changed and the evidence required to preserve the result.

1. **Establish focused reference contracts.** Keep regression coverage for
   JWasm's M510 structured-directive whitespace and case-insensitive include
   lookup, raw BUILDMSG output, compact MZ input, linker option translation,
   kernel entry layout, EXEPACK repair, and EXE header repair.
2. **Remove shadow source generation.** Assemble the checked-in source files
   directly and delete `bin/preprocess-jwasm`. The custom JWasm implementation,
   rather than a Homebrew text-processing tool, owns MASM-compatible include
   lookup and structured-directive parsing.
3. **Remove generated-message rewriting.** Build COMMAND, SYS, and FORMAT from
   native BUILDMSG output and delete `fix_cl_forward_refs.py` plus all recipe
   hooks that invoke it.
4. **Preserve source-defined linker layout.** Remove the post-`exe2bin`
   entry-byte patch and let the historical object/class order place START at
   zero. Add focused checks that the emitted jump reaches `DOSINIT` without
   mutation and that replicated DOSGROUP data offsets match resident tools.
5. **Stop globally canonicalizing MZ headers.** Let WLINK emit valid compact MZ
   headers and rely on native `exe2bin`'s format-aware parser. Refresh binary
   references only after runtime validation demonstrates that the differences
   are intentional.
6. **Make retained adapters strict.** Reject unknown WCC and WLINK arguments;
   explicitly translate meaningful compatibility options such as `-Os` and
   `/DOSSEG`; document intentional no-ops. Retain only the ABI/memory-model,
   case-insensitive C-include, and deterministic-library behavior that remains
   demonstrably necessary.
7. **Keep narrowly scoped binary transforms.** Preserve `fix-exepack`,
   `exefix`, WLIB timestamp normalization, and floppy BPB construction only
   where their focused contracts prove a real need. Each must be idempotent or
   deterministic and identify exactly which bytes it may change.
   Production BUILDIDX generation uses its non-mutating mode so repeated clean
   builds do not increment the checked-in message catalog level.
8. **Refresh documentation and references.** Remove current documentation that
   describes deleted preprocessors or proprietary compiler/emulator paths.
   Historical investigation notes may remain when clearly labelled as such.

Validation gate, in order:

- Run the focused transformation and native-build-tool tests.
- Perform a pristine build using the pinned custom JWasm and vendored Open
  Watcom binaries, with no manually copied intermediate artifacts.
- Verify deterministic results for serial and parallel builds (`-j1`, `-j4`,
  and `-j8`) so concurrent targets never share mutable scratch state.
- Run the complete kvikdos test layer for fast command-level coverage, then
  `make deploy` and the complete QEMU runtime matrix, including SYS, FORMAT,
  FDISK, C-hybrid utilities, drivers, and EMM386.
- Refresh golden manifests only from those validated artifacts. Preserve
  platform-specific overrides where macOS and Linux output genuinely differs.
- Push to `ddanila/MS-DOS` only after the local gates pass, then require the
  MS-DOS GitHub Actions matrix in the `ddanila` namespace to be green. Slow
  Open Watcom fork CI is informational and is not a blocker for this cleanup.

Definition of done: the production build consumes real MS-DOS sources through
custom JWasm and Open Watcom without hidden text rewrites or blanket binary
patches; every retained compatibility operation is narrow, documented, and
tested; clean serial and parallel builds are reproducible; and the complete
local runtime and `ddanila/MS-DOS` CI suites pass.

---

## Milestones

- **M0 (DONE)** -- Pure-asm image fully open-source-built (JWasm + wlink),
  byte-identical to MS LINK; complete floppy via `make deploy`.
- **M1 (DONE)** -- WS1 steps 1-4: kvikdos removed from all pure-asm target builds
  (DBOF, BUILDIDX, EXE2BIN, NOSRVBLD, MENUBLD, CONVERT reimplemented). Biggest
  single step toward the goal.
- **M2 (DONE)** -- **Zero proprietary build utilities**: all nine replaced by
  native, byte-compatible implementations.
- **M3 (DONE)** -- QEMU E2E validation is green and goldens are refreshed from
  a boot-validated, reproducible build. Linux CI confirms the same artifacts.
- **M4 (DONE)** -- WS2: first C-hybrid (ATTRIB) fully running under
  wcc+wlink+OW runtime. Host 290/290, forced parallel build, QEMU help 6/6,
  and BACKUP/RESTORE 38/38 are green.
- **M4b (DONE)** -- FC, REPLACE, and BACKUP migrated. BACKUP proves the
  wcc/wlink-to-native-CONVERT path and shares source replacements for the
  DBCS-aware COMSUBS searches and DOS country-aware uppercase service.
- **M4c (DONE)** -- RESTORE's twelve C objects migrated, completing the
  wcc/wlink/native-CONVERT pair. The shared runtime now also replaces COMSUBS
  return-code mapping and supplies cdecl DOS directory wrappers.
- **M4d (DONE)** -- FILESYS migrated to wcc+wlink. Its command-tail far pointer
  and SAL message bridges now use explicit Open Watcom-compatible segment
  handling; direct host help, forced parallel full build, QEMU help 6/6, and
  the QEMU miscellaneous suite 48/48 are green.
- **M4e (DONE)** -- JOIN migrated to wcc+wlink with separately named Open
  Watcom variants of the four shared INC C objects. COMSUBS substring search
  is source-backed, both compiler ABIs remain isolated, and the two-floppy
  ASSIGN/SUBST/JOIN QEMU suite passes 16/16 after a forced parallel full build.
- **M4f (DONE)** -- SUBST migrated onto JOIN's shared Open Watcom INC runtime,
  removing the last MS-C consumer of those objects and binary-only COMSUBS from
  both drive-splicing utilities. The same 16/16 QEMU suite and a forced
  parallel full build are green.
- **M4g (DONE)** -- MEM migrated to wcc+wlink. Its sole apparent application
  dependency in the binary-only Microsoft `MEM.LIB` was the C-startup
  `DOS_TopOfMemory` value; MEM now reads the equivalent top-of-memory field
  directly from its PSP. Far pointers use `MK_FP`, and the host 290/290 suite,
  QEMU help 6/6, and QEMU driver/config suite 17/17 are green.
- **M4h (DONE)** -- FDISK's twenty C modules migrated to wcc and its complete
  image, including the embedded hard-disk boot record, links with wlink. The
  matching OW2 floating-point runtime is now vendored, and the destructive-disk
  QEMU suite passes 13/13 across primary, extended, logical, and primary-only
  layouts.
- **M5 (DONE)** -- All C-hybrids, including EMM386,
  use wcc+wlink+wlib; MS CL/LINK/LIB and kvikdos are absent from the production
  build path.
- **M6 (DONE)** -- The native toolchain's remaining hidden
  source/generated-file rewrites and broad post-link patches are characterized,
  minimized, and retired where possible. JWasm consumes the actual source tree,
  kernel entry layout is produced correctly by the linker, retained adapters
  are strict and documented, and focused tests protect every intentional binary
  transformation.

## Decisions

- The target is the OSI-approved toolchain tier: custom JWasm plus Open Watcom.
- M6 completes the native-toolchain cleanup goal; future work can extend test
  depth or reduce the remaining documented compatibility adapters without
  reopening this milestone.
- WS1 goes first because it creates deterministic native reference tooling and
  removes emulation from the pure-assembly build path before the C-runtime work.
