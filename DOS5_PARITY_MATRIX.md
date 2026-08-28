# DOS 5 compatibility matrix

The maintained system reports DOS 5.00 because its kernel, configuration, and
command surfaces now implement the DOS 5 UMB/HMA contract. The `v4.0` source
directory name records ancestry and is not a runtime version claim.

This matrix prevents the version identity from implying that every unrelated
program shipped in the commercial MS-DOS 5 product is already present. It is
also the starting point for the broader DOS 5 parity project after
`UMB_PLAN.md` is complete.

## Version transition gate

| Surface | Required 5.00 behavior | Evidence |
| --- | --- | --- |
| `INT 21h/AH=30h` | Return major 5, minor 0 while preserving the existing per-program fake-version hook. | `tests/int21_system_probe.asm`, `tests/test_int21_system_qemu.sh` |
| `INT 21h/AX=3306h` | Return the unfaked 5.00 identity in `BX`, revision/flags zero in `DX`. | `tests/int21_system_probe.asm`, `tests/test_int21_system_qemu.sh` |
| Kernel and SYSINIT banners | Derive 5.00 from the shared version constants. | `INC/VERSIONA.INC`, build and boot tests |
| `COMMAND.COM VER` | Report the live kernel identity as 5.00. | `tests/run_tests.sh`, `tests/test_screen_expect.sh` |
| Boot-sector OEM identifier | Identify newly built media as `MSDOS5.0`. | `BOOT/MSBOOT.ASM`, `tests/test_sys.sh` |
| Utility version checks and banners | Use the shared 5.00 constants and maintained copyright message. | complete native build and utility runtime suite |
| UMB allocator/API | DOS 5 allocation strategies, linking, MCB lifecycle, cleanup, and standard XMS acquisition. | `tests/test_xms_umb_transaction_qemu.sh` and INT 21h memory suites |
| HMA and configuration | `DOS=HIGH/LOW`, `UMB/NOUMB`, provider absence, fallback diagnostic, and real relocation. | `tests/test_hma_qemu.sh`, CONFIG.SYS suites |
| High loaders and diagnostics | `DEVICEHIGH`, `INSTALLHIGH`, `LOADHIGH`/`LH`, region profiles, and UMB-aware `MEM`. | focused QEMU suites for each command |

All version surfaces change together. A build that mixes 4.x and 5.00 values is
invalid.

## Known follow-on gaps

These do not block the UMB/HMA compatibility identity, but remain explicit DOS
5 parity work:

- add the complete persistent `SETVER` database and utility behavior; the
  inherited per-process fake-version mechanism remains available;
- audit and implement non-memory DOS 5 kernel deltas, recording a black-box
  contract before each change;
- bring FDISK, FORMAT, SYS, and setup/update workflows to DOS 5 behavior beyond
  their currently tested DOS 4-derived contracts;
- decide which DOS 5 product utilities belong in this maintained distribution
  (for example DOSKEY, EDIT/QBASIC, HELP, DOSSHELL, LOADFIX, UNDELETE, and
  UNFORMAT) and implement only from license-compatible sources or clean-room
  observations;
- complete real-hardware or cycle-accurate 386+ acceptance and pre-386 fallback
  testing required by `UMB_PLAN.md`;
- broaden third-party, redirector, asynchronous-interrupt, and warm-reboot
  compatibility testing with DOS resident in the HMA;
- complete the advertised HIMEM/XMS conformance matrix before describing the
  repository driver as a general replacement for every commercial XMS manager.

Commercial DOS binaries and derived content are never committed. Reference
media is used only as an external black-box oracle.
