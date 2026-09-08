# External DOS application startup comparison

Use [dos_app_smoke.json](dos_app_smoke.json) for the candidate list, archive.org
items, pinned download hashes, startup commands, and screen witnesses. The
selection favors shells, file managers, editors, development tools, spreadsheets,
print formatters, and executable/archival tools
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

Python, QEMU, NASM, mtools, and Info-ZIP `unzip` must be installed. The latter
handles legacy ZIP shrinking/imploding after the same path validation as Python.
The manifest also supports individual executable downloads and ZIP-wrapped FAT
floppies; their original download is hash-checked before extraction.

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
PC-File uses its documented `/CHARMODE` option on both systems so the same
text-screen comparison can check its startup interface. CuteMouse is installed
as a TSR in each private image; mouse motion and clicks are outside this smoke.
The additional shell/archiver scenario performs one small child-process job and
checks the produced ZIP's contents and hash.

A passing pair requires both application witnesses, matching normalized text,
and matching video attributes. Normalization is limited to:

- QEdit and AS-EASY-AS free-memory fields, and RAR's memory-in-use field.
- DOS Navigator, AS-EASY-AS, and PC Tools clocks.
- DOS Navigator and PC Tools free disk space, independently checked against
  mtools' FAT free-space calculation for each image.
- D86's empty-debuggee segment addresses, expressed relative to CS. Segment
  relationships remain checked. One immediate `XOR BP,BP` initializes BP and
  arithmetic flags, whose inherited startup values differ between DOS builds.

Raw differences remain in the evidence. Different system binaries occupy
different numbers of clusters and leave different conventional memory amounts.
Neither difference alone implies a startup defect. Application text, enabled
operations, memory-use percentages, register relationships, and video attributes
remain compared. Any other screen difference or missing witness fails the run.

The HIGH profile now explicitly requests `EMM386.EXE 2048 RAM`. The earlier
record used `EMM386.EXE RAM`: the fork's historical parser defaults to a fixed
256 KiB pool (see `set_pool_size` in `src/MEMM/MEMM/INIT.ASM`), while retail offers
more EMS by default. AS-EASY-AS exposed this resource-policy difference in its
startup memory display. The explicit budget makes the application comparison
use equivalent EMS limits without changing either driver's default policy.
These tests do not establish identical automatic EMS sizing.

## EXEPACK compatibility

PC Tools Deluxe's PC Shell started under retail DOS but reported "Packed file
is corrupt" under the fork with DOS high. Its EXEPACK decoder converts low
source/destination addresses into wrapped segments that need A20 disabled.
A load-only `INT 21h/AX=4B01h` diagnostic showed retail repairing that decoder
in the loaded image; the fork had left it unchanged.

The fork's [EXEC loader](../src/DOS/EXEC.ASM) now recognizes this complete
decoder variant and replaces its normalization loop with one that clamps at
segment zero and retains the residual address in the offset. The repair applies
to normal/load-only EXEs below 64 KiB, after relocation; overlays and unmatched
signatures are excluded. It changes neither the on-disk file nor its entry,
size, or relocation layout. This is a narrow compatibility repair, not support
for every historical EXEPACK variant.

The [synthetic regression](exepack_low_probe.asm) contains a small packed program
whose final zero-run record reproduces the underflow. The
[runner](test_exepack_qemu.py) tests it with HIMEM and EMM386, and requires an
unrecognized but equivalent decoder to retain the original failure. No external
application is needed:

```sh
gmake test-exepack-qemu
```

The compact [regression record](exepack_baseline.json) retains pre-fix and fixed
kernel hashes and observed positive/negative outcomes. Use
`--floppy /path/to/pre-fix.img --expect-unpatched` with the Python runner to
require the original failure in both configurations. Application comparisons
continue to launch `PCSHELL.EXE` directly.

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

The compact [earlier application results](dos_app_smoke_baseline.json) and
[additional utility batch](dos_app_smoke_batch3_baseline.json) retain system and
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

## Composed application lifecycle qualification

Use the separate [lifecycle runner](test_composed_app_lifecycle_qemu.py) for the
frozen composed image. It verifies the build record and current source hashes,
then copies the candidate without transferring a default kernel or changing its
startup configuration. It checks the retail core against the existing retail
baseline and runs the same application packages and configuration on that copy.
Cached archives are hash-checked and extracted privately for each campaign.

```sh
python3 tests/test_composed_app_lifecycle_qemu.py COMPOSITION_DIR \
  --retail-image /path/to/retail-dos622-hdd.img \
  --record-baseline tests/memory_application_baseline.json
```

The jobs repeatedly launch PKZIP and PKUNZIP through 4DOS, validate complete
archive membership and contents, and compare extracted files byte for byte.
Binary inputs cross a segment boundary. DOS COPY transfers each extracted binary
to a virtual floppy and back, overwriting the preceding floppy file explicitly.
External pipe legs overwrite their largest conventional allocation to force
COMMAND transient reload; the resulting pipe files and inherited environment
must survive. Conventional/upper free totals and largest blocks, allocator/link
policy, and EMS availability must return to the same state after every job.

QEdit repeatedly reopens the same document, inserts a line, corrects a character
with Backspace, saves, and exits. Each reopen must display the preceding edit;
each saved checkpoint must contain exactly the accumulated text, and memory
accounting must still match. Corrupted extracted data, archives, memory snapshots,
and editor output must be rejected by the host-side oracles.

The [lifecycle record](memory_application_baseline.json) retains executed hashes,
operations, output hashes, memory snapshots, and controls. The comparison checks
persisted file contents, not identical application screens or archive timestamps.
Identical startup text does not equate the managers' automatic EMS sizing;
resource stability is checked within each system. These jobs do not qualify
other application features, physical media timing, or removable-media changes.
The next stabilization step is the promotion review in [MEMORY.md](../MEMORY.md).
