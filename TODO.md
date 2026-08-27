# MS-DOS 4.0 Build — TODO

## Complete behavioral coverage and traceability (ACTIVE)

The current coverage program is defined in `tests/COVERAGE.md`. Its first
machine-checked inventory parses all 109 live INT 21h dispatch entries from
`DOS/MS_TABLE.ASM`. The dispatch milestone is complete: 104 entries have
focused QEMU contracts, five hardware/write-only entries have explicit
justifications, and the normal test suite enforces `--require-complete`.
CI also rejects unexpected host-test skips. The runtime inventory is complete:
all 55 shipped commands, drivers, and TSRs and all 17 CONFIG.SYS directives have
focused contracts enforced by the normal test suite. All 110 allowed INT 21h
function/error pairs derived from `I21_MAP_E_TAB` are accounted for: 94 have
focused negative-path evidence and 16 have source-proven exclusions. The DOS
interrupt inventory similarly accounts for all 11 installed vectors. The active
depth milestone audits boundaries, state transitions, recovery, persistence,
and source-only exclusions; the installable-device inventory currently has 92
behavioral contracts and 48 justified exclusions across 140 request surfaces.
All 48 exclusions are post-failed-INIT requests in the two XMA drivers and are
runtime-proven unreachable on the supported QEMU hardware contract; every
reachable pass-through, no-op, unsupported, and ordinary handler is exercised.
Source-derived command-line depth currently covers all 35 COMMAND.COM built-ins,
six startup switches, two SELECT modes, and 124 switch/operator forms across
twenty-nine standalone utilities. A cross-inventory gate now accounts for all
41 shipped executable interfaces, including positional-only, interactive,
stream, keyword, and bootstrap surfaces. DEBUG's twenty live commands and all
four nested EMS subcommands are independently derived and contract-tested. All
41 executable help surfaces are also accounted for: 37 execute `/?`, while
four interfaces without a top-level help form have source-backed
classifications. Argument relationships and mutation-driven completeness are
now enforced as ordinary gates. The oracle-mutation audit disabled
command echo in every serial batch, exposed and corrected false FORMAT and SYS
status expectations, found two real RESTORE one-file/existing-target defects,
and added a normal-test gate that prevents any of the 51 `CTTY AUX` batches
from matching its own echoed commands. A source-checked mutation inventory now
strictly accounts for all 55 runtime components; removal of every artifact is
killed by an assigned behavioral QEMU suite, with no exclusions. The audit
also found that FLUSH13.EXE, PRINTER.SYS/4201.CPI, and the XMA2EMS.SYS/XMAEM.SYS
drivers were missing from the published floppy; focused tests now consume the
deployed copies instead of masking packaging omissions with source-tree
injection. COUNTRY.SYS selects Germany and is checked through the live DOS
country interface, while SORT, TREE, FC, and the boot files have explicit
deployed-artifact contracts rather than presence-only evidence.

## Native Open-Source Build (COMPLETE)

**Active goal (August 27 2026):** Deliver a reproducible, fully open-source
build of MS-DOS 4.0 on modern hosts, with no proprietary Microsoft binaries or
DOS emulation in the build path, and pass the complete QEMU test suite. The
JWasm/wlink assembly migration below is complete historical groundwork. Current
implementation starts with native replacements for all nine DOS-hosted build
utilities, then migrates every C-hybrid target to Open Watcom wcc/wlink/wlib and
a shared compatibility runtime. `PLAN.md` defines milestones and completion
gates.

**Native production build complete locally (August 27 2026):** MEMM/EMM386,
the final proprietary island, now builds with JWasm plus Open Watcom
`wcc`/`wlib`/`wlink`. WLINK far-data packing is disabled for this link so the
driver's protected-mode tables retain their required independent `SEG:0000`
layout. Explicit 32-bit source operands replace MASM-era split-immediate byte
encodings, and page-table copy sizing now handles both packed and independent
segment layouts. A focused QEMU test validates protected-mode entry plus EMS
allocation, mapping, cross-window memory aliasing, and release. EMM386 is
included in `make deploy`. The complete local QEMU matrix passes.

The WLIB compatibility wrapper now resolves DOS paths case-insensitively on
Linux and normalizes per-member DOS timestamps with repaired OMF checksums.
Two clean builds established byte-for-byte repeatability across all 59 artifacts
before the final tool refresh. GitHub Actions run `33051385481` reproduces the
refreshed 59-artifact golden set and passes all 23 build and QEMU jobs.
The refreshed custom Linux WCC deterministically changes only ATTRIB's local
stack-slot ordering and reduces EMM386's compiled image by one paragraph; their
goldens now pin those latest-toolchain outputs. The previously completed local
QEMU matrix and the complete Linux CI matrix both validate the sources end to
end.

**All command utilities link with WLINK (August 27 2026):** The remaining 22
Microsoft LINK recipes in `mk/cmd.mk` now use the pinned custom Open Watcom
linker. The migration also makes legacy layout intent explicit in source:
GRAPHICS' helper module has no entry record; SYS places DATA in an explicit
DGROUP matching its runtime DS; and FASTOPEN gives its four resident/overlay
segments separate one-segment groups so WLINK preserves their segment values.
The latter makes the WLINK load-module body byte-identical to Microsoft LINK's
for the same objects and fixes CONFIG.SYS `INSTALL=FASTOPEN` after multiple
drivers. A new EDLIN open/list/quit QEMU test closes its prior behavior gap.
The host suite passes 291/291 and the complete serialized QEMU target matrix
passes. Only MEMM remains: three CL calls, one LIB call, and one LINK call.

**First Open Watcom C hybrid complete (August 27 2026):** Production ATTRIB now
builds with native Open Watcom `wcc`, custom JWasm, `wlink`, and the vendored OW
DOS runtime; it no longer invokes MS CL or LINK. The old display hang was an ABI
layout mismatch: C parser structures need byte packing, but SYSDispMsg follows
the 12-byte offsets historically produced when MS C placed separate 11-byte
`m_sublist` globals on word boundaries. ATTRIB now models that stride explicitly
with padded records instead of linker-dependent adjacency. The port also fixes
the real `string[16]`/`string[16] = 0` overflow. Validation passes the complete
host suite (290/290), a forced `make -B -j8 build-all`, QEMU help (6/6), and the
two-disk BACKUP/RESTORE suite (38/38), including real FAT archive-bit changes.

**Second Open Watcom C hybrid complete (August 27 2026):** FC and its shared
KSTRING source now compile with `wcc`; its seven assembly modules use custom
JWasm and the executable links with `wlink`. The OW KSTRING object has a
distinct name so unmigrated MS-C consumers cannot accidentally reuse it. FC's
old generated header contained invalid trailing-comma prototypes, its local
`strcmpi` collided with the OW library, and its cdecl assembly expected a cdecl
`strlen`; these boundaries are now explicit, with a small compatibility module
for the assembly callback. A missing error-code argument in the out-of-memory
path was also fixed. All 16 focused FC behaviors pass within host 290/290, a
forced parallel full build and deployment succeed, and QEMU help/boot passes
6/6.

**Native MAPPER library complete (August 27 2026):** `MAPPER.LIB` now builds
with vendored host-native Open Watcom `wlib`; Microsoft LIB.EXE is no longer in
that production path. `bin/wlib` translates all three MS-LIB command forms used
by the tree: response-file creation, inline creation/addition, and module
replacement. The native library contains the same 53 modules and exported
symbol set as the reference. A forced parallel full build, host 290/290, and
the complete parallel QEMU target matrix pass. COMSUBS is a distinct issue: its
source is absent from this tree, so migrated consumers must use open-source
replacements for the small subset of entry points they need rather than retain
the checked-in binary library.

**Third Open Watcom C hybrid complete (August 27 2026):** REPLACE now builds
with `wcc`, custom JWasm, native `wlink`, and the native-wlib MAPPER library.
Its only COMSUBS dependencies were `com_strchr` and `com_strrchr`; source
replacements now query the active DOS DBCS lead-byte vector and skip complete
double-byte characters, so REPLACE no longer links the source-less binary
COMSUBS library. The port applies the proven ES=DGROUP SAL bridge fix, OW `_psp`
ownership, safe far-pointer construction, and null-string handling; it also
fixes an `argv[argc]` read and invalid omitted K&R arguments. All focused modes
pass within host 290/290, a forced parallel full build/deploy succeeds, and the
interactive QEMU `/P` workflow passes 10/10.

**Fourth Open Watcom C hybrid complete (August 27 2026):** BACKUP now builds
with `wcc`, custom JWasm, native `wlink`, native-wlib MAPPER, and the native
CONVERT replacement. REPLACE's DBCS-aware searches moved into shared
`INC/OWCOMSUB.C`, which also supplies `com_toupper` through DOS's country-aware
`INT 21h AX=6520h` service; neither target links binary-only COMSUBS.LIB. The
port fixes an `argv[argc]` read, a malformed `\\BACKUP\\CONTROL.*` literal,
and the OW pointer/stdio declarations, and sets ES=DGROUP at each SAL bridge.
Host parity is 290/290, a full parallel build/deploy succeeds, and the focused
two-disk BACKUP/RESTORE QEMU suite passes all 38 checks.

**Fifth Open Watcom C hybrid complete (August 27 2026):** RESTORE's twelve
production C objects now use `wcc`; its two SAL bridges use custom JWasm, and
`wlink` plus native CONVERT produce RESTORE.COM without MS CL/LINK or
COMSUBS.LIB. The shared COMSUB replacement adds the original identity
return-code-to-message mapping, while `INC/OWDOSFS.C` provides cdecl wrappers
for DOS `chdir`/`mkdir` services. The migration removes conflicting near/far
tentative definitions of the two transfer-buffer pointers, fixes the
`argv[argc]` parser read and DBCS reverse-scan underflow, and records all local
headers as real build prerequisites. The canonical build passes host 290/290,
a forced parallel full build/deploy, and the BACKUP/RESTORE QEMU suite 38/38.

**Sixth Open Watcom C hybrid complete (August 27 2026):** FILESYS now compiles
with `wcc`, its two assembly modules use custom JWasm, and `wlink` produces the
production executable without MS CL or LINK. The port constructs the PSP
command-tail far pointer without assigning through `FP_SEG`/`FP_OFF` macros and
sets ES=DGROUP at both SAL message bridges. Direct host `/?` output passes, a
forced parallel full build succeeds, QEMU help passes 6/6, and the QEMU
miscellaneous suite passes 48/48, including installing FILESYS after IFSFUNC.

**Seventh Open Watcom C hybrid complete (August 27 2026):** JOIN now uses
`wcc`, custom JWasm, `wlink`, native-wlib MAPPER, the Open Watcom DOS runtime,
and a source implementation of COMSUBS substring search. Four shared `INC` C
objects have separately named OW variants so legacy SUBST retains its MS-C ABI.
The port makes far-pointer construction compiler-explicit, fixes a system-table
copy overrun, `argv[argc]`, null-source `strcpy`, omitted message arguments, and
undeclared byte-return functions that left stale AH in Open Watcom callers. A
forced parallel full build succeeds, direct host help passes, and the complete
two-floppy ASSIGN/SUBST/JOIN QEMU suite passes 16/16, including JOIN list,
DIR/TYPE/COPY through the joined path, and unjoin.

**Eighth Open Watcom C hybrid complete (August 27 2026):** SUBST now uses
`wcc`, custom JWasm, `wlink`, native-wlib MAPPER, source-backed COMSUBS substring
search, and the four shared OW `INC` objects introduced with JOIN. Its standard
runtime calls use Watcom's annotated headers while parser/message boundaries
remain cdecl; the port also fixes `argv[argc]`, null-source `strcpy`, omitted
message arguments, and undeclared byte-return drive predicates. Direct host
help passes, a forced parallel full build succeeds, and the complete sequential
ASSIGN/SUBST/JOIN QEMU suite remains 16/16, including SUBST create, list,
write-through, path pass-through, and deletion. SHARE and IFSFUNC prerequisites
now name only the shared assembly objects their link files consume; `inc` uses
the OW variants, eliminating four otherwise-unused MS-C compilations from every
full build.

**Ninth Open Watcom C hybrid complete (August 27 2026):** MEM now compiles
with `wcc`; its parser and message bridges use custom JWasm, and `wlink` links
the Open Watcom DOS runtime. The checked-in Microsoft `LIB/MEM.LIB` is no
longer consumed: its only MEM-specific startup symbol, `DOS_TopOfMemory`, is
replaced by the equivalent top-of-memory field in the program's PSP. Pointer
construction uses Watcom's `MK_FP` instead of Microsoft C's assignable
`FP_SEG`/`FP_OFF` extension, and the message wrappers establish ES=DGROUP.
Direct host help and memory reports pass, the complete host suite passes
290/290, QEMU help passes 6/6, and the QEMU driver/config suite passes 17/17,
including a real MEM report under a custom CONFIG.SYS.

**Tenth Open Watcom C hybrid complete (August 27 2026):** all twenty FDISK C
modules now compile with `wcc`; custom JWasm assembles the five supporting
objects, and `wlink` produces both FDISK.EXE and its embedded FDBOOT image.
The C sources consistently use Watcom's annotated DOS interrupt and console
declarations, far-pointer construction uses `MK_FP`, and the SAL message
bridges establish ES=DGROUP. The matching snapshot's `math87s.lib` is now
vendored because FDISK is the first migrated utility to exercise Open Watcom's
floating-point runtime. The direct host help path passes, and the destructive
QEMU FDISK suite passes 13/13: primary, extended, and logical partitions are
verified on disk, followed by a separate primary-only regression scenario.

**Eleventh Open Watcom C hybrid complete (August 27 2026):** SMARTDRV now has
no Microsoft compiler or linker step. FLUSH13 compiles with `wcc` and links its
two custom-JWasm companions against the Open Watcom small-model runtime; the
assembly-only SMARTDRV driver also links with `wlink` before native EXE2BIN
conversion. The `/t:` parser now obtains its 16-bit value in an aligned local
and explicitly serializes the low and high bytes into the packed IOCTL packet,
rather than relying on Microsoft C's permissive incompatible-pointer write.
Direct FLUSH13 usage execution succeeds; the full host and QEMU driver suites
cover the emitted utility and loading SMARTDRV.SYS.

**SELECT assembly outputs migrated (August 27 2026):** `SELECT.COM` and the
`SELECT.DAT` panel payload now link with `wlink`, while the auxiliary
`SERVICES.LIB` is built with `wlib`. The interactive QEMU SELECT suite passes
6/6 with the rebuilt stub and panel data. The three C objects and SELECT.EXE
main link remain the active part of the SELECT Open Watcom migration.

