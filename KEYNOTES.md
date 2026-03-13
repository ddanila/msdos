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
| 23 others     | ❌ todo | see TODO.md                    |

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
- FDISK.EXE is the most complex CMD utility: NOSRVBLD (FDISK5.SKL→CL1, already done for SELECT), BUILDMSG (FDISK.SKL→CTL+CL files), MENUBLD (FDISK.MSG + USA-MS.MSG → FDISKM.C), 20 C files compiled with `-AS -Os -Zp -I. -I..\\..\\H -c`, 4 ASM files (_MSGRET, _PARSE, BOOTREC, REBOOT), linked against MAPPER.LIB + INC/COMSUBS.LIB. FDBOOT.OBJ and FDBOOT.INC reused from the SELECT build.
- MEM.EXE is built from `CMD/MEM/` source (BUILDMSG → CL + 2 MASM → LINK against `LIB/MEM.LIB`). Output stays as EXE — no CONVERT needed. MEM.EXE calls `sysloadmsg` which checks for DOS 4.0; it exits with "Incorrect DOS version" under kvikdos (which reports an older version) — this is expected, it works fine on the real floppy.
- DEBUG.COM is built from `CMD/DEBUG/` source (BUILDMSG → 11 MASM files → LINK → CONVERT). Unlike CHKDSK, BUILDMSG generates all CL files including CL1/CL2 — no empty stubs needed. DEBMES.ASM includes `SYSVER.INC` (local to DEBUG dir) and `sysmsg.inc`/`msgdcl.inc` from INC/.
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

## CI (GitHub Actions)

- Workflow: `.github/workflows/ci.yml`, runs on every push/PR to `master`.
- Runner: `ubuntu-latest` — has `/dev/kvm` but not accessible by default.
- KVM fix: add udev rule `KERNEL=="kvm", GROUP="kvm", MODE="0666"` before building.
- Steps: grant KVM → install deps (`gcc nasm python3 qemu-system-x86 mtools`) →
  build kvikdos → `make` → `make test` → `make deploy` → `make verify`.
- Free tier: unlimited minutes for public repos on GitHub Actions.

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
