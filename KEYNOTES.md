# MS-DOS 4.0 Build — Key Notes

## Workflow Rules
- Commit after every step that succeeds, push to remote (origin/master).

## Line Ending Rules

**CRLF required** (DOS tools parse as text, BUILDIDX computes byte offsets):
- MSG, SKL, LBR, LNK, INF, BAT, INI, IDX files

**LF only** (source code — CRLF corrupts MASM THEADR records in .OBJ output):
- ASM, C, H, INC files

These rules are enforced by `.gitattributes` in the MS-DOS submodule (`MS-DOS/.gitattributes`).
Without it, git may normalize CRLF→LF on checkout, causing `buildidx` to produce a different
`USA-MS.IDX` and breaking SHA256 checks in CI.

### CRLF-in-blob pitfall (perpetually "modified" MSG files)

Commit `18eeeab` in the upstream MS-DOS repo converted data files to CRLF **and stored CRLF
bytes directly in the git object store** (blobs). This conflicts with `text eol=crlf` in
`.gitattributes`, which tells git to store LF in blobs and convert LF→CRLF on checkout.
Result: git normalizes the working-tree CRLF to LF for comparison, finds it doesn't match the
CRLF blob, and permanently reports `v4.0/src/MESSAGES/USA-MS.MSG` (and similar files) as
"modified" even when the content is byte-for-byte identical to HEAD.

**Impact:** cosmetic only — `git diff --ignore-cr-at-eol` shows zero real differences, the
build is unaffected (working-tree files are still CRLF as DOS tools require).

**Correct long-term fix:** change `*.MSG text eol=crlf` → `*.MSG binary` in `.gitattributes`.
`binary` stores files as-is (CRLF blobs stay CRLF blobs) and disables normalization entirely,
which is semantically correct since BUILDIDX treats these files as byte-addressed binary data.
Avoided for now to not diverge from upstream with a large no-content-change commit.

## Build Architecture
- kvikdos cannot spawn subprocesses (exec replaces process), so NMAKE is unusable.
- Linux GNU Makefile calls kvikdos for each individual DOS tool invocation.
- `bin/dos-run` mounts C: at `MS-DOS/v4.0/src/` (uppercase mode) and uses `--cwd=C:\SUBDIR\`
  to set the initial DOS current directory, allowing `..` relative paths to work.

## Filename Case
- kvikdos mounts C: in uppercase mode — all DOS filenames must be uppercase in Makefile rules.
- ASM/OBJ/EXE/BIN/LIB targets: use uppercase (MSBOOT.OBJ, MAPPER.LIB, etc.).
- The `MESSAGES_OUT` target is `USA-MS.IDX` (uppercase), not `usa-ms.idx`.

## Build Status

### Core (libraries, kernel, boot)
| Module   | Status  | Output                    |
|----------|---------|---------------------------|
| MESSAGES | ✅ done | USA-MS.IDX                |
| MAPPER   | ✅ done | MAPPER.LIB                |
| BOOT     | ✅ done | INC/boot.inc              |
| INC      | ✅ done | *.OBJ in INC/             |
| BIOS     | ✅ done | BIOS/IO.SYS               |
| DOS      | ✅ done | DOS/MSDOS.SYS             |
| MEMM     | ✅ done | MEMM/EMM386.SYS           |

### CMD utilities
| Utility       | Status  | Output                         |
|---------------|---------|--------------------------------|
| COMMAND       | ✅ done | CMD/COMMAND/COMMAND.COM        |
| FORMAT        | ✅ done | CMD/FORMAT/FORMAT.COM          |
| SYS           | ✅ done | CMD/SYS/SYS.COM                |
| CHKDSK        | ✅ done | CMD/CHKDSK/CHKDSK.COM          |
| DEBUG         | ✅ done | CMD/DEBUG/DEBUG.COM            |
| MEM           | ✅ done | CMD/MEM/MEM.EXE                |
| FDISK         | ✅ done | CMD/FDISK/FDISK.EXE            |
| MORE          | ✅ done | CMD/MORE/MORE.COM              |
| SORT          | ✅ done | CMD/SORT/SORT.EXE              |
| LABEL         | ✅ done | CMD/LABEL/LABEL.COM            |
| FIND          | ✅ done | CMD/FIND/FIND.EXE              |
| TREE          | ✅ done | CMD/TREE/TREE.COM              |
| COMP          | ✅ done | CMD/COMP/COMP.COM              |
| ATTRIB        | ✅ done | CMD/ATTRIB/ATTRIB.EXE          |
| EDLIN         | ✅ done | CMD/EDLIN/EDLIN.COM            |
| FC            | ✅ done | CMD/FC/FC.EXE                  |
| NLSFUNC       | ✅ done | CMD/NLSFUNC/NLSFUNC.EXE        |
| ASSIGN        | ✅ done | CMD/ASSIGN/ASSIGN.COM          |
| XCOPY         | ✅ done | CMD/XCOPY/XCOPY.EXE            |
| DISKCOMP      | ✅ done | CMD/DISKCOMP/DISKCOMP.COM      |
| DISKCOPY      | ✅ done | CMD/DISKCOPY/DISKCOPY.COM      |
| APPEND        | ✅ done | CMD/APPEND/APPEND.EXE          |
| RECOVER       | ✅ done | CMD/RECOVER/RECOVER.COM        |
| FASTOPEN      | ✅ done | CMD/FASTOPEN/FASTOPEN.EXE      |
| PRINT         | ✅ done | CMD/PRINT/PRINT.COM            |
| FILESYS       | ✅ done | CMD/FILESYS/FILESYS.EXE        |
| REPLACE       | ✅ done | CMD/REPLACE/REPLACE.EXE        |
| JOIN          | ✅ done | CMD/JOIN/JOIN.EXE              |
| SUBST         | ✅ done | CMD/SUBST/SUBST.EXE            |
| BACKUP        | ✅ done | CMD/BACKUP/BACKUP.COM          |
| RESTORE       | ✅ done | CMD/RESTORE/RESTORE.COM        |
| GRAFTABL      | ✅ done | CMD/GRAFTABL/GRAFTABL.COM      |
| KEYB          | ✅ done | CMD/KEYB/KEYB.COM              |
| SHARE         | ✅ done | CMD/SHARE/SHARE.EXE            |
| EXE2BIN       | ✅ done | CMD/EXE2BIN/EXE2BIN.EXE        |
| GRAPHICS      | ✅ done | CMD/GRAPHICS/GRAPHICS.COM      |
| IFSFUNC       | ✅ done | CMD/IFSFUNC/IFSFUNC.EXE        |
| MODE          | ✅ done | CMD/MODE/MODE.COM              |

### DEV (device drivers)
| Module        | Status  | Output                         |
|---------------|---------|--------------------------------|
| ANSI          | ✅ done | DEV/ANSI/ANSI.SYS              |
| COUNTRY       | ✅ done | DEV/COUNTRY/COUNTRY.SYS        |
| DISPLAY       | ✅ done | DEV/DISPLAY/DISPLAY.SYS        |
| DRIVER        | ✅ done | DEV/DRIVER/DRIVER.SYS          |
| KEYBOARD      | ✅ done | DEV/KEYBOARD/KEYBOARD.SYS      |
| PRINTER       | ✅ done | DEV/PRINTER/PRINTER.SYS        |
| RAMDRIVE      | ✅ done | DEV/RAMDRIVE/RAMDRIVE.SYS      |
| SMARTDRV      | ✅ done | DEV/SMARTDRV/SMARTDRV.SYS      |
| FLUSH13       | ✅ done | DEV/SMARTDRV/FLUSH13.EXE       |
| VDISK         | ✅ done | DEV/VDISK/VDISK.SYS            |
| XMA2EMS       | ✅ done | DEV/XMA2EMS/XMA2EMS.SYS        |
| XMAEM         | ✅ done | DEV/XMAEM/XMAEM.SYS            |

### Other
| Module        | Status  | Output                         |
|---------------|---------|--------------------------------|
| SELECT        | ✅ done | SELECT.{EXE,DAT,COM,HLP}       |
| DEPLOY        | ✅ done | out/floppy.img                 |
| VERIFY        | ✅ done | headless QEMU boot confirmed   |
| SYS e2e test  | ✅ done | `make test-sys`                |

## Manual Testing (Interactive QEMU)

Run the floppy image in a graphical QEMU window for manual testing:

```bash
# Build the image first (if not already built):
make deploy