**Native SELECT tools (August 27 2026):** ASC2HLP and COMPRESS, the final two
proprietary build helpers, now have byte-compatible native Python replacements.
ASC2HLP compiles USA.TXT into the indexed SELECT help-file layout; COMPRESS
reproduces the original reserved-byte-aware RLE stream for SELECT.DAT. All nine
formerly proprietary helper utilities are now native. A no-emulation audit also
identified the source-built `MKCNTRY.EXE` execution as a separate remaining
kvikdos dependency; it was never proprietary and was subsequently hosted
natively as described below.

**Native MKCNTRY hosting (August 27 2026):** The JWasm/wlink-built MKCNTRY.EXE
contains its COUNTRY.SYS data as one contiguous region; its DOS code only writes
that region to a file. `bin/mkcntry` now extracts the payload on the host and is
byte-identical to the 12,806-byte reference output. The production build has no
non-toolchain DOS execution left: remaining kvikdos calls are the Microsoft C,
LINK, and LIB boundary targeted by the Open Watcom migration.

**Native BUILDMSG (August 27 2026):** `bin/buildmsg` is now a native Python
implementation of the message-skeleton compiler. Its regression corpus captures
every production invocation: 43 SKL inputs and 204 generated CL/CTL outputs are
byte-identical to the Microsoft utility, including localized continuations,
remapped extended/parse errors, synthesized class-1/class-2 fallback records,
and resident class procedure numbering. Every production CTL rule tracks the
native tool and shared catalog parser as prerequisites. Seven of the nine
DOS-hosted build utilities were native at this point except ASC2HLP and COMPRESS;
those final two are covered by the update above.

**August 26 2026 toolchain refresh:** assembly now uses the `custom` branch of
`ddanila/JWasm`, pinned in `jwasm/README.md`. The branch is based on the latest
upstream snapshot and fixes MASM-compatible PUBLIC spelling in case-insensitive
mode. The current pin is `9222ac7327f5cc23300181ab1ef8d7fdabc2fd0a`; it also
matches MASM 5.1's implicit-forward-JMP sizing, keeps forward conditional
branches short, and preserves scalar structure member sizes in indexed
expressions such as `[BX][DI].item_tag` and through `EQU` aliases. Open Watcom
C/link/library tools, headers, and DOS 16-bit libraries are
vendored from Current-build `638f7a4` (August 25 2026). The native wlink wrapper
now explicitly mirrors MS LINK symbol-case behavior and accepts separated dash
options without confusing hyphenated filenames. RECOVER's generated-message
dependencies are complete for parallel builds.

The apparent MSDATA `OUT` unresolved symbol was not intentional: JWasm's
host-width `NOT` made MSINIT's `IF (NOT IBM) OR (DEBUG)` true for the 16-bit
TRUE value `0FFFFh`. The condition now tests `IBM EQ 0`, and MSDATA.OBJ tracks
MSINIT.ASM as a real prerequisite. MSDOS, SHARE, and IFSFUNC consequently link
without unresolved symbols; the temporary `/UNDEFSOK` policy was removed.

KEYB's duplicate-start diagnostic was also a source-level MODEND issue:
KEYB.ASM correctly names `START`, while the library-style KEYBTBBL.ASM also
named `TABLE_BUILD` in its END directive. KEYBTBBL now emits a plain END;
KEYB.COM links with one entry point and converts successfully.

SELECT's five MS LINK L2002 failures were 16-bit relative-fixup distance
overflows, not malformed JWasm OMF. The service modules were extracted from
SERVICES.LIB after all explicit objects, placing GET_FUNCTION_CALL,
HANDLE_ERROR_CALL, and related SELECT-segment routines too far from their NEAR
callers. SELECT.LNK now lists those five modules explicitly beside SELECT0,
CASERVIC, and MOD_COPY, while CASSFAR remains a library. SELECT.EXE links and
the EXEPACK fixup completes successfully.

The first successful clean `make -j4` log audit exposed a hidden COMMAND.COM
L2029 that its Make recipe had ignored. RDATA.ASM now includes COMMAND.CL3 and
COMMAND.CL4, restoring the `$M_CLS_1`/`$M_CLS_2` definitions already required
by its dependency list. The leading `-` was removed from the COMMAND link
recipe: COMMAND.EXE must link successfully before EXE2BIN may run.

JWasm provisioning is now reproducible with `jwasm/build.sh`: it clones the
fork, checks out `9222ac7327f5cc23300181ab1ef8d7fdabc2fd0a`, builds for
macOS arm64 or Linux x86-64, and installs into the platform directory consumed
by `bin/jwasm-masm`. The macOS path was rebuilt successfully from scratch.

Runtime comparison against the MASM-built master image found two additional
assembler defects. First, `-Zm` shortened an implicit forward `JMP` that MASM
5.1 keeps near; STRUC.INC sequences such as `Jcc $+5 / JMP label` then branched
into the middle of an instruction and corrupted KEYB's parser. Second, JWasm
dropped the DB type from indexed structure members and encoded MODE's byte tag
comparisons as word comparisons. Both fixes live in the custom fork and have
binary regression tests. MODE's fragile structured-macro keyword loop was also
rewritten with explicit control flow in the MS-DOS source.

The initial forward-JMP patch also treated unresolved conditional branches as
near. That expanded COMMAND's transient parser layout and broke batch-file
reloads. The custom fork now limits the MASM 5.1 rule to unconditional `JMP`
and tests both encodings. COMMAND explicitly marks four in-range parser and
printing bridges `SHORT`; the full 290-test host suite covers batch execution
after a clean rebuild.

The master-reference coverage now runs on the migration output: the host suite
passes 290/290, the broad miscellaneous QEMU suite passes 48/48, focused MODE
passes 3/3 (including all keyword parameters and LPT redirection), and focused
KEYB passes 2/2. The CI workflow runs on both `master` and `jwasm-migration` and
includes the two focused regressions. The XCOPY host tests enable kvikdos's
case-insensitive host-filesystem mode, and COMMAND-sensitive QEMU checks run
before the known pipe-handle corruption case.

The last master-reference differences were DISKCOMP and DISPLAY.SYS. MASM
retains the DWORD type when `VOL_SERIAL EQU EXT_BOOT_SERIAL`; JWasm previously
reduced the alias to an untyped number, making `TYPE VOL_SERIAL` zero. The
custom fork now preserves structure-member types through constant aliases and
has a binary regression test; DISKCOPY/DISKCOMP passes 17/17. DISPLAY's local
`JUMP` macro used a mutable relocatable variable as a cached trampoline. JWasm
legally revisited that variable during backpatching, turning six jumps into
`JMP $` self-loops. The MS-DOS macro now emits a direct jump, its Make rule
tracks `MACROS.INC`, and the driver/CHCP suite passes 17/17, including code-page
850 prepare, select, and verification.

Runtime validation exposed two more MASM/JWasm differences in DOSMAC.INC.
The `JUMP` and `CONDRET` macros used mutable equates to chain nearby transfer
sites as a size optimization; JWasm could resolve those equates to the current
site and emit infinite `JMP $` / `JZ $` loops. They now emit direct jumps and a
direct conditional-return sequence. QEMU then boots the complete JWasm-built
IO.SYS, MSDOS.SYS, and COMMAND.COM stack; all five focused boot cases pass.

The broader QEMU EXEPACK/help smoke test originally stopped after FDISK help.
Object-level bisection showed that changing an unrelated JWasm object merely
changed the packed layout; the Microsoft EXEPACK stream became invalid after
`fix-exepack` transplanted a replacement unpacker stub. The raw linked FDISK
and an uncompressed FDISK both returned normally. FDISK is therefore linked
without `/E+`, and its recipe no longer runs `fix-exepack`. This costs about
4 KiB on the floppy but removes the layout-sensitive transformation. The help
test now checks return markers after FIND, EXE2BIN, FDISK, and IFSFUNC, and the
full FDISK QEMU suite validates `/PRI`, `/EXT`, `/LOG`, `/Q`, MBR/EBR contents,
and the primary-only edge case (13 checks).

Final build concurrency gates also pass: clean `make -j1`, `make -j4`, and
`make -j8` all exit zero with no assembler errors, linker errors, unresolved
symbols, or duplicate entry points. JWasm is now the sole production assembler
selected by the Makefile; the old `ASM=wasm` comparison switch is retired.

The final August 26 merge gate rebuilt from clean state both serially and with
`make -j8`, passed the 290-test host suite after each build, deployed the
parallel-built tree, and ran every QEMU Make target with four-way concurrency.
All targets passed, including the five isolated parallel FORMAT groups; no
shared-image, log, DOS-emulator, or compiler-temporary collision occurred.

`make -j4 deploy` also uncovered a second build-graph race: `deploy` started
`all` beside the floppy target even though both paths produced the same files.
Deployment now enters one jobserver-aware sub-make after kvikdos is ready, and
the floppy prerequisites explicitly include generated KEYBOARD.SYS. A clean
parallel build and populated FAT12 deployment complete successfully.

**Assembler migration end state:** All assembly uses the pinned custom JWasm;
clean serial/parallel builds, floppy deployment, and the full boot stack are
validated. The remaining native-toolchain migration uses Open Watcom (`wcc`,
`wlink`, and `wlib`) and is tracked separately. kvikdos remains for the
pre-built DOS build utilities; eliminating those is another future effort.

**Branch policy:** Active work lands directly on `master`. The deleted
`watcom-migration` and `jwasm-migration` branches are preserved by matching
`archive/*` tags.

**Historical WASM status (May 13 2026):** Upgraded to upstream WASM Current-build, which now also includes upstream PRs **#1621** (don't join trailing-comma lines outside WATCOM mode) and **#1622** (macro substitution drops quote delimiters from TC_STRING args), in addition to the previously-vendored PRs #1614, #1615, #1617, #1618. The original Microsoft `chSwitch,BYTE,<'/'>` form in `INC/CONST2.ASM` was restored — the temporary `<"/">` workaround was retired since #1622 fixes the underlying TC_STRING substitution. This section and the log below preserve the superseded WASM migration history.

**May 13 baseline build** (parallel `-j4`, full tree):
- Before preprocessor fix (`/tmp/build-may13.log`): 850 wasm errors across 97 ASM files; 167 make targets failed. Dominant E-codes: **E032 (296)**, E230 (61), E050 (59), E225 (52), E066 (50), E236 (38), E040 (35), E300 (23), E020 (22).
- After preprocessor fix (`/tmp/build-may13-pp.log`): **670 wasm errors (-180, -21%)**, dominant E-codes now **E032 (107)**, E230 (61), E050 (59), E225 (52), E066 (50), E040 (42), E094 (39), E236 (38), E074 (26 - up from 13), E300 (25). File count rose 97 -> 108 because previously-aborting files now get past `$StrucError` and surface the next layer (mostly E074: STRUC.INC `&` concatenation in macro bodies). INC subsystem still clean serially. No regressions.
- Subsystems by failure count: SELECT 31, MEMM/MEMM 20, CMD/FDISK 18, CMD/MODE 13, CMD/RESTORE 12, DEV/XMAEM 8, CMD/GRAPHICS 7, MEMM/EMM 5, CMD/KEYB 5, CMD/FC 5, INC 4, DEV/ANSI 4, CMD/IFSFUNC 4, ... (rest single-digit).
- INC failures are kvikdos CL.EXE temp-file clashes under parallelism, not wasm regressions.

