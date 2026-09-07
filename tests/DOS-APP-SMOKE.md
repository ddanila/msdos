# External DOS application startup comparison

Use [dos_app_smoke.json](dos_app_smoke.json) for the candidate list, archive.org
items, pinned download hashes, startup commands, and screen witnesses. The
selection favors shells, file managers, editors, and executable/archival tools
whose normal operation uses DOS memory, process, filesystem, and console
services. These features explain the selection; startup captures do not measure
which INT 21h functions ran or establish full application compatibility.

Build the default fork before running:

```sh
gmake -j4
gmake deploy
python3 tests/capture_dos_app_smoke.py --retail-image /path/to/retail-dos622-hdd.img
```

The retail input must be a bootable FAT16 hard disk with its first partition
in the MBR, genuine DOS 6.22 system files, and retail HIMEM.SYS and EMM386.EXE
under C:\DOS. The optional `--fork-floppy` defaults to `out/floppy.img`.
The runner copies both inputs, transfers the fork with SYS, installs its matching
COMMAND and memory managers, and verifies the transferred core files against the
floppy. It never modifies the supplied media. Experimental composed layouts
need separate qualification; this runner tests the supplied deployed floppy.

Downloads and extracted application files remain in ignored `.reference/dos-apps`.
All emulator disks, binary hashes, configuration files, QEMU invocations,
transitional and final text captures, video memory, PPM screenshots, raw and
normalized diffs, and the generated report remain in a private `out/` directory.
`--output` selects an empty output directory. The runner uses two QEMU instances
at a time, one per system, with the same 486 CPU, RAM, virtual hardware and RTC.

Use `--program` (repeatable) to select manifest entries, `--profile low`,
`--profile xms`, or `--profile high` to select memory configurations, and
`--seconds` to set the per-boot startup deadline. A matching screen must remain
recognizable for a short settling period before capture. Explicit manifest
keystrokes are sent on both systems where a startup prompt needs acknowledgement.
The additional shell/archiver scenario performs one small child-process job and
checks the produced ZIP's contents and hash.

A passing pair requires both application witnesses, matching normalized text,
and matching video attributes. The normalizer only removes QEdit's free-memory
number and DOS Navigator's clock and free-space numbers. Raw differences remain
in the evidence. DOS Navigator's displayed disk space must independently match
mtools' FAT free-space calculation; different system binaries occupy different
numbers of clusters. Free conventional memory differs between implementations
and remains visible in the raw captures. Neither difference alone implies a
startup defect. Any other screen difference or missing witness fails the run.

## Emulator correctness

The runner disables QEMU TCG block chaining with `-d nochain`. An affected
translator can follow a near CALL below the current CS base instead of wrapping
its 16-bit IP first. This happens when the unwrapped target and the CALL occupy
the same physical page. See
[the minimal probe](qemu_near_call_wrap_probe.asm) and
[the executable diagnostic](test_qemu_near_call_wrap.py):

```sh
gmake test-qemu-near-call-wrap
```

The diagnostic requires the workaround to pass. Its default-mode run may either
pass or report the specific known wrong-target signature; an unrelated crash,
setup failure, or timeout does not count as reproducing the bug. Use
`--require-default` to check that a replacement emulator has fixed chaining.
The relevant translator code is QEMU's
[`gen_jmp_rel`](https://github.com/qemu/qemu/blob/master/target/i386/tcg/translate.c).

This can masquerade as a DOS memory-manager defect. Retail EMM386 relocates the
EBDA and changes the conventional-memory ceiling, shifting 4DOS's code relative
to page boundaries. Keeping the EBDA in place with retail `NOMOVEXBDA` reproduced
the failure on stock DOS too. `MaxLoadAddress=600` or disabling 4DOS swapping also
avoided it, but those alter the application workload. Disabling emulator chaining
allows the original application commands and memory settings to run unchanged.
No DOS kernel or EMM386 change was justified by this finding.

## Recorded comparison

The compact [application results](dos_app_smoke_baseline.json) retain system and
application hashes, the configurations, emulator version, readiness checks,
comparison results, and screen hashes. The
[CPU diagnostic results](qemu_near_call_wrap_baseline.json) record the paired
chaining control. Full local captures remain under the run's ignored output
directory. These are observations for the recorded binaries, not automatically
updated compatibility guarantees.

To record a new campaign after building:

```sh
python3 tests/capture_dos_app_smoke.py \
  --retail-image /path/to/retail-dos622-hdd.img \
  --record-baseline tests/dos_app_smoke_baseline.json
```

For a comparison without updating the checked-in record, use
`gmake test-dos-app-smoke RETAIL_DOS_IMAGE=/path/to/retail-dos622-hdd.img`.