# Launch QEMU with SDL display:
./run-qemu.sh

# Or pass a custom image path:
./run-qemu.sh out/floppy-test.img
```

- Uses `-display sdl` (graphical window); requires `qemu-system-i386` and SDL libraries.
- Memory: 4 MB (matches the headless verify target).
- Equivalent `make` target: `make run-boot` (same image, same flags, but no SDL forcing).
- To quit QEMU: `Ctrl+Alt+Q` or close the window, or use the QEMU monitor (`Ctrl+Alt+2`, then `quit`).

### SYS.COM e2e test (`make test-sys`)

Tests that `SYS B:` correctly transfers system files to a blank floppy and that the result boots.

```bash
make test-sys
```

Steps performed by `tests/test_sys.sh`:
1. Copies `out/floppy.img` → `out/floppy-sys-boot.img`, adds `AUTOEXEC.BAT`: `CTTY AUX` + `SYS B:`.
2. Creates blank FAT12 `out/floppy-sys-target.img` with `dd` + `mformat -f 1440`.
3. Boots QEMU with A: = boot img, B: = target img; checks COM1 for `"System transferred"`.
4. Adds `AUTOEXEC.BAT` (`CTTY AUX` + `VER`) to target via `mcopy -o` on the host.
5. Boots QEMU from target img alone; checks COM1 for `"MS-DOS"`.

Key notes:
- `cache=writethrough` on QEMU floppy drives ensures B: writes are flushed to the file before QEMU is killed by `timeout`.
- SYS.COM is built from `CMD/SYS/` source (BUILDMSG → CL* → MASM → LINK → EXE2BIN) and included on the floppy image.
- FORMAT.COM is built from `CMD/FORMAT/` source (BUILDMSG → CL* → MASM × 7 → LINK → CONVERT). Uses `CONVERT.EXE` (not EXE2BIN) to produce COM. MSFOR.ASM needs `BOOT.CL1` copied from `BOOT/` dir (`include BOOT.CL1`) and `BOOT11.INC` from `INC/`.
- FC.EXE has no SKL/BUILDMSG — uses its own `MESSAGES.ASM` (not the system message framework). Requires `INC/KSTRING.OBJ` compiled from `INC/KSTRING.C` (referenced as `..\..\inc\kstring.obj` in the LNK file). 5 C files + 7 ASM files, stays EXE.
- FDISK.EXE is the most complex CMD utility: NOSRVBLD (FDISK5.SKL→CL1, already done for SELECT), BUILDMSG (FDISK.SKL→CTL+CL files), MENUBLD (FDISK.MSG + USA-MS.MSG → FDISKM.C), 20 C files compiled with `-AS -Os -Zp -I. -I..\\..\\H -c`, 4 ASM files (_MSGRET, _PARSE, BOOTREC, REBOOT), linked against MAPPER.LIB + INC/COMSUBS.LIB. FDBOOT.OBJ and FDBOOT.INC reused from the SELECT build.
- MEM.EXE is built from `CMD/MEM/` source (BUILDMSG → CL + 2 MASM → LINK against `LIB/MEM.LIB`). Output stays as EXE — no CONVERT needed. MEM.EXE calls `sysloadmsg` which checks for DOS 4.0; it exits with "Incorrect DOS version" under kvikdos (which reports an older version) — this is expected, it works fine on the real floppy.
- DEBUG.COM is built from `CMD/DEBUG/` source (BUILDMSG → 11 MASM files → LINK → CONVERT). Unlike CHKDSK, BUILDMSG generates all CL files including CL1/CL2 — no empty stubs needed. DEBMES.ASM includes `SYSVER.INC` (local to DEBUG dir) and `sysmsg.inc`/`msgdcl.inc` from INC/.
- MODE.COM: 16 ASM modules, 4 SKL classes (1/2/A/B). EXE2BIN. Handles serial/parallel/display/codepage. Standard AINC, no external libraries.
- IFSFUNC.EXE: 10 ASM modules, 3 SKL classes (1/2/A). Links 5 INC kernel objs (NIBDOS/CONST2/MSDATA/MSTABLE/MSDOSME) plus 2 DOS objects (MSDISP.OBJ/MSCODE.OBJ from DOS/ dir — already built by `dos` target). Stays EXE (resident IFS driver). MSDOS.CL1 step in original MAKEFILE not needed since DOS/INC targets already built it.
- GRAPHICS.COM: 13 ASM modules, `:util GRAPHICS` with CLA/CLB/CLC + CL1/CL2. .EXT files are regular ASM include headers. Key quirk: GRCPSD.OBJ is assembled from GRPARSE.ASM and GRPARSE.OBJ from GRCPSD.ASM (filenames swapped in repo — GRPARSE.ASM's TITLE says "GRLOAD.ASM"). GRCOLPRT.ASM includes GRCOMMON.ASM directly via `INCLUDE`. GRAPHICS.PRO (printer profile) shipped alongside GRAPHICS.COM on the floppy.
- EXE2BIN.EXE: 2 ASM (E2BINIT.ASM + DISPLAY.ASM), `:util EXE2BIN` with CLA/CLB/CL1/CL2. Link via @EXE2BIN.LNK with /DOSSEG /MAP /E flags. Stays EXE. Build produces the source version for the floppy; the build system itself still uses the pre-built exe2bin from TOOLS/ (chicken-and-egg).
- BACKUP.COM: 1 large C file + 2 ASM, `-AS -Od -Zp` (debug opts). Link: `/NOE BACKUP+_PARSE+_MSGRET,,,MAPPER+COMSUBS;` → CONVERT. BUILDMSG generates CL1/CL2/CLA.
- RESTORE.COM: 12 C files + 2 ASM, same flags/pattern as BACKUP. LNK uses `/STACK:50000`. Link via @RESTORE.LNK → CONVERT.
- GRAFTABL.COM: 10 ASM, no external libs, EXE2BIN. BUILDMSG generates CL1/CL2/CLA (no stubs needed).
- KEYB.COM: 10 ASM, no external libs, EXE2BIN. BUILDMSG generates CL1/CL2/CLA. Handles keyboard layout via INT 9/9C/2F/48 handlers; data tables in KEYBTBBL.ASM/KEYBI9.ASM/KEYBI9C.ASM.
- SHARE.EXE: 4 ASM + INC kernel objs (NIBDOS, CONST2, MSDATA, MSDOSME — same as JOIN/SUBST). BUILDMSG generates CL1/CL2/CLA. Link via @SHARE.LNK. Stays EXE (TSR file-sharing/locking).
- APPEND.EXE: 1 ASM file (no SKL/BUILDMSG), `link APPEND;`. Stays EXE.
- RECOVER.COM: 4 ASM files, no SKL. Linked then CONVERT to COM.
- FASTOPEN.EXE: 5 ASM files (no SKL), `link FASTOPEN+FASTOPC+FASTOPM+FASTOPS+FASTOPN;`. Stays EXE.
- PRINT.COM: 4 ASM files, no SKL. Linked then CONVERT to COM.

## CONVERT.EXE COM Runtime Environment

**All** of CHKDSK, RECOVER, EDLIN, PRINT, FORMAT, DEBUG, RESTORE, and BACKUP are built
with `CONVERT.EXE` (not `EXE2BIN`). Any modification to these tools must account for the
runtime environment CONVERT creates:

**How CONVERT works:** Wraps the linked EXE in a COM file with a 3-byte JMP at offset 0 that jumps to
CONVERT's own init code (appended at the END of the COM file). The init code:
1. Gets current IP via `CALL $+3; POP BX` (position-independent)
2. Reads relocation offsets from the COM header (around bytes 0x116–0x128)
3. Computes runtime segment addresses and patches far-jump targets in the init code itself
4. Copies code/data to final memory location
5. Does a **FAR JMP** to the actual EXE entry point

**CONVERT COM file layout** (verified on RECOVER.COM, CHKDSK.COM, etc.):
- COM byte 0–2: `E9 xx xx` — NEAR JMP to CONVERT init code at end of file
- COM byte 3–0xF: `"Converted\0"` marker + padding
- COM byte 0x10: embedded MZ EXE header starts here (512 bytes = 0x200 for these tools)
- COM byte 0x210 (= 0x10 + header_size): actual EXE data starts here
- True COM entry = `EXE_data_offset + EXE_IP` (e.g. RECOVER: 0x210 + 0x136F = 0x157F)

**MAP vs COM offset:** The `.MAP` file shows `Program entry point at 0000:NNNN` — this is the
EXE IP, NOT the COM file byte offset. To find the actual byte where execution begins in the COM
file: `COM_entry = 0x210 + EXE_IP` (for tools with the standard 512-byte header). Confirmed by
parsing the embedded MZ header: `header_paras * 16 = 0x200`, data offset `= 0x10 + 0x200 = 0x210`.

**Analyzing COM binaries:** `objdump` can disassemble raw COM/EXE bytes (`-b binary -m i8086`),
but for CONVERT COM files it doesn't understand the embedded MZ structure. Python is more flexible
for: (1) parsing OMF OBJ segment/symbol tables to verify code placement, (2) locating the embedded
MZ header and computing true entry offsets, (3) searching for byte patterns across segments.

After the FAR JMP: **CS = the EXE's code segment (DG or similar), not PSP**.

**Implications for any code modification:**
- `OFFSET label` gives the assembler's DG-relative value. At runtime CS=DG, so `CS:[DG_offset]`
  is valid. But DS is NOT PSP — do not use DS:[81h] to access the command line.
- PSP is still accessible via `INT 21h / AH=62h` (returns BX=PSP segment).
- For position-independent string addresses: use the `CALL/POP` trick — CALL pushes the
  runtime IP of the next byte (the string start), bypassing DG-relative OFFSET entirely.
- `PUSH CS; POP DS` sets DS=DG (CS at runtime), so `DS:DX` from CALL/POP is correct for
  INT 21h/09h string output.

**SHORT-jump range:** MASM 5.x conditional jumps (`JNE`, `JE`) are always SHORT (±127 bytes).
Use a relay: `JNE short_relay_label; [long code block]; short_relay_label: JMP NEAR far_target`.
Unconditional `JMP far_target` auto-promotes to NEAR (3 bytes) across MASM's two passes.

**Proven pattern for /? (implemented in PRINT, applicable to CHKDSK/RECOVER/EDLIN):**
```asm
   MOV   AH, 062H
   INT   21H          ; BX = PSP segment
   MOV   ES, BX       ; ES = PSP
   MOV   SI, 081H
