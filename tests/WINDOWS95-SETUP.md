# Windows 95 installer compatibility investigation

Local investigation on 2026-09-05 using the user's Windows 95 OEM CD in
QEMU 10.2.1 (Pentium TCG, 32 MiB RAM, 504 MiB FAT16 IDE disk, no network).
The CD and VM disks are not redistribution/test fixtures.
The observations below were made from base revision `e148ff1` plus the fixes
described here, before subsequent upstream BIOS/HMA changes through `e1d9bdf`.
The unresolved Windows-loader and ScanDisk cases have not been rerun on that
newer upstream state.

## Confirmed fixes

- `mk/cmd.mk` named `comsw.asm` instead of the tracked `COMSW.ASM`, breaking
  deployment on case-sensitive Linux. `test_toolchain_transforms.py` checks
  the exact prerequisite against directory entries; the old spelling fails.
- Failed opens leaked JFN reservations when the selected SFT was outside
  DOSGROUP. `AccessFile` loads DS with the SFT segment; `OpenE` then loaded
  the global `pJFN` through that DS instead of SS. Make the SS override
  explicit. Microsoft's CD-supplied EXTRACT.EXE repeatedly probes absent
  `DIA0.TMP` while holding two cabinet inputs open. Before the fix it runs
  out of handles; afterwards both PRECOPY cabinets extract to completion.
  The public regression uses no Microsoft files: the INT 21h system probe
  holds two NUL handles and performs 64 missing-file opens with FILES=60.
  It prints `INT21_MISSING_OPEN_LEAK` before the fix and
  `INT21_SYSTEM_PASS` afterwards.

## Still under investigation

Windows Setup reaches its graphical wizard with the corrected kernel and
`FILES=60`, `BUFFERS=30`, no HIMEM, and the CD-documented `SETUP /IS` option.
This path subsequently completed Windows installation and booted the guest
to its desktop. The installed guest also ran JUKUWIN and booted a simulated
C12 Juku; those host-specific fixes and results are recorded in the sibling
`8080-cosim/docs/windows-jukuhost-client-win95-acceptance.md`.
Earlier normal-Setup attempts were followed by damage to the staged setup
directory. Skipping ScanDisk avoided that symptom; the precise cause has
not been established. Loading the current HIMEM produced an insufficient
extended-memory error in the mini-Windows loader; this also remains open.

### HIMEM / mini-Windows loader

The failing configuration included:

```ini
FILES=60
BUFFERS=30
DEVICE=A:\HIMEM.SYS /TESTMEM:OFF
DOS=HIGH
```

`SETUP /IS` reported: `Insufficient extended memory to run Windows in standard mode.`
Removing both the HIMEM device line and `DOS=HIGH`, while retaining FILES and
BUFFERS, allowed the graphical loader to start. This does not isolate HIMEM
from HMA residency, and that observation preceded the failed-open cleanup fix.
The successful installation does not validate this configuration.

Next check: on fresh cloned disks with the corrected kernel, compare no HIMEM,
HIMEM with DOS=LOW, and HIMEM with DOS=HIGH under the same QEMU settings.
Record XMS installation/version, free-memory query, allocation and lock results
before invoking the CD's loader. Do not infer an XMS implementation defect solely
from the loader's generic memory message.

### ScanDisk / staged source directory damage

The original setup source was staged in `C:\WIN95`. Following normal Setup
attempts, that directory no longer listed the CAB files and instead listed
`WINTEMP.400`; subsequent Setup attempts reported a missing required CAB file.
A separate DOS `MD C:\PROBE` test left the source directory intact. Using
`SETUP /IS` avoided the observed directory damage.

These attempts preceded the failed-open cleanup fix, which can write through
the wrong pointer. ScanDisk has **not** been established as a separate remaining
kernel bug: stale state from an interrupted installation and the fixed cleanup
defect have not been excluded. Retest normal Setup and `/IS` on separate pristine
clones with the corrected kernel, comparing FAT/root/subdirectory metadata and
CAB hashes before and after the ScanDisk stage. Do not test repair operations on
the only copy of an installed guest or original media.

## Validation retained locally

`make -j4 deploy`, `python3 tests/test_toolchain_transforms.py`,
`bash tests/test_int21_system_qemu.sh`, `bash tests/test_int21_path_errors_qemu.sh`
(DOS=LOW and DOS=HIGH), and `bash tests/test_int21_file_memory_qemu.sh` passed.
The failed-open regression was observed failing before the segment fix and
passing afterwards. VM disks and diagnostics are under the sibling project's
ignored `build/win95/`; none of the proprietary installation files are committed.
The same deployment and focused regression commands also passed after
integrating upstream `e1d9bdf`, before publishing this report. That regression
rerun did not include the proprietary Windows installer/HIMEM/ScanDisk cases.
