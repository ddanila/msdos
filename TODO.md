# MS-DOS 4.0 Build — TODO

## Watcom Migration (ACTIVE)

**End state:** All assembly and C compilation uses Open Watcom (WASM, wcc, wlink, wlib) natively. The full E2E test suite passes on the WASM-built floppy image. kvikdos remains only for the 7 pre-built DOS build utilities (BUILDMSG, NOSRVBLD, EXE2BIN, CONVERT, BUILDIDX, DBOF, MENUBLD) — eliminating those is a separate future effort, not part of this migration.

**Current status:** Assembly migration complete (53/53 modules, 57 WASM compat issues fixed). COMMAND.COM + IO.SYS + MSDOS.SYS all boot — tests A–E pass on clean build (36976-byte MSDOS.SYS). Phase 1 kvikdos validation: VER works, 18/19 CMD utilities pass /? smoke tests. Source hygiene done (^Z stripped, SUBTTL/TITLE deleted, .gitattributes fixed). Full E2E pending.

**Key findings:**
- COMMAND.COM issue #52 (L2029 `$M_GET_MSG_ADDRESS` unresolved) fixed: renamed `$M_HAS_$M_GET_MSG_ADDRESS` → `$M_HAS_GETMSGADDR` to avoid WASM `$M_` symbol parsing bug.
- MSDOS.SYS issue #53 (`IF (NOT IBM) OR (DEBUG)` → `IF (IBM EQ 0) OR (DEBUG)`): WASM `NOT TRUE` in compound expressions evaluates as truthy. Copyright display code included erroneously, crashing DOSINIT.
- MSDOS.SYS issue #54 (`MSVERS LABEL WORD` → `MSVERS DW ...`): WASM emits `LABEL WORD` as absolute symbol (offset 0) instead of segment-relative. $GET_VERSION returned wrong version, COMMAND.COM failed version check.
- `bin/strip-wasm-segs` OMF post-processor created: strips WASM's auto-generated empty `_TEXT`/`_DATA` SEGDEFs that break MS LINK segment ordering in DOSGROUP.
- `test_wasm_boot.sh` FAT12 patcher: handles any file size via cluster chain extension/shrinking.
- Both MS LINK and wlink produce bootable COMMAND.COM from WASM OBJs.
- Full `IF NOT` audit complete (60+ instances across 38 files) — no `IF NOT` patterns remain.
- IO.SYS "Non-System disk" error (test E) was a boot sector BPB alignment bug, not an IO.SYS issue — see issue #58 below.
- Issue #58: boot sector BPB off-by-1. `MSBOOT.ASM`'s `JMP START` generated a 2-byte short JMP (no NOP), placing the BPB at offset 10. `mformat -k` always writes at the standard offset 11, corrupting all BPB fields and overwriting the first code instruction. Fix: added `NOP` after `JMP SHORT START` for the standard 3-byte boot JMP.

### Phase 0A: wlink proof-of-concept ✅ DONE