SKIP_SP: CMP BYTE PTR ES:[SI],' ' | JNE CHK_SL | INC SI | JMP SHORT SKIP_SP
CHK_SL:
   CMP   BYTE PTR ES:[SI], '/'
   JNE   NO_HELP          ; SHORT (target right below)
   CMP   BYTE PTR ES:[SI+1], '?'
   JE    DO_HELP           ; SHORT (target right below — 3 bytes past JMP)
NO_HELP:
   JMP   CONTINUE          ; NEAR unconditional — skips the whole help block
DO_HELP:
   CALL  HELP_END          ; pushes runtime addr of string, jumps to HELP_END
HELP_STR DB "...$"
HELP_END:
   POP   DX               ; DX = runtime CS-relative address of HELP_STR
   PUSH  CS | POP DS      ; DS = CS = DG
   MOV   AH, 09H | INT 21H
   MOV   AX, 4C00H | INT 21H
CONTINUE:
   ; original entry code
```

- FILESYS.EXE: 1 C file + 2 ASM, no SKL. Link: `link FILESYS+_PARSE+_MSGRET; /NOI` (note space before `/NOI`). Stays EXE.
- REPLACE.EXE: 1 C + 3 ASM, BUILDMSG for SKL. Links MAPPER.LIB + INC/COMSUBS.LIB. Stays EXE.
- JOIN.EXE / SUBST.EXE: 1C + 2ASM + INC kernel objects (ERRTST.OBJ, SYSVAR.OBJ, CDS.OBJ, DPB.OBJ already built by `inc` target). Links MAPPER.LIB + INC/COMSUBS.LIB. LNK files reference INC objs by relative path `..\..\inc\*.OBJ`. Stays EXE.
- CHKDSK.COM is built from `CMD/CHKDSK/` source (BUILDMSG → 9 MASM files → LINK → CONVERT). Key quirk: `CHKDISP.ASM` uses the `Msg_Services` macro which includes `CHKDSK.CL1` and `CHKDSK.CL2` — but CHKDSK.SKL has no class 1 or 2, so BUILDMSG doesn't generate them. Fix: `touch CHKDSK.CL1 CHKDSK.CL2` after BUILDMSG to create empty stubs. CHKDSK also uses `CONVERT.EXE` (not EXE2BIN).
- `-serial stdio` with a piped subshell feeds FORMAT's interactive prompts (press ENTER, volume label, format another) at timed intervals. QEMU stdout (COM1 output) is captured via `tee`. The blank target image is all-zeros — no pre-formatting needed; FORMAT.COM does it from scratch.

## Floppy Image (deploy / verify)

### MSBOOT.BIN layout
- EXE2BIN produces a flat binary with code ORG'd at `0x7c00`; file is 32256 bytes (= 0x7c00 padding + 512 bytes boot sector).
- Extract boot sector: `dd if=MSBOOT.BIN bs=1 skip=31744 count=512`.

### BPB patching (`bin/patch-bpb`)
- MSBOOT.BIN's built-in BPB targets a fixed disk (media `0xF8`); patch it to 1.44MB floppy geometry before calling `mformat -k`.
- 1.44MB parameters: 512 B/sec, 1 sec/cluster, 2 FATs, 224 root entries, 2880 total sectors, media `0xF0`, 9 sec/FAT, 18 sec/track, 2 heads.
- Extended BPB (DOS 4.0): drive `0x00` (floppy), ext_boot_sig `0x29`, volume label 11 bytes, FS type `"FAT12   "`.
- BPB occupies bytes 11–61 of the boot sector; bootstrap code starts at byte 62 (`0x3E`).

### mformat -k
- `mformat -i floppy.img -k ::` — formats FAT12 *keeping* the existing boot sector (reads BPB from it to build consistent FAT tables).

### File copy order
- `IO.SYS` **must** be the first directory entry; `MSDOS.SYS` must be second.
- Use `mcopy` (not loop-mount) to guarantee insertion order; then `mattrib +h +s +r` both files.

### verify target
- `floppy-test.img` = `floppy.img` + `AUTOEXEC.BAT` with `CTTY AUX\r\nVER\r\n`.
- `CTTY AUX` redirects DOS console to COM1; `VER` prints `MS-DOS Version 4.00` to COM1.
- QEMU flags: `-display none -serial file:out/serial.log`; `timeout 15` kills QEMU after output is captured.
- Pass condition: `grep -q "MS-DOS" out/serial.log`.

## Golden Checksums (tests/golden.sha256)

- **Always run `make clean` before `make gen-checksums`**, otherwise `buildidx` may report
  "not changed" and reuse a stale `USA-MS.IDX`, capturing a wrong checksum.
- Lesson learned: the `USA-MS.IDX` checksum was captured from a pre-CRLF-conversion build,
  causing CI to fail even though the fresh build was correct. Only fresh builds tell the truth.
- **FC.EXE is excluded** from golden.sha256. Local builds produce `4e36dad...` while CI
  produces `0494a906...` despite identical source and tools. Root cause unknown — likely
  KSTRING.OBJ (the only shared INC object, used only by FC) or C runtime resolution differs
  between environments. FC.EXE is still covered by Section 1 (file exists) and Section 4
  (/? smoke test). Do not add FC.EXE back to golden.sha256 without resolving this.

## CI (GitHub Actions)

- **Submodule pointer pitfall:** When committing changes to both the submodule and
  `tests/` (golden.sha256, run_tests.sh), always `git add MS-DOS` in the parent repo too.
  If only `tests/` is staged, CI will check out the OLD submodule commit and fail the
  smoke tests because the new binaries are missing. Verify with `git ls-tree HEAD MS-DOS`
  and confirm the hash matches the submodule's latest commit before pushing.
- Workflow: `.github/workflows/ci.yml`, runs on every push/PR to `master`.
- Runner: `ubuntu-latest` — has `/dev/kvm` but not accessible by default.
- KVM fix: add udev rule `KERNEL=="kvm", GROUP="kvm", MODE="0666"` before building.
- Steps: grant KVM → install deps (`gcc nasm python3 qemu-system-x86 mtools`) →
  build kvikdos → `make` → `make test` → `make deploy` → `make verify`.
- Free tier: unlimited minutes for public repos on GitHub Actions.
- kvikdos now builds and runs on macOS via software 8086 CPU backend (XTulator).
  Linux CI uses KVM (unchanged); macOS builds use the same codebase with `#ifdef __linux__` guards.

