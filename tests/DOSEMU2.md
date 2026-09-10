# External DOSEMU2 DOS API tests

The `dosemu2` submodule pins `ddanila/dosemu2`. Adaptations belong to its
`custom` branch; `devel` remains the upstream synchronization branch. Update
and push the fork before changing the parent repository's gitlink.

```sh
git submodule update --init dosemu2
make test-dosemu2-qemu
```

The target builds the matched production image and invokes the fork's QEMU
adapter in LOW and HIGH/UMB modes. The selected upstream Python test functions,
embedded NASM DOS programs, and assertions execute from the submodule. The
parent launcher only starts a separate Python process. No DOSEMU2 emulator
build is required. Dependencies are Python 3 with `pexpect`/`ptyprocess`, NASM,
mtools, and QEMU's i386 system emulator.

After building, select individual cases or an external boot floppy with:

```sh
python3 tests/test_dosemu2_qemu.py --list
python3 tests/test_dosemu2_qemu.py --mode low --case ds2_file_seek_read_SET
python3 tests/test_dosemu2_qemu.py --boot-image /path/to/dos-floppy.img --mode low
```

`FLOPPY_IMAGE` also overrides the default input. HIGH/UMB requires that image
to contain its matching HIMEM.SYS, EMM386.EXE, and English MEM.EXE at the root.
The adapter verifies the HMA report and usable UMB linking in HIGH mode. Never overwrite
reference media: each case receives a private boot-image copy and scratch FAT
disks. Logs, commands, generated program sources, image hashes, and per-case
results remain in a unique `out/dosemu2-qemu-*` directory. A failed assertion,
missing completion marker, unexpected emulator exit, or timeout fails the run.

## Scope

The adapter selects NASM-based FAT tests for FCB read/write/find/rename/delete,
handle reads at EOF and with an alternate DTA, and seeks/readback/tell including
large and negative offsets. Its case listing is authoritative. It uses actual
guest FAT12 disks for both program and data drives. It does not use DOSEMU2's
host filesystem redirector. The fixture writes a DOS-compatible OEM/version
signature because the historical BIOS rejects mtools' default OEM identifier.
This suite therefore does not qualify arbitrary formatter OEM strings.

This is an initial subset, not the complete DOSEMU2 suite. MFS/redirector,
network, LFN, DPMI, compiler-dependent C tests, and external binary collections
are not adopted by this target. Existing project probes continue to cover
contracts beyond this subset. QEMU uses the existing no-chaining workaround;
see [emulator limits](../EMULATION.md).

## Licensing

DOSEMU2 and its adaptations retain their upstream licensing in the submodule;
see `dosemu2/COPYING` and `dosemu2/COPYING.DOSEMU`, plus individual file notices.
Do not copy its implementation into the MIT DOS sources. Generated test
programs are separate test artifacts; redistributing them requires retaining
the applicable licenses and providing corresponding source. Reference DOS
media are external inputs and are not redistributed here.

The [qualification record](dosemu2_qualification.json) retains the tested pins,
boot-image hashes, case results, Microsoft control, and corruption control.