Proved that both MS LINK and wlink produce bootable COMMAND.COM from WASM OBJs. The crash was not a linker issue — it was the MSGSERV.ASM `IF NOT` bug (issue #51). wlink migration remains a future convenience step.

- [x] Hand-convert `COMMAND.LNK` to wlink directive syntax (`COMMAND.wlink`)
- [x] Link WASM-built COMMAND.COM OBJs with wlink (native, no kvikdos)
- [x] Boot test: both MS LINK and wlink COMMAND.COM boot to date prompt
- [ ] ~~If test passes, also test MSDOS.SYS~~ (deferred — MSDOS.SYS has its own runtime bugs)

**wlink response file format** (completely different from MS LINK):
```
FORMAT DOS
FILE obj1.obj, obj2.obj
NAME output.exe
OPTION MAP=output.map
OPTION STACK=50000
OPTION DOSSEG
LIBRARY lib1.lib
```
vs MS LINK positional: `obj1+obj2, output.exe, output.map, lib1 /STACK:50000;`

**If proof-of-concept succeeds:**
- [ ] Write `bin/wlink-mslink` wrapper — translates MS LINK response file format to wlink directives on the fly. Makes the switch transparent to the Makefile (`LINK := $(BIN)/wlink-mslink`). All 51 .LNK files work without modification.
- [ ] Handle /EXEPACK gap: 4 targets use it (SELECT, FIND, FDISK, EXE2BIN). wlink has no equivalent. Options: (a) skip packing — binaries slightly larger but functional, (b) use existing `bin/fix-exepack` as a post-link step.
- [ ] Verify segment ordering for kernel binaries (MSDOS.SYS, IO.SYS) — layout is critical.

**wlink flag mapping:**
| MS LINK | wlink | Notes |
|---------|-------|-------|
| `/MAP` | `OPTION MAP` | |
| `/DOSSEG` | `OPTION DOSSEG` | |
| `/STACK:N` | `OPTION STACK=N` | |
| `/NOI` | `OPTION CASEEXACT` | |
| `/EXEPACK` | none | Skip or post-process |
| `/NOE` | none | May not be needed |

### Cleanup: source hygiene ✅ DONE

**1. Strip `^Z` (0x1A) from all source files** ✅
Stripped ^Z from 332 ASM/INC/C/H files. WASM boot tests pass.
- [x] Python bulk strip: `data.replace(b'\x1a', b'')` across the submodule
- [x] Verify build still passes (W249 warnings gone)

**2. Fix `.gitattributes` for MSG files** ✅ (done in prior session)
- [x] Update `.gitattributes`: `*.MSG binary`
- [x] `git add --renormalize .` to fix blobs

**3. Delete commented-out SUBTTL/TITLE directives** ✅
Removed 37 lines across 13 files.
- [x] Remove all `;; SUBTTL` and `;; TITLE` lines

### Phase 0B: MSDOS.SYS and IO.SYS runtime debugging

Full `IF NOT` audit complete — all 60+ instances converted to `EQ 0`. The remaining failures are **not** `IF NOT` bugs.

**MSDOS.SYS (test C):** ✅ Fixed (issues #53, #54). 36976-byte clean build is correct — the "stale-OBJ regression" was actually a boot sector BPB bug (issue #58).

**IO.SYS (test E):** ✅ Fixed (issues #55, #56). Full WASM stack boots on clean build.

**Boot sector (issue #58):** ✅ Fixed. `MSBOOT.ASM` JMP was 2 bytes (no NOP), BPB at offset 10. `mformat -k` writes BPB at standard offset 11, corrupting all fields. Added NOP for standard 3-byte JMP.

- [x] Audit kernel source for remaining `IF NOT` patterns — done, all converted
- [x] Debug MSDOS.SYS crash: QEMU `-d in_asm` trace — fixed (issues #53, #54)
- [x] Debug IO.SYS disk read failure (test E) — fixed (issues #55, #56)
- [x] Fix and validate MSDOS.SYS boot (test C) — done (clean build works, issue #58 resolved)
- [x] Fix and validate IO.SYS (test E) — done
- [x] Fix boot sector BPB alignment (issue #58) — added NOP after JMP SHORT START
- [x] Fix `test_wasm_boot.sh` cluster overflow bug (COMMAND.COM truncation) — FAT chain extension + correct cluster range for 1.44MB
- [x] Fix issue #52: `$M_GET_MSG_ADDRESS` L2029 — renamed flag to `$M_HAS_GETMSGADDR`

### Phase 1: Individual binary validation under kvikdos (fast, no QEMU)

kvikdos can run COMMAND.COM (`/C` mode), any standalone .COM/.EXE, and has spawn support (8 levels deep). Much faster than QEMU for individual binary testing.

**COMMAND.COM under kvikdos:**

kvikdos invocation for COMMAND.COM 4.0 (needs mount + COMSPEC for transient checksum reload):
```bash
kvikdos/kvikdos-soft --dos-version=4 \
  --mount=C:MS-DOS/v4.0/src/CMD/COMMAND/ \
  --drive=C \
  --env=COMSPEC=C:\\COMMAND.COM \
  MS-DOS/v4.0/src/CMD/COMMAND/COMMAND.COM /C VER
```

- [x] Run WASM-built COMMAND.COM under kvikdos: prints "MS-DOS Version 4.00" — transient init works.
- [x] Fix kvikdos IOCTL 44/01 (Set Device Info): removed strict DH!=0 rejection and S_ISCHR gate on non-char fds (pipes).
- [x] Fix kvikdos IOCTL 44/08 (Get Drive Removable): was reading AL instead of BL for drive number.
- [ ] Run built-in commands: `/C DIR`, `/C COPY`, `/C SET FOO=BAR`, `/C FOR %X IN (A B C) DO ECHO %X` — tests TRANCODE dispatch table. Note: DIR gives "Extended Error 6" due to kvikdos FCB/INT 2Fh gaps, not a COMMAND.COM bug.
- [ ] Run Section 7 of run_tests.sh (COMMAND.COM built-in E2E) against WASM binary — covers 48 built-in command tests.
- [ ] If any built-in crashes, cross-reference the COMTAB dispatch offset with the OBJ analysis.

**Individual CMD utilities under kvikdos:**
- [x] Run /? smoke tests against 19 WASM-built CMD utilities. **18/19 pass, 1 kvikdos limitation:**
  - PASS: CHKDSK, COMP, DEBUG, EDLIN, FC, FDISK, FILESYS, FIND, FORMAT, JOIN, LABEL, MEM, MORE, NLSFUNC, SORT, SUBST, SYS, TREE — all print correct help text.
  - ATTRIB: prints correct help, then crashes on exit (`fatal: unsupported set interrupt vector int:00 to cs:0000 ip:0000`). This is a kvikdos limitation — ATTRIB restores INT 00 to null on exit. Not a WASM bug.
  - Not built yet (need full build chain): APPEND, ASSIGN, BACKUP, DISKCOMP, DISKCOPY, EXE2BIN, FASTOPEN, GRAFTABL, GRAPHICS, IFSFUNC, KEYB, MODE, PRINT, RECOVER, REPLACE, RESTORE, SHARE, XCOPY.
- [ ] Run Section 6 functional tests (FIND, FC, SORT, COMP, ATTRIB, MORE, DEBUG, EDLIN, etc.) against WASM-built binaries.

**Approach:** Modify `run_tests.sh` or create a wrapper that points `$SRC` to the WASM build output directory. No floppy image needed.

### Phase 2: Minimal QEMU boot (boot sector + IO.SYS + MSDOS.SYS + COMMAND.COM)

QEMU tests the boot chain that kvikdos cannot emulate.

- [x] Test B: MASM core + WASM COMMAND.COM — passes
- [x] Test C: MASM BIOS + WASM MSDOS.SYS — passes (stale-OBJ MSDOS.SYS; clean-build regression open)
- [x] Test D: WASM MSDOS.SYS + WASM COMMAND.COM — passes
- [x] Test E: full WASM — passes on clean build (issue #58 fixed)
- [x] Use `tests/test_wasm_boot.sh` (already exists) for all of the above

### Phase 3: Full E2E test suite on WASM build

- [ ] `make deploy` with WASM-built floppy image
- [ ] `make test` (kvikdos fast tests — reuses Sections 1–7)
- [ ] Full QEMU E2E test suite: FORMAT, SYS, FDISK, DISKCOMP, DISKCOPY, drivers, BACKUP/RESTORE, etc.
- [ ] Binary size comparison: MASM vs WASM for all outputs (track regressions)

#### Disassembly diff verification (MASM vs WASM)

Complementary to E2E tests: compare disassembled output from MASM and WASM builds to verify semantic equivalence at the instruction level. This directly catches the main class of WASM migration bugs — conditional assembly mismatches (`IF NOT`, `IFNDEF` behavioral differences) — without needing to boot anything.

**Approach:**
1. Build all modules with MASM (reference) — already available from master branch
2. Build all modules with WASM (migration)
3. Disassemble both with the same tool, diff the output
4. Triage differences: cosmetic (expected) vs semantic (bugs)

**Two-level comparison:**

**Level 1 — OBJ-level (per-module, most granular):**
Use `wdis` (Open Watcom disassembler, already vendored) to disassemble each `.OBJ` file. Compare per-module before linking, so each diff is small and localized.
```bash
wdis -a module_masm.obj > module_masm.dis
wdis -a module_wasm.obj > module_wasm.dis
diff module_masm.dis module_wasm.dis
```

**Level 2 — final binary (linked output):**
Use `ndisasm` (NASM project) for flat .COM/.BIN files, or `objdump` for MZ .EXE:
```bash
ndisasm -b 16 COMMAND_masm.COM > command_masm.dis
ndisasm -b 16 COMMAND_wasm.COM > command_wasm.dis
diff command_masm.dis command_wasm.dis
```

**Expected cosmetic differences (filterable noise):**
- `DS:` segment override prefixes (`3E` byte) — WASM requires explicit `DS:` where MASM inferred it
- Instruction encoding variants — same semantics, different opcode choice (e.g., `MOV AX,BX` as `89 D8` vs `8B C3`)
- Offset shifts cascading from the above (addresses change by 1+ bytes)

**Real bugs would look like:**
- Entire instruction blocks present in one but absent in the other — conditional assembly mismatch (e.g., `IF NOT` evaluating differently)
- Different branch targets — wrong label resolution
- Different immediate values — wrong EQU evaluation
- Missing or extra `EXTRN`/`PUBLIC` symbols — IFNDEF/EXTRN interaction bugs

**Tasks:**
- [ ] Vendor or confirm `wdis` availability (may need to add to `watcom/bin/`)
- [ ] Build reference MASM .OBJ set from master branch
- [ ] Write `bin/disasm-diff` script: automates wdis on paired OBJ files, filters known cosmetic diffs, reports unexpected changes
- [ ] Run OBJ-level diff on all 53 modules, triage results
- [ ] Run final binary diff on key outputs: COMMAND.COM, IO.SYS, MSDOS.SYS, FORMAT.COM, CHKDSK.COM
- [ ] Document all confirmed-cosmetic difference patterns for future reference

### Phase 4: C compiler + library manager migration

**Goal:** Replace CL.EXE (via kvikdos) with wcc (native Open Watcom) for all 7 C modules, and LIB.EXE with wlib.

**Flag mapping (CL → wcc):**
| CL flag | Meaning | wcc equivalent |
|---------|---------|----------------|
| `-AS` | Small memory model | `-ms` |
| `-Os` | Optimize for size | `-os` |
| `-Od` | No optimization (BACKUP/RESTORE) | `-od` |
| `-Zp` | Pack structs (1-byte align) | `-zp1` |
| `-c` | Compile only | implicit (wcc never links) |
| `-Fo<name>` | Output OBJ name | `-fo=<name>` |
| `-I<dir>` | Include directory | `-i=<dir>` |

**Recommended wcc invocation** (replacing `CL -AS -Os -Zp`):
```
wcc -ms -os -s -0 -ecc -zp1 -i=. -i=../../H -fo=<output>.OBJ <input>.C
```

**Known risks and compatibility notes:**
- **Calling convention (critical):** wcc defaults to `__watcall` (register-based: AX, DX, BX, CX). All ASM modules (`_MSGRET.ASM`, `_PARSE.ASM`, `BOOTREC.ASM`, etc.) expect `__cdecl` (stack-based, caller cleans). Must use `-ecc` flag to force cdecl globally.
- **Segment naming (safe):** wcc `-ms` produces identical segment layout to CL `-AS`: `_TEXT`/`_DATA`/`_BSS`/`DGROUP`. OBJs should link cleanly with existing ASM objects.
- **Struct packing (critical):** Default wcc alignment is 8-byte (`-zp8`). Must use `-zp1` to match CL `-Zp`. Wrong alignment silently breaks C↔ASM struct sharing.
- **Runtime startup:** Watcom's `cstart_s.obj` adds a `BEGDATA` segment with null-pointer detection byte. May conflict with MS LINK segment ordering. Options: (a) use wlink for C modules, (b) suppress with `-zl` flag, (c) provide custom startup.
- **C library:** If any module uses libc functions (printf, malloc, etc.), need to vendor `clibs.lib` (Watcom small-model DOS C library from `lib286/dos/`). Currently not in `watcom/` directory.
- **Inline assembly:** If any C files use `_asm`/`__asm` blocks, syntax differs. Watcom uses `#pragma aux` for some inline operations.
- **wlink .COM bug (issue #820):** wlink has been reported to corrupt .COM files when linking C code. Affects BACKUP.COM, RESTORE.COM (compiled as .EXE, then CONVERT to .COM). If using wlink, test these carefully. MS LINK does not have this issue.
- **Code size:** wcc `-os` produces roughly comparable output to CL `-Os`. Not smaller, not larger. The value is eliminating kvikdos, not shrinking binaries.

**C modules (7 total):**
| Module | Source dir | Libraries | Notes |
|--------|-----------|-----------|-------|
| FDISK | CMD/FDISK | MAPPER.LIB | Uses `-Od` (debug), MENUBLD-generated C source |
| BACKUP | CMD/BACKUP | COMSUBS.LIB | Compiled as EXE → CONVERT to COM |
| RESTORE | CMD/RESTORE | COMSUBS.LIB | Compiled as EXE → CONVERT to COM |
| REPLACE | CMD/REPLACE | — | |
| FC | CMD/FC | — | |
| FILESYS | CMD/FILESYS | — | Requires IFSFUNC TSR |
| SELECT | SELECT | SERVICES.LIB | Uses /EXEPACK (no wlink equivalent) |

**Tasks:**
- [ ] Vendor wcc small-model DOS C library (`clibs.lib`) into `watcom/lib/`
- [ ] Write `bin/wcc-cl` wrapper (translates CL calling convention to wcc, similar to `wasm-masm`)
- [ ] Test one simple module first (FC or REPLACE — no libraries, no COM conversion)
- [ ] Migrate remaining modules, verify each links with MS LINK
- [ ] Replace LIB.EXE with wlib (already vendored) for MAPPER.LIB, EMMLIB.LIB, COMSUBS.LIB, SERVICES.LIB
- [ ] Verify E2E tests pass with wcc-compiled and wlib-built binaries
- [ ] Binary size comparison: CL vs wcc for all 7 modules

### Phase 5: CI pipeline update

- [ ] Update `.github/workflows/ci.yml` to use native Open Watcom toolchain
- [ ] Verify CI passes on both Linux x64 and macOS ARM64
- [ ] Update build documentation (README.md dependencies section)

### Phase 6: Native replacements for DOS build utilities

**Goal:** Replace all 7 Microsoft-proprietary DOS build utilities with native Python scripts, eliminating kvikdos entirely from the build. Currently 86 total kvikdos invocations across the build.

**Summary:**

| Tool | Invocations | Complexity | Est. Python LOC | Replacement strategy |
|------|------------|-----------|----------------|---------------------|
| DBOF | 2 | Trivial | ~20 | Self-made Python script |
| BUILDIDX | 1 | Trivial | ~40 | Self-made Python script |
| EXE2BIN | 32 | Low | ~50 | Self-made Python script (or vendor Open Watcom's native exe2bin) |
| MENUBLD | 1 | Low-medium | ~80 | Self-made Python script |
| NOSRVBLD | 8 | Low-medium | ~150 | Self-made Python script |
| CONVERT | 7 | Medium | ~150 + asm stub | Self-made Python script with embedded x86 relocating stub |
| BUILDMSG | 36 | Medium-high | ~350 | Self-made Python script |

**Recommended order:** DBOF + BUILDIDX → EXE2BIN → NOSRVBLD + MENUBLD → CONVERT → BUILDMSG. Replacing the first 3 eliminates 35 of 86 kvikdos invocations.

---

#### 6.1 DBOF — binary to INC hex dump (trivial)

**What it does:** Reads a binary file and emits an ASM `.INC` file with `db` directives — 8 hex bytes per line, `0xxH` format, tab-indented.

**Invocations (2):**
```makefile
cd $(BOOT_DIR)  && $(DBOF) "MSBOOT.BIN BOOT.INC 7c00 200"
cd $(FDISK_DIR) && $(DBOF) "FDBOOT.BIN FDBOOT.INC 600 200"
```

**Arguments:** `INPUT.BIN OUTPUT.INC OFFSET_HEX SIZE_HEX` — offset is the load address (informational/for EQU generation), size is byte count to read (0x200 = 512 bytes).

**Output format** (from `BOOT.INC` / `FDBOOT.INC`):
```asm
	db	0FAH,033H,0C0H,08EH,0D0H,0BCH,000H,07CH
	db	08BH,0F4H,050H,007H,050H,01FH,0FBH,0FCH
```

**Implementation:** ~20 lines of Python. Read binary, chunk into 8-byte groups, format as `0xxH`.

- [ ] Write `bin/dbof` replacement (Python)
- [ ] Verify output matches original BOOT.INC and FDBOOT.INC byte-for-byte
- [ ] Update Makefile to use native script

#### 6.2 BUILDIDX — message index builder (trivial)

**What it does:** Reads `USA-MS.MSG` and produces `USA-MS.IDX` — a plain text index mapping each named message pool to its byte offset and entry count.

**Invocations (1):**
```makefile
cd $(MESSAGES_DIR) && $(BUILDIDX) USA-MS.MSG
```

**Output format** (from `USA-MS.IDX`):
```
0099
COMMON   0006 0038
EXTEND   0685 0090
COMMAND  14c8 0091
...
```
Line 1: total message count. Subsequent lines: `POOLNAME   OFFSET_HEX COUNT_HEX`.

**Implementation:** ~40 lines of Python. Scan MSG file for pool headers, record byte offsets and entry counts.

- [ ] Write `bin/buildidx` replacement (Python)
- [ ] Verify output matches original USA-MS.IDX byte-for-byte
- [ ] Update Makefile to use native script

#### 6.3 EXE2BIN — MZ EXE to flat binary (low)

**What it does:** Strips the MZ header from a DOS .EXE file and writes the raw code/data. Optionally applies segment relocations (adding a base segment to each relocation entry). Used for .COM files, boot sectors (.BIN), device drivers (.SYS), and data files (.DAT, .CPI).

**Invocations (32):** MSLOAD, MSBIO, MSDOS, COMMAND, MORE, LABEL, TREE, COMP, ASSIGN, DISKCOMP, DISKCOPY, GRAFTABL, KEYB, GRAPHICS, MODE, SELECT, FDBOOT, SYS, FIND, SORT, ATTRIB, APPEND, SHARE, MEM, NLSFUNC, FASTOPEN, IFSFUNC, device drivers (DRIVER, ANSI, VDISK, RAMDRIVE, KEYBOARD, PRINTER, DISPLAY).

**Special cases:**
- MSBIO uses stdin redirection: `$(EXE2BIN) "MSBIO.EXE MSBIO.BIN" <LOCSCR` — LOCSCR provides the load segment for relocation
- PRINTER & DISPLAY use `<ZERO.DAT` for same purpose
- Most invocations have zero relocations (just header stripping)

**MZ header format:** 28-byte fixed header. Signature `MZ`/`ZM` at offset 0. `e_cblp` (bytes on last page) at 0x02, `e_cp` (pages) at 0x04, `e_crlc` (relocation count) at 0x06, `e_cparhdr` (header size in 16-byte paragraphs) at 0x08, `e_lfarlc` (relocation table offset) at 0x18. Code starts at `e_cparhdr * 16`.

**Algorithm:**
1. Read MZ header, validate signature
2. Skip to `header_paragraphs * 16` (code start)
3. For each relocation entry: read segment:offset pair, add base segment to the word at that file offset
4. Write everything from code start to end

**Open-source alternatives:**
- Open Watcom ships a native `exe2bin` ([source](https://github.com/open-watcom/open-watcom-v2/blob/master/bld/wl/exe2bin/exe2bin.c), ~450 lines C) — not currently vendored
- FreeDOS exe2bin ([GitLab](https://gitlab.com/FDOS/base/exe2bin)) — Sybase Open Watcom Public License

**Implementation:** ~50 lines of Python. Most invocations are zero-relocation (just skip header + copy), making it especially simple.

- [ ] Write `bin/exe2bin` replacement (Python)
- [ ] Handle stdin base segment for MSBIO/PRINTER/DISPLAY special cases
- [ ] Verify output matches original for all 32 invocations (binary diff)
- [ ] Update Makefile to use native script

#### 6.4 MENUBLD — FDISK menu data to C source (low-medium)

**What it does:** Reads `FDISK.MSG` (menu definitions with `^rrcc^` cursor positioning, `<H>`/`<R>`/`<U>` attributes, `<I>` insert placeholders) and `USA-MS.MSG`, generates `FDISKM.C` — C source with `char far *menu_XX = "..."` declarations. The input and output are nearly identical text — MENUBLD primarily substitutes localized strings from USA-MS.MSG.

**Invocations (1):**
```makefile
cd $(FDISK_DIR) && $(MENUBLD) "FDISK.MSG ..\\..\\MESSAGES\\USA-MS.MSG"
```

**Implementation:** ~80 lines of Python. Copy-through with string substitution from MSG pool.

- [ ] Examine FDISK.MSG vs FDISKM.C to document exact transformations
- [ ] Write `bin/menubld` replacement (Python)
- [ ] Verify FDISKM.C output matches original
- [ ] Update Makefile to use native script

#### 6.5 NOSRVBLD — simple message class generator (low-medium)

**What it does:** Simpler variant of BUILDMSG. Takes a `.SKL` file and `USA-MS.MSG`, produces `.CL1`–`.CL5` files containing raw `DB` directives with label names — no class structure wrappers, no `PROC`. Used for kernel-level messages (BIOS, DOS, boot sector) that use a simpler retrieval mechanism.

**Invocations (8):**
```makefile
cd $(BOOT_DIR)    && $(NOSRVBLD) BOOT.SKL "..\MESSAGES\USA-MS.MSG"
cd $(BIOS_DIR)    && $(NOSRVBLD) MSBIO.SKL "..\MESSAGES\USA-MS.MSG"
cd $(DOS_DIR)     && $(NOSRVBLD) MSDOS.SKL "..\MESSAGES\USA-MS.MSG"
cd $(FDISK_DIR)   && $(NOSRVBLD) FDISK5.SKL "..\\..\\MESSAGES\\USA-MS.MSG"
cd $(XMA2EMS_DIR) && $(NOSRVBLD) XMA2EMS.SKL "..\\..\\MESSAGES\\USA-MS.MSG"
cd $(XMAEM_DIR)   && $(NOSRVBLD) XMAEM.SKL "..\\..\\MESSAGES\\USA-MS.MSG"
```
(Plus 2 more for BIOS/DOS additional SKLs.)

**SKL format** (line-oriented):
```
:class N          — start class N
:def NNN "text"   — define message NNN with literal text
:def NNN LABEL DB ... — define with assembly DB directives
:use NNN COMMONXX — reference shared message from USA-MS.MSG
:end              — end of file
```

**Output format:** Simple labeled `DB` lines:
```asm
LABEL	DB	"message text",0Dh,0Ah
```

**Implementation:** ~150 lines of Python. Parse SKL directives, resolve `:use` references from MSG file, emit `DB` lines.

- [ ] Examine existing .CL1 outputs to document exact format
- [ ] Write `bin/nosrvbld` replacement (Python)
- [ ] Verify output matches original for all 8 invocations
- [ ] Update Makefile to use native script

#### 6.6 CONVERT — EXE to COM with relocating stub (medium)

**What it does:** Unlike EXE2BIN (which requires zero relocations for .COM), CONVERT handles .EXE files **with relocations** by prepending a small x86 relocating stub. The stub patches segment references at load time, then jumps to the real entry point. The output is a .COM file that is self-relocating.

**Invocations (7):**
```makefile
cd $(FORMAT_DIR)  && $(CONVERT) "FORMAT.EXE"
cd $(CHKDSK_DIR)  && $(CONVERT) "CHKDSK.EXE"
cd $(DEBUG_DIR)   && $(CONVERT) "DEBUG.EXE"
cd $(EDLIN_DIR)   && $(CONVERT) "EDLIN.EXE"
cd $(RECOVER_DIR) && $(CONVERT) "RECOVER.EXE"
cd $(PRINT_DIR)   && $(CONVERT) "PRINT.EXE"
cd $(BACKUP_DIR)  && $(CONVERT) "BACKUP.EXE BACKUP.COM"
cd $(RESTORE_DIR) && $(CONVERT) "RESTORE.EXE RESTORE.COM"
```

**How it works:**
1. Parse MZ header and relocation table
2. Prepend a fixed x86 relocating stub (~50-80 bytes of 16-bit machine code)
3. Append the relocation table entries (compact format)
4. Append the EXE body (minus MZ header)
5. The stub, at .COM load time: reads relocation entries, patches each segment reference (adds current CS), sets up SS:SP, far-jumps to real CS:IP

**Reference implementations:**
- [exe2com.asm](https://github.com/leonardo-ono/Assembly80863DCubeAdlibMusicDemoTest/blob/master/exe2com.asm) — ~43 lines of NASM showing the relocating stub concept

**Implementation:** ~150 lines of Python + embedded x86 stub blob (~80 bytes, hand-crafted once in assembly). The Python script assembles: stub + relocation data + EXE body. The stub itself is fixed binary — write it once, embed as a byte literal.

- [ ] Reverse-engineer the exact stub format by examining existing CONVERT output (e.g., FORMAT.COM)
- [ ] Write the relocating stub in NASM/WASM, assemble to binary blob
- [ ] Write `bin/convert` replacement (Python) embedding the stub
- [ ] Verify output matches original for all 7 invocations (boot test FORMAT.COM, CHKDSK.COM, DEBUG.COM)
- [ ] Update Makefile to use native script

#### 6.7 BUILDMSG — full message compiler (medium-high)

**What it does:** The main message compiler. Takes a `.SKL` skeleton file and `USA-MS.MSG` message database, produces `.CTL` (class count) + `.CL*` files (CL1, CL2, CLA, CLB, etc.) — full MASM-compatible assembly includes with message structures, length-prefixed `DB` strings, and lookup `PROC`s.

**Invocations (36):** COMMAND, SYS, FORMAT, CHKDSK, FDISK, BACKUP, RESTORE, REPLACE, FC, and 27 more across CMD, DEV, and SELECT modules.

**Invocation pattern:**
```makefile
cd $(CMD_DIR) && $(BUILDMSG) "..\\..\\MESSAGES\\USA-MS" UTIL.SKL
```

**SKL format** (line-oriented):
```
:util NAME        — utility name
:class N|A|B|...  — start message class (numeric or letter)
:def NNN "text"   — define message inline
:use NNN COMMONXX — reference shared message from MSG pool
:use NNN EXTENDXX — reference extended error message
:use NNN PARSEXX  — reference parser error message
:end              — end of file
```

**Output formats:**
- **CTL file:** Single line: `$M_NUM_CLS EQU N` (class count)
- **CL letter files (CLA, CLB):** Full MASM include with `$M_CLASS_A_STRUC`, `$M_ID` entries, `DB` strings with length prefix, `$M_CLS_1 PROC` returning ES:DI to class structure
- **CL numeric files (CL1, CL2):** Same structure with `$M_MSGSERV_N PROC` names, `$M_N_FF_STRUC` message IDs

**Implementation:** ~350 lines of Python. The core logic:
1. Parse SKL directives (`:util`, `:class`, `:def`, `:use`, `:end`)
2. Parse USA-MS.MSG to resolve `:use` references (MSG file has named pools: COMMON, EXTEND, PARSE, per-utility, etc., each with numbered entries)
3. Generate MASM assembly output with correct structure (`$M_CLASS_ID`, `$M_ID` structs, length-prefix `DB`, lookup `PROC` with `PUSH CS / POP ES / LEA DI`)
4. Handle class naming: numeric → `$M_MSGSERV_N`, letter → `$M_CLS_N`
5. Generate CTL file with class count

**Main challenge:** Getting the assembly template byte-exact. The `$M_CLASS_ID`/`$M_ID` struct macros and the `PROC` boilerplate must match what the existing SYSMSG.INC message framework expects at runtime.

- [ ] Document exact CL/CTL output format by examining multiple existing outputs
- [ ] Document USA-MS.MSG pool structure and reference resolution
- [ ] Write `bin/buildmsg` replacement (Python)
- [ ] Verify output matches original for all 36 invocations (binary diff of CL/CTL files)
- [ ] Run full E2E test suite with Python-generated message files
- [ ] Update Makefile to use native script

---

## INT 21h Unit Test (standalone, master branch)

Goal: a standalone `.COM` test harness that exercises every INT 21h function and reports pass/fail. Runs on real DOS (QEMU) and validates the kernel independently of the toolchain. Can be built and used on master branch — not tied to the Watcom migration.

**Source of truth:** `DOS/MS_TABLE.ASM` dispatch table (109 entries, AH=00h–6Ch). Each handler's expected behavior must be verified from the kernel source code, not from generic DOS documentation.

**Design:**
- Single `.ASM` file → `.COM` (no LINK, no message framework, no dependencies)
- Self-contained: creates its own test files, cleans up after itself
- Output: one line per test group to serial/console (`PASS: File I/O` or `FAIL: File I/O - AH=3Ch`)
- Exit code: 0 = all pass, 1 = any failure
- Usable in CI: boot QEMU with CTTY AUX, capture serial, grep for FAIL

**Test groups (by INT 21h AH function):**

### Core file I/O (17 functions)
| AH | Test |
|----|------|
| 3Ch | Create file, verify handle returned |
| 3Dh | Open existing file (read, write, r/w modes) |
| 3Eh | Close handle, verify double-close fails |
| 3Fh | Read bytes, verify count and content |
| 40h | Write bytes, read back and compare |
| 41h | Delete file, verify open fails after |
| 42h | Seek (beginning, current, end), verify position |
| 43h | Get/set file attributes (readonly, archive) |
| 45h | Dup handle, write via dup, read via original |
| 46h | Dup2 (force dup), verify redirect works |
| 56h | Rename file, verify old name gone + new exists |
| 57h | Get/set file date/time, verify roundtrip |
| 5Ah | Create temp file, verify unique name |
| 5Bh | Create new (fail if exists), verify error on second call |
| 5Ch | Lock region, verify concurrent access blocked |
| 68h | Commit (flush), verify no error |
| 6Ch | Extended open/create (DOS 4.0+), verify action codes |

### Directory (4 functions)
| AH | Test |
|----|------|
| 39h | Mkdir, verify exists |
| 3Bh | Chdir into it, verify with 47h |
| 47h | Get current dir, verify path string |
| 3Ah | Rmdir, verify gone |

### Find first/next (2 functions)
| AH | Test |
|----|------|
| 4Eh | Find first with wildcard, verify DTA filled |
| 4Fh | Find next, verify iteration + termination |

### Memory management (4 functions)
| AH | Test |
|----|------|
| 48h | Allocate block, verify segment returned |
| 4Ah | Resize block (grow and shrink) |
| 49h | Free block, verify double-free fails |
| 58h | Get/set allocation strategy, verify roundtrip |

### Process control (testable subset)
| AH | Test |
|----|------|
| 4Ch | Exit with code (implicitly tested — the test itself exits) |
| 4Dh | Get child exit code (after spawning a tiny helper) |
| 62h | Get PSP, verify segment matches CS-10h for .COM |
| 30h | Get DOS version, verify major=4 |
| 2Eh | Set verify flag, 54h get verify — roundtrip |

### Console I/O (testable via serial/CTTY AUX)
| AH | Test |
|----|------|
| 02h | Output char, verify echo |
| 09h | Print $-terminated string |
| 06h | Direct console I/O (output mode) |
| 0Bh | Check input status (should be "no input ready") |

### Date/time
| AH | Test |
|----|------|
| 2Ah | Get date, verify year ≥ 1980 |
| 2Ch | Get time, verify hours 0-23 |

### System info
| AH | Test |
|----|------|
| 19h | Get default drive, verify 0-25 range |
| 0Eh | Set default drive, 19h get — roundtrip |
| 1Ah | Set DTA, 2Fh get DTA — roundtrip |
| 25h | Set interrupt vector, 35h get — roundtrip |
| 33h | Get/set Ctrl-C check — roundtrip |
| 65h | Get extended country info (NLS), verify buffer filled |
| 66h | Get global code page, verify non-zero |
| 69h | Get disk serial number, verify structure |

### FCB legacy (selective — verify not broken)
| AH | Test |
|----|------|
| 29h | Parse filename into FCB, verify fields |
| 11h/12h | FCB find first/next, verify DTA |

### Not tested (by design)
- 00h, 31h (terminate/TSR — can't return from these)
- 4Bh (exec — complex, tested separately in E2E suite)
- 5Dh-5Fh (network — not relevant)
- 03h-05h (aux/printer — hardware dependent)
- IOCTL 44h (device-specific, too many subfunctions)

---

## UMB Support (Upper Memory Blocks)

Goal: add UMB support to our MS-DOS 4.0 fork so device drivers and TSRs can be loaded into upper memory (640K–1MB), freeing conventional memory. Backporting the MS-DOS 5.0 concept.

Reference implementations (for study, not copying):
- **FreeDOS kernel** — UMB link/unlink, `DOS=UMB`, `DEVICEHIGH`, arena chain management.
- **JEMM** (Japheth's EMM386) — UMB provider via INT 2Fh/AX=4310h (XMS), V86 page mapping.

### Phase 1: EMM386 — UMB provider

- [ ] Study how UMBs are exposed: INT 2Fh/AX=4310h → XMS driver entry, functions 10h (Request UMB) / 11h (Release UMB)
- [ ] Study our EMM386 source (`MEMM/`) — V86 mode setup, page table management, existing EMS page frame mapping
- [ ] Add XMS UMB allocation (function 10h): map available upper memory regions (C000–EFFF gaps) as allocatable UMBs
- [ ] Add XMS UMB release (function 11h)
- [ ] UMB region detection: scan adapter ROM signatures (55AA) and video RAM for free gaps; configurable (e.g., `DEVICE=EMM386.SYS I=C800-EFFF`)
- [ ] Test: verify XMS UMB functions work from a test program under QEMU

### Phase 2: MSDOS kernel — UMB-aware memory management

- [ ] Study MS-DOS 5.0+ MCB arena chain structure: how UMBs are linked as a second arena above conventional memory
- [ ] Study FreeDOS kernel source for the UMB link/unlink mechanism
- [ ] `DOS=UMB` CONFIG.SYS directive: kernel calls XMS to request UMBs at init and links them into the MCB chain
- [ ] `DOS=HIGH,UMB` combination
- [ ] MCB chain linking: create MCB headers for UMB regions and chain them to end of conventional memory arena
- [ ] INT 21h/AH=58h subfunction 03h (Set UMB Link State) and 02h (Get UMB Link State)
- [ ] Test: verify `MEM` shows upper memory region, allocation from UMBs works

### Phase 3: COMMAND.COM / CONFIG.SYS — DEVICEHIGH, LOADHIGH

- [ ] `DEVICEHIGH=` CONFIG.SYS directive: load device drivers into UMBs (try UMB first, fall back to conventional)
- [ ] `LOADHIGH` / `LH` COMMAND.COM built-in: load TSRs into UMBs
- [ ] `MEM /C` or similar: show which programs/drivers are in upper memory
- [ ] Test: boot with `DOS=UMB`, `DEVICEHIGH=ANSI.SYS`, verify ANSI.SYS loads into UMA

### Phase 4: HMA — Load DOS High

Load MSDOS.SYS kernel into the HMA (first 64K-16 bytes above 1MB), freeing ~40-50K of conventional memory. Requires A20 gate control and XMS driver.

- [ ] Study HMA mechanics: A20 gate, FFFF:xxxx wrapping, the 64K-16 byte limit
- [ ] XMS prerequisite: EMM386 or minimal HIMEM.SYS must provide functions 01h/02h (Request/Release HMA) and A20 control (03h–07h)
- [ ] Decide: add HMA/A20/XMS support to EMM386, or implement separate HIMEM.SYS
- [ ] `DOS=HIGH` CONFIG.SYS directive: request HMA, enable A20, relocate kernel to FFFF:0010+
- [ ] INT 21h dispatch fix-ups: entry points must remain in low memory or use A20-aware thunks
- [ ] Test: boot with `DOS=HIGH,UMB`, verify MEM shows DOS in HMA and conventional memory increases by ~45K

### Notes

- From-scratch implementation for fun/learning. FreeDOS and JEMM as architectural references only.
- Existing EMM386.SYS already does V86 mode and EMS page mapping — UMB/HMA extend this.
- Testing strategy: QEMU with ≥1MB RAM, verify via MEM output.

---

## E2E Test Coverage Summary

All commands have functional E2E tests. kvikdos handles fast tests (`run_tests.sh`), QEMU+serial for disk/TSR/interactive tests. CI runs parallel jobs per test target (`.github/workflows/ci.yml`).

| Tool | Functional | Test location |
|------|-----------|---------------|
| COMMAND.COM | 48 kvikdos tests + COMMAND /? (QEMU) + CHCP show/set 850 | run_tests.sh §7, test_misc_qemu.sh, test_drivers_qemu.sh |
| MEM | basic + /PROGRAM + /DEBUG | run_tests.sh §6 |
| FIND | /V /N /C + errorlevel-2 + stdin pipe | run_tests.sh §6, test_misc_qemu.sh |
| FC | /A /B /C /N /W /L /LB /T /5 + error | run_tests.sh §6 (15 tests) |
| ATTRIB | +R -R +A -A /S | run_tests.sh §6 (8 tests) |
| COMP | identical/diff/hex/limit/not-found | run_tests.sh §6 (7 tests) |
| TREE | basic /F /A | run_tests.sh §6 (5 tests) |
| SORT | stdin /R /+N | run_tests.sh §6 (5 tests) |
| MORE | stdin, file | run_tests.sh §6 (3 tests) |
| DEBUG | R/E/D/F/H/C/M/S/A/U/N/W/L + G execute | run_tests.sh §6, test_debug_qemu.sh |
| EDLIN | 18 tests + /B binary mode | run_tests.sh §6 |
| XCOPY | /A /D /E /M /P /S /V /W — all v4.0 flags | run_tests.sh §6, test_prompt_yesno.sh |
| REPLACE | /A /P /R /S /U /W — all v4.0 flags | run_tests.sh §6, test_prompt_yesno.sh |
| GRAFTABL | 437 850 /STATUS | run_tests.sh §6 |
| LABEL | read-only + interactive set/delete | run_tests.sh §6, test_label.sh |
| ASSIGN | B=A redirect + clear | test_assign_subst_join.sh |
| SUBST | D: create/list/delete + file I/O (COPY, DIR, TYPE, pass-through) | test_assign_subst_join.sh |
| JOIN | B: join/list/verify/unjoin + file I/O (TYPE, COPY through joined path) | test_assign_subst_join.sh |
| EXE2BIN | 3 tests | run_tests.sh §6, test_share_nlsfunc_exe2bin.sh |
| CHKDSK | disk stats, /V, file alloc, /F orphan fix | test_misc_qemu.sh, test_chkdsk_fix.sh |
| FORMAT | 12 variants: /V /S /B /F:720 /T /4 /1 /8 /C /Z /SELECT /AUTOTEST | test_format.sh |
| SYS | boot verification | test_sys.sh |
| DISKCOPY | /1, /V parse error | test_diskcomp_diskcopy.sh |
| DISKCOMP | /1, /8 | test_diskcomp_diskcopy.sh |
| BACKUP | /S /M /A /F /D /T /L | test_backup_restore.sh |
| RESTORE | /S /N /M /B /A /E /L /P | test_backup_restore.sh, test_prompt_yesno.sh |
| SHARE | /F /L /NC | test_share_nlsfunc_exe2bin.sh |
| NLSFUNC | install + CHCP interaction + CP switch | test_share_nlsfunc_exe2bin.sh, test_drivers_qemu.sh |
| APPEND | /E /X path /PATH:ON /PATH:OFF | test_append.sh |
| KEYB | US, GR, UK,850, FR /ID:189 | test_misc_qemu.sh |
| FDISK | /PRI /EXT /LOG /Q + primary-only (PTM P941) | test_fdisk.sh |
| PRINT | /D /B /Q /S /U /M /P /C /T | test_misc_qemu.sh |
| FASTOPEN | C:=50, /X | test_misc_qemu.sh |
| GRAPHICS | load, reload, /R /B /LCD /PB:STD | test_misc_qemu.sh |
| MODE | CON /STATUS, COLS/LINES, RATE/DELAY, COM1, LPT1, LPT1:=COM1: | test_misc_qemu.sh |
| RECOVER | file-mode recovery | test_recover.sh |
| IFSFUNC | install + already-installed | test_misc_qemu.sh |
| FILESYS | install (requires IFSFUNC) | test_misc_qemu.sh |
| SELECT | stub INT 16H + SELECT.EXE exec + error path | test_select.sh |
| Device drivers | ANSI.SYS, RAMDRIVE.SYS, VDISK.SYS, DISPLAY.SYS, SMARTDRV.SYS | test_drivers_qemu.sh |
| CONFIG.SYS | BUFFERS FILES LASTDRIVE BREAK STACKS FCBS INSTALL SHELL COUNTRY | test_drivers_qemu.sh |

## Bug Fix Regression Coverage

All bug fixes from dos4-enhancements branch have regression tests:

| Fix | Commit | Test |
|-----|--------|------|
| EDLIN /B (2 fixes) | 52f514b + 61b2920 | §6 ^Z test |
| FOR hang (ES corruption) | c70042b | §7 FOR loop timeout |
| SET/PROMPT hang (ES corruption) | ae75edf | §7 stress test (10 alternating calls) |
| FDISK R6001 + semicolon | a5a02a9 | test_fdisk.sh boot 2 (primary-only, PTM P941) |
| COMMAND parser crash (signed cmp) | 4ed73cb | §7 VER with argbuf at 0x80BD |
| COMMAND boot crash (help code path) | 58a0bb4 | test_misc_qemu.sh COMMAND /? |

## QEMU-only tests (won't migrate to kvikdos)

| Test | Reason |
|------|--------|
| test_format.sh | INT 13h formatting, BPB geometry, QMP disk swapping |
| test_sys.sh | Boot verification |
| test_diskcomp_diskcopy.sh | Track-by-track INT 13h |
| test_label.sh | FAT volume writes, interactive prompts |
| test_backup_restore.sh | Multi-disk, interactive prompts |
| test_append.sh | TSR persistence (INT 2Fh + KEEP_PROCESS) |
| test_assign_subst_join.sh | TSR drive table manipulation, multi-disk |
| test_share_nlsfunc_exe2bin.sh | TSR persistence |
| test_misc_qemu.sh | CHKDSK INT 13h; all TSR tools |
| test_debug_qemu.sh | DEBUG G needs INT 21h/AH=5Dh |
| test_recover.sh | FAT chain walking + INT 13h |
| test_chkdsk_fix.sh | FAT12 corruption + interactive Y/N |
| test_prompt_yesno.sh | Interactive Y/N prompts (XCOPY/REPLACE/RESTORE /P) |
| test_fdisk.sh | INT 13h disk partitioning |
| test_drivers_qemu.sh | CONFIG.SYS device drivers, boot verification |
| test_select.sh | INT 16H keyboard (BIOS), INT 10H video, screen_expect |