## MS-DOS Fork Branch Strategy

The MS-DOS submodule (`MS-DOS/`) has two branches:
- `main` — minimal patches to make the source build (CRLF fixes, UTF-8, `.gitattributes`).
  Stays close to original Microsoft source; should always produce binary-identical output.
- `dos4-enhancements` — our additions (help strings, etc.). Branches off `main`.

Workflow: develop on `dos4-enhancements`; merge upstream changes into `main` first,
then rebase `dos4-enhancements` on top.

## Adding /? Help Strings to CMD Tools

### General pattern (external tools)
- **C tools** (`argv`-based): check `argv[1]` for `"/?"`; `printf` the help string; `exit(0)`. Add `#include <stdio.h>` and `#include <stdlib.h>` if not already present.
- **ASM EXE tools** (DS=PSP at entry): scan `DS:[81H]`, skip spaces/tabs, check `'/'` then `'?'`; `PUSH CS / POP DS` to reach help string in code segment; `INT 21H/09H` to print; `INT 21H/4CH` to exit.
- **COM tools** (CS=DS=PSP): same as ASM EXE but no `PUSH CS / POP DS` needed — CS already equals DS.
- **CONVERT COM tools** (CS=DG, not PSP): use `INT 21H/62H` → ES=PSP, check `ES:[81H]`; `CALL HELP_END / DB "...$" / HELP_END: POP DX; PUSH CS / POP DS; INT 21H/09H` (CALL/POP trick for position-independent string address). See detailed example under "## CONVERT.EXE COM Runtime Environment".

