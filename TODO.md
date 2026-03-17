# MS-DOS 4.0 Build — TODO

## UMB Support (Upper Memory Blocks)

Goal: add UMB support to our MS-DOS 4.0 fork so that device drivers and TSRs
can be loaded into the upper memory area (640K–1MB), freeing conventional memory.
This is a feature MS-DOS 5.0 introduced; we're backporting the concept to our 4.0 fork.

Reference implementations (for study, not copying):
- **FreeDOS kernel** — MSDOS/kernel side: UMB link/unlink, `DOS=UMB`, `DEVICEHIGH`, arena chain management.
- **JEMM** (Japheth's EMM386) — EMM386 side: UMB provider via INT 2Fh/AX=4310h (XMS), V86 page mapping.

### Phase 1: EMM386 — UMB provider

EMM386 must provide UMBs to the kernel via the XMS interface.

- [ ] Study how UMBs are exposed: INT 2Fh/AX=4310h → XMS driver entry, functions 10h (Request UMB) / 11h (Release UMB)
- [ ] Study our EMM386 source (`MEMM/`) — understand V86 mode setup, page table management, existing EMS page frame mapping
- [ ] Add XMS UMB allocation (function 10h): map available upper memory regions (C000–EFFF gaps not used by ROM/adapters) as allocatable UMBs
- [ ] Add XMS UMB release (function 11h)
- [ ] UMB region detection: scan adapter ROM signatures (55AA) and video RAM to find free gaps in upper memory; make regions configurable (e.g., `DEVICE=EMM386.SYS I=C800-EFFF` include ranges)
- [ ] Test: verify XMS UMB functions work from a test program under QEMU

### Phase 2: MSDOS kernel — UMB-aware memory management

The kernel needs to link UMBs into the MCB (Memory Control Block) arena chain.

- [ ] Study MS-DOS 5.0+ MCB arena chain structure: how UMBs are linked as a second arena above conventional memory
- [ ] Study FreeDOS kernel source for the UMB link/unlink mechanism
- [ ] `DOS=UMB` CONFIG.SYS directive: when set, kernel calls XMS to request UMBs at init and links them into the MCB chain
- [ ] `DOS=HIGH,UMB` combination: support both directives together
- [ ] MCB chain linking: after obtaining UMB regions from XMS, create MCB headers and chain them to the end of the conventional memory arena
- [ ] INT 21h/AH=58h subfunction 03h (Set UMB Link State): allow programs to include/exclude UMBs from allocation
- [ ] INT 21h/AH=58h subfunction 02h (Get UMB Link State)
- [ ] Test: verify `MEM` shows upper memory region, allocation from UMBs works

### Phase 3: COMMAND.COM / CONFIG.SYS — DEVICEHIGH, LOADHIGH

- [ ] `DEVICEHIGH=` CONFIG.SYS directive: load device drivers into UMBs (kernel init code — try UMB first, fall back to conventional)
- [ ] `LOADHIGH` / `LH` COMMAND.COM built-in: load TSRs into UMBs
- [ ] `MEM /C` or similar: show which programs/drivers are in upper memory
- [ ] Test: boot with `DOS=UMB`, `DEVICEHIGH=ANSI.SYS`, verify ANSI.SYS loads into UMA, conventional memory increases

### Phase 4: HMA — Load DOS High

Load MSDOS.SYS kernel into the HMA (High Memory Area, first 64K-16 bytes above 1MB at FFFF:0010–FFFF:FFFF),
freeing ~40-50K of conventional memory. Requires A20 gate control and an XMS driver (HIMEM.SYS or EMM386).

- [ ] Study HMA mechanics: A20 gate enable/disable, FFFF:xxxx wrapping vs linear access, the 64K-16 byte limit
- [ ] Study how MS-DOS 5.0+ relocates kernel code/data to HMA (FreeDOS `kernel/hma.c` as reference)
- [ ] XMS prerequisite: EMM386 or a minimal HIMEM.SYS must provide XMS function 01h (Request HMA) / 02h (Release HMA) and A20 control (functions 03h–07h)
- [ ] Decide: add HMA/A20/XMS support to EMM386 (it already does V86), or implement a separate minimal HIMEM.SYS
- [ ] `DOS=HIGH` CONFIG.SYS directive: at init, request HMA via XMS, enable A20, relocate kernel resident code/data to FFFF:0010+
- [ ] Fix-up INT 21h dispatch: kernel entry points must remain in low memory (or use A20-aware thunks) since callers expect segment ≤ 0xFFFF
- [ ] A20 management: enable A20 while DOS code in HMA executes, handle transitions correctly
- [ ] `MEM` display: show "nnnnK DOS resident in HMA" when DOS=HIGH is active
- [ ] Test: boot with `DOS=HIGH,UMB`, verify MEM shows DOS in HMA and conventional memory increases by ~45K

### Notes

- This is a from-scratch implementation for fun/learning. Use FreeDOS and JEMM as architectural references only.
- The existing EMM386.SYS in our build already does V86 mode and EMS page mapping — UMB and HMA support extend this, don't replace it.
- Testing strategy: QEMU with ≥1MB RAM, verify via MEM output and actual program loading.

## E2E Tests — Remaining Per-Command Coverage

**Harness:** kvikdos for fast tests (`run_tests.sh`), QEMU+COM1 for disk-heavy ops. CI runs parallel E2E jobs for each test target; see `.github/workflows/ci.yml` for the full list.

### COMMAND.COM built-ins — remaining (interactive / needs special setup)

| Command | Remaining options |
|---------|-------------------|
| DIR | `/P` (pause/page — interactive) |
| DATE | no-arg (show date), set date — interactive |
| TIME | no-arg (show time), set time — interactive |
| PAUSE | no-arg (waits for keypress) — interactive |
| CHCP | `CHCP nnn` (set — needs DISPLAY.SYS) |

### External CMD tools

#### XCOPY — remaining (interactive)
- [ ] `XCOPY src dest /P` — prompt per file (interactive)
- [ ] `XCOPY src dest /W` — wait before start (interactive)

#### REPLACE — remaining
- [ ] `REPLACE src dest /P` — prompt (interactive)
- [x] `REPLACE src dest /U` — only if dest older
- [ ] `REPLACE src dest /W` — wait before start (interactive)

#### BACKUP — remaining
- [ ] `BACKUP C: A: /F` — format target if needed

#### RESTORE — remaining
- [ ] `RESTORE A: C: /P` — prompt on conflicts (interactive)

#### EDLIN — remaining
- [ ] `EDLIN file /B` — binary (ignore ^Z) — needs QEMU

#### DEBUG — remaining
- [ ] Load file (needs QEMU)

#### FDISK
- [ ] `FDISK` — interactive (smoke test: launches and exits)
- [ ] `FDISK /PRI` — create primary partition

#### PRINT
- [ ] `PRINT /D:PRN file` — print to device
- [ ] `PRINT /T` — cancel queue
- [ ] `PRINT file /P` — add to queue
- [ ] `PRINT file /C` — remove from queue
- [ ] `PRINT /Q:5 file` — set queue size

#### ASSIGN — remaining
- [ ] `ASSIGN A=B` — redirect A: to B: (TSR operation, needs QEMU)
- [ ] `ASSIGN` — clear all assignments (TSR operation, needs QEMU)

#### JOIN — remaining
- [ ] `JOIN A: C:\FLOPPY` — join drive to path (needs QEMU)
- [ ] `JOIN A: /D` — remove join (needs QEMU)

#### SUBST — remaining
- [ ] `SUBST X: C:\LONGPATH` — create substitution (needs QEMU)
- [ ] `SUBST X: /D` — remove substitution (needs QEMU)

#### FASTOPEN
- [ ] `FASTOPEN C:=50` — cache 50 entries
- [ ] `FASTOPEN C:=50 /X` — use expanded memory

#### GRAPHICS
- [ ] `GRAPHICS` — load default (GRAPHICS.PRO)
- [ ] `GRAPHICS COLOR4 /R` — color4 reversed
- [ ] `GRAPHICS HPDEFAULT /B` — with background

#### MODE
- [ ] `MODE COM1: 9600,N,8,1` — configure serial
- [ ] `MODE LPT1: 80,66` — configure parallel
- [ ] `MODE CON COLS=80 LINES=25` — configure console
- [ ] `MODE CON RATE=30 DELAY=1` — typematic rate
- [ ] `MODE CON /STATUS` — show console status

#### RECOVER
- [ ] `RECOVER A:file` — recover bad-sector file
- [ ] `RECOVER A:` — recover entire disk

#### IFSFUNC
- [ ] `IFSFUNC` — load IFS driver (smoke test)

#### FILESYS
- [ ] `FILESYS` — load (smoke test, internal tool)
