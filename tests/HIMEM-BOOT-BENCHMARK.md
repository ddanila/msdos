# HIMEM startup performance

Compare the default HIMEM memory test with `/TESTMEM:OFF` on matched bootable
FAT16 hard disks. Each input must contain its own `HIMEM.SYS` and `EMM386.EXE`
at the root. Microsoft DOS is an external input; never commit its media.

```sh
python3 tests/benchmark_himem_test.py \
  --fork-image /path/to/fork.img \
  --microsoft-image /path/to/microsoft622.img \
  --output out/himem-comparison --repeats 9 --max-test-ratio 1.1
```

The script makes private copies with identical startup files, hardware and
timing MBRs. It times disk boot to the first AUTOEXEC application, excluding
BIOS POST. One warm-up per variant is discarded; subsequent boots are shuffled
and run sequentially. The memory-test cost is the difference between the median
default and disabled-test boots. The optional ratio gate compares that cost,
not total boot time. The report also retains both total boot medians.

Use `--mode high` to isolate HIMEM from EMM386 and UMB initialization,
`--memory` to vary RAM, and `--fork-himem` to test a candidate driver on private
copies. Keep the final qualification matched to a complete production build.
Verify HMA/UMB installation and memory-test failure behavior separately: an
early driver rejection must never be counted as a performance improvement.

Raw timing markers, QEMU commands, installed binary hashes and summaries remain
under the selected output directory. These are host elapsed-time measurements
under QEMU TCG with block chaining disabled, not physical 486 timings. Near-zero
differences require more repetitions or phase instrumentation before accepting
a performance claim.

`python3 tests/test_himem_testmem_qemu.py` exercises the actual linked 386 test
routine, independently reads back its complete tested span through BIOS block
moves, and checks the following guard. It covers 1 KiB, a full 64 KiB chunk,
and a partial final chunk, plus injected faults at the first byte, a chunk
boundary, and the final byte with either pattern. Each case tests both A20
entry states and verifies CR0, the complete GDTR and IDTR, ES, DS, SP, IF, DF,
NT, and CMOS-index/mask readback. Deterministic vector-2 injections exercise
NMI handling before, during, and after the protected-mode transitions, including
both windows between changing CR0 and the far jump. These are software
injections through the real interrupt gates, not asynchronous hardware timing
coverage. `--production` uses the production driver's build flags;
`--a20-backend bios|kbc` forces fallback A20 methods, and repeatable `--case`
arguments select focused cases. `make test-himem-testmem-qemu` runs both full
driver variants and the focused A20 fallback cases; it is also a prerequisite
of `make test-himem-qemu`. Ordinary driver installation and
the 286 path remain covered by the existing HIMEM option and platform tests.

Recorded measurements and validation scope are retained in the
[qualification manifest](himem_boot_qualification.json).