### COMMAND.COM built-in /? pattern
- **`fSwitchAllowed` flag** (TDATA.ASM COMTAB): bit 1 must be set or the dispatcher rejects `/` as "Invalid switch" before the handler is called. Commands with flag `0` need it changed to `fSwitchAllowed`.
- **Handler entry**: DS=CS=TRANGROUP. Scan `DS:[81H]` (command tail set up by `cmd_copy`), skip spaces/tabs, check `'/'` then `'?'`.
- **Print**: `MOV DX, OFFSET TRANGROUP:HELP_STR; MOV AH, 09H; INT int_command`. No `PUSH CS / POP DS` needed — DS already equals CS at handler entry.
- **Exit**: `return` (maps to `ret`; dispatcher uses `call BX` so `ret` returns correctly).
- **REM special case**: REM was mapped directly to `TCOMMAND` (not a callable handler). Fix: new `REM_HANDLER` proc in TCODE.ASM that checks `/?` and `return`s, or `jmp TCOMMAND` for normal REM. Add `PUBLIC REM_HANDLER` + `EXTRN REM_HANDLER:NEAR` in TDATA.ASM.
- **Help string placement**: place `DB "...$"` data only where execution cannot fall through — after a `ret`/`return`, or after an unconditional `jmp`. Never between two executable labels unless preceded by `jmp`.
- **Short-jump range**: MASM 5.x conditional jumps (`JZ`, `JNZ`, etc.) are always ±127 bytes. A large help string (e.g., FOR_HELP_STR = 284 bytes) placed before a handler's body pushes all backward jumps to labels before the string out of range. Fix: move the string to *after* a `jmp` that exits the flow; or add relay labels (`JNZ short_relay; JMP far_target; short_relay:`).