**Preprocessor `< AL eq 1 >` -> `<AL,eq,1>` fix:** `_comma_sep_struc_args.fix_angles` was emitting leading/trailing commas when the angle-bracketed text had whitespace adjacent to `<` / `>` (`< AL eq 1 >` -> `<,AL,eq,1,>`). The resulting blank macro args propagated through `.if -> $TopTest -> $Test` and hit `ifb <a1> = TRUE` -> `$StrucError` at STRUC.INC line 33. Patched to trim leading whitespace inside angle brackets and to drop a trailing-space-induced comma before `>`. Underlying wasm bug (whitespace-doesn't-split-substituted-macro-args in MASM mode) **still needs filing** -- that fix would let the preprocessor pass retire entirely. Tracked in [[project_no_preprocessor_endstate]].

**kvikdos fix (this session):** DOS INT 21h/AH=4Ah `inplace_realloc` corrupted the arena when growing into the trailing Z-type free block — wrote a fake M-type next-MCB and a `psize` past end-of-arena, fatal-tripping later validation as "adjacent free MCBs". Hit by Microsoft C 5.10 (CL.EXE) compiling INC/*.C files. Fixed in submodule and rebuilt `kvikdos-soft`.

**Parallel build race fixed (Aug 26):** `make -j` now completes the shared
`kvikdos-soft` prerequisite before entering the parallel build. All calls through
`bin/dos-run` share a portable atomic lock, preventing concurrent CL/BUILDMSG/etc.
processes from colliding on fixed-name DOS scratch files (`C1001`/`C1042`). Native
JWasm and wlink jobs still run in parallel. Verified with a clean `make -j4`: both
race classes are gone; the run reaches the separately tracked JWasm-version BIOS
link issue.

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

### Jun 4 2026 session: STRUC.INC blocker re-diagnosed; CMD/MODE cleared; remaining work is upstream

This session overturned the central assumption that ~296 E032 errors were all "STRUC.INC `&` substitution" (a single unfixable upstream bug). Systematic per-file probing (`bin/wasm-masm` directly with each subsystem's `inc`/`hinc` include dirs) showed the real picture is several **distinct** issues, most of them source-fixable.

**Biggest win -- `.FOR` comma cascade (cleared all of CMD/MODE):**
- STRUC.INC's `.FOR idx = start TO stop [STEP n]` uses **space-separated** args. WASM splits macro args on commas only (the filed whitespace-split bug), and the preprocessor's `_comma_sep_struc_args` pass covers `.IF`/`.WHILE`/`.UNTIL`/etc. but **NOT `.FOR`**. So `.for` received one giant arg, mis-expanded, corrupted its macro-stack (`$st`), and **cascaded** E032/E074 into every subsequent `.IF`/`.NEXT` in the file.
- Fix: explicit commas at the call sites -- `.FOR idx,=,start,TO,stop[,STEP,n]` (MASM-compatible, since MASM splits on commas AND whitespace). Sites: `CMD/MODE/{MAIN,INVOKE,MODEPRIN}.ASM`, `SELECT/MACROS3.INC`.
- Result: the **entire CMD/MODE subsystem (16 files) now assembles 0 errors** (was ~13 failing). The E032s there were `.FOR`-comma cascades, NOT `&` substitution; `.IF`/`.WHILE`/`.REPEAT`/`.UNTIL` were never broken.

**Key `&` rule (confirmed by isolation tests):** WASM's `&` macro concatenation **works when it forms a MACRO CALL** (`j&c` -> `jeq`, a `$BuildJump` alias -- assembles fine) but **fails when it forms an INSTRUCTION mnemonic** (`loop&c` -> `loop`/`loope`, `j&c` -> `je`) with E235/E065/internal-error. Consequence: `.IF`/`.WHILE` using STRUC condition *names* (EQ/NEQ/LT/GT/ZERO/NONZERO, which have `jeq`/`jneq`/... aliases) are fine; only instruction-forming concats broke.
- Fixed `STRUC.INC` `$CondLoop` to emit `loop $l&l` directly instead of `loop&c $l&l` (the `$l&l` operand is variable-name concat, which WASM handles). No conditional `.LOOP` exists in the tree. No regression.

**Per-file source fixes landed this session** (all verified to 0 errors via `bin/wasm-masm`):
- `DEV/XMAEM/INDEINS.MAC` -- comment `.XLIST`/`.LIST` (`.MAC` is not a preprocessed extension, so its raw listing directives reached WASM). Cleared the XMAEM subsystem (was 8 failing).
- `CMD/EXE2BIN/LOCMES.ASM` -- `addr` macro renamed to `set_addr` (WASM reserves ADDR; 10x E094).
- `MEMM/MEMM/INITDEB.ASM` -- stale `DEBC/DEBD/DEBW1/DEBW2_GSEL` -> `DEB1..DEB4_GSEL` (VDMSEL.INC renamed them; 4x E040). (Leaves a separate pre-existing `ddata` undefined-segment issue.)
- `MEMM/MEMM/KBD.ASM` -- `(NOT mask) AND 0FFh` on byte ops (E048), and explicit `WORD PTR` on `ds:[67h]` writes (W096).
- `MEMM/MEMM/INIT.ASM` -- added missing `extrn hi_size:word` (E251).
- `MAPPER/OLDGETCN.ASM` -- typeless STRUC fields `ra`/`DResv` given `db` (E032). Cleared the MAPPER subsystem.
- `DEV/PRINTER/PARSE4E.ASM`, `CPSPI.ASM` -- renamed labels colliding with the `DF` directive and with `CPSPEQU.INC` DW vars (note: these two are superseded orphan files, not built).

**Retired 3 preprocessor passes** (source now handles them; `bin/preprocess-wasm` shrinks toward deletion):
- `PCTOUT_PAT` (`%OUT`) -- all uncommented `%OUT` commented in source.
- `LISTING_PAT` (`.XLIST`/`.LIST`/`.CREF`/...) -- all v4.0 preprocessed-extension files cleared.
- `SUBTTL_PAT` -- v4.0/src had 0 uncommented `SUBTTL` already.

**Methodology notes (save future effort):**
- **Orphaned old-version files** inflate an all-`.ASM` probe: `CPSPI.ASM` (live: `CPSPI07.ASM`), `PARSE4E.ASM` (`PARSER.ASM`), `CPSFONT.ASM`, `PTRMSG.ASM`, `DISPMES.ASM`, `INDEMSUS.ASM`, `LOCMES/LOCATE`. Cross-check `MAKEFILE`/`*.LNK` before investing -- only real targets matter.
- **CP437 byte hazard:** these sources are CP437/latin-1 with high-bit box-drawing glyphs in banner comments. The UTF-8 Edit/Write tooling re-encodes every high-bit byte on save (corrupting comments). Edit byte-preserving (Python `encoding='latin-1'`); verify with `git diff --stat`.

**Remaining real-target blockers -- all confirmed UPSTREAM WASM macro-engine bugs (not cleanly source-fixable):** only ~5 files left (DEV/ANSI x2, CMD/GRAPHICS x2, CMD/KEYB x1).
1. **AND/OR conjunctions** (`$GetConj`, the ANSI root): `.IF cond AND` / `.IF cond2` -- `$GetConj` fails to detect the `AND` (its nested `irp` + `ifnb <&parm>` + `exitm` structure breaks WASM's parser at the engine level; isolated repro fails E249/E065), so `$TopTest` takes the wrong branch and `$Test` gets mis-parsed args (`cmp a1,a3` E040). Cascades into later `.IF`s.
2. **`.loop` E206 block-nesting** (GRCOLPRT/GRLOAD2): block-nesting miscount in the `.loop` macro body during nested expansion; persists with `$CondLoop`=nop, and `.until` uses the same `$Pop`/`exitm`/`$Label` patterns yet works -- a subtle engine bug.
3. **E043 jump-out-of-range** (CMD/KEYB/PARSER): STRUC.INC's short/near `$Dist` logic overflows.

A source workaround for #1/#2 would mean **reimplementing STRUC.INC's macro-stack/conjunction machinery** (nested-`irp` + `&`-substitution + `exitm` are fundamental to its design) -- very high effort and regression risk for ~5 files. This **vindicates the original "prefer the upstream WASM fix" guidance** for the STRUC.INC family (same bug class as the already-filed #24). Recommended next step: file the minimal repros (conjunction `$GetConj`, `.loop` E206) against `ddanila/open-watcom-v2`; landing them cascade-clears the remainder. The source-fixable (non-engine) surface is now exhausted.

### JWasm experiment (Jun 5 2026, branch `jwasm-migration`, LOCAL only)

Exploring **JWasm** (Japheth/Baron-von-Riedesel fork) as an alternative to Open
Watcom `wasm` for assembly, keeping Open Watcom for C. Motivation: the WASM path
declared its remaining ~5 blocked files (ANSI/GRAPHICS/KEYB) "upstream macro-
engine bugs" -- JWasm is far more MASM-compatible (`-Zm` = MASM 5.1 mode, multi-
pass, full macro engine) and may clear them without an upstream fix, and could
let us drop `bin/preprocess-wasm` entirely.

Setup (local, not pushed): branches `jwasm-migration` in both repos; MS-DOS
worktree at `../msdos-jwasm` off `dos4-enhancements`; JWasm vendored at
`jwasm/macos-arm64/jwasm` (gitignored, build recipe in `jwasm/README.md`);
`bin/jwasm-masm` wrapper (drop-in for `bin/masm`, **no preprocessor**).

Findings so far:
- JWasm v2.21 builds on macOS arm64 (one-line `malloc.h`->`alloca.h` patch),
  emits 16-bit OMF, multi-pass.
- STRUC.INC's macro engine (the `&` / macro-stack that broke WASM) **works**
  under JWasm with 5 localized STRUC.INC adaptations (see the MS-DOS
  `jwasm-migration` commit): OPTION NOKEYWORD for the dotted names,
  `$LastLabelOrg` init, `$EquateLabel` eq-`$` drop, `$GetConj`/`$GetDist`
  ifidni dispatch.
- **Verified: `.IF/.ELSE/.WHILE/.REPEAT/.UNTIL` assemble 0 errors -> OMF.**
- JWasm also splits macro args on commas only (not whitespace), so the `.FOR`
  and conjunction call-site comma edits are still needed (same as WASM; MASM-
  compatible).
- Still open: two-line AND/OR conjunctions (`.IF NZ,AND`), a double-negation
  jump-alias edge (`jnNEQ`), `ifndef <bracketed>` A4248 warnings, then an
  end-to-end real-file + link test.

**Update (Jun 5, iter 2):**
- AND-conjunction (`.IF NZ,AND` / `.IF <mem,EQ,const>`) **verified working**
  under JWasm with the committed STRUC.INC adaptations -- the `$GetConj`
  ifidni rewrite was the key. This was WASM's "upstream-only" ANSI blocker.
- `NEQ` is **unused** in real conditionals, so the `jnNEQ` edge is moot.
- A4248 warnings **cleared** (`ifndef <$ll&l>` -> `ifndef $ll&l`); core test
  now 0 errors / 0 warnings.
- `.FOR` comma edits applied to the 6 real sites (MODE + SELECT/MACROS3).

**PIVOTAL FINDING (reshapes the approach):** a MODE-subsystem sweep showed
the dominant remaining error (A2209) is the **space-separated bracketed
condition** `.IF <a EQ b>` -- JWasm passes `<a EQ b>` as a single arg (no
whitespace split), so the whole blob lands in the condition slot and
`jn&c` builds garbage (e.g. `jnv`). The comma form `.IF <a,EQ,b>` works.
This affects the COMMON comparison form, **~1811 sites across 65 files** --
far too many for call-site edits. So a **minimal comma-separation
preprocessor pass is required** (the `fix_angles` / `_comma_sep_struc_args`
logic already in `bin/preprocess-wasm`).

Net revised picture: the JWasm path is **adapted STRUC.INC (5 small edits)
+ a MINIMAL comma-sep preprocessor + OpenWatcom for C**. The preprocessor
does NOT fully disappear, but it shrinks from `bin/preprocess-wasm`'s ~789
lines / many passes to essentially ONE pass (comma-separate structured-
directive args) -- and, crucially, there are **no unfixable macro-engine
walls** (the `&` / nested-macro / conjunction engine all work natively
under JWasm, unlike WASM). Next step: extract the comma-sep pass into a
`bin/preprocess-jwasm` (or inline it in `bin/jwasm-masm`), then sweep
subsystems end-to-end and link-test with `wlink`.

#### DOS kernel sweep (Jun 5 2026) -- 63 of 83 `.ASM` assembling

`bin/preprocess-jwasm` + `bin/jwasm-masm` now exist (committed). Sweeping
`v4.0/src/DOS` (`-I. -I..\INC -I..\HINC`) drove the pass count from 0 to
**63 of 83** via these fixes (each clears/corrects many files at once):

1. **`DOSMAC.INC` `invoke` keyword freed** (`OPTION NOKEYWORD:<invoke>`) --
   the DOS `invoke` macro collided with jwasm's reserved INVOKE directive.
2. **`SYSVAR.INC` `Buffinfo` struct renamed `BuffPoolInfo`** -- collided with
   the unrelated `BUFFER.INC BUFFINFO` (single-buffer header vs buffer-pool
   manager); A2139 across every DOS file pulling in both includes. Only the
   BUFFER.INC name is referenced by name (`SIZE BUFFINFO`), so the SYSVAR one
   was the safe rename. (Same shape as the ANSI `INIT_REQ_HDR` collision.)
3. **`DOSMAC.INC` call macros `EXTRN` -> `EXTERNDEF`** (invoke, transfer,
   short_addr, long_addr). These emit `IFNDEF name / EXTRN name:NEAR` on pass
   2 so a proc called before its definition is declared external. MASM 5.10
   makes this benign (pass 1 fills the whole symbol table, so on pass 2 a
   same-module forward proc reads as defined -> no EXTRN). **jwasm `-Zm`
   evaluates `IFNDEF` textually each pass** (verified: a proc/equate defined
   LATER reads as undefined at an earlier site even on pass 2 -- no cross-pass
   symbol memory at earlier positions), so it emits EXTRN for same-module
   forward calls, clashing with the later `PROC` -> A2143. `EXTERNDEF` is the
   MASM/jwasm directive with exactly the needed semantics: PUBLIC if defined
   locally, EXTERN otherwise, idempotent and pass-independent. Confirmed:
   dropping the auto-EXTRN entirely is NOT viable (A2102 storm, 54 files --
   genuine cross-module externs are not all explicitly declared, so the
   auto-EXTRN is load-bearing). No jwasm CLI option restores MASM's two-pass
   table behavior; EXTERNDEF is the fix.
4. **`VERSION.INC` `IBM EQU IBMVER` guarded with `ifndef IBM`** -- per-variant
   switch files (STDSW/MSSW/STDASW/HIGHSW/STDIOCTL/MSIOCTL) each set
   `IBM EQU <value>` at the top; VERSION.INC then redefined it (unguarded)
   when pulled in via SYSVAR.INC -> A2143. `MSVER` directly above it was
   already `ifndef`-guarded; `IBM` was just missing the same guard. Switch
   value now wins; VERSION.INC supplies the default otherwise. (+6 files:
   STDPROC/STDCODE/STDDISP/MSDISP/MSCODE etc.)
5. **`IF NOT <flag>` masked to 16 bits** (`(NOT flag) AND 0FFFFh`) in DOS
   .ASM. jwasm `-Zm` evaluates `NOT` WITHOUT masking to the word size, so
   `IF NOT Installed` with `Installed=TRUE(0FFFFh)` computes `NOT 0FFFFh` as
   a WIDE nonzero value and takes the IF branch -- MASM 5.10 computes 16-bit
   `NOT 0FFFFh = 0` and takes the ELSE branch. This (a) produced A2102 when
   the skipped ELSE branch defined a label the IF branch jumps to (OPEN.ASM
   `update_size`, MACRO.ASM `okdone`), and (b) **silently selected the wrong
   conditional-assembly branch** in files that still "passed" -- a real
   miscompilation, not just a sweep count issue. `(NOT x) AND 0FFFFh` is
   provably identical to MASM 16-bit NOT for any value (0->true, 0FFFFh->
   false, 1->0FFFEh). 49 sites / 23 files. (+2 pass: OPEN, MACRO; corrects
   branch selection in ~21 others.) **7 more sites in shared INC files are
   deferred** to when their other consumer subsystems are swept.
6. **`print.asm` `Out` label renamed `PrintOut`** -- `OUT` is the x86 I/O
   instruction mnemonic, so the console-output label `Out:` (+ 5 `CALL Out`)
   was rejected A2209. Same reserved-word-collision class as ECHO->cmd_echo.
   Cleared DOSPRINT + SHRPRINT (which include print.asm). (+2 files.)
7. **`FINFO.ASM` `I_need EXTERR_ACTION set` -> `,BYTE`** -- a
   whitespace-split macro call (stray `set` token, defaults to BYTE via the
   I_NEED macro) that jwasm comma-split into one bad symbol -> A2084. Matched
   the `,BYTE` neighbors; identical resulting EXTRN. (+1 file.)
8. **`SEGCHECK.ASM` stale `buf_link` -> `buf_next`** -- the buffer-chain
   link migrated from a far DWORD `buf_link` to a near WORD `buf_next`
   (BUF.ASM shows the exact side-by-side change); the debug `BUFCheck`
   routine still used the removed field -> A2102. Applied the same
   `LES ... buf_link` -> `MOV ... buf_next` migration. (+1 file.)
9. **`MSSW.ASM` IBM guard + `MSINIT.ASM` OUT keyword** -- cleared STDDATA +
   STDTABLE. They set IBM=FALSE via stdsw.asm then transitively pull mssw.asm
   (MSSW.ASM:5 forced IBM=ibmver -> A2143 different-value redef); guarded
   with `ifndef IBM` like VERSION.INC. STDDATA then hit `OUT`-as-external-
   proc-call in MSINIT.ASM:534 (`invoke OUT`); OUT is defined in another
   module (link-resolved), so freed it with `OPTION NOKEYWORD:<OUT>` rather
   than renaming. (+2 files.)

Remaining 20 failures -- only **2 are genuinely standalone** (have `END`);
the other 18 are include-fragments (false sweep failures):
- **Include-fragments, not standalone-assemblable** (18): no `END`, pulled
  into a parent. DISP/MS_CODE -> MSDISP/STDDISP, STDCODE/MSCODE; switch
  files STDSW/MSSW/STDASW/HIGHSW/STDIOCTL/MSIOCTL (`IBM EQU` config);
  EXEC/MSINIT/KSTRIN/STRIN/PRINT/MSHALO/MSCONST/DISPATCH/MS_TABLE/STDDOSME
  (start with `I_need`/`Break`/`procedure`). A2099 "END directive required"
  / A2209 on `Break`/`procedure`/`I_Need`/`OUT` at the top are the tell.
  NOT real blockers; the standalone sweep over-counts them.
- **Standalone, config-gated** (`CTRLC.ASM`): A2102 `TOGLPRN`, only defined
  in the per-variant switch files -- needs the build's switch file / `-D`
  config (real make flow), not a source fix.
- **Standalone, build-artifact** (`DOSMES.ASM`): A2106 can't open
  `msdos.cl1` (generated message file) -- needs the make flow.

The 2 remaining standalone failures (CTRLC config flag, DOSMES build
artifact) both need the real make flow, not source fixes. **The DOS
subsystem is effectively source-clean under jwasm** -- the rest of the gap
is include-fragments (assemble only via their parents) + the make-flow
dependency. Next milestone is wiring jwasm into `make` (generate `.CTL` /
message files, link with `wlink`) rather than more standalone source fixes.

FIXED this session that were formerly in this list: OPEN.ASM `update_size`
+ MACRO.ASM `okdone` (IF-NOT-mask), DOSPRINT/SHRPRINT (`Out` rename),
FINFO.ASM (`i_need` comma), SEGCHECK.ASM (`buf_link` -> `buf_next`),
STDDATA/STDTABLE (MSSW IBM guard + MSINIT OUT keyword).

#### BIOS subsystem sweep (Jun 5 2026) -- 10 of 14, SOURCE-CLEAN

Same flags as DOS (`-I. -I..\INC -I..\HINC`). Initial: 6/14. All 14 are
standalone (have `END`). **All source errors now fixed; the remaining 4
failures (MSBIO2, MSLOAD, SYSIMES, SYSINIT1) only fail on generated `.CL`
message-overlay files (MSBIO.CL1/CL2/CL3/CL5) -- a make-flow dependency,
not a source bug.** So BIOS, like DOS, is source-clean under jwasm.

Source fixes applied:
- `SYSINIT2.ASM` -- two trailing-comma EXTRNs (A2209, jwasm line-joins
  them) + `repe movsb` -> `rep movsb` (A2028; REPE/REPZ valid only on
  CMPS/SCAS).
- `MSHARD.ASM` -- `REPZ INSW`/`REPZ INSB` -> `REP` (same A2028 class;
  .286c already present).
- `MSDISK.ASM` -- BIOS `PUSHPOP.INC` never initialized `?stackdepth`
  (DOSMAC.INC inits it for DOS; MASM treated the undefined symbol as 0).
  Added `?stackdepth = 0` outside the IF1.
- `MSINIT.ASM` -- `MOV DS:WORD PTR CHROUT*4,OFFSET WORD PTR OUTCHR`
  (A2065) rewritten to the bracketed form the file already uses elsewhere:
  `MOV WORD PTR DS:[CHROUT*4],OFFSET OUTCHR`.
- `MSLOAD.ASM` -- `not END_OF_FILE` into a byte var (A2048, NOT-width)
  masked to `(not END_OF_FILE) AND 0FFh`. (MSLOAD still needs MSbio.cl1.)

#### CMD/CHKDSK sweep (Jun 5 2026) -- 8 of 9

Flags `-I. -I..\..\INC -I..\..\H` (per its MAKEFILE: inc=..\..\inc,
hinc=..\..\h). Initial 1/9; all standalone (END).
- **FIXED**: `CHKEQU.INC` `TRUE EQU NOT FALSE` -> `(NOT FALSE) AND 0FFFFh`
  (A2143: jwasm leaves NOT wide so it != DOSSYM `TRUE EQU 0FFFFh`; the
  16-bit mask makes it 0FFFFh, a benign redef). **This `TRUE EQU NOT FALSE`
  idiom is likely systemic across subsystem EQU files -- watch for it.**
- **FIXED**: CHKEQU.INC local struct `A_DeviceParameters` (BPB template)
  collided with shared IOCTL.INC `A_DEVICEPARAMETERS` -> A2139. Renamed the
  local one to `Chk_DeviceParameters` (Buffinfo-style; members stay global
  for `[bx].SectorsPerFAT`, and the one by-name use BPB_Buffer:96 resolves
  to IOCTL's -- which MASM also used there). + CHKINIT:605 `repnz movsb` ->
  `rep movsb` (A2028). (-> 5/9.)
- **FIXED**: CHKFAT:56 `public ...,` + CHKPROC:32 `EXTRN ...,` trailing
  commas (A2209, jwasm line-joins). (-> 6/9.)
- **FIXED**: A2048 byte-flag `<- word TRUE` (CHKPROC fTrunc/IsCross +
  CHKPROC2 SecondPass; `MOV`/`CMP byteflag,TRUE` where flags are `DB` but
  `TRUE`=0FFFFh). Masked each to `(TRUE) AND 0FFh` = 0FFh (flags tested only
  vs False=0). **This is a systemic pattern -- now in the memory catalog.**
  (-> 8/9.)
- Remaining 1: **CHKDISP** -- needs the generated `CHKDSK.CTL` (build
  artifact, make flow) + the shared `SYSMSG.INC:53 TRUE = NOT FALSE`
  EQU-vs-= conflict. So CMD/CHKDSK is **source-clean** apart from CHKDISP's
  message-file dependency.

#### CMD/FORMAT sweep (Jun 5 2026) -- 5 of 7, SOURCE-CLEAN

Flags `-I. -I..\..\INC -I..\..\H`. Initial 4/7. Fixes (both cataloged
patterns): byte-flag vs word `TRUE` (A2048) masked to `(TRUE) AND 0FFh`
-- fBigFat/fLastChance/Old_Dir/Format_End/Cluster_Boundary_Flag, 12 sites
in FORMAT.ASM + 4 in MSFOR.ASM; `repnz movsb` -> `rep movsb` (A2028), 3
sites in MSFOR.ASM. FORMAT.ASM clean; the 2 remaining (DISPLAY, MSFOR)
fail only on generated `FORMAT.CTL` / `BOOT.CL1`. So source-clean.

#### Message-file generation: a SOLVED make-flow step (Jun 5 2026)

The `.CTL` / `.CL*` "Cannot open file" failures seen across EVERY swept
subsystem (DOS DOSMES, BIOS MSBIO2/SYSIMES/SYSINIT1/MSLOAD, CHKDSK CHKDISP,
FORMAT DISPLAY/MSFOR, ...) are **one and the same make-flow step, already
tooled** -- NOT source bugs and NOT jwasm work. They only appear because a
standalone file sweep doesn't run the message-compiler step.

Mechanism (from `TOOLS/TOOLS.INI` inference rules):
- `.msg.idx`:  `buildidx $*.msg`                        (-> `bin/buildidx`)
- `.skl.ctl`:  `buildmsg $(msg)\$(COUNTRY) $*.skl`      (-> `bin/buildmsg`)
- `.skl.cl1`:  `nosrvbld $*.skl $(msg)\$(COUNTRY).msg`  (-> `bin/nosrvbld`)

Tools are the DOS exes `TOOLS/BUILDIDX.EXE`/`BUILDMSG.EXE`/`NOSRVBLD.EXE`,
run via `bin/dos-run` -> `kvikdos` (or `kvikdos-soft` when /dev/kvm is
absent, e.g. **macOS** -- so this works on the dev host). Inputs are the
checked-in per-utility `*.skl` + `MESSAGES/USA-MS.MSG` (+ `USA-MS.IDX`).

**Verified Jun 5**: ran `bin/buildidx`/`bin/buildmsg` on FORMAT (kvikdos-soft,
macOS) -> produced FORMAT.CTL + FORMAT.CL1/CL2/CLA/CLB/CLC. With those
present, DISPLAY.ASM no longer fails on the missing `.CTL`. (Generated
`.ctl`/`.cl*` are gitignored build artifacts -- never commit them.)

**KEY follow-on**: generating the `.CTL` UNMASKS the next real source
blocker -- DISPLAY.ASM then hits `FORMSG.INC(859): A2164 No segment
information to create fixup: Sublist`.

##### Sublist A2164 -- root-caused (Jun 5 2026), a deep SHARED blocker

FORMSG.INC builds message-description tables: `Sublist = No_Replace` (=0,
absolute) or `Sublist = Sublist_msgXxx` (a relocatable sublist-table label),
then `Define_Msg`/`Create_Msg` emits `dw Sublist` into the `data` segment.

Minimal reproducer (fails A2164 at `data ends`; verified):
```
data segment public 'DATA'
ST1 label dword
	dw 5
Create_Msg macro p1,p4
p1 label word
	dw p4
	endm
Sublist = 0          ;; absolute
	Create_Msg M1,Sublist
Sublist = ST1        ;; relocatable
	Create_Msg M2,Sublist
data ends
end
```
Root cause: **jwasm locks a redefinable `=` symbol's type on first use; a
symbol assigned BOTH an absolute (0) and a relocatable (label) value across
reassignments cannot be turned into a fixup** -> A2164 flushed at segment
end. Order-independent; `offset` doesn't help; all-absolute or all-relocatable
both work, only the MIX fails. MASM 5.10 allowed the mix.

This is **NOT a small fix**: No_Replace must stay 0 (runtime "no replaceable
params" check), so we can't just make it relocatable; and the
`Sublist`/`Create_Msg` message pattern is **shared across many utilities**
(FORMAT, CHKDSK, ... every program with replaceable-parameter messages).
Options: (a) a jwasm-engine fix (allow `=` to switch absolute<->relocatable,
matching MASM) -- likely the cleanest; (b) restructure Create_Msg to branch
absolute-vs-relocatable (emit literal `dw 0` for the no-replace case via a
separate macro path). Deferred -- needs a design decision, not a quick edit.

#### CMD/FC sweep + CMACROS.INC (Jun 5 2026) -- 2 of 7 (started)

Flags `-I. -I..\..\INC -I..\..\H`. FC's .ASM files are C-interfacing
(include `INC/CMACROS.INC`, Microsoft's C-callable-assembly package).
- **FIXED (shared)**: CMACROS.INC defined macros-from-macros via MASM
  `&macro`/`&endm` escaping (addSeg builds `add_IGROUP` etc.) -> A2209.
  jwasm counts nested `macro`/`endm` without the `&`, so dropped the 9+9
  escapes (kept `&`-symbol concatenations). Unblocks the nested-macro wall
  for ALL C-interfacing assembly. FC 1 -> 2; the other 5 advance past it.
- **FIXED (shared)**: CMACROS.INC IRP-nested double-amp `&&` concat
  (`?T&&x`, `_&&x`, ...) -> single `&` (30 sites). jwasm wants one `&` where
  MASM needed `&&`. Cleared GETL/MAXMIN/MOVE/STRING.
- **FIXED**: ITOUPPER.ASM `parmW c` -- `c`/`C` is jwasm's reserved C
  calling-convention keyword; added `OPTION NOKEYWORD:<C>`.
- **CMD/FC now 7 of 7, source-clean.** The CMACROS.INC C-interface package
  (Microsoft C-callable assembly) assembles under jwasm after the
  `&macro`/`&endm` + `&&` fixes -- this unblocks C-interfacing assembly
  across all utilities that include cmacros.

#### CMD/FDISK sweep (Jun 5 2026) -- source-clean

Flags `-I. -I..\..\INC -I..\..\H`. Only source fix: FDBOOT.ASM:30
`repnz movsw` -> `rep movsw` (A2028, cataloged conditional-rep). The 3
remaining sweep failures are all make-flow/build-order deps: _MSGRET needs
FDISK.CTL, FDBOOT needs fdisk5.cl1, and BOOTREC includes the GENERATED
`fdboot.inc` (FDBOOT.obj -> link -> exe2bin -> dbof fdboot.bin fdboot.inc),
a build-order dependency. So source-clean.

#### DEV/PRINTER sweep (Jun 5 2026) -- 7 of 9, source-clean

Flags `-I. -I..\..\INC -I..\..\H`. Fixes (cataloged patterns):
- CPSPM10/PRTINT2F use INVOKE as a cross-module proc name (PUBLIC/EXTRN
  INVOKE) -> A2209; freed via OPTION NOKEYWORD:<invoke> in shared
  CPSPEQU.INC. PARSE4E uses DF as a code label (vs the DF data directive)
  -> renamed to DF_LBL. (3 -> 6.)
- CPSPI: DF label -> DF_LBL + HWCP_1/HWCP_2 used as code labels while
  CPSPEQU.INC defines them as data words (`DW`) -> A2143 + A2249; renamed
  the local labels -> HWCP_LP1/HWCP_LP2. (6 -> 7.)
- **source-clean**: remaining 2 (CPSPI07, PTRMSG) need the generated
  PRINTER.CTL / PTRMSG.INC message files (make flow).

#### CMD/DEBUG sweep (Jun 5 2026) -- 10 of 12, source-clean

Flags `-I. -I..\..\INC -I..\..\H`. One source fix: DEBUG.ASM skeleton
CONST (143) and DATA (149) segments used default align while their content
reopens (154/184) and every other DEBUG file use `SEGMENT PUBLIC BYTE` ->
A2078 "Segment definition changed: alignment" (jwasm requires consistent
attrs on reopen; MASM took the first). Added BYTE to the 2 skeleton defs.
Remaining: DEBEQU (equ-fragment needing IBMVER from its includer) + DEBMES
(generated DEBUG.CTL). So source-clean.

#### SELECT (source-clean) + DEV/SMARTDRV local cmacros (Jun 5 2026)

- **SELECT** (38 files, flags `-I. -I..\INC -I..\HINC`): 33/38 assemble;
  the 5 failures (PANELS/SCROLL need PANEL.INF; SELECT0/SSTUB/VAR need
  SELECT.CTL) are all generated-file deps -> **source-clean**. (The earlier
  MACROS5 `OPTION NOKEYWORD:<GOTO>` fix cleared the bulk.)
- **DEV/SMARTDRV** has a LOCAL copy of CMACROS.INC (not the INC/ one);
  FL13.ASM includes it via -I. and hit the same `&macro`/`&endm` + `&&`
  jwasm issues. Applied the same fixes (9+9 + 30). FL13 clean. NB: watch for
  other subsystems carrying local CMACROS.INC copies. Remaining SMARTDRV:
  mostly include-fragments (no END, start with BREAK). SMARTDRV.ASM: pass-2
  (IF2) alignment-assertion guards used `OFFSET <forward-label>`
  (ABOVE_BLKMOV/ABOVE_END/ABOVE_RESET_END defined later) -> A2102 (jwasm
  cant evaluate forward OFFSET in IF); commented out the no-code %out guards.
  SMARTDRV.ASM clean.

#### MEMM (memory manager) sweep (Jun 5 2026) -- 20 of 42 (started)

Flags `-I. -I..\..\INC -I..\..\H` (NB: also needs `-I..\EMM` -- several
files `include emmdef.inc` which lives in the sibling MEMM/EMM dir; without
it they hit A2106, NOT a source bug).
- **FIXED (shared)**: vm386.inc DwordS struct fields LowWord/HighWord clash
  with jwasms reserved LOWWORD/HIGHWORD operators -> A2209. Freed via
  OPTION NOKEYWORD:<LowWord HighWord> (jwasm approach; the WASM catalog
  renamed them to LoWord/HiWord instead). Cleared 5 files (15 -> 20).
- **FIXED (+5)**: length EQUs `X equ (this byte - label)` -> `($ - label)`
  (A2188; jwasm wont reduce THIS BYTE - label to absolute; cataloged THIS-BYTE
  pattern). 12 sites in TABDEF/INIT/MEMM386/PPAGE/MEMMCOM/MEMMONF. (26 -> 31.)
- Note: emmdef.inc "not found" needs `-I..\EMM` (sibling MEMM/EMM dir), not a
  source bug -- with it, the count is out of 42 properly.
- **FIXED**: ERRHNDLR `C = 46` / `ENTER = 28` scan-code constants clash with
  reserved C (conv) / ENTER (instr) -> OPTION NOKEYWORD:<C ENTER>. (31 -> 32.)
- **FIXED**: OEMDEP.INC bare `_TEXT`/`LAST` reopens -> explicit attrs
  (match VDMSEG.INC); cleared MEMMINC. (32 -> 33.)
- **FIXED**: A2078 bare-segment-before-VDMSEG -- made the pre-vdmseg bare
  opens explicit in VMINST (R_CODE:83, _TEXT:88), VMTRAP (_TEXT:104), ROM_SRCH
  (LAST:72). (33 -> 36.) The whole A2078 VDMSEG cluster is now cleared.
- **FIXED**: LIDT/LGDT `qword ptr` -> `fword ptr` (A2049; 6-byte FWORD
  descriptor in 16-bit mode) in RETREAL/UTIL/INITDEB (4 sites). RETREAL+UTIL
  clean. (36 -> 38.)
- **FIXED**: EKBD `wait` code-label -> `wait_loop` (vs WAIT instr); KBD DCODE
  bare `segment` -> `USE16` (under .386p jwasm defaults bare segs to USE32, so
  `offset AltChrs` was 32-bit -> A2048). (38 -> 40.)
- Remaining 2: INIT (A2188/other), INITDEB (known stale symbols: `ddata` has no
  segment declared, `DEBC_GSEL`->`DEB1_GSEL`-style -- needs external-lib segment
  layout, surface not guess; see WASM-patterns memory). MEMM essentially
  source-clean modulo these two.

#### More subsystems (Jun 5 2026)

- **CMD/MODE** 13/16: source-clean modulo MAIN (MODE.CTL artifact), MODEMES
  (deferred Sublist A2164), INVOKE (`max_pknum = $ - OFFSET <EXTRN
  des_start_packet>` -- uncomputable cross-module EQU, deep).
- **CMD/GRAPHICS** 12/14: source-clean (GRCOMMON is an include-fragment of
  GRCOLPRT; GRINST needs GRAPHICS.CTL).
- **DEV/KEYBOARD** 25/25 SOURCE-CLEAN: KEYBMAC.INC defined macros named
  OPTION + GOTO (reserved) -> freed via OPTION NOKEYWORD:<OPTION GOTO>
  (cleared 21 country-layout files at once); KDFSU.ASM `_KB` -> `AT_KB`
  (undefined truncation typo).

#### DEV/DISPLAY/EGA (source-clean) + CMD/COMMAND start (Jun 5 2026)

- **DEV/DISPLAY/EGA** 7/22: source-clean. The 15 `<cp>-<size>.ASM` font-data
  files are include-fragments (no END, A2082) pulled into the `*-CPI.ASM`
  parents (which pass).
- **CMD/COMMAND** 2 -> 20 of 39 (flags `-I. -I..\..\INC -I..\..\H`):
  shared COMEQU.ASM + FORDATA.ASM + TSPC.ASM used bare `(?)` initializers
  (`DW (?)`/`DB (?)`) -> A2209; replaced the direct forms with `?` (kept
  `N DUP (?)`). 2 -> 22 of 39. Remaining 17:
  - **A2143 TRUE cluster FIXED**: guarded `SYSMSG.INC` TRUE/FALSE with
    `ifndef` (+16-bit mask) -- defers to DOSSYM `TRUE EQU 0FFFFh`. Advanced
    INIT/RDATA/RUCODE/TPRINTF + CHKDISP past the TRUE A2143 to their
    generated .CTL (now source-clean). Tree-wide message-include fix, no
    regression. PARSE2 has a separate `switch_count` A2143 (TBD).
  - **A2209 cluster FIXED**: goto/ECHO (PUBLIC proc names) + addr (macro)
    are reserved (GOTO/.ECHO/ADDR); freed via OPTION NOKEYWORD:<GOTO ECHO
    ADDR> in COMSW.ASM (common first include). Cleared TBATCH2/TUCODE;
    UINIT source-clean (only .CTL left). (22 -> 24 of 39.)
  - **PATH2 FIXED**: WORD PTR on `argv[BX].<word_member>` (argv is a DB array;
    member typed BYTE -> A2048). (24 -> 25 of 39.)
  - Remaining real: PARSE2 `switch_count EQU $-switch_list` (switch_list EXTRN
    -- uncomputable cross-module $-OFFSET, deep, like MODE max_pknum; deferred).
    Rest are data/equ/segment fragments (no END) + .CTL-blocked source-clean
    files. **CMD/COMMAND is effectively source-clean** modulo fragments, the
    generated COMMAND.CTL, and the PARSE2 cross-module EQU.

#### CMD/EDLIN (Jun 5 2026) -- 4 of 6, source-clean

Byte flags (EA_Flag/lc_flag/continue/parse_switch_b, all db) set/compared vs
word `True` -> A2048; masked to `(True) AND 0FFh` (8 sites, incl. an explicit
`byte ptr cs:[parse_switch_b],true`). 1 -> 4. Remaining: EDLEQU (fragment),
EDLMES (EDLIN.CTL artifact). Source-clean.

#### DEV/XMAEM (Jun 5 2026) -- 10 of 12

INDEINS.MAC LJCOND macro `DW (OFFSET &DISPL)-(&TEMP)`: dropped `&` on TEMP
(a local `=` symbol, not a macro param) -> A2209 cleared. Remaining 2 are
deep/artifact:
- INDEDMA: A2193 -- LJ* macros hand-code 386 long jumps as `DW (OFFSET
  target)-(here)`; when `target` is EXTRN (DISPLAY in INDEEXC), jwasm rejects
  an external symbol in DW arithmetic (can't form the external-relative
  fixup MASM emitted). **Deep** -- joins the cross-module $-OFFSET class
  (MODE max_pknum, COMMAND switch_count, Sublist A2164).
- INDEMSG: needs generated xmaem.cl1.

#### CMD/KEYB (Jun 5 2026) -- 9 of 10, source-clean

CMD/KEYB has its OWN copy of KEYBMAC.INC (separate from DEV/KEYBOARDs) with
the same OPTION + GOTO reserved-macro-name issue -> freed via
OPTION NOKEYWORD:<OPTION GOTO>. Cleared KEYBI2F/KEYBI48. 6 -> 9. Only KEYBCMD
remains (generated .CTL). (Reinforces: watch for LOCAL copies of shared
includes -- CMACROS.INC and KEYBMAC.INC both have per-subsystem copies.)

#### More CMD utilities (Jun 5 2026)

- **CMD/IFSFUNC** 8/10: source-clean (IFSERROR/IFSINIT need IFSFUNC.CTL).
- **CMD/GRAFTABL** 6 -> 9 of 10: GRTAB/GRTABHAN/GRTABP call the cosmetic
  HEADER listing macro before it is defined (it announces the section that
  defines it) -> A2209 (jwasm needs macros defined before use). Commented the
  single premature call per file. GRTABSM needs a generated .CTL. Source-clean.
- **CMD/FASTOPEN** 3 -> 4 of 5: same premature-HEADER pattern in FASTP.ASM
  (call 90, def 93); commented. FASTSM needs fastopen.CTL. Source-clean.
- **CMD/LABEL** + **CMD/NLSFUNC**: premature HEADER (LABEL:127, NLSPARM:96)
  commented. NLSFUNC/DOESMAC.INC was CORRUPTED -- the BREAK listing macro was
  defined inside the CallInstall macro body (single ENDM closed CallInstall),
  so BREAK only existed at CallInstall expansion -> A2209 at `BREAK <...>`
  calls. Moved BREAK out after CallInstalls ENDM (canonical DOSMAC layout).
  LABEL/NLSPARM clean; NLSFUNC.ASM source-clean (NLSFUNC.CTL + message-system
  $M_NUM_CLS remain).

#### CMD/PRINT + VERSION.INC MSVER (Jun 5 2026)

CMD/PRINT pridefs.inc: `TRUE EQU NOT FALSE` -> 16-bit mask (A2143 vs DOSSYM).
Then HARDINT A2143 -- root cause: `MSVER EQU NOT IBMVER` (VERSION.INC) is wide
under jwasm, so the mutually-exclusive `IF MSVER` / `IF IBM` blocks BOTH ran
-> HARDINT redefined. Masked `MSVER EQU (NOT IBMVER) AND 0FFFFh` in VERSION.INC
(**tree-wide IF MSVER fix**, provably 16-bit-MASM-equiv, no regression --
CHKDSK unchanged). The 4 PRINT_* files now source-clean (only PRINT.CTL left).

#### CMD/SHARE (Jun 5 2026) -- 1/4

GSHARE.ASM `DOSAssume SS <DS>,"..."` -> added comma (`SS,<DS>`; macro-args-
without-commas, A2209). GSHARE then hits DEEP A2080: a build-variant
`IF / SHARE ENDS / END / ELSE / CODE ENDS / ENDIF` closes a different segment
per branch -> jwasm block-nesting tracker rejects it (block-nesting-in-skipped-
IF class). Deferred. GSHARE2/SHARESR need SHARE.CTL; SHARELNK passes.

#### More CMD utilities, batch 2 (Jun 5 2026)

Premature-HEADER (cataloged, commented): TREE.ASM:185, DCOPYP.ASM:93,
DCOMPSM.ASM:101 -> TREE/DCOPYP clean, DCOMPSM source-clean (.CTL).
ASSIGN/ASSGMAIN.ASM: included CURDIR.INC (calls BREAK) + a premature
`BREAK <...>` before defining BREAK -> moved the BREAK macro def above the
includes. Source-clean. **CMD/SYS**: SYS never defines BREAK at all (no DOSMAC
include; the WASM build relied on the preprocessor stripping BREAK) -> added
the standard BREAK macro at the top of the shared SYSHDR.INC. SYS2 clean,
SYS1/SYSSR source-clean (SYS.CTL). Most other utilities (SORT/JOIN/APPEND/SUBST/ATTRIB/FIND/
MORE/REPLACE/XCOPY/COMP/EXE2BIN) fail only on generated .CTL -- source-clean.

#### DEV driver re-sweep with CORRECT include depth (Jun 11 2026)

**Include-depth gotcha:** DEV drivers live at `src/DEV/<drv>` (depth 2), so the
right MASM include flags are `-I. -I..\..\INC -I..\..\HINC` -- NOT the depth-3
`..\..\..\INC` (that level is only for `DEV/DISPLAY/EGA`, `DEV/DISPLAY/LCD`,
`DEV/PRINTER/<model>`). RAMDRIVE/XMAEM happened to pass with the wrong depth-3
flags only because they include LOCAL copies via `-I.`. Sweeping a depth-2
driver with depth-3 flags makes STRUC.INC unfindable, so the custom `.IF`/
`.WHILE` macros never load and jwasm falls back to its BUILT-IN HLL parser ->
a flood of bogus **A2199 "Syntax error in control-flow directive"**. Those
A2199s are NOT a real structured-directive incompatibility -- they vanish with
the correct depth.

Re-swept all DEV main targets with correct flags (message-file `.CTL`/`.CL*`
A2106 + `$M_NUM_CLS` A2102 cascade filtered out, as that's the separate
build-tool step):
- **Source-clean:** ANSI (ANSI/IOCTL/ANSIINIT/PARSER), DISPLAY (DISPLAY/INIT/
  PARSER), PRINTER (PRTINT2F/CPSPI07/PARSER/CPSPM10/CPSFONT3), DRIVER, SMARTDRV,
  RAMDRIVE, XMAEM (all 12), DISPLAY/LCD.
- **DRIVER fixed this pass:** `repe movsb` -> `rep movsb` (A2028), DRIVER.ASM:1055.
- **VDISK fixed (Jun 11):** VDISKSYS.ASM `CMP/MOV CS:PC_386,TRUE` (1056/1103/
  1595) -> `(TRUE) AND 0FFh` (PC_386 is DB, TRUE EQU 0FFFFh; A2048). VDISK now
  source-clean.
- **XMA2EMS fixed (Jun 12):** EMSINIT.INC:9 `DB (?)` -> `DB ?` (A2209,
  cataloged bare-(?) pattern) + XMA1DIAG.INC 4x `LOCK MOV` -> dropped LOCK
  (A2028 -- NOT the repe/movs catalog class; LOCK is invalid on MOV, #UD on
  386+, MASM 5.10 emitted it blindly). XMA2EMS.ASM assembles 0 errors ->
  real OMF OBJ. That was the LAST DEV driver with genuine source errors --
  all DEV drivers now source-clean. (DIAGS.ASM's 51x A2082 is a standalone
  diagnostic, not in XMA2EMS.LNK.)
- **jwasm-masm wrapper bug found+fixed (Jun 12):** jwasm SILENTLY IGNORES any
  option placed after the source filename, and the wrapper passed
  `-Fo=<output>` last -- so NO sweep to date ever wrote an OBJ (error counts
  were still valid; jwasm fully assembles regardless). Moved `-Fo<output>`
  (attached form) before the filename; verified XMA2EMS.OBJ is real 8086 OMF.

CMD/EXE2BIN: DISPLAY clean, E2BINIT needs EXE2BIN.CTL; LOCMES freed `addr` macro
(reserved ADDR) + TRUE mask -> clean. LOCATE.ASM is an ancient 86-DOS loader
with its `INCLUDE E2BMACRO.INC` commented out (line 35), so MESSAGE/addr are
undefined -> A2209; likely vestigial, uncommenting would also need DOSSYM/
SYSCALL -- left as-is.

#### Stage B pilot: ATTRIB ported MS CL -> Open Watcom wcc (Jun 17 2026)

First C-hybrid utility migrated off proprietary Microsoft C (CL.EXE) onto
Open Watcom `wcc` + `wlink` + OW C runtime. ATTRIB is the pilot for the
~remaining C-hybrid utilities (the toolchain's last proprietary dependency
alongside MS LIB/EXE2BIN). `ATTRIB /?` now prints help and the parser
parses correctly under the all-open-source toolchain. The fixes below keep
the source compiling and running under MS CL too (verified each step), so
this is additive, not a fork.

**1. wcc-strict C source fixes** (`ATTRIB.C`/`ATTRIB.H`): wcc errors
(E1176) on size-incompatible pointer conversions MS C silently allowed.
`(BYTE)" "` -> `(BYTE)' '` (x4); widened generic pointer params to `void*`
(`Display_msg msgsub`, `Get_far_str source`) clearing ~14 call-site
mismatches; explicit near->far / exact-type casts at the rest. Added
`<stdlib.h>` and `exit()` -> `exit(0)` (wcc rejects argless `exit`).

**2. C-runtime init (the key blocker):** the original MS-C `XCMAIN` asm
startup bypasses OW init, leaving stdio/heap uninitialized (printf silent).
Fix (option b): let OW's `cstart` be the entry instead. `pspbyte.c` now
provides a C `main()` that reconstructs the DOS command tail from PSP:0x80
(on the stack, as XCMAIN did) and calls `inmain()` -- the OW-side XCMAIN
replacement. `criterr.asm` extracts the standalone INT 24h crit-err handler
out of `attriba.asm` (wcc small-model segments) so it works without XCMAIN.
The worker `main(line)` was renamed `do_attrib(line)` to free the real C
`main`. Link without `attriba`/`op start`; cstart auto-pulls as entry.

**3. getpspbyte/putpspbyte shim:** OW clib lacks the MS SLIBCE PSP-byte
accessors. Implemented via OW's `_psp` (set by cstart) -- INT 21h/62h
returned a wrong PSP under kvikdos.

**4. Memory-corruption / parse heisenbug, root-caused to THREE distinct
wcc-vs-MS-CL ABI differences** (each recurs across the DOS C utilities --
same fixes apply tree-wide):
- `strcpy(fix_es_reg, NUL)`: `NUL` is `#define`d `0x0`, so this reads from
  a NULL pointer. MS C's DGROUP:0 null-guard is zeroed so it copied nothing
  (and reloaded ES=DS as the intended side effect). wcc's DGROUP:0 isn't
  guaranteed zero -> strcpy overran the 1-byte `fix_es_reg[]` and clobbered
  the command-tail buffer. `strcpy(fix_es_reg, "")` keeps the ES-reload side
  effect, reads a valid empty string, safe under both. 16 sites.
- `_PARSE.ASM`: the asm `_parse()` interface set SI/DI from inregs but never
  ES; `sysparse` reads the parse control block at ES:DI. MS C kept ES=DS
  (via the fix_es_reg hack); wcc doesn't, and Get_DBCS_vector's intdosx
  leaves ES = the DBCS buffer segment -> Parse Error 9. Added `push ds /
  pop es` before the sysparse call.
- `_MSGRET.ASM`: same class -- `sysloadmsg`/`sysgetmsg`/`sysdispmsg` read
  control blocks / substitution pointers at ES:DI but never set ES. Added
  `push ds / pop es` before each SAL call.

**Reusable takeaway for the rest of the C-hybrid migration:** the wcc port
pattern is (a) wcc-strict pointer/`exit` source fixes, (b) swap XCMAIN asm
startup for OW `cstart` + a `main()` that rebuilds the command tail and
calls `inmain`, (c) provide the missing SLIBCE PSP shims via `_psp`, and
(d) force `ES=DGROUP` (`push ds/pop es`) before every asm interface that
reads ES:DI control blocks, since wcc does not maintain ES=DS the way MS C
did with the `fix_es_reg`/`NUL`-strcpy idiom.

#### wlink SIGSEGV on SELECT (reproduced + root-caused Jun 18 2026)

SELECT was one of the 2 remaining build LINK failures (with RESTORE, both
C-hybrid). Reproduced and isolated: **Open Watcom `wlink` SEGFAULTS while
loading certain jwasm-produced OMF object files** -- it is NOT a missing-
symbol / EXEPACK / C-runtime issue.

Reproduce (objects must already be assembled in `v4.0/src/SELECT`):
```
cd MS-DOS/v4.0/src/SELECT
../../../../bin/wlink "/noe @select.lnk"     # exit 245 (= 256-11, SIGSEGV); leaves a 0-byte SELECT.EXE
```
Minimal repro -- a SINGLE object crashes wlink, no libs, no other objects:
```
watcom/bin/macos-arm64/wlink format dos name X.EXE file SELECT1.obj   # exit 139 (= 128+11, SIGSEGV)
```

Findings:
- **Deterministic** (6/6 runs), and independent of `SERVICES.LIB`/
  `CASSFAR.LIB` -- crashes with NO libraries at all.
- The crash is in wlink's OMF reader: stderr stops right after
  `loading object files`, before any fixups/symbol resolution.
- **6 of the 32 objects each crash wlink on their own**: `SELECT1`,
  `ROUTINE2`, `ROUTINES`, `SCN_PARM`, `PRN_DEF`, `S_DISPLY`. The other 26
  (incl. the MS-CL-compiled C objects `GET_STAT`/`GLOBAL`/`INT13`/`BOOTREC`,
  which carry a Watcom/MS default-library COMENT 0x9F -> SLIBCE) link past
  the load phase to a normal undefined-symbol error.
- All 6 crashers are **jwasm-produced `.ASM` objects** (no producer COMENT);
  a naive OMF record walk parses them cleanly to MODEND, so the malformed/
  mishandled record is something wlink's reader chokes on specifically. Both
  crashers and clean asm objects share the same record-type set (THEADR/
  COMENT/EXTDEF/PUBDEF/LNAMES/SEGDEF/GRPDEF/FIXUPP/LEDATA/MODEND) and the
  same DGROUP/SELECT segment layout, so the trigger is finer-grained than
  record type -- not yet byte-pinned.

Status: this is a **wlink robustness bug** (segfault on input it should
reject gracefully), triggered by jwasm OMF output -- file against
ddanila/open-watcom-v2. Next step to pin it: byte-level diff of a crasher
vs a clean asm object's SEGDEF/COMENT/LEDATA records (or `git bisect` the
wlink source around the OMF loader). RESTORE (the other C-hybrid link
failure) still needs the same triage.

**JWlink cross-check (Jun 18 2026): NOT a workaround, but it NAMES the bug.**
Built JWlink (Japheth's fork of OW wlink, the linker side of the JWasm
ecosystem) natively on macOS arm64 -- clone `Baron-von-Riedesel/JWlink`,
`make -f GccUnix.mak CC=clang`, then link manually (drop Linux-only `-s` /
`-Wl,-Map`), same recipe as jwasm. JWlink **crashes identically** (SIGSEGV
on all 6 objects) -- expected, since it shares OW wlink's OMF reader. BUT,
run without `option quiet`, it prints a real diagnostic before dying on
SELECT1.obj:
```
loading object files
Error! E2153: invalid segment/group/external index (6) in relocation
```
So the trigger is a **malformed FIXUPP (relocation) record** -- a fixup
whose segment/group/external index is out of range -- which reframes the
blocker as a likely **jwasm OMF-emission bug** (bad fixup index), not a
pure linker defect. Both linkers trust the index, run off their tables, and
segfault; JWlink at least reports E2153 first. (A quick hand-rolled OMF
FIXUPP parser desynced -- do NOT trust ad-hoc index dumps; pin it with a
real dumper like OW `wdump`, or by diffing jwasm's SELECT1.obj against an
OW-`wasm`-assembled one to confirm which assembler emits the bad fixup.)
Takeaway: the fix likely belongs in jwasm (ddanila/JWasm fork), with a
defensive bounds-check in the OW wlink OMF loader as a secondary filing.

**ROOT-CAUSED + FIXED (Jun 18 2026): jwasm `.ALPHA` emits inconsistent OMF.**
Instrumented JWlink's `FindNode` (objnode.c) printed `FindNode bad SEG
index=6 (num=3)`: a fixup/directive references segment 6 when only 3 SEGDEFs
precede it. The culprit COMENT is the `LDIR_OPT_FAR_CALLS` ('O') linker
directive jwasm writes after each CODE segment's SEGDEF (`omf.c:915`),
emitting `seg_idx`. SELECT1.asm uses **`.ALPHA`**, which makes jwasm SORT the
SEGDEF output alphabetically (`CONST,DATA,SELECT,_BSS,_DATA,_TEXT`) while
`SortSegments` (`segment.c:1513`) DELIBERATELY keeps each segment's
definition-order `seg_idx` ("don't change indices, they're stored in
fixup.frame_datum"). The linker numbers segments by APPEARANCE order, so
after the sort `seg_idx` (and thus the FARCALLS COMENT and every FIXUPP
frame_datum) is out of sync with the linker's index -> forward/out-of-range
reference -> `FindNode` NULL -> NULL deref -> SIGSEGV. (`-zld`, jwasm's
no_opt_farcall, suppresses only the COMENT -> no crash but then E3011 on the
link-pass-separator, because the fixup indices are still inconsistent.)

Fix (chosen: source-side, since `.ALPHA` is used in 25 files, ALL in SELECT,
and nowhere else tree-wide): **`.ALPHA` -> `.SEQ`** in the 25 SELECT files
(MS-DOS commit). `.SEQ` makes jwasm emit definition-order SEGDEFs, so all
indices line up. VERIFIED: `bin/wlink "/noe @select.lnk"` now exits 1
(normal), not 245 (SIGSEGV) -- it loads all 32 objects and proceeds to
normal symbol resolution; the only remaining errors are the pre-existing
`SLIBCE.lib`/`SELECT.lib` C-runtime deps, i.e. SELECT is now the SAME
C-hybrid (Stage B) class as the other C utilities, no longer a crash.
(Layout note: `.SEQ` orders segments sequentially instead of alphabetically;
for SELECT's normally-linked .EXE this is GROUP/class-driven and expected to
be behavior-neutral, but a built SELECT.EXE should be smoke-tested once the
C-runtime side lands.) The deeper jwasm engine fix (renumber seg_idx after
sort + remap fixups, MASM-style, so `.ALPHA` works) remains a candidate to
file against ddanila/JWasm, but is not needed for the migration.

#### RESTORE.COM link failure triaged (Jun 18 2026) -- pure C-hybrid, no crash

The other remaining build LINK failure. Triaged: **NOT a crash and NOT a
jwasm/linker defect** -- RESTORE is a heavily-C utility (restore/restpars/
rtt*/rtdo*/rtold*/rtnew*/rtfile* are C; only `_parse`/`_msgret` are asm),
so it's the same C-hybrid (Stage B) class as ATTRIB and SELECT. Two findings:

1. **`bin/wlink` `/STACK:nnnn` parse gap (fixed):** RESTORE.LNK starts its
   objects field with `/STACK:50000`. The wrapper's option-stripping regex
   (`/\w+`) left the `:50000` remnant, which `names()` turned into a bogus
   object `:50000.obj` -> `E2008 cannot open`. Fixed: strip `/\w+(?::value)?`
   (so `/OPT:value` is removed whole) and translate `/STACK:nnnn` -> wlink
   `option stack=nnnn`. Also affects FDISK.LNK / REPLACE.LNK (the only other
   LNKs using `/STACK`). Verified no regression on the pure-asm DRIVER link
   (still exits 0). 

2. **Real blocker = the MS C 5.10 runtime + DOS family API (Stage B):** past
   the `/STACK` fix, `bin/wlink "@restore.lnk"` exits 1 (normal, no SIGSEGV)
   and reports `cannot open SLIBCE.lib` + undefined `__acrtused`, `_printf`,
   `_strcpy`, `__chkstk`, `_intdos`, ... (MS C runtime) and the DOS family
   API `DOSOPEN`/`DOSFINDFIRST`/`DOSSETSIGHANDLER`/... bindings. `mapper.lib`
   + `comsubs.lib` open fine. So RESTORE links cleanly up to symbol
   resolution; it just needs the C runtime -- i.e. the wcc port (ATTRIB
   recipe) or keep MS CL/LINK for it.

