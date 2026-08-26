# PLAN: Full open-source toolchain for MS-DOS 4.0

Goal: build the complete MS-DOS 4.0 image with a **100% open-source, no-cost,
copyright-preserving** toolchain -- no proprietary Microsoft binaries and no
emulator (kvikdos) anywhere in the build path. This file is the strategic
roadmap: decisions and unlocks. The running technical log stays in `TODO.md`;
deep notes in `docs/agent-notes/`.

Last updated: 2026-08-27.

---

## Where we are

The build has three tool layers. Two are done; the rest is the remaining work.

| Layer | Tool today | Open source? | Status |
|-------|-----------|--------------|--------|
| Assembler (all `.ASM`) | JWasm `-Zm` (`bin/jwasm-masm`) | Yes (SOWPL) | **DONE** -- 0 errors tree-wide |
| Linker (pure-asm targets) | Open Watcom `wlink` (`bin/wlink`) | Yes (SOWPL) | **DONE** -- byte-identical to MS LINK |
| Linker (C-hybrid targets) | MS LINK via kvikdos | **No** | Stage B |
| C compiler (C-hybrids) | MS CL 5.10 via kvikdos | **No** | Stage B (deferred) |
| Library manager | MS LIB / OW `wlib` | Mixed | wlib vendored; not fully switched |
| Build utilities (9 tools) | Native Python wrappers / DOS `.EXE`s | Mixed | **7 of 9 native** |

The **pure-assembly milestone is shippable**: every `.ASM` in the floppy image
is assembled by JWasm and linked by wlink, and `make deploy` produces a complete
1.44MB boot floppy end-to-end. What still pulls in proprietary tools:

1. **~14 C-hybrid utilities** (ATTRIB, BACKUP, RESTORE, FC, FDISK, FILESYS,
   JOIN, MEM, REPLACE, SUBST, SELECT, SMARTDRV, EMM386, MEMM) still compile
   with **MS CL** and link with **MS LINK**, because they depend on the MS C
   5.10 runtime (`SLIBCE.LIB`) and the OS/2-style DOS "family API".
2. **2 proprietary DOS build utilities** still run under kvikdos: ASC2HLP (2)
   and COMPRESS (1). DBOF, BUILDIDX, EXE2BIN, NOSRVBLD, MENUBLD, CONVERT, and
   BUILDMSG now have native byte-compatible replacements.

Reaching the goal means eliminating both. They are independent workstreams with
very different risk profiles (see below).

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

### WS1 -- Replace the 9 kvikdos-run build utilities (7/9 DONE)

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
6. **ASC2HLP + COMPRESS** (SELECT.HLP only, 3 calls) -- lowest priority;
   SELECT-help-specific.

Current state: only SELECT's ASC2HLP/COMPRESS help pipeline and the C-hybrid
compile/link steps still use DOS-hosted proprietary tools.

### WS2 -- Migrate the C-hybrids off MS CL/LINK (HARD, long tail)

The wcc port of ATTRIB proved the pattern works
end-to-end (links, `/?` runs) but the core path still hangs in per-utility
MS-C-ABI layers -- each fixed layer (pointer ABI -> ES=DGROUP -> off-by-one ->
message-substitution layout) uncovers the next, and there is **no systematic
silver bullet**, x ~14 utilities. Root cause is the missing open **SLIBCE /
DOS-family-API runtime**, not the compiler.

Strategy -- treat it as a runtime project, not a per-file grind:
1. **Build a shared OW-based compat runtime module** ("open-slibce"): the
   `getpspbyte`/`putpspbyte` shims, the `ES=DGROUP` asm-interface fix in
   `_PARSE.ASM`/`_MSGRET.ASM`, the OW-`cstart` entry recipe (`pspbyte.c`
   `main()` + `criterr.asm`), and the message-substitution (`sysdispmsg`
   `m_sublist`) contiguity fix -- factored out of ATTRIB into one reusable unit.
   The banked ATTRIB groundwork is the seed.
2. **Nail ONE utility fully working** (finish ATTRIB: resume at the
   `sysdispmsg` `m_sublist` layout layer). A single genuinely-running C-hybrid
   validates the runtime module and turns the rest into repetition.
3. **Templatize across the remaining ~13.** Simplest first (FC, REPLACE -- no
   libraries, no COM conversion), then the COM-converted ones (BACKUP/RESTORE),
   then the library-heavy ones (FDISK/MAPPER.LIB, SELECT/SERVICES.LIB, EMM386).
4. **Switch LIB.EXE -> `wlib`** for MAPPER/EMMLIB/COMSUBS/SERVICES libs (wlib
   already vendored; low risk, do alongside).

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

### WS4 -- Preprocessor retirement, CI, and validation (finish line)

- **Shrink `bin/preprocess-jwasm` toward deletion.** It is down to essentially
  one pass (comma-separate structured-directive args). End state: JWasm consumes
  the sources directly. Either land the upstream MASM-mode whitespace-arg-split
  fix in the JWasm fork, or bake the equivalent as direct source edits on
  `master`. Track each retired pass.
- **Keep the complete QEMU suite green.** The boot/serial harness and all QEMU
  Make targets passed the August 26 merge gate, including parallel FORMAT
  groups. Extend those tests as each native replacement lands.
- **CI**: add an explicitly kvikdos-free native-toolchain job as WS1 lands;
  retain reference jobs only while they prove parity with a tool being replaced.

---

## Milestones

- **M0 (DONE)** -- Pure-asm image fully open-source-built (JWasm + wlink),
  byte-identical to MS LINK; complete floppy via `make deploy`.
- **M1 (DONE)** -- WS1 steps 1-4: kvikdos removed from all pure-asm target builds
  (DBOF, BUILDIDX, EXE2BIN, NOSRVBLD, MENUBLD, CONVERT reimplemented). Biggest
  single step toward the goal.
- **M2** -- Finish ASC2HLP/COMPRESS: **zero proprietary
  build utilities**; kvikdos gone except for the C-hybrid compile/link step.
- **M3** -- WS4: qemu E2E validation green in CI; preprocessor deleted; golden
  refreshed from a boot-validated build.
- **M4** -- WS2: first C-hybrid (ATTRIB) fully running under wcc+wlink+open
  runtime; shared open-slibce module proven.
- **M5 (GOAL)** -- All ~14 C-hybrids on wcc+wlink; MS CL/LINK/LIB and kvikdos
  fully removed. 100% open-source toolchain.

## Decisions

- The target is the OSI-approved toolchain tier: custom JWasm plus Open Watcom.
- M5 is the active goal. M2 is an intermediate milestone, not a stopping point.
- WS1 goes first because it creates deterministic native reference tooling and
  removes emulation from the pure-assembly build path before the C-runtime work.