### pipefail / SIGPIPE fix in run_tests.sh
Capture `strings` output into a variable first, then grep — avoids SIGPIPE false negative under `set -o pipefail`:
```bash
bin_str=$(strings "$SRC/CMD/COMMAND/COMMAND.COM")
if echo "$bin_str" | grep -q "$expected"; then ...
```
Direct pipeline `strings ... | grep -q ...` can cause SIGPIPE when grep exits early, which `pipefail` treats as a failure.

## kvikdos Emulation Notes (for running MS-DOS 4.0 tools)

### DOS version
- kvikdos upstream default is version 5. MS-DOS 4.0 tools call `sysloadmsg` which checks
  for DOS 4.x via INT 21h/AH=30h; getting 5 causes "Incorrect DOS version" exit.
- **Fix:** use `--dos-version=4` flag (added to kvikdos fork). `bin/dos-run` passes it
  automatically so all tools work correctly.

### INT stubs added to kvikdos fork (needed for functional MS-DOS 4.0 tool testing)
| INT / Function | Purpose | kvikdos behavior |
|---|---|---|
| INT 21h/AH=65h | GetExtendedCountryInfo (NLS) | Returns identity collating table (0x0420) and country_info (0x0522); handles AL=01h,02h,04h,05h,06h,07h. Needed by `sysloadmsg`. |
| INT 12h | BIOS Get Conventional Memory Size | Returns AX=640 (KB). Needed by MEM.EXE. |
| INT 15h/AH=C1h | Get EBDA Segment | Returns CF=1 (no EBDA). Needed by MEM.EXE. |
| INT 2Fh/AH=B7h | APPEND (any sub-function) | Returns AX=BX=0 (not installed). Needed by TREE.COM. |
| INT 67h/AH=40h..62h | EMS functions | Returns AH=0x86 (EMM not present). Needed by MEM.EXE EMS check. |
| INT 21h/AH=87h | GETPID (MS-DOS 4.0 multitasking) | Returns PID=1, parent PID=0. MS C 5.10 `getpid()` calls this during compilation. |
| MMIO 0xA0000–0x110000 reads | High memory / ROM area | Returns zeros. Needed for MEM.EXE reading INVARS ExtendedMemory via segment 0xFFF0. |

### Static data placed in low-memory readonly region (re-initialized on each run)
- **0x0420..0x0521** — identity collating table (word 0x0100 = 256 length + 256 identity bytes). Used by INT 21h/AH=65h.
- **0x0522..0x0539** — country_info copy (0x18 bytes). Used by INT 21h/AH=65h/AL=01h.
- These addresses are in the KVM readonly-guest slot (0x0000..0x0FFF), safely between the BIOS data area and the hlt table (0x0540).

### MEM.EXE status
- MEM.EXE (no args) runs and prints 3 lines but exits with code 128 instead of 0.
- Output is correct: "655360 bytes total memory / available / 651264 largest executable".
- Exit code 128 (0x80) is probably from C runtime returning AX leftover from `sysloadmsg`.
- MEM /PROGRAM and MEM /DEBUG require proper INVARS (INT 21h/AH=52h) MCB chain walk — not yet tested.

### Remaining known gaps for E2E functional tests
- **SORT.EXE**: after `sysloadmsg` succeeds (with INT 65h fix), C runtime calls INT 21h/AH=4Ah to shrink allocation; test needed to confirm sufficient memory is freed for sort buffer.
- **FIND.EXE**: should work after INT 65h fix; needs test with a real file.
- **TREE.COM**: should work after INT 2Fh/B7h fix; needs test with a directory structure.
- **COMP.COM**: should work after INT 65h fix; needs test with two files.

## EXEPACK A20 Gate Bug

**Symptom:** "Packed file is corrupt" on real DOS hardware / QEMU when running tools
linked with Microsoft LINK 3.65 `/EXEPACK` (or `/EX`, `/E+`).

**Root cause:** The EXEPACK decompressor stub embedded by LINK 3.65 has an A20 gate bug:
when the relocation fixup loop accesses memory near the 1 MB boundary (segment ~0x10000),
A20 wrap-around causes the wrong memory to be read/written, triggering the error message
that is embedded in the stub itself.