Net: with SELECT's crash fixed and RESTORE triaged, **neither remaining link
failure is a crash or a toolchain bug** -- both are the known C-hybrid
C-runtime dependency (Stage B). RESTORE additionally builds `.COM` via
`convert restore.exe restore.com` (CONVERT, a kvikdos build util).

#### Stage B deep-debug of the ATTRIB pilot (Jun 18 2026; resolved Aug 27)

Took a time-boxed crack at making the ATTRIB pilot actually RUN under
wcc+wlink+OW-cstart (not just link). Result: it **builds and links clean and
`ATTRIB /?` works**, but the **core path still hangs** -- and the trace shows
why it's hard. The path was instrumented end-to-end (printf+fflush, since
stdio is buffered and a hang swallows un-flushed output):

1. **Parser far-pointer capture WORKS.** `Get_far_str` returns the correct
   filename; the stored far pointer's segment == DS. (Earlier ES=DGROUP fixes
   in _PARSE/_MSGRET hold up.)
2. **`Make_fspec` WORKS.** It resolves `C:\CMD\ATTRIB\` and splits the
   filename into the global `file` -- the old note "filename MISSING" was a
   misread; the split is by design.
3. **`Find_first` WORKS.** Matches the file; `Get_reg_attrib` reads the `A`
   attribute (which prints).
4. **HANG is in `Regular_attrib -> Display_msg(9) -> sysdispmsg`, on the 2nd
   substitution (the filename).** It prints sub #1 (the `  A` attr string)
   then spins on sub #2. `Find_next` is never reached (ruled out the carry-
   flag-loop theory). `fspec` itself is valid + NUL-terminated (the DOS
   ASCIIZ call used it fine), so the issue is in the SAL message-substitution
   layer -- how wcc lays out / passes `m_sublist` records. The later resolution
   showed that SYSDispMsg follows the stored 12-byte stride: the records are 11
   bytes under `-Zp`, but MS C word-aligned the independent globals. An explicit
   padded pair now preserves that ABI without relying on global placement.

**Genuine bug found (not the hang cause):** `Regular_attrib` has
`char string[16]` then `string[16] = '\0'` -- a 1-byte stack overflow (valid
indices are 0..15). Real UB; MS C tolerated it via stack padding, wcc may not.
Fix is `char string[17]`; it is now committed alongside the layout fix.

**Historical assessment:** the C-hybrid port is a
deep, multi-layered, per-utility effort -- each fixed layer (pointer ABI ->
ES regs -> off-by-one -> message-substitution layout) uncovers the next, x
~30 utilities. Ruling: **pure-asm (jwasm+wlink) is the shippable open-source
milestone (complete + byte-identical); Stage B (wcc port of the C-hybrids)
was deferred at the time. The August 27 work resumed and completed this pilot;
the reusable groundwork is now a verified production path for the remaining
C hybrids.

#### Full E2E build GREEN (Jun 18 2026) -- complete open-source-built floppy

`make deploy` (default: jwasm+wlink for ALL assembly, MS CL/LINK for the
C-hybrids) now builds the **complete 1.44MB boot floppy end-to-end (exit 0)**
-- kernel (IO.SYS/MSDOS.SYS), COMMAND.COM, all ~36 CMD utilities (incl. the
C-hybrids ATTRIB/RESTORE/BACKUP/FC/REPLACE/JOIN/SUBST/...), all DEV drivers,
SELECT, EGA.CPI. This is the shippable milestone: every `.ASM` in the image is
assembled+linked by the open-source toolchain.

Three build-flow fixes were needed (all committed):
1. `mk/dos.mk` MSDOS.SYS DOSINIT map regex -- was MS-LINK format (uppercase
   hex, leading space); wlink emits column-0 lowercase hex + optional `*`.
   Anchored to line start, case-insensitive, optional `*`.
2. ATTRIB restored to MS-buildable -- the deferred Stage B `main`->`do_attrib`
   rename left crt0 `_main` unresolved under MS LINK (L2029). Reverted the
   Stage B ATTRIB source (history 69602f0..d5e3086).
3. ANSI `Display_Loaded_Before_me`/`...Me` case mismatch -- jwasm `-Mx` +
   wlink `option caseexact` (MS LINK was case-insensitive). Source made
   case-consistent.

Note: RESTORE/ATTRIB build fine in the PRODUCTION flow because it uses MS LINK
+ SLIBCE (the C runtime is present). The earlier "RESTORE link failure" was
only the ALL-open-source (wlink, no SLIBCE) path -- i.e. Stage B, not this
milestone.

**Runtime/boot test is BLOCKED in this sandbox (environment, not the build):**
qemu can't be driven headlessly here -- `-serial stdio` yields empty serial
(documented earlier) AND the QMP monitor socket fails with BrokenPipe (the
screen_expect path). So `make test-*` all fail with no captured output. Boot +
functional test-suite validation needs a working-qemu environment (Linux/CI).
Byte-parity vs `tests/golden.sha256` is currently inconclusive (52/58 differ;
the golden is a stale local snapshot of unclear provenance -- do NOT regenerate
it from an unbooted build). NEXT: run the test suite where qemu works (or fix
the qemu serial/monitor wiring for macOS), then refresh golden from a
boot-validated build.

#### Misc subsystems (Jun 5 2026)

DEV/DISPLAY/LCD 7/7 clean. Most DEV drivers (ANSI/DRIVER/VDISK) + MEMM/EMM +
COMP fail only on generated .CTL (source-clean). DEV/RAMDRIVE: A2082 in
syscall.inc (includes it outside a segment block -- to check). CMD/EXE2BIN:
DISPLAY clean, E2BINIT needs EXE2BIN.CTL; LOCMES freed `addr` macro (reserved
ADDR) + TRUE mask -> clean. LOCATE.ASM is an ancient 86-DOS loader with its
`INCLUDE E2BMACRO.INC` commented out (line 35), so MESSAGE/addr are undefined
-> A2209; likely vestigial, uncommenting would also need DOSSYM/SYSCALL --
left as-is.

#### RECOVER + more (Jun 5 2026)

CMD/RECOVER: RECPARSE.INC/RECdata.INC had trailing-comma `public` lines
(jwasm line-joins -> A2209, e.g. into "parms_input_block LABEL BYTE");
stripped 5 trailing commas. RECINIT/RECPROC clean; RECDISP/RECOVER source-
clean (RECOVER.CTL). CMD/BACKUP, RESTORE, MEM, COMP: source-clean (only
_MSGRET/*SM .CTL). 

#### Tree-wide completeness probe (Jun 6 2026)

Swept EVERY .asm dir (depth-based include paths) filtering for non-A2106
(real source) errors. After fixing the last 3 found -- BOOT/MSBOOT.ASM
(repz movsb -> rep), ASSGPARM.ASM:97 + TREEPAR.ASM:76 (premature HEADER) --
**every remaining non-artifact error is now either a fragment, a deep case,
or a vestigial file**:
- **Fragments** (no END, assemble only via parent): COMSEG/COMSW/ENVDATA/
  IFEQU/TRANMSG/COMEQU/FORDATA/TDATA, DEBEQU, EDLEQU, GRCOMMON, EGA font
  files (437-*/850-*/...), SMARTDRV ABOVE/DEVSYM/DIRENT/AB_MACRO.
- **Deep set** (documented): PARSE2 switch_count + MODE INVOKE max_pknum
  (external `$-OFFSET` EQU); MODEMES Sublist A2164; GSHARE A2080 conditional-
  segment; RAMDRIVE/XMAEM ABOVE_* external long-jumps. EXE2BIN LOCATE
  (vestigial, commented-out include).
- Everything else: source-clean (residual = generated `.CTL`/message files).

**The per-file source-fixing phase is effectively COMPLETE.** Remaining work
is the make-flow (.CTL/.CL/.idx via bin/buildmsg/buildidx/nosrvbld -- already
tooled) to validate the source-clean-but-.CTL-blocked files end-to-end, plus
the small deep set (best addressed by an upstream jwasm capability for
external-symbol expressions, or targeted per-site reworks).

#### Sublist A2164 -- revised diagnosis (Jun 6 2026)

Attempted the Create_Msg restructure (`IFE Parm4 / dw 0 / ELSE / dw Parm4`)
to dodge the suspected `=` type-lock. It fixes the isolated reproducer but
NOT real FORMSG.INC -- the A2164 count is unchanged (still 10x at data ends),
so the failing fixups are NOT Create_Msg's `dw Sublist`. They are in the
**Sublist tables** (`dw offset <EXTRN>` like PercentComplete, and `dw data`
segment). So Sublist A2164 is the **external-symbol-in-expression deep class**
(same as max_pknum / switch_count / XMAEM-RAMDRIVE long-jumps), NOT a macro
type-lock. Reverted the IFE change. Cross-segment `=` ruled out (works).
DEFINITIVE (via -Fl listing): the external-offset revision was ALSO wrong
(plain `dw offset <extern>` works). The listing shows `Sublist` typed Number
(final 0, from the No_Replace=0 assignments) but `dw Sublist` emits data-label
offsets needing a segment-relative fixup the `=` lost via the 0/label mix ->
A2164. IFE and `= OFFSET label` both ruled out (count unchanged). So there are
actually TWO distinct deep roots, not one:
  (1) **RESOLVED** -- Sublist `=` absolute/reloc mix: fixed by converting the
      per-message `Sublist = X` to `Sublist EQU <X>` TEXT equates, so `dw Sublist`
      substitutes to `dw <label>` (direct, proper fixup) or `dw 0`. FORMAT done
      (FORMSG.INC, DISPLAY.ASM fully assembles with FORMAT.CTL). A mechanical
      per-assignment edit; apply the same to other Sublist msg files (MODE/MODEMES).
  (2) external `$-OFFSET` / displacement. **max_pknum (MODE) + switch_count
      (COMMAND) were DEAD broken EQUs -- removed (INVOKE/PARSE2 now clean).**
      **XMAEM LJ*-to-external SOLVED (no .386 needed):** INDEDMA's 2 long
      conditional jumps to extern `DISPLAY` went through LJCOND, which hand-
      encodes a 386 near Jcc as `DW (OFFSET DISPL)-(TEMP)` -- jwasm A2193 on the
      external offset arithmetic (verified: no DW form works; only a real jump
      instruction forms the relocation). Added an `LJX` macro (INDEINS.MAC) that
      emits the equivalent inverse-short-Jcc-over-real-near-`JMP DISPL` idiom
      (.286P-safe, proper extern fixup); used at the 2 sites. LJCOND untouched
      for the many local-target LJ jumps. All 12 XMAEM modules now source-clean
      (INDEMSG/INDEMSUS xmaem.cl1 A2106 = the message-file build step). RAMDRIVE
      already assembles clean (its LJ issue was the Wait-mnemonic/ABOVE_* set,
      both fixed). So the LJ*-external class is closed without a .386 rework.
      RAMDRIVE forward-OFFSET IF2 alignment assertions neutralized (like SMARTDRV,
      6 blocks). **RAMDRIVE A2082 SOLVED: it was `Wait EQU 77` in RAMDRIVE's
      local SYSCALL.INC -- `WAIT` is a reserved x86 (FWAIT) mnemonic in jwasm
      -Zm, so the equate parsed as an instruction emitted outside any segment
      (jwasm mis-blamed syscall.inc:91, the include site, via a stale line
      counter). Fixed with `OPTION NOKEYWORD:<Wait>` before the equate (same
      pattern STRUC.INC uses for the dotted directive names). RAMDRIVE.ASM now
      assembles clean (only A4073 size-assumed + A4184 AT-segment-data
      warnings). Only this local copy had the line; canonical INC/SYSCALL.INC
      never did. Generalizes: any DOS symbol colliding with an x86 mnemonic
      needs OPTION NOKEYWORD or rename.**
Both are jwasm-engine gaps best fixed upstream; per-msg-file restructure is the
source alternative for (1).

#### Make-flow end-to-end validation (Jun 6 2026)

Confirmed: a simple `.CTL`-blocked source-clean utility (CMD/MORE) **fully
assembles** under jwasm once its message files are generated -- ran
`bin/buildmsg ..\..\MESSAGES\usa-ms MORE.SKL` -> MORE.CTL/CL1/CL2, copied in,
and MORE.ASM assembled with ZERO errors. So every `.CTL`-blocked file that is
Sublist-FREE (i.e. uses only No_Replace=0, so `dw Sublist`=`dw 0`, no fixup) is
DONE the moment the make-flow runs -- that is the large majority of utilities.
Only the few with replaceable-parameter messages (Sublist label tables) hit the
A2164 deep case. Net: the migration is effectively complete for source + the
non-Sublist .CTL class; remaining = (a) run/wire the message make-flow,
(b) the 2 jwasm-engine gaps (Sublist `=`-reloc fixup; external `$-OFFSET`).
(Generated .CTL/.CL are gitignored -- not committed.)

#### Sublist RESOLVED tree-wide (Jun 6-11 2026)

Text-equate fix (`Sublist EQU <X>`) applied to all 5 replaceable-param message
files (FORMSG/CHKMSG/MODEDEFS/RECMSG/E2BTABLE). Verified end-to-end on FORMAT +
MODE. Sublist A2164 no longer a deep blocker.

Note: `***** Possible stack size error in X *****` from the `EndProc` macro
is a `%OUT` message, NOT a jwasm error -- filter sweeps on `Error A[0-9]`,
not the bare word "error".

### Source editing policy: direct edits over preprocessor passes

This is a one-way migration to WASM — MASM support is dropped, and the MS-DOS sources already live in a fork (the `MS-DOS` submodule tracks our own branch). New WASM-compat fixes should therefore be **direct edits to the source files**, not new transformations added to `bin/preprocess-wasm`.

Rationale:
- Error line numbers match what's on disk — much easier debugging.
- Changes are visible in the submodule's `git log` / `git blame`.
- No shadow-directory magic to reason about in `bin/wasm-masm`.
- The preprocessor is 789 lines of Python; shrinking it is a goal.

The existing preprocessor passes stay for now and are retired incrementally — each pass is replaced by either a direct source edit (for simple renames/strips) or kept only when the transform is genuinely computed (e.g., `SF_BITS<>` bit packing). End state: `bin/preprocess-wasm` deleted, `bin/wasm-masm` reduced to a thin MASM→WASM flag-translation wrapper.

### Upstream WASM bugs — status

1. **`IFDEF name` + later `name macro` SIGSEGV ✅ FIXED upstream (PR #1617, in May 7 binary).** Previously crashed wasm with exit 139. Verified clean in repro:

   ```asm
   IFDEF foo
   ENDIF
   foo macro
       nop
   endm
   ```

   E236 source-level guards in the 6 INC files (`dosmac.INC`, `JUMPMAC.INC`, `MSMACRO.INC`, `CHKMACRO.INC`, `RECMACRO.INC`, `FORMACRO.INC`) are now unblocked. Not yet attempted on the broader subsystems — `inc` cleanup only required dropping `IF2` wrappers in the EXTRN-emitter macros, which is unrelated to the E236 family.

2. **Preprocessor-stripped BREAK leaves dangling PURGE.** Our `bin/preprocess-wasm` strips `BREAK MACRO … ENDM` blocks (listing directive). Any `PURGE BREAK` we emit as part of an include-guard block therefore references a macro that never exists, producing E251. Fix path: stop stripping `BREAK` in the preprocessor and bake the removal into source directly per the direct-edit policy above. Not yet exercised — only relevant if/when we add PURGE guards.

3. **`IRP itm,<p>` with single-quoted-char forwarded via macro arg → E020 ✅ FIXED upstream (PR #1622, in May 13 binary).** Was filed as fork PR ddanila/open-watcom-v2#21, landed upstream as #1622. `INC/CONST2.ASM` restored to the original Microsoft `<'/'>` form on `watcom-migration` -- assembles clean.

4. **Trailing-comma line joining outside WATCOM mode ✅ FIXED upstream (PR #1621, in May 13 binary).** Was filed as fork PR ddanila/open-watcom-v2#22, landed upstream as #1621. Not currently exercised in the MS-DOS sources, but available now in the vendored binary.

### Phase 0A: wlink proof-of-concept ✅ DONE

Both MS LINK and wlink produce bootable COMMAND.COM from WASM OBJs.

**Remaining wlink tasks:**
- [ ] Write `bin/wlink-mslink` wrapper — translates MS LINK response file format to wlink directives on the fly. All 51 .LNK files work without modification.
- [ ] Handle /EXEPACK gap: 4 targets use it (SELECT, FIND, FDISK, EXE2BIN). wlink has no equivalent.
- [ ] Verify segment ordering for kernel binaries (MSDOS.SYS, IO.SYS) — layout is critical.

### Cleanup: source hygiene ✅ DONE

Stripped ^Z from 332 files, fixed `.gitattributes` for MSG files, removed SUBTTL/TITLE remnants.

### Phase 0B: MSDOS.SYS and IO.SYS runtime debugging ✅ DONE

All kernel boot issues resolved: `IF NOT` audit (60+ instances), MSDOS.SYS (issues #53, #54), IO.SYS (issues #55, #56), boot sector BPB alignment (issue #58), `$M_GET_MSG_ADDRESS` L2029 (issue #52). Full WASM stack boots on clean build.

### Phase 1: Individual binary validation under kvikdos ✅ DONE

**COMMAND.COM:** 46/46 kvikdos built-in tests pass. No crashes.

**CMD utilities:** 18/19 /? smoke tests pass (ATTRIB has kvikdos INT 00 limitation, not a WASM bug). Section 6 functional tests: 49 pass, 65 fail — most failures are kvikdos tty/interactive limitations (DEBUG 13, EDLIN 16), not WASM bugs.

**Known remaining issues:**
- ATTRIB (5 fail): path resolution (Extended Error 2/9)
- MEM (3 fail): kvikdos memory reporting gap
- COMP (1 fail): wildcard FindFirst on absolute paths

### Upstream WASM fixes — RESOLVED

All 4 WASM bugs fixed upstream (Apr 13 2026 Current-build):
- 3 original fork fixes (merged 2026-04-01): EXTRN:ABS byte comparison, $M_ symbol parsing, BYTE PTR forward-ref
- EXTRN:ABS E050 (confirmed fixed; preprocessor workaround kept for safety)
- NameDirective NULL deref crash (ddanila/open-watcom-v2#14): `invoke` macro body `call name` triggers SIGSEGV via T_NAME directive handler. Preprocessor renames `invoke` → `do_invoke`, eliminating 61 of 62 segfaults.

### Remaining WASM compat work — plan

**97 clean, 431 fail, 1 segfault (XMA2EMS).** MASM target dropped — WASM-only going forward.

#### Completed fixes (this session)

Modules fully resolved: GRAFTABL, PRINT, BACKUP, SHARE, RECOVER (+link), FASTOPEN, ASSIGN, XCOPY, DISKCOMP, DISKCOPY, APPEND. Plus 6 of 11 MODE files fixed.

Key preprocessor improvements:
- BREAK/HEADER listing macro stripping (invocations + definitions)
- OPTION → KB_OPTION rename (WASM reserved word)
- invoke → do_invoke rename (WASM reserved word — crashed WASM via NULL deref in NameDirective; 61 segfaults fixed)
- EXTRN:ABS → local EQU resolution (scans source dir for PUBLIC EQU values; kept even after upstream fix)
- $M_NUM_CLS, FALSE/TRUE/IBM, ERR_*, and many more IFNDEF EQU guards
- TYPE→SIZE handles (TYPE x) in DUP; multi-space collapse in angle brackets
- endm_depth tracking in resolve_wasm_conditionals main loop

Key source fix patterns:
- WASM reserved words: DISPLAY→DISP_MSG, ECHO→ECHO_PTS, REPEAT→REPT_LP, FOR→FOR_LP, invoke→do_invoke (preprocessor), addr macro removed
- NOT mask overflow: `(NOT x) AND 0FFh/0FFFFh`
- REP CMPSB → REPE CMPSB; REPE MOVSB → REP MOVSB
- EXTRN:ABS comparisons with BYTE: use register intermediates or literals
- Forward-ref EQUs: reorder before DB/DW, or hardcode with ERRNZ assert
- Procedure/ERRNZ macro redefinitions: remove (use DOSMAC.INC version)
- THIS WORD → LABEL WORD; EQU $ → LABEL BYTE
- push cs:mem → mov ax,cs:mem / mov ds,ax (8086 compat)
- Trailing commas on PUBLIC before ifdef: remove

#### Assembly failures remaining (5 CMD modules, 14 files)

| Module | Files | Primary issues |
|--------|-------|----------------|
| MODE | 5 | STRUC.INC `.IF`/`.WHILE` macro cascade (E032 $StrucError) |
| GRAPHICS | 4 | CMACROS.INC nested `&macro`/`&endm` incompatible with WASM |
| KEYB | 2 | STRUC.INC loop range (E043) + ANSI.INC segment issues |
| IFSFUNC | 2 | DOSMAC.INC `error` macro refs kernel-only symbols; INSTALLED collision |
| EXE2BIN | 1 | DOSMAC.INC Procedure macro confuses WASM proc/endp tracking |

**Root causes (all hard problems):**
- **STRUC.INC E032** (~19 from CMD, ~198 from SELECT/DEV): `$StrucError` fires because WASM macro expansion handles arguments differently from MASM in some `.IF`/`.WHILE` patterns. Simple cases work (tested). Complex cases with segment overrides or BIT keyword fail. May be a WASM macro expansion bug worth reporting upstream.
- **CMACROS.INC**: Uses `&macro`/`&endm` nested macro definition syntax that WASM fundamentally doesn't support. Already has partial `IFNDEF __WASM__` guards but they're incomplete.
- **DOSMAC.INC Procedure/EndProc**: WASM tracks proc/endp differently when opened via macro expansion. PURGE not supported.
- **EXTRN:ABS E050**: ~~WASM treats all ABS externs as WORD-sized~~ — **fixed upstream** (Apr 13 2026 build, confirmed). Preprocessor workaround (resolve to local EQU) kept for safety.

#### Link-only failures (4 modules, assemblies OK)

| Module | Error | Cause |
|--------|-------|-------|
| COMMAND | L2002 fixup overflow | triageError cross-segment call (ignored in build) |
| RECOVER | L2029 unresolved | 5 symbols (`int_23_old_off/seg`, `append`) — ifdef-guarded data not defined |
| REPLACE | L1101 invalid OBJ | _REPLACE.OBJ — WASM produced malformed OMF record |
| RESTORE | L1101 invalid OBJ | MAPPER.LIB SIGHAND module — same OMF corruption |

#### Non-CMD failures (lower priority)

- **SELECT** (28 files) — MACROS.INC nested macros, STRUC.INC cascade
- **MEMM** (23 files) — 386 mode code, E102 CPU setting, VM386.INC
- **DEV** (23 files) — PRINTER, KEYBOARD, DISPLAY, ANSI driver

#### Next steps

1. **Investigate XMA2EMS segfault** — 1 remaining crash, different root cause from the invoke/name crash
2. **STRUC.INC macro investigation** — need to understand why complex `.IF` patterns trigger `$StrucError` in WASM but not MASM. Test more patterns to narrow down.
3. **CMACROS.INC** — may need WASM-specific rewrite of cBegin/cEnd/cProc macros
4. **Link failures** — REPLACE/RESTORE OMF corruption worth reporting upstream too

### Phase 2: Minimal QEMU boot ✅ DONE

All 4 boot tests pass (B through E). Full WASM stack boots on clean build. Tests in `tests/test_wasm_boot.sh`.

### Phase 3: Full E2E test suite on WASM build

**Blocked by:** 5 CMD modules with assembly errors (14 files) + 4 with link errors (see plan above). `make deploy` requires all CMD modules to build.

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

**Goal:** Replace all 9 Microsoft-proprietary DOS build utilities with native
host tools, eliminating kvikdos from this part of the build. The seven tools
detailed below are followed by ASC2HLP and COMPRESS, which are used only for
SELECT help generation. Invocation counts in this historical analysis are a
baseline; remeasure them as each replacement lands.

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

- [x] Write `bin/dbof` replacement (Python)
- [x] Verify output matches original BOOT.INC and FDBOOT.INC byte-for-byte
- [x] Update Makefile to use native script

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

The first line is actually a hexadecimal message-file revision, not a total.
The original utility increments it in both the `.MSG` source and generated
`.IDX`; the native implementation preserves that behavior byte-for-byte.

- [x] Write native `bin/buildidx` replacement
- [x] Verify USA-MS.IDX output byte-for-byte and cover the source-level update
- [x] Remove DBOF and BUILDIDX from the emulated production path

**Implementation:** ~40 lines of Python. Scan MSG file for pool headers, record byte offsets and entry counts.

- [ ] Write `bin/buildidx` replacement (Python)
- [ ] Verify output matches original USA-MS.IDX byte-for-byte
- [ ] Update Makefile to use native script

#### 6.3 EXE2BIN — MZ EXE to flat binary (low)

**What it does:** Strips the MZ header from a DOS .EXE file and writes the raw code/data. Optionally applies segment relocations (adding a base segment to each relocation entry). Used for .COM files, boot sectors (.BIN), device drivers (.SYS), and data files (.DAT, .CPI).

**Production invocations (30):** MSLOAD, MSBIO, MSDOS, COMMAND, SYS, MORE,
LABEL, TREE, COMP, ASSIGN, DISKCOMP, DISKCOPY, GRAFTABL, KEYB, GRAPHICS, MODE,
SELECT, FDBOOT, SEL-PAN, CPI-HEAD, and device drivers (DRIVER, ANSI, VDISK,
RAMDRIVE, KEYBOARD, PRINTER, DISPLAY, SMARTDRV, XMA2EMS).

**Special cases:**
- MSBIO uses stdin redirection: `$(EXE2BIN) "MSBIO.EXE MSBIO.BIN" <LOCSCR` — LOCSCR provides the load segment for relocation
- PRINTER & DISPLAY use `<ZERO.DAT` for same purpose
- Most invocations have zero relocations (just header stripping)

**MZ header format:** 28-byte fixed header. Signature `MZ`/`ZM` at offset 0. `e_cblp` (bytes on last page) at 0x02, `e_cp` (pages) at 0x04, `e_crlc` (relocation count) at 0x06, `e_cparhdr` (header size in 16-byte paragraphs) at 0x08, `e_lfarlc` (relocation table offset) at 0x18. Code starts at `e_cparhdr * 16`.

**Algorithm:**
1. Read MZ header, validate signature
2. Skip to `header_paragraphs * 16` (code start)
3. For each relocation entry: read segment:offset pair, add base segment to the word at that file offset
4. Discard the pre-entry prefix (normally 0x100 bytes for `.COM` targets) and
   write the remaining image

**Open-source alternatives:**
- Open Watcom ships a native `exe2bin` ([source](https://github.com/open-watcom/open-watcom-v2/blob/master/bld/wl/exe2bin/exe2bin.c), ~450 lines C) — not currently vendored
- FreeDOS exe2bin ([GitLab](https://gitlab.com/FDOS/base/exe2bin)) — Sybase Open Watcom Public License

**Implementation:** ~50 lines of Python. Most invocations are zero-relocation (just skip header + copy), making it especially simple.

- [x] Write `bin/exe2bin` replacement (Python)
- [x] Handle stdin base segment for MSBIO/PRINTER/DISPLAY special cases
- [x] Verify output hashes against the original for all 30 production calls
- [x] Remove EXE2BIN from the emulated production path

#### 6.4 MENUBLD — FDISK menu data to C source (low-medium)

**What it does:** Reads `FDISK.MSG` (menu definitions with `^rrcc^` cursor positioning, `<H>`/`<R>`/`<U>` attributes, `<I>` insert placeholders) and `USA-MS.MSG`, generates `FDISKM.C` — C source with `char far *menu_XX = "..."` declarations. The input and output are nearly identical text — MENUBLD primarily substitutes localized strings from USA-MS.MSG.

**Invocations (1):**
```makefile
cd $(FDISK_DIR) && $(MENUBLD) "FDISK.MSG ..\\..\\MESSAGES\\USA-MS.MSG"
```

**Implementation:** ~80 lines of Python. Copy-through with string substitution from MSG pool.

- [x] Examine FDISK.MSG vs FDISKM.C and document the marker substitution
- [x] Write `bin/menubld` replacement (Python)
- [x] Verify FDISKM.C output against the Microsoft-tool hash
- [x] Remove MENUBLD from the emulated production path

#### 6.5 NOSRVBLD — simple message class generator (low-medium)

**What it does:** Simpler variant of BUILDMSG. Takes a `.SKL` file and `USA-MS.MSG`, produces `.CL1`–`.CL5` files containing raw `DB` directives with label names — no class structure wrappers, no `PROC`. Used for kernel-level messages (BIOS, DOS, boot sector) that use a simpler retrieval mechanism.

**Production invocations (6):**
```makefile
cd $(BOOT_DIR)    && $(NOSRVBLD) BOOT.SKL "..\MESSAGES\USA-MS.MSG"
cd $(BIOS_DIR)    && $(NOSRVBLD) MSBIO.SKL "..\MESSAGES\USA-MS.MSG"
cd $(DOS_DIR)     && $(NOSRVBLD) MSDOS.SKL "..\MESSAGES\USA-MS.MSG"
cd $(FDISK_DIR)   && $(NOSRVBLD) FDISK5.SKL "..\\..\\MESSAGES\\USA-MS.MSG"
cd $(XMA2EMS_DIR) && $(NOSRVBLD) XMA2EMS.SKL "..\\..\\MESSAGES\\USA-MS.MSG"
cd $(XMAEM_DIR)   && $(NOSRVBLD) XMAEM.SKL "..\\..\\MESSAGES\\USA-MS.MSG"
```

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

`:def` supplies the label and implicit pool name; localized bytes still come
from the message catalog. `:use` supplies an explicit pool. Continuation lines
in the catalog become additional tab-indented `DB` directives.

- [x] Write native `bin/nosrvbld` replacement
- [x] Verify all 11 generated class files against Microsoft-tool hashes
- [x] Remove NOSRVBLD from the emulated production path

#### 6.6 CONVERT — EXE to COM with relocating stub (medium)

**What it does:** Unlike EXE2BIN (which requires zero relocations for .COM), CONVERT handles .EXE files **with relocations** by prepending a small x86 relocating stub. The stub patches segment references at load time, then jumps to the real entry point. The output is a .COM file that is self-relocating.

**Production invocations (8):**
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
1. Prepend a 16-byte near jump and `Converted` signature.
2. Copy the complete MZ executable unchanged, including its header and
   relocation table.
3. Append a fixed 123-byte loader. At COM load time it interprets the embedded
   MZ header, applies relocations, moves the load image to offset `100h`, sets
   SS:SP, and far-jumps to the original CS:IP.

**Reference implementations:**
- [exe2com.asm](https://github.com/leonardo-ono/Assembly80863DCubeAdlibMusicDemoTest/blob/master/exe2com.asm) — ~43 lines of NASM showing the relocating stub concept

The native implementation embeds that loader directly. Its documented NASM
source is checked in beside the converter, and parity tests prove that assembling
the source produces the exact embedded bytes; no generated blob is needed at
bootstrap time.

- [x] Reverse-engineer the exact wrapper and loader format across all outputs
- [x] Write native `bin/convert` replacement
- [x] Verify all eight production outputs against Microsoft-tool hashes
- [x] Track the converter as a prerequisite of every generated COM file

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

This table is a historical functional-test summary. The authoritative live
inventory is `tests/runtime_coverage.json`; it currently exposes runtime and
CONFIG.SYS gaps that this older prose table did not account for. kvikdos handles
fast tests (`run_tests.sh`), while QEMU+serial covers disk, TSR, driver, and
interactive behavior. CI runs parallel jobs per test target.

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
| EMM386 | protected-mode entry; EMS allocate/map/alias/release | test_emm386_qemu.sh |

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