**Affected binaries (built by our Makefile):**
| Tool | Link flag | Makefile |
|------|-----------|----------|
| FIND.EXE | `/EX` | `mk/cmd.mk` |
| FDISK.EXE | `/E+` | `mk/cmd.mk` |
| IFSFUNC.EXE | `/EX` | `mk/cmd.mk` |
| EXE2BIN.EXE | `/E+` | `mk/cmd.mk` |
| SELECT.EXE | `/EXEPACK` | `mk/select.mk` |

**Why smoke tests don't catch it:** kvikdos automatically detects EXEPACK at load time
(detection: `EXE_IP ∈ {16,18,20}` AND `'RB'` signature at `EXE_IP-2`) and replaces the
buggy stub with a fixed 283-byte version from exepack-1.3.0 (see `kvikdos/kvikdos.c`
lines ~1351–1391). This means `make test` passes, but the output EXE is still broken
for real DOS.

**Fix:** `bin/fix-exepack` patches the stub in-place at build time (same logic kvikdos
does at runtime). Called automatically after each affected LINK step in the Makefile.
- Detection: `EXE_IP ∈ {16,18,20}` AND `'RB'` sig at `EXE_IP-2`
- Old stub boundary found via `\xcd\x21\xb8\xff\x4c\xcd\x21` + 22-byte error string
- New header grows 16→18 bytes: adds `skip_len=1` at offset 14, moves `'RB'` to offset 16
- References: https://www.bamsoftware.com/software/exepack/

**Lesson:** Always test on real DOS or QEMU after linking with EXEPACK. kvikdos masks
this class of bug entirely.

## COMMAND.COM /? Help — Transient Corruption Bug (OPEN — CI broken)

### Symptom
Adding /? help strings to COMMAND.COM built-ins (CLS, EXIT, CTTY, CHCP, TRUENAME,
REM, GOTO, SHIFT, IF, FOR, CALL, and COMMAND itself — commits 5d10cef + 58a0bb4)
causes ALL built-in commands to silently fail at runtime. `CTTY AUX` and `VER`
produce no output to serial. DOS boots, prompt appears, but every internal command
is dead.

### What works
- Commits up to c08f024 (DIR, COPY, SET, PROMPT, PATH, CD, MD, RD help) produce a
  working COMMAND.COM (41,719 bytes).
- The /? check code pattern is correct (DS:[81H] scan, print via INT 21h/09h, return).
- COMTAB entries in the broken binary look structurally correct (35 entries, valid
  handler offsets, matching flag bytes).

### What's broken
- Full 58a0bb4 COMMAND.COM (43,991 bytes): all built-ins fail silently.
- Earlier bisection (in the prior session) pointed to TFOR.ASM as the critical file,
  and suggested a pure size boundary at 43,312→43,313 bytes where TRANTAIL PARA
  alignment causes a 16-byte gap (TRANSPACEEND crosses from 0x83F0 to 0x83F1,
  SetSize jumps from 2111 to 2112 paragraphs).

### Size theory — DISPROVEN (partially)
- Adding 2,300 bytes of zero padding at ORG 100H in TCODE.ASM (before SETDRV) to the
  c08f024 base produces a 44,019-byte COMMAND.COM that **works correctly** under QEMU.
  This is LARGER than the broken 43,991-byte binary.
- **Conclusion**: total binary size alone does not cause the failure. The bug is in the
  SPECIFIC code or data changes, not a generic size boundary. The earlier "size theory"
  from the prior session's bisection with TFOR.ASM dummy padding was a coincidence —
  the padding happened to be at a location that triggers the same symptom.
- The issue is likely related to code placement, jump ranges, or data corruption in
  the transient portion caused by one of the specific changes in 5d10cef/58a0bb4.

### Investigation status
- Need to bisect which specific file's changes (from the 5d10cef+58a0bb4 delta)
  cause the failure: TCODE.ASM, TDATA.ASM, TCMD2A.ASM, TCMD2B.ASM, TBATCH2.ASM,
  TFOR.ASM, or INIT.ASM.
- The TDATA.ASM changes include: REM handler → REM_HANDLER (new), EXIT/CLS flags
  0 → fSwitchAllowed. These are worth testing in isolation.
- INIT.ASM adds COMMAND /? help to the RESIDENT portion (before SYSLOADMSG) — this
  shifts TRANGROUP origin by 0x200 but shouldn't affect transient internals.

### How to test locally (macOS)
```bash
# Requires: brew install qemu mtools coreutils
# Build floppy image:
dd if=/dev/zero of=out/floppy-test.img bs=512 count=2880 status=none
dd if=MS-DOS/v4.0/src/BOOT/MSBOOT.BIN of=out/floppy-test.img \
   bs=1 skip=31744 count=512 conv=notrunc status=none
bin/patch-bpb out/floppy-test.img
export MTOOLS_NO_VFAT=1 MTOOLS_SKIP_CHECK=1
echo 'drive a: file="out/floppy-test.img"' > /tmp/mtoolsrc
export MTOOLSRC=/tmp/mtoolsrc
mformat -k a:
mcopy MS-DOS/v4.0/src/BIOS/IO.SYS a:IO.SYS
mattrib +h +s +r a:IO.SYS
mcopy MS-DOS/v4.0/src/DOS/MSDOS.SYS a:MSDOS.SYS
mattrib +h +s +r a:MSDOS.SYS
mcopy MS-DOS/v4.0/src/CMD/COMMAND/COMMAND.COM a:COMMAND.COM
printf "CTTY AUX\r\nVER\r\n" > /tmp/autoexec.bat
mcopy -o /tmp/autoexec.bat a:AUTOEXEC.BAT
# Boot and check:
rm -f out/serial.log
gtimeout 15 qemu-system-i386 -display none -fda out/floppy-test.img \
   -boot a -m 4 -serial file:out/serial.log 2>/dev/null; true
cat out/serial.log  # should show "MS-DOS Version 4.00"
```

**macOS mtools note**: `mattrib -i image.img` does not work on mtools 4.0.49.
Use MTOOLSRC drive mapping instead (as shown above). Also needs `MTOOLS_NO_VFAT=1`.
`timeout` is not available on macOS — use `gtimeout` from `brew install coreutils`.

## kvikdos Modifications (in kvikdos/kvikdos.c)
- `current_dir[DRIVE_COUNT]` expanded from 1 to 64 bytes per drive.
- `ah=0x3b` (CHDIR) implemented.
- `ah=0x29` (Parse Filename for FCB) fully implemented.
- `ah=0x46` (Force Duplicate File Handle / dup2) implemented.
- `ah=0x4d` (Get Child Process Exit Code) implemented.
- `ah=0x5b` (Create New File / O_CREAT|O_EXCL) implemented — needed by ASC2HLP.EXE.
- Spawn support (ah=0x4b al=0): saves full 640KB memory + CPU state, restores parent after child exits.
- `cd <path>` support added to batch interpreter.
- Filenames starting with `.` allowed (needed for `.CL1` files).
- `--cwd=<drive>:\<path>\` flag added to set initial DOS current directory.
- is_args_normal check now accepts both `\0` and `\r` as args terminator.
- `INT 3` (software breakpoint) handled as no-op — needed by COMPRESS.COM.
- INT 21h/AH=87h GETPID stub — returns PID=1 (MS-DOS 4.0 multitasking API, called by MS C 5.10 getpid()).
- macOS: `MADV_DONTNEED` does not zero pages (unlike Linux); spawn/re-exec path uses memset instead.

## Paths
- C standard headers (dos.h, stdio.h, etc.) are in `TOOLS/BLD/INC/`, not `TOOLS/INC/`.
- INCLUDE env var in bin/dos-run: `c:\\TOOLS\\BLD\\INC`.
- LIB env var in bin/dos-run: `c:\\TOOLS\\BLD\\LIB` (for SLIBCE.LIB needed by SELECT C objects).
- DOS/MSDOS.CL1 must be generated by NOSRVBLD before assembling INC/MSDOSME.OBJ (via DIVMES.ASM include chain).
- CMD utilities use BUILDMSG (not NOSRVBLD) to generate `.ctl` + `.cl*` files from `.skl`.
  - Rule: `buildmsg ..\..\MESSAGES\USA-MS COMMAND.SKL` (basename without .msg, then SKL file)
  - Key: check first line of .skl — `:class 1` → NOSRVBLD; `:util` → BUILDMSG.
- CMD AINC: `-I. -ID:\\TOOLS\\INC -I..\\..\\INC -I..\\..\\DOS` (two levels up from CMD/COMMAND/).
- DEV AINC: same as CMD AINC for most modules; RAMDRIVE/KEYBOARD use `-I. -I..\\..\\INC` (no DOS dir); SMARTDRV/XMAEM use `-I.` only; XMA2EMS uses `-I. -I..\\..\\INC`.
- XMAEM.MAKEFILE bug: target named `xmaem.ctl` but SKL is class 1, so NOSRVBLD generates `xmaem.cl1`. Use NOSRVBLD and target CL1.
- XMAEM.SYS: produced directly by LINK (output named `.sys` in LNK file) — no EXE2BIN needed.
- SELECT AINC: `-I. -I..\\INC` (one level deep from SRC/SELECT/). BRIDGE/CASERVIC use CASVAR.INC and CASRN.INC from INC/.
- SELECT C objects: compile with `-AS -Od -Zp -I. -c`.
- CASSFAR.LIB: pre-built, already in SELECT/ dir (no need to build from SHELL/CASSFAR).
- ASC2HLP.EXE and COMPRESS.COM: pre-built in TOOLS/.
- BOOTREC.OBJ: built in CMD/FDISK/ (needs FDBOOT.INC from FDBOOT.BIN via DBOF), then copied to SELECT/.
- FDBOOT.INC chain: NOSRVBLD(FDISK5.SKL)→CL1 → MASM FDBOOT.OBJ → LINK → EXE2BIN → DBOF(600 200).
- SELECT.LNK uses /EXEPACK (supported by LINK 3.65) and /noe flag (pass as `link /noe @SELECT.LNK`).
- COMPRESS.COM hardcoded: reads SEL-PAN.DAT, writes SELECT.DAT (must run in SELECT/ dir).
- MEMM: two sub-dirs: EMM/ (EMMLIB.LIB) and MEMM/ (EMM386.SYS).
- EMM AFLAGS: `-Mx -t -DI386 -DNOHIMEM -I..\\MEMM`; CFLAGS: `/ASw /G2 /Oat /Gs /Ze /Zl /c`.
- MEMM AFLAGS: `-Mx -t -DI386 -DNoBugMode -DNOHIMEM -I..\\EMM`; MAPDMA.C needs `-I..\\EMM`.
- EMM386.SYS: link `/NOI @EMM386.LNK` → emm386.exe, then rename to emm386.sys (no exe2bin).
