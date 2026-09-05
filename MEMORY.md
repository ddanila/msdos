# DOS 6.22 memory model

This document records the durable HMA, UMB, XMS, and EMS constraints. Detailed
delivery history belongs in Git; current evidence belongs in the test manifests.

## Public behavior

The system reports DOS 6.22 consistently through `INT 21h/AH=30h`,
`AX=3306h`, system banners, and `COMMAND.COM VER`. It retains the `MSDOS5.0`
boot-sector OEM identifier used by retail MS-DOS 6.22. The existing
per-program fake-version hook affects the documented call but not the
true-version query.

The supported memory surface includes:

- allocation strategies `00h..02h`, `40h..42h`, and `80h..82h`;
- UMB link/query control through `INT 21h/58xxh`;
- `DOS=HIGH|LOW` and `DOS=UMB|NOUMB`;
- `DEVICEHIGH`, `INSTALLHIGH`, `LOADHIGH`/`LH`, and UMB-aware `MEM`;
- XMS 3.00 HMA, A20, extended-memory, and UMB functions, including the 32-bit
  free-memory, allocate, handle-information, and resize calls;
- EMM386 EMS-only default mode plus `RAM` and `NOEMS` UMB modes.

## Arena invariants

`src/DOS/ALLOC.ASM` owns allocation, resize, free, coalescing, and process cleanup.
`arena_head` remains the conventional arena head. `UmbArenaHead` identifies the
upper arena, `UmbLinkMcb` the conventional bridge, and `UmbLinked` only the
public link state—not whether UMB storage exists.

- Ordinary scans include UMBs only while the public chain is linked.
- Upper-only strategies never infer the arena from a segment threshold.
- Upper-then-low strategies retry conventional memory only after no upper block
  fits.
- Provider gaps are system-owned; allocation and coalescing cannot cross them.
- Process cleanup visits both arenas even when the public UMB link is off.
- Link changes validate the saved bridge and signatures before mutation.
- UMB acquisition and registration are transactional; any failure releases all
  acquired extents and exposes no partial arena.

SYSINIT alone uses the signed private `5804h` handoff to register the complete
validated map. Ordinary `5804h` calls retain the public invalid-function result.
Provider discovery, allocation, and release otherwise use standard XMS calls.

## HIMEM and EMM386 ownership

HIMEM owns the XMS entry point, HMA allocation, A20 nesting, extended-memory
handles, and the UMB allocation table. EMM386 obtains its backing pool through
XMS when the repository HIMEM peer is present. It removes UMB backing pages
from the EMS pool, installs stable mappings, and registers all extents
atomically.

The EMS and UMB ownership sets must stay disjoint. A committed UMB mapping must
remain stable across EMS map changes, DMA, alternate register sets, task
switches, failed initialization, and warm reboot. Page-frame windows, video
memory, option ROMs, explicit exclusions, and the system-ROM area are not UMB
candidates. `X=` exclusions override `I=` inclusions regardless of argument
order.

A third-party XMS provider remains valid for DOS. Repository EMM386 may decline
its UMB feature when its private HIMEM peer is absent, but must not replace or
damage the third-party manager.

## EMM386 footprint

Volkov Commander 4.05's `Alt+F5` MCB walk is the comparison oracle, using
identical 8 MiB QEMU hardware and startup files. Retail DOS 6.22 leaves a
618,736-byte largest conventional block. Before relocation was repaired, this
system left 455,984 bytes and a 128,688-byte low `system` block.

With HIMEM and `DOS=HIGH` alone the low block is 20,144 bytes. The former
EMM386-attributable increase was 108,544 bytes in both `NOEMS M5` and `RAM M5`;
`RAM` separately changes the upper arena, so that increase was not the EMS page
frame or UMB backing pool.

This build defines `NOHIMEM`, so `InitTab` uses the extended-buffer
`get_buffer`/`moveb` path before shrinking `driver_end`. The XMS allocator had
initialized only the EMS backing pool, leaving `get_buffer` unable to relocate
`PAGESEG` and `LAST`. It now reserves a relocation tail in the same locked XMS
handle. UMB mappings are committed before the initialization-only `LAST` state
is discarded, and the relocated page directory is installed in both the live
descriptor state and TSS.

The other large fixed cost was allocating maximum-capacity tables for all 255
handles and 255 fast register sets. These tables now occupy resident `VDATA`
according to the selected `H=` and `A=` capacities; the full option ranges are
unchanged.

Each fast register set formerly retained mapping slots for all 52 possible
windows even when the selected frame and banking layout exposed far fewer. The
runtime context size now determines the resident stride, while the maximum
`B=`/`A=` configuration still receives all 52 slots. Normal EMM386 residency
drops by 384 bytes without changing the public context size or option limits.
Saved page maps also use a byte owner: `H=255` exposes handles 0 through 254,
so `FFh` is an unambiguous unused marker. This removes another 64 bytes in the
normal `H=64` configuration without changing its four saved frame mappings.

The `P=` and `FRAME=` parser formerly kept its 20 page identifiers, 20 segment
values, and four frame candidates in resident DGROUP. Every consumer runs in
the discardable `LAST` initialization segment. Those 70 bytes now live beside
their consumers and use `CS`-relative references; paragraph rounding reduces
the installed EMM386 allocation by 64 bytes. Explicit frame selection,
individual page assignment, and EMS 4.0 alternate-register services remain
covered.

The selected initial mode, `W=`, `RAM`/`NOEMS`, temporary page identifier, and
resident-break pointer are likewise needed only while `LAST` installs the
driver. Keeping these ten bytes with their initialization consumers removes one
more installed paragraph. Normal, `OFF`, `AUTO`, both `W=` forms, `RAM`, and
`NOEMS` startup paths remain covered.

The detected DOS version and the selected pool, `L=`, `D=`, and `B=` values are
also installation inputs rather than runtime state. Moving these nine bytes to
`LAST` removes another installed paragraph while keeping explicit XMS reserve,
DMA reserve, and banking-boundary configurations covered.

The candidates used to construct the DMA page list—high and extended starts,
counts, and the temporary ranges on either side of a 64 KiB boundary—are also
installation-only. Moving them beside `InitEPage` in `LAST` removes 14 resident
bytes and crosses an allocation boundary, reclaiming one 16-byte paragraph.
The final DMA page list remains resident, but now occupies two bytes per
selected `D=` page in the compacted VDATA arena instead of a fixed 32-byte
array. The default `D=16` therefore pays for one entry while `D=256` retains
all 16. Accepted and rejected `D=` reserves and the extended EMS 4.0 lifecycle
remain covered.

Installation message flags and the 12-byte option-token buffer now live in
`LAST`; the parser writes and reads the latter explicitly through that segment.
The pool base and sizes, temporary availability totals, XMS entry and handle,
and relocation-tail size are likewise used only while allocation, table setup,
or failed-install cleanup is running. Moving those 19 bytes out of DGROUP with
the parser state removes 34 linked resident bytes after alignment and reduces
the installed allocation by 32 bytes. The complete option grammar, allocation
failure paths, and runtime command parser remain covered.

The physical address of the relocated text and the temporary stack, IDT, and
page-directory segment values are also consumed only during table setup. They
now live in `LAST`; the page-table segment deliberately remains resident
because split-UMB setup still consumes it during the transition. The unused
error-prefix word is gone. Return-to-real trapping now uses the saved port 84h
token itself as the pending-sequence state, invalidating it on any port 85h
output instead of retaining separate last-port and unread port-85 bytes. These
data and code reductions reclaim another 48 installed bytes while preserving
runtime `ON`/`OFF`/`AUTO`, split UMBs, and warm transitions.

The IDT and complete TSS, including its 8 KiB I/O bitmap, now follow `PAGESEG`
in the load image. Initialization builds them conventionally, then copies them
with the page tables into the locked XMS relocation tail and repoints their
descriptors. This preserves interrupt and I/O trapping while removing both
tables from the resident conventional span.

The NOHIMEM initialization stack retains its full 1 KiB depth and now follows
the discardable `LAST` image rather than separating DGROUP from `_TEXT`.
`InitTab` rebases the live 512-byte ring-0 stack on dynamic resident storage
before virtual mode starts, so the loader stack is outside the installed
allocation. This recovers 1,024 conventional bytes without reducing either
stack's depth.

The linker now places reflected EMS services and the real-mode transition path
before the protected-only trap engine. Initialization copies the complete
logical `_TEXT` to locked XMS, points the protected selectors at that copy,
then reuses the low protected suffix for the selected VDATA extent. Runtime
`ON`, `OFF`, and `AUTO` remain supported because DMA initialization, A20
control, interrupt masking, and the return path stay in the low prefix.

The transient `EMM386 ON`/`OFF`/`AUTO` parser now follows the protected-only
suffix boundary. Later command invocations execute their own loaded image, so
that parser need not remain in the installed driver.

The 386 LOADALL emulators formerly kept their 512-byte scratch buffer and an
alignment pointer in conventional DGROUP. Both emulators execute only after
the protected `_TEXT` copy is locked in XMS, whose `VDMCA_GSEL` descriptor is
its writable alias. The buffer now resides in the protected-only suffix. The
relocation allocation and buffer offset are rounded so the physical buffer
remains dword-aligned even though `_TEXT` is byte-combined. This removes 518
linked DGROUP bytes; protected-only code and alignment storage grow without
changing the retained `_TEXT` boundary. That change reduced the comparison
configuration to 13,808 installed bytes for EMM386, or 13,824 bytes including
its arena header.
The enforced normal EMM386 module budget remains 14 KiB including that header.
Runtime modes, frame and banking layouts, maximum option capacities, EMS 4.0,
UMB integration, warm reboot, and `/NUMHANDLES=24..32` shifted-load boots remain
covered.

OS/E enable state has only three values, so it now uses a byte instead of a
dword. This also lets the compiler use byte operations in the EMS 4.0 query and
enable/disable paths. An unreferenced four-byte `VEMMD_SSbase` relic is gone.
Together the changes remove six linked DGROUP bytes and 26 bytes from the low
code prefix, crossing one installed paragraph. EMM386's OS/E key remains a full
32-bit value, and the OS/E lifecycle, EMS 4.0, runtime modes, DMA, maximum
options, UMB integration, warm reboot, and shifted-load matrix remain covered.

The protected fatal-error formatter no longer retains initialization's
five-word decimal-power table: its two-digit result uses one division, while
the full table now follows its initialization-only consumer in `LAST`. The
saved fault record is dead before the real-mode dialog writes its boot,
continue, and video-mode bytes, so those three bytes share the record's first
three bytes. The parity handler's external move-status declaration is also a
byte, matching its owner and preventing a parity fault from overwriting the
adjacent A20-toggle state. These changes remove 14 bytes from `_DATA` and one
byte from the retained code prefix, crossing a paragraph boundary and reducing
EMM386 to 13,776 installed bytes. EMS modes and options, EMS 4.0, UMB rollback,
warm reboot, and `/NUMHANDLES=24..32` shifted-load boots remain covered.

The 56-byte DMA port list is immutable installation input, not part of the
runtime DMA snapshot. Its only consumer is `InitELIM`, which marks those ports
in the TSS I/O bitmap before installation completes. The list now lives in
discardable `LAST`, and `InitELIM` selects that segment explicitly while
building the bitmap. Runtime DMA register state and the reserved DMA page list
remain resident. Removing the table from `_DATA` advances the aligned stack and
code by four paragraphs, reducing EMM386 to 13,712 installed bytes. DMA reserve
options, runtime modes, EMS 4.0, UMB rollback, warm reboot, and the complete
shifted-load matrix remain covered.

The legacy `_VM1_EMM_Pages` word was written during setup but had no consumer;
the runtime context dimensions superseded it. It is now removed. The DMA page
count now matches its fixed 16-entry array with a byte rather than a word, while
the full `D=` range remains unchanged. The fatal-error prompts also use their
BIOS length fields without unused DOS-string terminators, and the privileged
error prompt states its two choices once. Together these changes remove 20
bytes from `_DATA`, cross the next aligned boundary, and reduce EMM386 to
13,696 installed bytes. Normal and maximum options, DMA reserve handling, EMS
4.0, runtime modes, UMB rollback, warm reboot, and shifted-load boots remain
covered.

The exception dialog now says `EMM386 exception #` and `Enter to reboot` while
retaining the exception number, CS:EIP, error code, bell, and reboot action.
The 12-byte `_DATA` reduction crosses another paragraph boundary, reducing
EMM386 to 13,680 installed bytes and increasing the VC largest block by the
same 16 bytes. Fault handling, the focused memory-manager suites, and the
complete shifted-load matrix remain covered.

The EMS page-frame query now selects its returned frame once and shares the
final register store. This removes 15 linked bytes and crosses the next driver
paragraph, reducing EMM386 to 13,664 installed bytes. A latent DOS-high defect
initially hid that gain: `CURADD` and the EMS buffer-map workspace follow their
code into the HMA, but several accesses still selected the released low copy
through `SS`. Those accesses now follow `CS`, as the existing 512-byte transfer
workspace already did. The `/NUMHANDLES=24..32` shifted-load matrix boots, and
the paired VC block grows by 64 bytes because the smaller driver also improves
downstream paragraph placement.

The retained GDT still contained two historical general-work descriptors named
for unused 286 debugger call gates. No module referenced either selector; the
five Deb386 work descriptors and its all-address descriptor remain unchanged.
Removing only those two entries and renumbering the following internal
selectors reduces the GDT from 312 to 296 bytes and EMM386 from 13,664 to
13,648 installed bytes. The released paragraph reaches VC directly, raising
its largest block to 594,656 bytes without changing usable UMB space. Runtime
commands, all frame and banking forms, sparse physical pages, maximum `H=` and
`A=`, DMA reservation, EMS 4.0 and OS/E, UMB transactions, warm reboot, and the
complete shifted-load matrix pass.

Three reserved OEM descriptors were likewise unreferenced. The live OEM0
diagnostic alias remains, and the EMS map/move scratch descriptor now follows
it directly. Removing those 24 bytes also removes the former eight-byte
paragraph gap before DGROUP, reducing the GDT from 296 to 272 bytes and the
installed EMM386 allocation from 13,648 to 13,616 bytes. VC receives both
paragraphs and reaches 594,688 bytes; usable UMB space is unchanged. The same
runtime, EMS 4.0, maximum-option, frame, DMA, UMB, shifted-load, and warm-reboot
gates pass with the compact selector layout.

The LIM 3.2 saved-map table no longer stores a handle number in every record:
the table is already indexed by handle. Its first mapping word uses `FFFEh` as
the free-slot sentinel, leaving `FFFFh` available for a legitimately unmapped
window. Records shrink from nine to eight bytes. The six-byte code increase is
more than offset by 64 bytes of default-table storage and improved final
alignment, reducing installed EMM386 from 13,616 to 13,552 bytes. VC receives
all four paragraphs and reaches 594,752 bytes. The extended EMS probe saves an
unmapped first window and verifies duplicate-save, protected-deallocation,
restore, and duplicate-restore status codes; the full focused EMM386 suite
passes.

The physical-window page-table lookup no longer repeats the invariant
`PAGET_GSEL` selector in all 52 entries. It retains only each varying 16-bit
PTE offset and loads the shared selector at the two mapping sites. This removes
104 data bytes for four additional code bytes; final alignment contributes the
remaining four bytes of the measured six-paragraph reduction. EMM386 now
occupies 13,456 bytes and VC's largest block reaches 594,848 bytes. All frame,
banking, sparse-`Pn=`, maximum-option, EMS 4.0, UMB, and runtime-mode gates pass.

The DATA segment formerly padded the 12-byte `IBMPATCH` compatibility area to
625 bytes even though `SWAP_END` excludes that padding from every saved task
context and no symbol or reference occupies it. Removing the 612 unused bytes
while retaining the mandatory byte immediately after `SWAP_END` reduces
`DOS_LOW_GATE_END` from 7,598 to 6,986 linked bytes and its allocation from
7,600 to 6,992 bytes. The entire 608-byte paragraph gain joins VC's largest
block, which reaches 595,456 bytes. Kernel-layout, undocumented-structure,
filesystem, FCB, interrupt, HMA, configured-stack, concurrent-provider, and
warm-reboot gates pass.

The 52 mappable-window records no longer repeat their internal physical page
number. Frame records are physical pages `0..P-1`; missing frame slots `P..3`
have no record; and every later record is therefore its dense index plus
`4-P`, where `P` is the installed frame-page count. Retaining only each segment
removes 104 data bytes; the API, partial-map, unmap, and DMA paths derive the
number when needed. The added instructions leave a net five-paragraph saving:
EMM386 occupies 13,376 bytes, VC's largest block reaches 595,536 bytes, and the
gap falls to 23,200 bytes. The complete frame and banking matrix, sparse `Pn=`,
EMS 4.0, load options, DMA reservation, concurrent UMB/EMS, rollback, and warm
reboot gates pass.

EMS function 58h now has one implementation instead of two. The dispatch table
already targeted `_GetMappablePAddrArrayFixed`; the older C function had no
caller but still occupied 128 retained bytes and carried a second copy of its
record-walking rules. Removing that unreachable body and its private
declarations reduces EMM386 to 13,248 bytes. All eight paragraphs reach VC's
largest block, now 595,664 bytes, and the gap falls to 23,072 bytes. Function
58h, EMS 4.0, every frame and banking mode, sparse `Pn=`, maximum options,
runtime control, concurrent UMB/EMS, rollback, and warm reboot pass after the
resulting low-prefix layout shift.

The remaining EMM40 function inventory exposed one unreachable 10-byte
`UndefinedFunction` body: invalid function numbers are rejected directly by
the dispatcher. In the handle-name service, the entry guard already restricts
the subfunction to get or set, so the set branch no longer repeats that test or
carries an impossible third error arm. Together these remove 15 code bytes and
one alignment byte, reducing EMM386 to 13,232 bytes and raising VC's largest
block to 595,680 bytes. The gap is now 23,056 bytes. Handle-name lookup,
duplicate and invalid-subfunction results, the complete EMS surface, shifted
loads, runtime modes, UMB/EMS isolation, rollback, and warm reboot pass.

Two single-purpose EMM entry points now share state directly. `ReallocatePages`
reads the already imported `free_count` instead of calling a four-byte getter,
and LIM 4.0 warm-boot preparation points at the identical current-status
handler used by function 40h. The dispatch source names that alias explicitly,
and the coverage checker continues to account for function 5Ch independently.
The 16-byte reduction lowers EMM386 to 13,216 bytes, raises VC's largest block
to 595,696 bytes, and leaves a 23,040-byte gap. Allocation, reallocation,
function 5Ch, all 30 EMS functions, frames, options, runtime modes, UMB/EMS
isolation, rollback, and warm reboot pass.

Four register-only services no longer pay for separate C call frames.
Unallocated-page counts and the EMS version now return directly from assembly,
while two deliberately unsupported translation queries share one explicit
invalid-function handler. Deallocation also avoids clearing a handle field that
cannot participate in its subsequent relocation scan. The resulting 17-byte
static reduction crosses an allocation paragraph: EMM386 occupies 13,200 bytes,
VC's largest block reaches 595,712 bytes, and the gap falls to 23,024 bytes.
All 30 EMS functions, every frame and banking mode, load and runtime options,
XMS/UMB coexistence, rollback, and warm reboot pass from a forced clean build.

The LIM 3.2 page-frame-address query now joins the register-only assembly
services. Its error path still reports an incomplete frame and retains the
documented `B000h` fallback when no frame segment exists; its normal path returns
the configured frame and current status. The dispatcher-owned handler is 33
bytes instead of the 50-byte C routine and relies on the dispatcher's saved
register-frame pointer rather than reloading it. After module alignment, the
static low image is 14 bytes smaller and its final two padding bytes disappear,
releasing one installed paragraph:
EMM386 is 13,184 bytes, VC's largest block is 595,728 bytes, and the gap is
23,008 bytes. The full EMS surface, frame/banking and load-option matrices,
runtime modes, extended lifecycle, XMS/UMB coexistence, rollback, and warm
reboot gates pass from a forced clean build.

The remaining dispatcher-only register services now share the same assembly
convention. Handle-count queries write `BX` and fall through to the common
status return; direct status calls and function 5Ch use that same tail. Version
and unsupported-function handlers use the `BP` register frame already
established by `int67_Entry`, while the unallocated-page helper retains its
reload because function 59h also calls it from C. Removing the two C routines
and redundant frame reloads reduces retained `_TEXT` by 19 bytes. Three bytes
of stack alignment remain, and the installed allocation drops one paragraph to
13,168 bytes. VC's largest block reaches 595,744 bytes and the retail gap falls
to 22,992 bytes. The complete EMS, frame/banking, load/runtime, extended
lifecycle, XMS/UMB coexistence, rollback, and warm-reboot gates pass.

`EMMstatus` was initialized to zero and never changed, so retaining a word and
reloading it on every successful EMS return implemented no state. Success paths
now emit `OK` directly and the initialization write and exported symbol are
gone. Removing the historical leading word as well exposed a real binary-layout
constraint: driver-load `OFF` stopped booting when later EMMDATA offsets moved.
An anonymous two-byte layout pad therefore preserves those offsets; it is
absorbed by later segment alignment and costs no installed bytes. The final
layout removes 50 retained code bytes while preserving the 802-byte `_DATA`
extent, dropping EMM386 by three paragraphs to 13,120 bytes. VC's largest block
reaches 595,792 bytes and the retail gap falls to 22,944 bytes. Repeated
`ON`/`OFF`/`AUTO`/`W=` boots and the complete EMS, frame/banking, option,
extended-lifecycle, XMS/UMB, rollback, and warm-reboot gates pass.

The context-save byte count now lives directly in its function 59h hardware-
information word instead of being copied there for every query, and the FRS
stride aliases that same word because both values are defined as the allocation
word plus the selected mapping context. This removes four duplicated data bytes,
the repeated table update, and the redundant initialization write. Compact
immediate success/version returns complete the paragraph-sized bundle. Retained
`_TEXT` falls by 14 bytes; `_DATA` is 798 bytes; and EMM386 occupies 13,104
bytes. VC's largest block reaches 595,808 bytes and the retail gap falls to
22,928 bytes. Maximum alternate sets and mapping contexts, all load modes, the
complete EMS surface, frames/banking, extended lifecycle, XMS/UMB coexistence,
rollback, and warm reboot pass.

EMS function 52h now implements its volatile-handle attribute contract in a
compact assembly handler. Subfunction 0 retains the shared handle validator and
its exact invalid-handle return, subfunction 1 reports unsupported persistence,
subfunction 2 reports volatile-only capability, and other values retain the
invalid-subfunction result. The handler shares the dispatcher's saved-register
frame and removes 22 net retained bytes, releasing another installed paragraph.
EMM386 occupies 13,088 bytes, VC's largest block reaches 595,824 bytes, and the
retail gap falls to 22,912 bytes. Function 52h error/lifecycle coverage, all 30
EMS contracts, frames and banking, load/runtime options, XMS/UMB coexistence,
rollback, and warm reboot pass.

HIMEM's UMB transaction table remains fixed-capacity, but its XMS handle table
now follows all other resident data. The initialization break includes only
the configured `/NUMHANDLES=` records and is rounded up to a paragraph so the
last record cannot be released partially. Parser, CPU detection, diagnostics,
and destructive memory-test code now follow the resident break. The normal
32-handle configuration stays within 3 KiB of conventional memory. The UMB
record count now also represents registration state: a valid registration is
never empty, and unregistering clears the count. Removing the redundant
committed flag and its writes crosses a paragraph boundary and saves 16 more
installed bytes. Each UMB record also stores its allocation state in the high
bit of its size: no valid UMB can approach the bit's 32,768-paragraph value.
This removes the former flag byte from all 32 records and simplifies their copy
loops, saving another 48 installed bytes. The complete 128-handle option remains
available and tested, as do all 32 UMB extents.

The XMS move engine formerly retained a word solely to recover its current
chunk length after BIOS `INT 15h/87h`, plus instructions to store and reload
it. Keeping that value on the active routine's stack removes the word and both
memory accesses. This moves the default resident break from `0BADh` to `0B9Dh`,
crossing a paragraph boundary and reclaiming 16 installed bytes without
changing the move descriptor, 64 KiB chunk limit, or maximum handle capacity.

HMA ownership now uses the high bit of `/HMAMIN=`. The accepted range is
`0..63`, so that bit cannot collide with a configured minimum and is masked
before the byte is converted to a request size. Global and local A20 operations
share their identical enable and reconciliation tails while retaining separate
nesting counters and local-underflow behavior. Together these changes cross the
next paragraph boundary, reducing HIMEM to 2,960 installed bytes. HMA ownership,
all A20 backends, XMS 3, 128 handles, 286 operation, UMB transactions, and the
EMM386 address-phase matrix remain covered.

The XMS 3 allocate, extended-handle-information, and reallocate wrappers now
share their identical unsupported and unrepresentable-request exits. The
individual functions still return `80h` and `A0h` respectively, but eliminating
four duplicate tails removes 14 linked bytes and crosses the next resident
paragraph. HIMEM now occupies 2,944 installed bytes. XMS 3 success and error
paths, 286 rejection, 128 handles, HMA/A20 backends, UMB transactions, and the
EMM386 `/NUMHANDLES=24..32` address-phase matrix remain covered.

The 87-byte `detect_highest_page` routine is used only while installing HIMEM,
but previously preceded the resident break. Moving it beside the other
discardable initialization code changes the default raw break from `0B7Dh` to
`0B25h`, and its paragraph-rounded allocation from `0B80h` to `0B30h`. HIMEM
therefore occupies 2,864 installed bytes. The HIMEM, XMS 3, documented-option,
UMB-transaction, HMA/DOS-high, and 286 suites pass. In the paired VC image, 32
of the 80 component bytes join the largest block; the remainder stays accounted
for as downstream paragraph and arena layout.

The XMS Move source and destination paths formerly duplicated the same
offset-error translation: an out-of-range conventional address must return
`ERR_BAD_LENGTH`, while other failures retain their source- or destination-
specific code. Sharing that translation removes eight linked bytes and moves
the default raw break from `0B25h` to `0B1Dh`. The rounded allocation crosses
to `0B20h`, so HIMEM now occupies 2,848 bytes. All 16 saved bytes join the paired
VC largest block, and the complete HIMEM/XMS/HMA/UMB/286 gates pass.

The remaining common XMS error tails now reuse one `ERR_NO_MEMORY` exit, HMA
request failures share their final jump, UMB request failures share theirs, and
local A20 underflow reuses the existing A20 error exit. XMS Lock also replaces
ten single-bit shifts with the 286-native variable-count shift while producing
the same `DX:BX` physical address. The bundle removes 24 linked bytes, moves the
default raw break from `0B1Dh` to `0B07h`, and crosses the allocation boundary
to `0B10h`. HIMEM occupies 2,832 bytes, and all 16 installed bytes enlarge the
paired VC block after the full option, error, XMS, HMA, UMB, and 286 gates.

Four resident XMS paths now reuse registers without changing their documented
outputs: free-memory query preserves the largest gap on the stack, allocation
derives the handle number in its spent SI, Lock forms the address directly in
BX, and handle information counts free records directly in BL before restoring
BH. The eight-byte reduction moves the default raw break from `0B07h` to
`0AFFh`, crossing to a `0B00h` allocation. HIMEM occupies 2,816 bytes, and the
full 16-byte installed gain reaches VC's largest block with all focused gates
passing.

XMS handles no longer retain a separate active byte. Every ordinary EMB starts
at least 64 KiB above 1 MiB because the HMA is reserved separately, so a zero
base is an unambiguous free-record sentinel even for a valid zero-length EMB.
The record now contains only lock count, base, and length. This saves one byte
per configured handle, reduces the default allocation from `0B00h` to `0AE0h`,
and retains the full 128-handle option. The paired VC block gains all 32 default-
record bytes. The core test now explicitly covers zero-length allocation,
information, and release in addition to the complete focused matrix.

With base-zero as the free sentinel, allocation no longer needs to clear the
lock byte: a record can become free only through a release that already rejects
nonzero locks. Release likewise need not clear length because every scan ignores
it while base is zero and allocation overwrites it before publishing the handle.
Removing these two writes moves the raw default break from `0AD8h` to `0AD0h`
and the rounded allocation from `0AE0h` to `0AD0h`. HIMEM occupies 2,768 bytes,
and all 16 installed bytes enlarge the
paired VC block. Handle reuse, exhaustion, zero-length records, locked release,
reallocation, moves, warm reboot, maximum options, and 286 operation pass.

Handle allocation now derives the free record's public handle number from the
scan's remaining count instead of dividing its byte offset afterward. The
requested size stays in BX and is restored to DX on a no-memory failure, while
success returns the precomputed handle in DX. Handle validation compares DX
directly with a zero-extended word limit, and range scans share two already-
zero CH values. Tighter A20 reconciliation completes a 19-byte linked reduction,
moving the default raw break from `0AD0h` to `0ABDh` and the rounded allocation
to `0AC0h`. HIMEM occupies 2,752 bytes; all 16 installed bytes reach the paired
VC block, and the complete focused matrix passes.

The extended XMS handlers no longer repeat the 386 check made by their sole
dispatcher. The forced-286 build retains its rejecting stubs, while the normal
build has one authoritative CPU gate before any XMS 3 handler can be called.
Removing the four redundant checks and their dead error exits shortens the
resident prefix by 42 bytes, moves the default raw break from `0ABDh` to
`0A93h`, and reduces the rounded allocation to 2,720 bytes. The paired VC block
gains the complete 32 installed bytes. XMS 2/3, documented options, HMA/A20,
UMB transactions, warm reboot, and forced-286 behavior pass.

The dispatcher's non-386 rejection now shares the same unsupported-function
exit as an undefined extended XMS call. This removes six more linked bytes,
moves the default raw break from `0A93h` to `0A8Dh`, and crosses the next
paragraph boundary. HIMEM occupies 2,704 bytes, and the complete 16-byte gain
joins VC's largest block. The same focused XMS, option, HMA/A20, UMB, warm-
reboot, and forced-286 gates pass.

All handle scans now load the complete word-sized handle limit. This removes
three redundant `CH` clears and the realloc caller's hidden zero-high-byte
contract. The A20 enable and reconciliation calls share their identical result
tail, and undefined extended calls fall through to their alias dispatcher.
Together these changes remove 16 linked bytes, move the default raw break from
`0A8Dh` to `0A7Dh`, and reduce HIMEM to 2,688 installed bytes. The entire
paragraph joins VC's largest block, with the focused XMS, option, HMA/A20, UMB,
warm-reboot, and forced-286 gates passing.

The free-memory scanners now rely on the public XMS dispatcher's saved `CX`,
`SI`, `DI`, and `BP` instead of saving the same registers again internally.
Handle information still preserves its validated `SI` across the nested free-
handle count because it consumes that pointer afterward. This removes 14
linked bytes, moves the default raw break from `0A7Dh` to `0A6Fh`, and crosses
the allocation boundary: HIMEM occupies 2,672 bytes and VC's largest block
grows by the complete 16-byte paragraph. Core XMS, XMS 3, 128 handles,
documented options, HMA/A20, UMB transactions, warm reboot, and forced-286
tests pass.

Free-memory queries now keep the largest interval in `AX` and return the total
in `DX`, eliminating stack shuffling in both the XMS 2 and XMS 3 paths. The XMS
3 allocation and reallocation wrappers tail-jump to their 16-bit engines, the
version result is formed directly from the pool comparison, HMA requests load
only their byte-sized minimum, the private relocation response no longer saves
an overwritten `AX`, and an unreferenced error stub is gone. These independent
changes remove another 16 linked bytes, move the default break from `0A6Fh` to
`0A5Fh`, and reduce HIMEM to 2,656 bytes. VC gains the complete paragraph and
the same focused, shifted-load, and real-286 gates pass.

UMB insertion and coalescing now use the register ownership already provided by
the enclosing XMS dispatcher. Insertion leaves its caller's live `DI` untouched;
coalescing returns no register result; and its nested removal helper preserves
only the `CX` loop count that coalescing consumes afterward. Removing the other
redundant save/restore pairs shortens the resident prefix by 20 bytes, moves the
default break from `0A5Fh` to `0A4Bh`, and reduces HIMEM to 2,640 bytes. The
paired VC block gains another complete paragraph, with 32-extent transaction
stress, rollback, all handle phases, and real-286 execution passing.

The 8042 wait helper now exposes its scratch `AX` and `CX` to callers that
immediately overwrite them or return through the XMS dispatcher. The BIOS move
loop preserves only `DS` and the `SI` handle pointer it consumes after
`INT 15h/AH=87h`; `ES` and `DI` are dispatcher-owned. UMB removal uses the
dispatcher-owned `BP` rather than saving `CX`, registration clears its count
from the already-zero loop register, and insertion increments the stored count
directly. This removes 14 linked bytes, moves the default break from `0A4Bh` to
`0A3Dh`, and reduces HIMEM to 2,624 bytes. VC gains the full paragraph; the
real-286 BIOS move, UMB transaction, and shifted-handle gates all pass.

UMB release no longer maintains an unused record index. Its single-use
coalescer tail-returns through the common XMS success path, and removal shifts
the bounded remainder of the fixed 32-record table instead of calculating a
second live end pointer. Entries beyond `umb_count` are deliberately ignored,
so copying their inactive slots cannot publish capacity or state. This removes
16 linked bytes, moves the default break from `0A3Dh` to `0A2Dh`, and reduces
HIMEM to 2,608 bytes. The complete paragraph reaches VC after the 32-extent
model, rollback, shifted-handle, and real-286 gates pass.

Three helpers with exactly one caller now live directly in their consumers.
Allocation scans the handle table without manufacturing carry state for a
call/return boundary, handle information counts free entries while preserving
its live handle pointer, and reallocation performs its local kilobyte-to-byte
conversion in place. Removing the obsolete helper procedures saves 14 linked
bytes, moves the default break from `0A2Dh` to `0A1Fh`, and crosses the next
paragraph boundary. HIMEM now occupies 2,592 bytes and VC receives the complete
16-byte gain. The focused XMS 2/3, documented-option, UMB transaction/model,
warm-reboot, `/NUMHANDLES=24..32`, and real-286 gates all pass. Incremental
HIMEM compaction now pauses while the larger EMM386 and DOS/BIOS ranges are
attributed.

## Memory-parity status

Use identical 8 MiB QEMU hardware, startup files, and VC 4.05 binaries for all
comparisons. Retail leaves a 618,736-byte largest conventional block; the
pre-compaction baseline leaves 558,240 bytes. The validated compacted build
with shared system-stack dispatch, the protected DMA trap engine, the first
COMMAND HMA relocation, the discarded EMM386 initialization stack, and the
five-slot resident COMMAND message table, the corrected high-driver register
contract, transient redirection state, the bounded COMMAND message workspace,
the shared EMM386 dispatch table, derived physical-window PTE offsets, the
shared bounded segment lookup, the first relocatable COMMAND code family, and
the protected OEM mapping/parity boundary, and the protected `GoVirtual`
continuation, protected stack-selector conversion, transient command-mode
client split, production GDT compaction, byte-sized physical-window indexes,
runtime-sized sparse `Pn=` exceptions, and runtime-sized DMA and mappable-window
lists, protected parity-vector state, byte-bounded counters, the compact
production GDT, selected-BIOS compaction, removal of unreachable DOS dispatcher
state, compact unsupported code-page-switch dispatch, and compact BIOS
warm-reboot vector restoration and compact BDS flag updates leave 607,792
bytes. Compacting the external-disk BDS and `INT 2Fh` paths raises that result
to 607,808 bytes. Moving the unreferenced 95-byte binary-identification record
to discardable initialization storage raises that result to 607,888 bytes.
Removing three bytes of dead DOS table state raises the current result to
607,904 bytes. Overlaying the MZ header on existing EXEC workspace raises the
current result to 607,920 bytes. Keeping CLOSE's former global cluster scratch
in the directory entry until FASTOPEN classification and moving two alignment
bytes across the low/HMA boundary raises the current result to 607,936 bytes, a
10,800-byte gap.
Exact byte parity is not required, but a large unexplained loss is not
acceptable.

The VC owner-to-owner spans now reconcile the complete difference rather than
treating it as an undifferentiated target:

| Status | Accounted difference | Bytes |
| --- | --- | ---: |
| Advantage | EMM386 resident allocation | -32 |
| Open | HIMEM resident excess | 1,488 |
| Advantage | FILES/FCBS/BUFFERS/LASTDRIVE/STACKS aggregate | -16 |
| Open | Retained DOS/BIOS pre-shell payload and layout | 7,456 |
| Open | COMMAND owner-to-owner span | 880 |
| Equal | VC owner-to-free span | 0 |
| Open | Conventional ceiling/EBDA | 1,024 |
| **Total** | **VC largest-block gap** | **10,800** |

The earlier 32,928-byte DOS relocation-hole recovery remains closed. Remeasure
the rows above after each retained change instead of assuming that every byte
is another oversized component. The 7,456-byte DOS/BIOS row is an exact
owner-level remainder. Phase A3 now accounts for every byte of both the
6,816-byte DOS low prefix and the selected 8,448-byte BIOS image. E1 must turn
those ownership ranges into proved address and lifetime contracts.

## Road to retail-or-better conventional memory

The target is a largest conventional block of at least **618,736 bytes** in the
fixed VC 4.05 comparison, without reducing supported memory-manager options or
usable UMB space. The current result is 607,936 bytes, so 10,800 more bytes must
join the largest free block. Total free memory is supporting evidence, not a
substitute for this metric: saving bytes below a resident island may leave the
largest block unchanged.

The present accounting identifies the whole target but not yet every individual
symbol responsible for it:

| Workstream | Current excess or opportunity | Cumulative result if fully recovered |
| --- | ---: | ---: |
| EMM386 resident allocation | -32 bytes | 607,936 bytes |
| HIMEM resident allocation | 1,488 bytes | 609,424 bytes |
| COMMAND resident allocation | 880 bytes | 610,304 bytes |
| Layout and conventional ceiling | 8,464 bytes | 618,768 bytes |

Matching the two oversized named components recovers at most 2,368 bytes
and therefore cannot meet the goal; layout work is mandatory unless a component
becomes smaller than retail by the remaining amount.

### Success equation and critical path

Treat the 10,800-byte gap as a portfolio, not as four independent size targets.
For every retained change record:

```text
remaining gap = 10,800 - EMM386 gain - HIMEM gain - COMMAND gain
                         - DOS/layout gain - ceiling gain
```

Only growth of the largest VC block counts as a gain. Component shrinkage that
lands in a separate free island is pending layout work until that island is
joined to the largest block. No workstream is required to match retail's
private size: one may beat retail and cover an irreducible difference elsewhere.

The currently proved upper bound from matching the remaining oversized named
components is 2,368 bytes. Moving the 1 KiB EBDA without allocating a
replacement block raises that to 3,392 bytes, still leaving **7,408 bytes**.
The final route must
therefore include at least one of these outcomes:

- recover at least 7,408 bytes from retained DOS/BIOS layout and fragmentation;
- make EMM386, HIMEM, or COMMAND collectively at least 7,440 bytes smaller than
  their retail counterparts; or
- combine smaller layout and better-than-retail component gains to the same
  total.

The first EMM386 symbol census is complete, and the explicit EMS 56h return
gateway restores paragraph independence after the latest split. The critical
path is:

1. **Complete:** the documentation-and-measurement investigation attributes
   DR-DOS's larger ordinary HMA-mode block and separates portable techniques
   from low-memory and video-memory compatibility extensions;
2. keep every mutable symbol in DOS's relocated tail addressed through the HMA
   copy, and retain `/NUMHANDLES=24..32` as a mandatory gate;
3. **Complete:** the top-level COMMAND census and exact HMA
   owner/lifetime/slack census established a checked 475-byte first payload and
   18,076 bytes of initially free DOS-owned HMA tail storage; continue the
   symbol-level
   COMMAND and DOS/BIOS ownership work while keeping all attribution reports
   current;
4. **In progress:** COMMAND's complete 1,281-byte normal resident utility and
   critical catalog range now uses the bounded DOS HMA-tail allocator, the
   mutable far-pointer/formatter table remains low, the 81-byte redirection
   state is reloadable transient data, and the message workspace has a
   compiled-catalog capacity bound. The relocated code now includes the
   character/DBCS services and generated GET, DISPLAY, character, and numeric
   message engine. These changes recover 2,480 paragraph-rounded bytes while
   leaving 15,485 bytes for later HMA payloads.
   Continue with coherent cold resident state, using DR-DOS's small
   HMA-resident shell as the measured precedent while preserving every reload
   and asynchronous entry path;
5. **In progress:** EMM386 now retains a 483-byte dual-mode `_TEXT` gateway;
   `GoVirtual` crosses explicitly into its protected continuation and EMS 56h
   returns through an explicit low trap gateway. Continue with the remaining
   transition, fault, and DMA gateways and safe metadata compactions;
6. give mutable DOS state an explicit placement ladder: HMA first,
   relocation-safe XMS second, and bounded deterministic UMB placement last;
   complete DOS/BIOS ownership while doing so;
7. coalesce recovered ranges into the largest block and recover the EBDA
   ceiling paragraph only after identifying already-owned
   destination storage;
8. revisit HIMEM only if a measured residual remains; and
9. defend retail-or-better memory with a local fixed-image regression floor.

This ordering is a dependency order, not a promise that the early inexpensive
work is sufficient. If the censuses show that safe compaction plus the EBDA and
layout work cannot close the then-current gap, proceed directly to the
architectural EMM386 gateway split; do not spend time chasing isolated bytes
that cannot reach the largest block.

### Complete improvement inventory

This is the bounded backlog for reaching the target. It covers every currently
identified way to increase the fixed image's largest conventional block without
removing behavior. Add newly discovered map ranges here before optimizing them.
An item is an opportunity, not an assumed saving: retain it only when the paired
capture shows that its bytes join the largest block. Estimates remain ranges
until an A/B image measures them.

| Priority | Opportunity | Available evidence | Likely scale | Principal constraint |
| --- | --- | --- | ---: | --- |
| Complete | Audit DR-DOS's HMA-mode advantage | Controlled DR-DOS 6.0 and OpenDOS 7.01 matrices reconcile owner spans, public memory APIs, HMA ownership, optional policies, and warm reset | research complete | No source code used; pinned artifacts, identical inputs, isolated probes, and compatibility modes remain separated |
| Complete | Census fixed HMA ownership and COMMAND's top-level resident ranges | The checked maps identify 18,076 initially free bytes of DOS-owned HMA tail and exact ownership ranges for the DOS low prefix and selected BIOS image | attribution complete | Deeper COMMAND work is paused; E1 must prove relocation contracts |
| Paused | Move more COMMAND cold state high or transient | The 1,281-byte normal catalog and 1,166-byte code range are high; 820 of the remaining 955 low service bytes belong to the installed interrupt handler and registered disk callback | under one kilobyte, then better-than-retail opportunities | Resume only as a coherent interrupt/data redesign, not for gateway-scale helpers |
| 1 | Complete the small EMM386 low gateway backed by locked XMS | Local active EMM386 is 32 bytes below retail after compacting internal fast-register-set flags and real-mode contribution alignment; services, return and A20/NMI trap handling, protected `RetReal`, stack-selector conversion, OEM mapping/parity handling, and the protected `GoVirtual` continuation execute from locked XMS | create further better-than-retail headroom | Remaining transition, DMA, and fault gateways; inactive `AUTO`; all EMS maps |
| 2 | Compact EMM386 runtime-sized metadata and alignment | Physical-page IDs, DMA pages, and mappable-window indexes now scale with the selected layout; measured subranges can supplement the gateway redesign | tens to hundreds of bytes per item | Full `H=`/`A=`/`D=`/banking ranges and EMS 4.0 formats |
| 3 | Classify and relocate eligible DOS low state | The local system-to-COMMAND span costs 8,896 bytes more than retail; after measured manager and table differences, 7,456 bytes remain DOS/BIOS-owned | low kilobytes | Some low addresses are ABI/BIOS fixed; HMA/XMS/UMB lifetimes differ |
| 3 | Remove MCB/alignment islands or change load order | Compare first-free and every allocation boundary | paragraphs to kilobytes | Identical startup files and stable ownership |
| 3 | Place eligible permanent allocations high | Local UMB advantage over retail is only 1,216 bytes | at most 1,216 bytes without falling below retail UMB capacity | Must not disguise a conventional regression |
| 4 | Relocate the EBDA into already-owned safe low storage | Exact 1,024-byte ceiling loss is measured | 1,024 bytes | Physical BIOS/DMA access; destination must not consume the gain |
| 4 | Revisit HIMEM only after larger ranges | 1,488-byte component excess; resident break is explicit | tens to hundreds of bytes | 128 handles, 32 UMB extents, all A20 backends |

There are six kinds of useful change:

1. **Remove bytes:** delete dead or duplicate code/data; narrow fields; derive
   values instead of storing them; share compatible exits, strings, and
   workspaces.
2. **Discard bytes:** move parser, detection, setup, diagnostics, and temporary
   tables beyond a component's resident break.
3. **Relocate bytes:** copy protected-only EMM386 state to its locked XMS image,
   DOS state to the HMA, or eligible permanent allocations to UMBs.
4. **Resize bytes:** allocate tables for selected runtime capacities while still
   supporting their documented maximums when those maximums are requested.
5. **Join bytes:** remove paragraph padding, MCB islands, and load-order holes so
   a recovered range enlarges the largest block instead of creating a smaller
   free island.
6. **Raise the ceiling:** move the live EBDA safely and reclaim its original top
   kilobyte; never fake the BIOS-reported size.

Compression is useful only if the compressed object need not be resident or can
execute from the relocated XMS copy. A resident decompressor plus workspace is
otherwise merely another low-memory allocation. Likewise, changing `FILES`,
`FCBS`, `BUFFERS`, `LASTDRIVE`, `STACKS`, the shell environment, the EMS frame,
or the startup files is configuration tuning, not implementation parity, and is
excluded from the fixed comparison.

The following ideas are valid only behind explicit measurement and compatibility
gates:

- make fixed arrays dynamic only when their worst-case runtime growth remains
  possible; saving default-image bytes by silently reducing maximum capacity is
  not an improvement;
- share identical resident routines, strings, descriptors, scratch buffers, and
  error exits across modules where their lifetime and calling conventions match;
- replace word fields with bytes, bit sets, sentinels, or derived values only
  after proving every public numeric value still fits and unallocated states stay
  unambiguous;
- reorder resident segments to remove paragraph padding and place variable tails
  at the allocation break;
- copy immutable protected-mode tables to the existing locked EMM386 XMS image
  and keep only relocation-safe low gateways;
- use HMA space left after DOS only for data that is valid while A20 is enabled
  and whose ownership cannot collide with DOS, buffers, or third-party users;
- use UMBs for permanent state only when the fixed comparison remains
  deterministic and total usable UMB capacity remains at least retail's 47,888
  bytes; and
- become smaller than a retail component when that is simpler and safer than
  reproducing retail's private layout. The user-visible target is available
  memory and compatibility, not byte-for-byte internal identity.

These tempting shortcuts are excluded: falsifying `INT 12h` or the BDA size,
overwriting or page-mapping the live EBDA, reclaiming ROM/video/excluded ranges,
dropping supported option capacity, weakening rollback or warm-reboot behavior,
or consuming unreported UMB space merely to improve the conventional number.

### Actionable candidate register

This register turns the inventory into experiments. It is complete for the
currently known opportunities; new map evidence may add candidates. A candidate
is not an achievement until its focused compatibility tests and paired VC
capture pass.

| Phase | Area | Experiment | Decision evidence |
| ---: | --- | --- | --- |
| Complete A1 | Measurement | Keep VC aggregates and block counts distinct from the earlier raw `MEM /D` process snapshot | The report labels both accounting models and its parser has a local regression test |
| Complete A2 | Measurement | Reconcile the full VC gap through system, COMMAND, VC, free-block, and ceiling spans, isolating the retained DOS/BIOS remainder | The current report proves `8,896 + 880 + 0 + 1,024 = 10,800`; the component census isolates 7,456 bytes for E1 |
| Complete A3 | Measurement | Add reproducible HIMEM, EMM386, COMMAND, DOS, and BIOS resident-range reports from their linker maps | HIMEM, EMM386, COMMAND top-level lifetimes, fixed HMA layout, and every byte of the 6,816-byte DOS low prefix and selected 8,448-byte BIOS image are accounted |
| B1 | HIMEM | Continue the map-guided audit of dispatch, validation, move, lock, A20, HMA, request-header, and error paths; share tails only where outputs and reentrancy agree | Exact XMS 2/3 errors, all A20 backends, HMA, moves, warm reboot, and 286 execution pass |
| B2 | HIMEM | Audit the move descriptor, UMB transaction records, handle records, counters, sentinels, immutable values, and alignment for narrower or derived representation | Zero-length and 128 handles, 32 UMB extents, rollback, locks, reallocations, and legacy bounce pass |
| B3 | HIMEM | Move every remaining parser, CPU/memory detection, destructive test, message, and installation temporary beyond the rounded resident break | Map proves no runtime reference crosses the break; normal and maximum option footprints are budgeted |
| B4 | HIMEM | If compaction stalls, investigate storing immutable tables or cold state in DOS-owned HMA slack, or a relocation-safe XMS area | Ownership is explicit, third-party XMS coexistence works, and no DOS buffer/HMA capacity is lost |
| Complete C1 | EMM386 | Maintain byte-range accounting for the current 490-byte low `_TEXT` prefix and 424-byte `_DATA`, including local labels, anonymous gaps, VDATA overlay, discarded loader stack, and paragraph padding | Every retained byte is real-only, dual-mapped, mutable runtime, compatibility state, discarded initialization state, or unresolved |
| C2 | EMM386 | Compact descriptors, flags, counters, map owners, DMA state, GDT entries, option-sized arrays, VDATA stride, and mutually exclusive workspaces | Normal and maximum `H=`/`A=`/`B=`/`D=`/frame layouts and every EMS 4.0 map format pass |
| C3 | EMM386 | Move further immutable tables, exception support, protected dispatch, and protected-only routines into the existing locked XMS image | Faults, DMA, mappings, inactive `AUTO`, `ON`/`OFF`, UMBs, and warm reboot pass |
| C4 | EMM386 | Split ordinary EMS service dispatch from mapping-sensitive activation so services that do not require virtual mode can live in the relocated image | EMS 3.2/4.0, non-empty function 56h maps, alternate sets, and inactive queries pass |
| C5 in progress | EMM386 | Replace `RRProc` and the return-to-real continuation with a small position-independent low gateway, then relocate the remaining transition module | Init-only `RR_Trap_Init` is high; active 84h/85h handlers remain low until a redesigned continuation passes repeated transitions, faults, modes, shifted loads, and warm reboot |
| C6 | EMM386 | Revisit the deferred shared exception-message buffer only with a probe around both protected-to-real copies | The buffer is correct before and after return, and installation plus exception dialogs complete |
| D1 complete | COMMAND | Refine the generated resident byte-range census from lifetime classes to symbol/module ownership | The checked report anchors every permanent-low range and identifies the asynchronous ranges that prevent another simple move |
| D2 paused | COMMAND | Continue after the completed normal resident catalog relocation with rare formatting, help/error text, and callable services that can safely live high or in the reloadable transient | Resume only as a coherent handler/data redesign; DOS=LOW, `/MSG`, reload, `/F`, batch, pipes, `INT 2Eh`, Ctrl+C, real critical errors, termination, and 286 execution remain gates |
| D3 | COMMAND | If necessary, redesign the resident/transient interface around a smaller stable state block and reload gateway | The complete internal-command surface and shell state survive every reload path |
| E1 | DOS/BIOS | Attribute and compact retained-low DOS/BIOS gateways, DPBs, SFT/CDS anchors, device-chain state, tables, buffers, stacks, and compatibility data | Internal structures, drivers, redirectors, filesystem, async interrupts, EXEC, and warm reboot pass |
| E2 | DOS/BIOS | Move only explicitly HMA-safe DOS state above the resident image; consolidate low bounce areas and workspaces whose lifetimes cannot overlap | A20-off callbacks and real-mode near pointers never target HMA; maximum buffers and sector sizes pass |
| E3 | Layout | Reorder or combine permanent allocations, eliminate avoidable MCBs and paragraph padding, and coalesce every recovered island into the main free block | VC's largest block grows by the measured amount; component accounting still reconciles |
| E4 | Placement | Put eligible post-provider permanent allocations in existing UMBs only when deterministic under the unchanged startup file | Conventional gain is real and free UMB remains at least retail's 47,888 bytes |
| E5 | Ceiling | Relocate the 1 KiB EBDA into verified already-owned slack, copy it before atomically updating `40h:0Eh`, and reclaim `9FC0h..9FFFh` | BIOS users, DMA, interrupts, and warm reboot pass; `INT 12h` becomes 640 KiB without a replacement allocation |
| F1 | Architecture | If B through E leave a measured remainder, choose the smallest of the EMM386 gateway split, DOS-low ownership redesign, or COMMAND boundary redesign that covers it with margin | A written byte budget shows why smaller changes cannot reach the target |
| F2 | Regression | Enforce VC largest block >=618,736, free UMB >=47,888, component budgets, identical inputs, and clean-build reproducibility in the local suite | Floors pass repeatedly and across the supported machine/option matrix; CI remains off until requested |

The immediate execution order is C2-C5: continue the OpenDOS-style small
EMM386 gateway from the now-relocated EMS services and shared helpers, taking
measured metadata wins with it. E1-E4 then apply the DOS placement ladder and
coalesce layout. E5 is a bounded 1,024-byte finishing step. HIMEM stays paused
unless the measured residual justifies it; deeper COMMAND work and F1 remain
fallbacks after those larger tranches establish the residual.

The EMM386 census is reproducible from a clean linker map:

```sh
python3 tests/report_emm386_residency.py --check \
  src/MEMM/MEMM/EMM386.MAP
```

The current map divides `_TEXT` at `IOTrap_Tab`: 490 low bytes precede the
boundary and 17,568 non-low bytes follow it. The report now accounts for
the complete 1,678-byte static low-image address range: a 388-byte real-mode
gateway, 176-byte GDT, 424-byte `_DATA`, 177-byte constants, 10-byte BSS,
13 bytes of alignment, and the 490-byte dual-mode `_TEXT` prefix. The full
1,024-byte initialization stack follows `LAST` and is discarded. The report
also divides the retained prefix by linked module and
`_DATA` into driver/messages, EMS tables, A20/OEM transition state, DMA, and
move-state ranges.
For the fixed configuration it then accounts for the complete 1,904-byte VDATA:
512 bytes of saved maps, 256 bytes of handle records, 512 bytes of names,
512 bytes of page arrays, six mappable-window indexes, a two-byte default DMA
page list, and 104 bytes of normal/alternate register sets. An
option-dependent alignment gap precedes the 512-byte protected stack; the fixed
configuration uses 2 alignment bytes, bringing the computed installed
allocation to 4,096 bytes, 32 bytes below retail and matching `MEM /D`.
Command-line counts
allow the same layout equation to be checked for other supported configurations.
C1 is complete; C2 now selects reductions from measured ranges.

### Decision gates

| Gate | Required evidence | Decision |
| --- | --- | --- |
| Layout independence | Complete: one-paragraph reductions exposed `SS`-relative accesses to `CURADD` in the released low copy of DOS's relocated tail; a disk read overwrote COMMAND's entry at `A061h` | The accesses now follow `CS` into the HMA, the binary layout test rejects the old encodings, and `/NUMHANDLES=24..32` boots after a real paragraph reduction |
| Attribution | All conventional ranges and every EMM386, HIMEM, and COMMAND resident symbol have an owner, lifetime, and size | EMM386 symbol ownership and HIMEM allocation-range accounting are complete; COMMAND plus deeper DOS and BIOS ownership remain |
| Safe compaction exhausted | Every low-risk candidate has an A/B component delta and VC largest-block delta | Calculate the exact architectural/layout remainder |
| Layout route chosen | EBDA destination and all low islands are proved safe, or their gains are rejected explicitly | Implement only gains that join the largest block |
| Architecture justified | DR-DOS measurements identify a roughly 5 KiB resident shell and OpenDOS a small EMM386 gateway as portable precedents | Try COMMAND/HMA first, then the EMM386 protected/XMS gateway; size later DOS/layout work from the new residual |
| Target reached | VC reports at least 618,736 bytes and usable UMB capacity is at least 47,888 bytes | Run all compatibility gates and establish regression floors |

At each gate, update the baseline rather than carrying projected savings
forward. The roadmap is complete only when the equation reaches zero on a clean
build and the fixed comparison remains reproducible.

The one-paragraph layout dependency is closed. A 15-byte EMM386 code reduction
changes SYSINIT's resize request from `0586h` to `0585h` paragraphs; both calls
return correctly. The smaller layout then starts COMMAND.COM at physical
`A060h`, where a disk read changed its expected `E9 CD 1B` entry to
`E9 00 E6`.

A live write watchpoint identified the instruction and registers rather than
inferring them from the value. DOS buffer code copied `NEXTADD=E600h` to
`CURADD` at `SS:7691h`; with the retained DOS stack segment `029Dh`, that
address is physical `A061h`. `CURADD`, `BUF_EMS_MAP_BUF`, and `low_ems_buf` are
linked after `DOS_LOW_GATE_END` and copied to the HMA with their code. The
512-byte workspace already used `CS`, but `CURADD` and the EMS map save/restore
path incorrectly selected the released low copy through `SS`.

All consumers now select the relocated copy through `CS`. The kernel-layout
test rejects the former SS-prefixed `CURADD` encodings and scans the complete
released code tail for any SS-relative target inside that tail. The audit found
and corrected one additional case: the private allocation query now reads
`hma_resident` from its HMA copy. The actual reduced driver boots every
`/NUMHANDLES=24..32` phase. Padding and load-order constraints are no longer
needed to protect this boundary.

The DMA register snapshot and final DMA page list remain low:
real-mode transition code refreshes the snapshot and initialization constructs
the page list before protected state is available. Moving either requires a
gateway or dual-copy design, not a linker move.

After layout independence is restored, the next implementation tranche is:

1. design the EMM386 low gateway around the existing locked XMS image, keeping
   its complete byte accounting current and bundling safe metadata reductions;
2. classify DOS low-prefix ownership and apply the HMA/XMS/bounded-UMB
   placement ladder;
3. coalesce layout and take the bounded EBDA paragraph after proving its
   destination; and
4. use the measured residual to decide whether HIMEM, COMMAND, or a deeper resident
   boundary redesign is warranted.

The first COMMAND/HMA tranche is complete and further shell relocation is
paused: catalogs, character services, and the message engine are high. Resume
COMMAND only as a coherent interrupt/data redesign after the larger EMM386 and
DOS opportunities have been measured.

Every tranche retains maximum-option, EMS, DMA, runtime-mode, warm-reboot,
shifted-load, 286 where applicable, and paired VC tests.

Two HIMEM shortcuts have already been rejected and must not be retried without a
different design. Recovering saved caller registers from fixed stack offsets
passed narrow probes but hung the paired boot because the call depth is not a
stable ABI. Carrying source/destination move errors in `BL` corrupts the `BX`
handle consumed by endpoint resolution. The retained implementation therefore
keeps explicit caller state and move-error state until a reentrant replacement
has its own stable storage or calling convention.

Making `umb_count` byte-sized is also rejected on the 286 path: each consumer
would need an additional instruction to clear the high half of its loop count,
growing resident code by more than the one data byte recovered.

Sharing the two EMM386 fatal-error messages through one conventional output
buffer is deferred. A prototype reduced `_DATA` by 76 bytes but stalled after
EMM386's installation banner. Adding the same 209 bytes as inert protected-text
padding boots, so protected-suffix growth is not the cause; reading the
template through the writable `VDMCA_GSEL` alias did not fix the prototype.
The unresolved dependency is therefore in the copy mechanism, its addressing,
or the destination layout. Retry only with a deliberate exception-screen probe
that proves the buffer before and after return to real mode.

Splitting `MEMM386.EXE`'s utility entry, installation check, and link routine
beyond `IOTrap_Tab` is also rejected for now. It saved 80 installed bytes, but
the extended EMS sequence hung while returning from function 58h after earlier
alter-map and move operations. Tracing proved that the function handler,
`int67_Entry`, and `_AutoUpdate` completed; instrumentation changed the later
failure point, demonstrating a hidden layout-sensitive return dependency.
Retry only after the real/virtual return frame and offset ownership are fully
accounted, and require the complete EMS 4.0 sequence rather than narrow probes.

Inlining the single-use `MaskIntAll` and `RestIntMask` wrappers is likewise
rejected for now. It reduced the installed allocation from 5,088 to 5,072
bytes and passed the ordinary EMM386 boot, but the extended EMS 4.0 lifecycle
hung. Keep the wrappers until the transition return-frame and layout dependency
is explained; any retry must pass the complete extended sequence.

Three later compaction probes show that the earlier stack fix did not close all
layout dependencies. Shortening the resident privileged-error dialog by 28
data bytes moved `_TEXT` one paragraph earlier and stalled `/NUMHANDLES=24`.
Independently,
shrinking the retained `GetPageFrameAddress` code by 15 bytes left `_TEXT` at
the same segment but moved the compacted VDATA/stack break one paragraph
earlier; it produced the same stall. A 14-byte HIMEM handle-scan reduction
crossed HIMEM's default break, passed `/NUMHANDLES=24`, and stalled at 25.
All three reach the installation banner and then fail before the shell prompt,
while ordinary configurations and focused component suites pass. Paired
instruction traces disprove the earlier reflected-`INT 21h/AH=4Ah` hypothesis:
the passing `BX=0586h` and reduced `BX=0585h` resizes both return, and execution
remains functionally aligned until DOS transfers control to COMMAND.COM. A live
watchpoint then identifies DOS buffer code—not EXEC owner restoration—as the
writer: an SS-relative update of the relocated-tail `CURADD` word lands at
COMMAND offset 1 in the reduced layout. CS-relative tail state closes this
dependency and permits the reduction to remain.

The next HIMEM paragraph exposed a separate EMM386 prerequisite. A prototype
packed HMA ownership into `/HMAMIN=`'s unused high bit and shared the identical
local/global A20 success tails. Focused HMA, A20, XMS 3, option-limit, and UMB
transaction/model tests passed, and the default HIMEM break moved from `0B9Dh`
to `0B8Bh`. The fixed hard-disk boot then stalled immediately after EMM386's
installation banner when DOS released the resulting paragraph. Diagnostic
padding and `/NUMHANDLES=` sweeps proved that the symptom followed the load
paragraph rather than the packed HIMEM state.

Historical A/B builds narrow the dependency to `1dec794`, which moved 19 bytes
of allocation state from DGROUP to LAST. Its parent `75aa2da` boots behind
stock HIMEM `/NUMHANDLES=29`; `1dec794` and later builds stall. Restoring those
variables to DGROUP fixes the shifted boot, but leaving them discardable and
adding an equal DGROUP pad also fixes it. A 12-byte pad moves `_TEXT` and all
later segments by one paragraph and exactly cancels HIMEM's one-paragraph load
shift; that configuration boots as well. The variables are therefore not live
after installation. At that point the evidence identified an address or
page-boundary assumption in EMM386's protected-text layout.

The root cause of that earlier failure was the final VDATA compaction, not the
discarded variables.
`CompactVData` moved the dynamic arrays below `_TEXT` and lowered `driver_end`,
but left `VDMS_GSEL` pointing at the old ring-0 stack beyond that break. DOS was
therefore allowed to overwrite a live exception stack; the time and address of
the overwrite determined whether the first continuation survived. Compaction
now rebases `VDMS_GSEL` at the new rounded break and retains its complete
512-byte stack. The old extra guard paragraph is unnecessary because the base
and length are explicit. Hard-disk boots pass for `/NUMHANDLES=24..32`, spanning
the previously failing phases, and the runtime mode, EMS 4.0, capacity, UMB,
DMA, fault-rollback, and two-boot warm-reset paths remain required gates.

### Milestones to the target

The work proceeds by evidence, not by assuming all component excess is
recoverable:

1. **Complete: finish attribution.** The checked linker-map reports cover
   HIMEM, EMM386, COMMAND, the fixed HMA layout, every byte of the DOS low
   prefix, and every byte of the selected BIOS image. E1 now adds address and
   lifetime proofs before relocating or compacting a range.
2. **Take safe component wins.** Finish table, field, duplicate-code, init-state,
   and alignment audits. Require an A/B result and focused maximum-option tests
   for every retained change.
3. **Reach component parity or document the irreducible difference.** Target
   HIMEM 1,104, EMM386 4,128, and COMMAND 2,960 bytes as comparison points, not
   hard implementation limits. If all three are matched, the projected largest
   block is 610,144 bytes.
4. **Recover real layout bytes.** Safely relocating the EBDA raises that
   projection to 611,168 bytes. At least another 7,568 bytes must then come from
   DOS/BIOS low-layout compaction, fragmentation removal, safe high placement,
   or making one or more components smaller than retail.
5. **Cross and defend 618,736.** Once the fixed image reaches the retail floor,
   run the full local release suite, maximum-capacity configurations, warm
   reboot, and paired UMB comparison. Add a regression assertion for the largest
   conventional block and retain any margin rather than stopping at an
   alignment-sensitive exact tie.

After each milestone, update the table above with measured—not projected—bytes.
If a saving changes a component allocation but not the largest block, classify
the resulting island and keep it open as layout work.

### 1. Make each byte attributable

Before another structural change, turn the paired boot comparison into a
repeatable local measurement that records the VC largest block, `MEM /D` MCB
chain, component sizes, first free paragraph, conventional-memory ceiling, and
UMB regions for both systems. Keep the hardware, startup files, VC binary, and
environment size identical. Add retained-allocation boundaries from linker maps
or generated manifests for HIMEM, EMM386, COMMAND, DOS, and BIOS.

For each experiment, report both the allocation-size change and the largest-
block change. Classify any difference as resident code, resident data, alignment
or MCB overhead, an unavailable conventional range, or fragmentation. This is
the prerequisite for resolving the 8,592-byte layout row rather than moving it
between labels.

`tests/capture_vc_memory_comparison.py` implements the paired capture. It
rejects images whose `CONFIG.SYS` or VC binary differs, boots each private copy,
runs `MEM /D`, opens VC 4.05 Memory Info, and writes a Markdown comparison with
the raw conventional MCB rows. Its focused probe also records `INT 12h`, the
BIOS Data Area memory-size word, and the EBDA segment after CONFIG.SYS. Run it
against prepared current and retail hard disk images:

```sh
python3 tests/capture_vc_memory_comparison.py \
  CURRENT.IMG RETAIL-622.IMG out/vc-memory-comparison.md
```

The current milestone reproduces 607,936 versus 618,736 bytes, the component
figures below, a conventional ceiling of `9FC0h` versus retail's `A000h`, and
the 1,216-byte local UMB advantage. This completes the repeatable measurement
foundation; generated reports remain build evidence rather than tracked
documentation.

The report also records every VC row's address, block count, grouped payload,
and owner. These rows belong to the VC snapshot after `MEM` exits; the raw
`MEM /D` rows were captured while MEM itself was allocated. The two views are
therefore displayed separately and must not be added together. In the current
VC snapshot, the grouped `DOS 6.22` payload is 27,856 bytes versus retail's
18,880, an 8,976-byte difference that includes the memory managers and retained
DOS layout. COMMAND contributes another 880 bytes, while the one-kilobyte
ceiling difference acts at the opposite end of the largest block. Phase A2
must decompose that DOS aggregate without mixing in the earlier MEM process
image.

The generated owner-to-owner spans provide an exact top-level reconciliation:

| Span | Difference |
| --- | ---: |
| System start through COMMAND start | 8,896 bytes |
| COMMAND start through VC start | 880 bytes |
| VC start through conventional free block | 0 bytes |
| Conventional ceiling | 1,024 bytes |
| **Total** | **10,800 bytes** |

The pre-COMMAND system span contains EMM386's 32-byte advantage, a 1,488-byte
HIMEM excess, and a 16-byte advantage in the other configured system tables.
Subtracting those measured components leaves **7,456 bytes** of retained
DOS/BIOS payload and layout. Owner-level accounting and A3 are closed; E1 must
now prove which exact ranges can move or shrink without changing their public,
interrupt, device, disk, or A20-off contracts.

The first A3 map census is reproducible with:

```sh
make test-dos-bios-residency
```

For the current build, `DOS_LOW_GATE_END` is 6,816 linked and paragraph-rounded
bytes below the HMA. The HMA copy contains 39,440 bytes
after its fixed `0010h` entry offset, and DOS's `LAST` initialization segment is
1,795 discardable bytes. The BIOS has 15,888 linked bytes of resident-code
capacity and 20,074 discardable SYSINIT bytes; its possible hardware-selected
resident boundaries range from 8,224 bytes for floppy-only through 12,384 bytes
when all optional legacy blocks are retained. The fixed QEMU comparison selects
one hard disk, no 96-TPI or legacy AT-ROM extension, a CMOS clock, and no K09
extension. `ENDONEHARD` contributes and rounds to 8,320 bytes; the
contiguous relocated 121-byte day converter and 5-byte BCD converter establish
the exact `2100h` or 8,448-byte resident BIOS boundary.

The DOS low prefix consists of 3 bytes of loader entry, 1,072 bytes of
constants, 1,783 bytes of mutable data, 2,365 bytes of tables, 1,592 bytes of
code, and one alignment byte. The checked report assigns every byte of the
constants, data, tables, and code to an ownership range. Exact coverage is not
permission to move a range: near pointers, asynchronous entries, device
callbacks, and A20-off paths must first be classified.

The constants census isolates 301 bytes of bootstrap SFT, 261 bytes of console
buffers, 119 bytes of UMB/lock state, 200 bytes of nucleus and SHARE-compatible
state, and smaller request, error, process, and identity ranges. The table
census isolates 623 bytes of error maps and INT 21 dispatch, 795 bytes of
country/case-folding/messages, 283 bytes of swap/fake-version state, 256 bytes
of FCB character classes, and the remaining communication and lookup tables.
These are ownership budgets only; E1 must still prove each range's address and
lifetime contract before selecting HMA, relocation-safe XMS, or UMB storage.

The selected BIOS census likewise covers all 8,448 bytes. Its largest ranges
are 1,803 bytes of generic disk IOCTL/INT 2F services, 1,575 bytes of core data
and device headers, 1,480 bytes of disk transfer/error paths, 751 bytes of
media-change/BPB services, and 741 bytes of sector/low-level I/O. The remaining
2,098 bytes cover console, auxiliary, printer, clock, model/vector, disk-init,
descriptor, helper, loader, and alignment ranges. BIOS work should start with
the large disk paths, but only after separating always-addressed entry points
and callback state from compactable helpers.

The checked CODE census now covers every byte below `DOS_LOW_GATE_END`: 12
bytes of EMS user-map storage, 771 bytes of core system-call dispatch, 70 bytes of HMA
driver request entry, 76 bytes of low DPB pointer workspace, 11 bytes of the
HMA driver/XMS tail, 387 bytes of absolute-disk services, 199 bytes of shared
system/FCB return and error handling, and 68 bytes of the INT 2F gateway. The
largest next classification targets are therefore the 771-byte dispatcher and
387-byte absolute-disk gateway; the DPB, asynchronous entry, return, and INT 2F
ranges remain low until their pointer and A20-off contracts are proved.

The fixed VC image's grouped pre-MCB payload is 15,264 bytes: the exact
6,816-byte paragraph-rounded DOS gateway plus the exact 8,448-byte selected
BIOS image. The following system MCB contains 12,592 bytes; enumerated
components occupy 12,480 bytes, leaving 112 bytes. Together with 32 bytes of
group-level MCB/gap overhead, these ranges account for the current 15,408-byte
non-component system footprint. Retail's corresponding remainder is 7,952
bytes, producing the already measured 7,456-byte excess. The likely
large gains are therefore a smaller DOS low-gateway architecture and BIOS
resident-code compaction; the 112-byte system-MCB residue and alignment are
bounded secondary opportunities.

### Complete opportunity inventory and execution road

Every presently credible route to the target is listed below. Byte figures are
measured excesses or hard ceilings, not forecasts. An unmeasured candidate earns
no credit until a paired VC capture shows that its paragraphs joined the largest
block.

| Order | Opportunity | Evidence or ceiling | Next actionable result |
| ---: | --- | ---: | --- |
| Complete | Split the remaining COMMAND service census | The normal catalogs and 1,166-byte relocatable code range are high; the checked 955-byte low range is now divided into nine ownership spans | 820 bytes are asynchronous or registered handlers; independent helpers are gateway-scale |
| Paused | Move more COMMAND cold state high or transient | COMMAND remains 880 bytes above retail and DR-DOS demonstrates a smaller resident shell | Resume as a coherent interrupt/data redesign after larger workstreams, preserving reload and asynchronous paths |
| Complete | Close the EMM386 mode-transition regression | Narrowed EMS counters retained stale 16-bit C declarations and two FRS paths retained word reads; inactive modes also disabled physical A20 despite an enabled logical client state | C and assembly widths now agree, the return path preserves logical A20 state, and default, `AUTO`, `RAM`, and `NOEMS` boot with `DOS=HIGH` in the address-phase gate |
| 2 | Complete the EMM386 low gateway | The active 4,096-byte allocation is 32 bytes below retail after fixing the inactive-mode A20 return, compacting internal fast-register-set flags, and removing real-mode contribution padding; services, return and A20/NMI trap handling, protected `RetReal`, stack-selector conversion, OEM mapping/parity, and the `GoVirtual` continuation execute from locked XMS | Redesign the remaining transition, DMA, and fault gateways for further headroom; preserve inactive `AUTO` and every EMS map |
| 2 | Compact EMM386 metadata while changing that boundary | The loader stack is discarded, duplicate PTE offsets and inverse segment index are gone, physical-window segments, public `Pn=` identifiers, DMA pages, mappable-window indexes, bounded counters, and parity-vector state are runtime-sized, narrowed, derived, shared, or protected-high; protected entry/services/helpers are high, the two-function control gateway is table-free, the production GDT omits six debugger and six unused legacy descriptors, and `NOHIMEM` hooks are absent | Take further independently testable VDATA, table, and alignment wins only when they create better-than-retail margin or support the gateway design |
| 5 in progress | Census and relocate eligible DOS low state | Part of the 7,456-byte DOS/BIOS remainder; 6,816 bytes allocated locally after discarding initialization-only data, removing dead state, sharing EXEC workspace, and eliminating CLOSE scratch state | Continue the address/lifetime audit, then apply HMA, relocation-safe XMS, and bounded UMB placement |
| 6 in progress | Compact the selected BIOS resident image | Part of the same 7,456-byte remainder; the fixed hardware path is now exactly 8,448 bytes | Continue map-guided compaction without changing BIOS-visible services |
| 7 | Remove MCB, allocation-order, and paragraph fragmentation | 112 bytes inside the system MCB plus 32 bytes group-level overhead are bounded; further islands need a live map | Make every recovered paragraph grow VC's largest block rather than a separate hole |
| 8 | Place eligible permanent allocations in existing UMBs | Local free UMB exceeds retail by only 1,216 bytes | Accept only deterministic placement that leaves at least 47,888 usable UMB bytes |
| 9 | Recover the EBDA ceiling paragraph | Exactly 1,024 bytes | Use already-owned proved-safe storage, update the BDA atomically, then test BIOS, DMA, interrupts, and reboot |
| 10 | Revisit HIMEM only if the measured residual requires it | 1,488-byte excess over retail; incremental work paused | Resume only with a paragraph-scale, map-supported opportunity and preserve every existing gate |
| 11 | Redesign the DOS-low or COMMAND boundary further | Architectural fallback | Choose the smallest design with a byte budget that covers the remaining measured gap and compatibility margin |

The completed broad DR-DOS checkpoint suggests the architectural order, but a
focused clean-room revalidation is the next planning gate before more layout
work: confirm the documented high-memory policies against a live comparable
DR-DOS system, reconcile its larger block to owners, and turn only externally
supported techniques into local byte budgets. Then extend the EMM386 low
gateway and apply the DOS placement ladder in the resulting order. The `M5`
plus `DOS=HIGH` transition regression is closed and remains a mandatory gate
for later boundary changes. The initial COMMAND/HMA gain is retained, but
deeper shell work is paused. Recover the bounded EBDA paragraph only near the
end, and revisit HIMEM only for a measured residual. Recalculate the success
equation after every retained step and keep both the conventional and UMB
floors visible.

### DR-DOS clean-room adoption register

Published DR-DOS manuals define the externally promised placement policies;
the controlled measurements below quantify their effects. No DR-DOS source
code is permitted. Runtime inspection is limited to public interfaces,
allocation maps, addresses, and lifetimes and must not be used to reconstruct
proprietary instruction sequences.

**Next priority:** revalidate the highest-value DR-DOS findings before further
memory-layout implementation. Start from published vendor documentation,
reproduce the pinned live comparison, and vary one documented control at a
time. The deliverable is an owner-reconciled adoption table that ranks local
changes by expected largest-block gain and compatibility risk. This is a
focused follow-up to the completed broad survey, not a new product survey, and
must not use DR-DOS source code. After that gate, continue the small EMM386
gateway and move eligible DOS state through the measured placement ladder.

Use this sequence:

1. inventory the relevant vendor documentation for kernel, shell, buffer,
   driver, UMB, HMA, XMS, EMS, and page-frame placement;
2. reproduce the fixed DR-DOS baseline on the same CPU, RAM, BIOS, startup
   policy, and tools used for the MS-DOS 6.22 comparison, recording media hashes;
3. vary one documented control at a time, including `HIDOS`, `HIBUFFERS`, the
   memory manager, EMS page-frame policy, and high-loading policy;
4. capture the largest conventional block, MCB/UMB ownership, HMA usage,
   XMS/EMS reports, resident device spans, and relevant public API behavior;
5. reconcile every material delta to a documented policy or mark it unknown;
   do not infer implementation details from the binary; and
6. translate only portable results into local owners, byte budgets, compatibility
   risks, and regression gates, then resume implementation in ranked order.

For this follow-up, answer these questions in order:

1. which documented DR-DOS configuration produces the best ordinary,
   compatibility-safe largest block on the fixed comparison machine;
2. how much of its advantage belongs to COMMAND/kernel HMA placement, resident
   memory-manager gateways, buffers, UMB policy, allocation order, and the
   conventional-memory ceiling;
3. which gains remain when low-memory, text-video, relocated-EBDA, and other
   optional compatibility tradeoffs are excluded; and
4. which remaining techniques map to a named local owner and a public contract
   that can be tested without knowledge of proprietary implementation details.

Reuse the existing capture tooling and pinned media. Add a new probe only when
an owner, lifetime, placement policy, or public API result remains unresolved;
record commands, hashes, deltas, and conclusions, but keep generated images and
captures untracked.

The checkpoint is complete when the ordinary-mode advantage is accounted for
well enough to choose our next design, optional compatibility tradeoffs are
separated from the main score, and every proposed adoption has a local owner
and testable contract. Additional DR-DOS runs then return to being targeted
fallbacks for unresolved owner, lifetime, or public API questions.

| Priority | Externally evidenced technique | Local budget and owner | State and decisive gate |
| --- | --- | --- | --- |
| Paused | Keep the kernel and permanent shell payload in HMA; documented for 286-class HIDOS and measured on both DR-DOS generations | COMMAND is 880 bytes above retail; 15,485 bytes remain in the local DOS-owned HMA tail | First tranche complete: catalogs and the 1,166-byte relocatable code range recover 2,480 paragraph-rounded bytes. Resume only as a coherent interrupt/data redesign with reload, `INT 2Eh`, `INT 24h`, A20, DOS=LOW, `/MSG`, and real-286 gates |
| 1 | Retain only a small conventional/UMB gateway for the 386 memory manager; OpenDOS reports a 1,200-byte conventional device range and an 800-byte UMB owner | Active EMM386 is 32 bytes below retail after preserving the inactive-mode A20 return, compacting internal fast-register-set flags, and removing real-mode contribution padding, while services, return/A20/NMI trap handling, protected `RetReal`, stack-selector conversion, OEM mapping/parity handling, parity-vector state, and the `GoVirtual` continuation are high | Continue toward the smaller owner by redesigning remaining transition, fault, and DMA entries; all EMS maps, modes, shifted loads, and warm reboot must pass |
| 2 | Place mutable DOS structures high, then prefer HMA for buffers; DR-DOS 6 measures a 12,800-byte conventional move and documents `HIDOS`/`HIBUFFERS` | The local DOS/BIOS remainder is 7,456 bytes; only 1,216 bytes of UMB advantage may be spent before falling below retail | Classify each owner, then use HMA, relocation-safe XMS, and finally deterministic UMB placement; filesystem, device, redirector, EXEC, A20-off, and rollback paths must pass |
| Config | Omit the EMS page frame when applications do not require it | Already represented by the fixed `NOEMS` comparison | Preserve as a configuration choice and test both framed and frameless EMS; it is not an implementation saving |
| Excluded | Recover text-video and low-memory ranges only as explicit compatibility modes | DR-DOS can add 96 KiB of text-video space, but neither ordinary comparison uses it | Excluded from the parity score; any future opt-in mode must withdraw the range before incompatible graphics use |
| Finish | Relocate EBDA storage | Exactly 1,024 bytes at the fixed ceiling; not used by either ordinary DR-DOS result | Finishing step only, into already-owned proved-safe storage with BIOS, DMA, interrupt, and reboot coverage |

The evidence sources are the vendor [DR-DOS 6 Optimization and Configuration
Tips](https://bitsavers.org/pdf/novell/dr_dos/DR_DOS_6.0_Optimization_and_Configuration_Tips_199109.pdf),
the [DR-DOS 6 User Guide](https://www.bitsavers.org/pdf/novell/dr_dos/DR_DOS_6.0_User_Guide_2ed_199108.pdf),
the [Novell DOS 7 User Guide](https://bitsavers.org/pdf/novell/dr_dos/DR_DOS_7_User_Guide_1993.pdf),
and hashed DR-DOS media from the [PCjs DR-DOS 6 archive](https://www.pcjs.org/software/pcx86/sys/dos/dresearch/6.00/).
Generated captures remain untracked. The baseline comparison is complete; do
not repeat broad DR-DOS surveys. DR-DOS source code and reconstruction of
proprietary instruction sequences remain out of scope.

### Completed baseline investigation: DR-DOS HMA-mode memory

**Status and priority:** the clean-room baseline and focused mechanism
checkpoint are complete. The first coherent COMMAND/HMA relocation is complete
and deeper shell work is paused. Apply the validated lessons by building the
small EMM386 low gateway, then introducing the HMA/XMS/UMB placement ladder for
movable DOS state.

The research goal was to explain, byte by byte where possible, why a
comparable DR-DOS system exposes a larger conventional block in HMA mode and to
identify techniques that can safely improve this implementation. Do not obtain,
inspect, or use DR-DOS source code. Published documentation, normal program and
API behavior, executable metadata, runtime memory maps, debugger observations,
and measurements of legitimately available binaries are allowed. Record
techniques and externally visible contracts, never copied code or instruction
sequences.

The focused checkpoint uses this reproducible method:

1. **Build reproducible images.** Use the same 8 MiB 386-class hardware profile,
   disk geometry, VC 4.05 binary, shell environment, and semantically equivalent
   `CONFIG.SYS`/`AUTOEXEC.BAT` settings for this DOS, retail MS-DOS 6.22, and
   each available DR-DOS/Novell DOS release. Record exact versions and hashes;
   repeat supported kernel/XMS cases on the established 286 profile separately.
2. **Establish a minimal HMA baseline.** Boot only the kernel, its documented
   XMS/UMB manager, COMMAND, and VC. Match `FILES`, `FCBS`, `BUFFERS`,
   `LASTDRIVE`, `STACKS`, environment size, EMS-page-frame policy, and loaded
   drivers. Do not count extra low-memory, text-video, or relocated-EBDA modes
   in the fair baseline.
3. **Capture the full layout.** Record VC's largest block and totals, `MEM` or
   the vendor equivalent, `INT 12h`, BDA conventional-memory and EBDA fields,
   the MCB chain, device and system allocations, UMB regions, EMS frame, first
   free owner, COMMAND boundary, and conventional ceiling. Reconcile the
   largest-block result as owner-to-owner spans as done for MS-DOS.
4. **Toggle one documented policy at a time.** The decisive matrix covers
   kernel-high/HMA, `HIDOS`, `HIBUFFERS`, EMS-frame policy, low-memory recovery,
   text-video recovery, and `/XBDA`. Driver/TSR-high placement, UMB linking, and
   load order are established local features rather than explanations of the
   kernel baseline; DPMS serves only as a published architectural precedent.
   Do not hold the checkpoint open for those non-decisive controls.
5. **Probe observable contracts.** Determine HMA ownership and A20 behavior,
   XMS/EMS/UMB API results, allocation order, initialization-versus-resident
   size, buffer placement, device-chain ownership, warm reboot behavior, and
   compatibility fallbacks. Use runtime watches only to establish ownership and
   lifetime boundaries, not to reproduce proprietary implementation details.
6. **Classify each gain.** Mark it as a portable implementation technique, a
   configuration choice already available here, an optional compatibility-risk
   extension, or an unexplained delta requiring another controlled probe. A
   DR-DOS number alone is not evidence for a design change.
7. **Produce an adoption table.** For every portable technique, name the local
   owner/range it could replace, expected largest-block gain, prerequisites,
   compatibility risks, and focused tests. Reorder the EMM386, DOS/BIOS,
   COMMAND, layout, and EBDA backlog only after this table reconciles the
   observed DR-DOS advantage.

The investigation is complete when identical-input captures reproduce each
system, every material DR-DOS advantage is attributed or explicitly bounded as
unknown, and each adoptable technique has a local byte budget and regression
gate. Generated disk images, memory dumps, and reports remain untracked build
evidence; durable commands, hashes, conclusions, and decisions belong here or
in a focused checked-in measurement script.

#### First controlled result: OpenDOS 7.01

`tests/capture_drdos_memory.py` builds temporary boot media from a user-supplied
Caldera OpenDOS 7.01 binary archive, inserts the same VC 4.05 binary used by the
MS-DOS comparison, and captures five configurations on the fixed QEMU `pc`, 486
CPU, 8 MiB profile. It neither reads nor retains DR-DOS source or binary files.
The harness rejects media or VC identity drift unless explicitly overridden,
records the emulator identity, retains every normalized VC owner row, and can
preserve the raw VC, `MEM /A`, and ceiling outputs with `--evidence-dir`.
The tested `DODL701.EXE` SHA-256 is
`4d25bb3f10cf13596c7b962ab7fdd4f9165e80bef318b72e22b450817b8ee151`;
VC's SHA-256 remains
`b408f14da5bcba174f5e86107437b22b2863ee6ec72f79bdadf1b812607405fb`.
Reproduce the matrix with:

```sh
python3 tests/capture_drdos_memory.py \
  DODL701.EXE out/msdos622-original-vc405.img \
  out/drdos-memory-investigation.md
```

All variants use `FILES=30`, `FCBS=4,0`, `LASTDRIVE=Z`, `STACKS=9,256`,
15 buffers, and a 512-byte shell environment. EMS and its 64 KiB frame are
disabled. VC runs after the vendor `MEM /A` process exits.

| Configuration | VC largest block | Pre-COMMAND system span | COMMAND span | Free UMB | Free HMA |
| --- | ---: | ---: | ---: | ---: | ---: |
| Kernel and buffers low; no memory manager | 579,840 | 53,376 | 6,608 | 0 | 0 |
| HIMEM; `DOS=HIGH`; `HIDOS=OFF`; `BUFFERS=15` | 618,256 | 20,256 | 1,312 | 0 | 9,092 |
| EMM386; no frame; `DOS=HIGH`; `HIDOS=OFF`; `BUFFERS=15` | 622,480 | 16,016 | 1,312 | 117,968 | 9,092 |
| Same, with `HIDOS=ON` | **627,488** | **11,008** | **1,312** | 112,976 | 9,092 |
| Same, with `HIBUFFERS=15` | 627,488 | 11,008 | 1,312 | 112,976 | 9,092 |

The ordinary OpenDOS result is 8,752 bytes above retail MS-DOS 6.22 and 31,664
bytes above this implementation. Its advantage over retail reconciles exactly:

| Owner-to-owner contribution | OpenDOS 7.01 | Retail MS-DOS 6.22 | OpenDOS gain |
| --- | ---: | ---: | ---: |
| System start through COMMAND start | 11,008 | 18,992 | 7,984 |
| COMMAND start through VC start | 1,312 | 3,104 | 1,792 |
| VC start through free block | 12,720 | 12,720 | 0 |
| Conventional ceiling loss | 1,024 | 0 | -1,024 |
| **VC largest-block advantage** | **627,488** | **618,736** | **8,752** |

The current implementation has the same 1 KiB ceiling loss as OpenDOS, so its
31,664-byte deficit to OpenDOS is entirely below COMMAND: 26,512 bytes in the
pre-shell system span and 5,152 bytes in COMMAND's span.

The controlled transitions identify four mechanisms:

- `DOS=HIGH` moves 28,464 bytes of kernel code, 3,968 bytes of DOS BIOS code,
  7,980 bytes of buffers, and 5,296 bytes of COMMAND into the HMA. OpenDOS
  reports 9,092 HMA bytes still free. The high COMMAND portion explains the
  5,296-byte reduction from its low configuration and 1,792-byte advantage over
  retail COMMAND; this is a direct precedent for our resident/transient work.
- Replacing standalone HIMEM with the integrated no-frame EMM386 configuration
  reduces the conventional system span by 4,240 bytes and grows VC's block by
  4,224 bytes. The runtime map exposes only a 1,200-byte installed-device range
  inside the conventional system block and an 800-byte EMM386 UMB allocation.
  This supports a small-low-gateway architecture, but does not yet locate all
  protected state; attribution needs runtime ownership probes rather than a
  conclusion from the 179,585-byte executable size.
- `HIDOS=ON` moves exactly 4,992 payload bytes of DOS system data into a UMB.
  Its 16-byte MCB accounts for the 5,008-byte conventional gain. This is pure
  relocation, not compaction, and maps directly to the open DOS-low ownership
  and deterministic-high-placement workstreams.
- `HIBUFFERS=15` produces no additional delta on OpenDOS 7.01 because the
  ordinary `BUFFERS=15` configuration already reports all 7,980 buffer bytes in
  the HMA. DR-DOS 6 documentation describes `HIBUFFERS` as the explicit policy,
  so this behavior must be treated as a version difference until DR-DOS 6 is
  measured.

OpenDOS leaves `INT 12h`, the BDA conventional-memory word, and the EBDA at
639 KiB, 639 KiB, and `9FC0h`. Thus its ordinary advantage is not produced by
the risky first-64-KiB or video-memory extensions, nor by EBDA recovery. Those
remain separate experiments. This OpenDOS pass validates the tooling and shows
that the later EMM386 design no longer spends the 28 KiB UMB used by DR-DOS 6;
the actual DR-DOS 6 comparison follows.

#### Primary result: DR-DOS 6.0

The same tool accepts the PCjs archival JSON representation of the original
Digital Research 1.2 MiB startup disk, verifies its declared disk MD5, and
creates only temporary working images. The tested JSON SHA-256 is
`8902dc7040ae08c2941c48ce0540277ae2f3005f8e564ea45a602f414286b40f`;
the decoded disk MD5 is `a01ecc2548744606c0d8baa74daa64ae`. The image and
directory listing are published at [PCjs DR-DOS
6.00](https://www.pcjs.org/software/pcx86/sys/dos/dresearch/6.00/). Reproduce
the capture with:

```sh
python3 tests/capture_drdos_memory.py \
  DRDOS600-STARTUP.json out/msdos622-original-vc405.img \
  out/drdos6-memory-investigation.md \
  --evidence-dir out/drdos6-memory-evidence
```

The strengthened harness reproduced all nine DR-DOS 6 variants under QEMU
11.1.1 with the expected media, decoded-disk, and VC hashes. The aggregate
figures below are unchanged; the report now also records raw-evidence hashes
and normalized owner rows for each variant. A separate fresh boot runs the
source-free public-interface recorder, so its queries cannot perturb the VC
measurement.

| Configuration | VC largest block | Pre-COMMAND system span | COMMAND span | Free UMB | Free HMA |
| --- | ---: | ---: | ---: | ---: | ---: |
| Kernel and buffers low; no memory manager | 571,328 | 62,240 | 6,256 | 0 | 0 |
| HIDOS driver; kernel high; DOS data low | 611,808 | 26,752 | 1,264 | 0 | 18,800 |
| EMM386; no frame; kernel high; DOS data low | 615,024 | 23,520 | 1,264 | 90,096 | 18,800 |
| Same, with `HIDOS=ON` | **627,824** | **10,720** | **1,264** | 77,280 | 18,800 |
| Same, with `HIBUFFERS=15` | 627,824 | 10,720 | 1,264 | **84,688** | 10,880 |

The public-interface pass narrows the mechanism boundary without exposing
implementation details:

| Configuration | XMS | A20 | Largest XMS UMB | EMS |
| --- | --- | ---: | ---: | --- |
| Kernel and buffers low | unavailable | — | — | unavailable |
| HIDOS kernel high | 2.00; driver 2.50 | on | unavailable | unavailable |
| EMM386, no frame, DOS data low | 2.00; driver 2.50 | on | 90,096 bytes | unavailable |
| Same, `HIDOS=ON` | 2.00; driver 2.50 | on | 77,280 bytes | unavailable |
| Same, `HIBUFFERS=15` | 2.00; driver 2.50 | on | 84,688 bytes | unavailable |
| EMM386 with automatic frame | 2.00; driver 2.50 | on | 15,568 bytes | 4.0; `CC00h`; 430 of 440 pages free |

The XMS UMB query matches VC's free-UMB total exactly in every EMM386 case.
`INT 21h/AX=5802h` returns carry set in every DR-DOS 6 configuration, so its
high-placement policy does not depend on publicly linking the MS-DOS UMB arena.
`/FRAME=NONE` removes the EMS interface rather than merely hiding a frame;
`/FRAME=AUTO` supplies EMS 4.0. These are observable API contracts, not evidence
about proprietary internal code.

The isolated HMA transaction is also complete. `HIDOS.SYS`, EMM386 with
`HIDOS=ON`, and EMM386 with `HIBUFFERS=15` all report A20 enabled, reject a
whole-HMA request with XMS error `91h` (already allocated), and report A20 still
enabled afterward. No release is issued after a failed request. Thus DR-DOS's
reported free-HMA value is unused tail inside the system-owned HMA allocation,
not a second allocatable HMA. In the ordinary `HIDOS=ON`, `HIBUFFERS=15`
configuration, the complete public-interface record is byte-for-byte identical
before and after a controlled warm reset.

DR-DOS 6 therefore leaves 9,088 bytes more than retail MS-DOS 6.22 and 32,000
bytes more than this implementation. The fair ordinary comparison reconciles
without counting recovered low or video memory:

| Owner-to-owner contribution | DR-DOS 6.0 | Retail MS-DOS 6.22 | DR-DOS gain |
| --- | ---: | ---: | ---: |
| System start through COMMAND start | 10,720 | 18,992 | 8,272 |
| COMMAND start through VC start | 1,264 | 3,104 | 1,840 |
| VC start through free block | 12,720 | 12,720 | 0 |
| Conventional ceiling loss | 1,024 | 0 | -1,024 |
| **VC largest-block advantage** | **627,824** | **618,736** | **9,088** |

The transitions explain how it gets there:

- Kernel-high moves 37,952 bytes of kernel, 3,552 bytes of DOS BIOS, and 4,992
  bytes of COMMAND to the HMA. It reduces the pre-COMMAND system span by 35,488
  bytes and COMMAND by 4,992, growing VC's block by 40,480 bytes. The allocations
  are sequential apart from 224 bytes of HMA gaps/overhead and leave 18,800
  bytes free before moving buffers.
- Replacing the 286-capable HIDOS provider with EMM386 reduces the conventional
  system span by another 3,232 bytes and grows VC's block by 3,216 bytes. With
  the EMS frame disabled, DR-DOS 6 explicitly places 28,672 bytes of EMM386
  driver code in a UMB and leaves 90,096 UMB bytes free.
- `HIDOS=ON` reduces the conventional system span by exactly 12,800 bytes. The
  corresponding DOS UMB allocation is 12,816 bytes including its MCB and
  contains the 7,680-byte buffer set plus other mutable DOS structures.
- `HIBUFFERS=15` does not change conventional memory. It moves the 7,680-byte
  buffer payload from UMB to HMA, increasing free UMB by 7,408 bytes while free
  HMA falls by 7,920 bytes. The HMA map explains that cost: 208 bytes precede
  COMMAND, 16 bytes separate COMMAND from a small free range, and moving buffers
  to the end introduces 240 unused bytes after them. The compacted DOS UMB block
  shrinks by 7,408 bytes; it is not a byte-for-byte migration because the arena
  is repacked around the remaining DOS state.
- The final conventional owner spans are only 10,720 bytes for the system and
  1,264 bytes for COMMAND. The current implementation uses 37,520 and 6,464,
  respectively; these two differences exactly explain its 32,000-byte deficit
  to DR-DOS because both have the same `9FC0h` ceiling.

#### Adoption priorities from the measured design

The measurements change emphasis but do not justify copying DR-DOS placement
blindly:

1. **Move COMMAND cold state high or transient.** DR-DOS 6 proves a shell can
   retain 4,992 bytes in the HMA and operate with a 1,264-byte conventional
   span. Our HMA DOS image is 39,440 bytes, so a similarly sized experiment fits
   within the nominal 65,520-byte area before accounting for ownership and A20
   constraints. This is the cleanest measured route toward COMMAND's 5,152-byte
   deficit to DR-DOS.
2. **Prefer the later small-gateway EMM386 architecture.** Spending DR-DOS 6's
   28,672 UMB bytes would violate our requirement to preserve at least retail's
   47,888 free UMB bytes. OpenDOS 7.01 demonstrates the same services with only
   an 800-byte reported EMM386 UMB allocation. Continue the protected/XMS
   relocation and low-gateway split rather than copying the older UMB layout.
3. **Give mutable DOS state a high-placement ladder.** DR-DOS gains 12,800
   conventional bytes by putting DOS state in a UMB, then moves buffers to HMA
   to recover most of that UMB. Locally, place HMA-safe state in proved DOS-owned
   HMA slack first, use relocation-safe XMS storage where callbacks permit it,
   and use deterministic UMB placement only within the measured 1,216-byte UMB
   advantage over retail. Fall back transactionally when a tier is unavailable.
4. **Keep low-memory, video-memory, and EBDA recovery separate.** Neither
   measured ordinary DR-DOS result uses them. They cannot explain the advantage
   and must remain optional or bounded finishing work.

#### Optional policies and compatibility boundary

The isolated DR-DOS 6 policy runs complete the numerical picture:

| Policy added to the ordinary 627,824-byte configuration | Largest block | Total free DOS memory | Free UMB | Free HMA | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| 64 KiB EMS frame | 627,824 | 656,208 | 15,568 | 10,880 | Conventional unchanged; 69,120 UMB bytes lost to the frame and resulting layout |
| `/XBDA` | 627,824 | 725,328 | 84,688 | 10,880 | No change without video recovery on this BIOS |
| `MEMMAX +L` | 627,824 | 725,328 | 84,688 | 10,880 | No usable additional block in this occupied low layout |
| `/VIDEO` and `MEMMAX +V` | **726,128** | **823,632** | 84,688 | 10,880 | Adds exactly 96 KiB to the largest block |

The video case raises the allocator's contiguous top by 99,328 bytes: 96 KiB
of text-video address space plus the 1 KiB previously occupied by the EBDA. It
also grows the low system span by 1,024 bytes because EMM386 relocates that EBDA
to `02ACh` below COMMAND, leaving a net largest-block gain of exactly 98,304
bytes. The BDA
and `INT 12h` rise only from 639 to 640 KiB; the extra video range is managed by
DR-DOS rather than advertised as ordinary BIOS conventional memory. This mode
requires text-only operation and must be disabled before graphics software, so
it remains an opt-in extension outside the parity baseline.

An 86Box IBM AT run also boots DR-DOS 6's `HIDOS.SYS /BDOS=FFFF` path on an
8 MHz 80286 and reaches the memory probe marker. This confirms that the
kernel/COMMAND HMA design is not dependent on virtual-8086 mode; UMB placement
and the EMM386 architecture remain 386-specific.

The clean-room gate is met: both releases reproduce from hashed binary media;
the ordinary-mode advantage reconciles through owner spans and documented
policies; optional gains are separated; public XMS, UMB, EMS, HMA, A20, and
warm-reset behavior is recorded; and each portable technique has a local owner
and regression boundary. Further work is implementation-led: complete the
EMM386 low gateway, then design the DOS state placement ladder against the
existing HMA and UMB floors.

#### Published leads already identified

The following preliminary conclusions come only from published Digital
Research and Novell documentation; no DR-DOS source code was consulted.

DR-DOS 6 MemoryMAX combines several policies that MS-DOS exposes less
cohesively: move the kernel to the HMA, move eligible DOS data structures to
UMBs with `HIDOS=ON`, place as many disk buffers as possible outside
conventional memory with `HIBUFFERS`, and load drivers and TSRs high. The manual
also recommends placing hardware reservations at an edge of the UMA, loading
the largest residents first, allowing for a driver's larger initialization
footprint, and omitting the 64 KiB EMS page frame when no application needs it.
These are directly relevant to our DOS-prefix ownership, buffer placement, UMB
coalescing, load-order tooling, and `NOEMS` tests. They do not explain a smaller
EMM386 implementation by themselves. See the [DR-DOS 6 Optimization and
Configuration Tips](https://bitsavers.org/pdf/novell/dr_dos/DR_DOS_6.0_Optimization_and_Configuration_Tips_199109.pdf),
pp. 4–12, and the [DR-DOS 6 User Guide](https://www.bitsavers.org/pdf/novell/dr_dos/DR_DOS_6.0_User_Guide_2ed_199108.pdf),
pp. 379 and 382.

DR-DOS memory figures must not be compared blindly with the fixed MS-DOS 6.22
baseline. MemoryMAX can make most of the first 64 KiB address range available
to applications as "low memory"; its published example consequently reports
626 KiB conventional memory available. The same manual warns that some packed
programs fail there and provides `MEMMAX -L` to hide the range. MemoryMAX can
also expose up to 96 KiB of unused text-video address space, which must be
disabled before graphics software. These are useful opt-in compatibility modes,
not honest credits toward the retail-or-better baseline.

Novell DOS 7 adds two further ideas. Its documented `/XBDA` policy can relocate
the extended BIOS data area when recovering video address space; this supports
our bounded EBDA investigation but does not relax its copy, ownership, BDA
update, and hardware-test requirements. DPMS lets specially written drivers and
TSRs keep most code or data in extended memory behind a small conventional
gateway. That is a useful precedent for the proposed EMM386 low-gateway split
and a possible future resident-service API, but it cannot shrink unmodified
programs and is outside the parity target. `/VIDEO`, `/XBDA`, and `MEMMAX`
are documented in the DR-DOS 6 User Guide, pp. 260–262 and 413–415. The later
placement and DPMS descriptions are in the [Novell DOS 7 User
Guide](https://bitsavers.org/pdf/novell/dr_dos/DR_DOS_7_User_Guide_1993.pdf) and
Novell's [memory-management application note](https://ftp.zx.net.nz/pub/archive/novell/doc/app_notes/9310_Managing_Memory_in_a_DOS_Workstation_using_Novell_DOS_7.pdf).

These leads define hypotheses, not the conclusion. Measure them before choosing
between EMM386 compaction, DOS/BIOS ownership changes, COMMAND, layout
coalescing, and the bounded EBDA step. Low-memory and text-video recovery remain
separate opt-in experiments, and a DPMS-like interface is relevant only if it
serves repository drivers beyond EMM386.

A trial shared DOS HMA-entry routine removed 12 linked low-prefix bytes but did
not cross the 7,600-byte allocation boundary, so VC remained at 594,544 bytes.
It was rejected: subparagraph savings matter only when bundled with a nearby
reduction that releases a paragraph, and shared entry machinery must justify
its extra control-flow risk with an observed allocation gain.

### 2. Reduce EMM386's low allocation

Active EMM386 now occupies 4,096 bytes, 32 below retail. Potential further
reductions, in preferred order, are:

- compact retained data and descriptor metadata, size every table from the
  selected `H=`, `A=`, frame, and DMA configuration, and remove paragraph or
  linker padding that is not an address-stability requirement;
- move additional protected-only code and immutable tables into the locked XMS
  image while retaining explicit low gateways for real-mode entry and return;
- redesign the EMS dispatcher so ordinary and mapping-sensitive functions can
  execute from the relocated image without losing inactive `AUTO` queries;
- replace the shared `RRProc`/return-to-real continuation with a relocation-safe
  gateway, then move the return trap module as one unit;
- separate installation and transient `ON`/`OFF`/`AUTO` command parsing from
  state genuinely needed by the installed driver; and
- audit low GDT, stack, DMA snapshot, exception diagnostics, and compatibility
  state for duplication with the relocated GDT, IDT, TSS, `_TEXT`, or VDATA.

The first current tranche moves the unchanged 1,024-byte loader stack after
the discardable `LAST` segment. The stack remains present while DOS initializes
the EXE, but the final driver break excludes it; the separately rebased
512-byte ring-0 stack remains resident. The fixed capture measures EMM386 at
12,064 bytes and VC at 597,312 bytes, exact 1,024-byte improvements, with
49,104 bytes of free UMB unchanged. Command/API, page-frame and banking,
maximum `H=`/`A=`, `L=`/`D=`, EMS 4.0, concurrent UMB/EMS, injected-failure
rollback, warm reboot, and 286/386/486 hardware gates pass.

The next gateway slice separates allocation mutations from low-mode queries.
Functions 43h, 45h, 51h, and 5Ah now use the existing protected INT 67h entry;
inactive `AUTO` activates only when one of those mutations requires it. Their
shared allocation implementation is a separate object after `IOTrap_Tab`, so
only the locked-XMS copy survives VDATA compaction. Query functions remain in
the reflected low dispatcher and do not activate an idle `AUTO` system;
explicit `OFF` rejects allocation without entering or recursing through the
protected gateway. This
reduces the installed allocation by another 560 bytes to 11,504 and raises VC
by the same amount to 597,872; the complete EMS lifecycle, maximum capacities,
frames, `AUTO`/`OFF`, rollback, and warm reboot gates pass.

Completing that family moves function 51h (`ReallocatePages`) out of the mixed
EMS 4.0 service object. Its dedicated protected object removes
another 272 low bytes, reducing EMM386 to 11,232 and raising VC to 598,144.
The residency checker now requires every allocation mutation to remain beyond
`IOTrap_Tab`; extended EMS, maximum capacities, frames, `AUTO`/`OFF`, rollback,
warm reboot, and the 286/386/486 hardware gates pass.

The first complete mapping-service split compiles `EMMP.ASM` into explicit low
query and protected-only objects. Functions 44h, 48h, 4Eh, 4Fh, 50h, 55h, 56h,
57h, and 5Bh now occupy only the locked-XMS copy. Non-activating functions 47h
(save map) and 58h (mappable physical-address query) initially remained low; moving 58h in
the initial prototype caused the inactive-`AUTO` probe to stall and was
rejected. The corrected boundary removes 3,760 low bytes, reducing EMM386 to
7,472 and raising VC to 601,904. The reporter enforces both sides of the split,
and the full EMS, mode, capacity, rollback, reboot, and hardware gates pass.

The next low-gateway compaction replaces thirteen repeated function-number
comparisons in `EMM_rLink` with a named 25-bit bitmap covering exactly functions
43h, 44h, 45h, 48h, 4Eh-51h, 55h-57h, 5Ah, and 5Bh. The required 386 `BT`
instruction tests the table while preserving the caller's `BX`; all other
functions continue through the non-activating real/virtual dispatcher. This
removes 34 linked low bytes and two installed paragraphs: EMM386 falls to 7,440
bytes and the paired VC block rises by 32 bytes to 602,848. LIM 3.2/4.0,
frames, banking, sparse maps, `ON`/`OFF`/`AUTO`, maximum capacities, XMS/DMA
reservations, UMB rollback, warm reboot, and 286/386/486 hardware gates pass.

The protected entry formerly retained a second 60-byte function vector even
though the complete LIM vector is present at the same `_TEXT` offset in both
the conventional and locked-XMS copies. `EMM_pEntry` now uses that shared
vector after the bitmap and `EMM_Flag` have selected a protected-only service;
external protected-mode calls still reflect, and low-only query entries cannot
reach the high path. Removing the duplicate vector and its null stub cuts 61
linked low bytes and four installed paragraphs. EMM386 falls to 7,376 bytes,
VC rises to 602,912, and the complete API, capacity, frame, banking, mode,
rollback, reboot, and hardware gates pass.

The physical-window table formerly retained a page-table offset for every one
of its 52 possible windows even though each offset is exactly the already-kept,
16 KiB-aligned segment divided by 64. Mapping now converts the compact dense
segment table back to the internal frame numbering and derives the offset at
the two consumers. Removing the parallel 104-byte table and rejecting missing
frame slots adds 32 bytes only to the protected/XMS copy, eliminates the
default stack-alignment gap, and reduces installed EMM386 by seven paragraphs
to 7,264 bytes. The paired VC block rises
by the same 112 bytes to 603,024; free UMB remains 49,104 bytes. The reporter
rejects restoration of the redundant table or growth above the new ceiling,
and all EMS API, frame, banking, sparse-page, mode, capacity, DMA-reservation,
rollback, reboot, HIMEM/UMB, and 286/386/486 hardware gates pass.

The 60-byte `EMM_MPindex` inverse array duplicated the authoritative dense
physical-window segment table. Function 58 keeps its established ascending-
segment output by using one bounded lookup; partial maps, Map Handle Array, and
DMA translation use the same exact-segment rule. Removing the array and its
initializer adds 30 bytes to the shared low query path, including a safe empty-
table result, but slightly shrinks the protected/XMS copy. Alignment leaves a
net one-paragraph installed saving. EMM386 falls to
7,248 bytes and the paired VC block rises to 603,040; free UMB remains 49,104
bytes. The census rejects either inverse table returning or growth beyond the
new ceiling. Function 58, partial maps, sparse `Pn=`, all frames and banking
layouts, DMA reservation, runtime modes, EMS 4.0, rollback, warm reboot, and
the 286/386/486 manager matrix pass.

The character-device request path formerly retained a 13-word dispatch table,
although command 0 was the only distinct operation and commands 1 through 0Ch
all selected the same null result. Direct validation now calls initialization
only for command 0, returns the same zero status for the twelve valid null
requests, and preserves the unknown-command error for 0Dh and above. Removing
the table and two single-use wrappers cuts the real-mode gateway from 474 to
442 bytes. EMM386 falls from 7,248 to 7,216 bytes, the paired VC block rises by
32 bytes to 604,176, and its retail excess falls to 3,088 bytes. Driver/API,
frames and banking, all load modes and maximum option capacities, UMB
reporting, and the 386/486 hardware matrix pass.

The next architectural split gives the protected `INT 67h` entry its own
object after `IOTrap_Tab`. It was previously linked into the same `_TEXT`
object as the real/virtual selector and `_AutoUpdate`, so its protected-only
166 bytes survived in the conventional prefix even though the IDT reaches the
locked-XMS copy. `EMM_rLink`, its service bitmap, inactive queries, AUTO
activation and release, and `RRProc` remain low. The ownership checker now
requires `EMM_pEntry` beyond the split. Alignment turns the 166-byte linked
move into a 176-byte installed reduction: EMM386 falls from 7,216 to 7,040
bytes and VC rises by the same amount to 604,352. EMS 3.2/4.0, frames and
banking, all load modes and maximum capacities, concurrent UMB/EMS rollback,
warm reboot, and the 386/486 hardware matrix pass.

Function 59h hardware information is the first ordinary service moved through
that protected gateway. A dedicated `EMMINFO` object follows `IOTrap_Tab`, and
the service bitmap activates the locked-XMS copy even from inactive `AUTO`;
its subfunction 1 call to the low unallocated-page helper remains valid because
the complete low prefix is mirrored at identical offsets in that copy. Removing
the 68-byte low implementation crosses four paragraphs: EMM386 falls from
7,040 to 6,976 bytes, and the paired VC block rises to 604,416. The explicit
inactive-`AUTO` probe, EMS 4.0 sequence, modes, frames, capacity limits, UMB
rollback, DMA paths, `/NUMHANDLES=24..32` shifted-load boots, and the two-boot
warm-reset suite pass.

Functions 53h and 54h now form a second protected service object containing
handle-name mutation, lookup, and directory enumeration. The low copy retains
OS/E state control but no longer carries these 447 code bytes; mutable name
scratch and the handle tables remain in DGROUP. Function 54h subfunction 2 is
also exercised from inactive `AUTO`, while the extended EMS probe covers name
set/get, lookup, enumeration, duplicate handling, and subsequent map changes.
The split crosses 28 paragraphs: EMM386 falls from 6,976 to 6,528 bytes and the
paired VC block reaches 604,864. All focused suites, UMB rollback, warm reboot,
the `/NUMHANDLES=24..32` disk matrix, and 286/386/486 hardware gates pass.

Function 52h handle attributes now uses a small protected attribute object.
Its register-only query is explicitly exercised from inactive `AUTO`; the full
attribute error and lifecycle cases remain in the EMS 4.0 probe. Moving its 40
low bytes crosses two paragraphs, reducing EMM386 from 6,528 to 6,496 bytes and
raising the paired VC block to 604,896. The focused, lifecycle, shifted-load,
and hardware matrices pass.

Functions 40h, 41h, 42h, 46h, and 4Bh form a protected core-query object, and
the 4Ch/4Dh handle-size and enumeration object is protected as the same coherent
family. The bitmap is rebased to 40h; 54h is included with its relocated handle
directory, and 5Ch is included because its warm-boot contract aliases the
relocated status implementation. Omitting those two alias bits caused the
initial lifecycle failures, not the far-buffer implementation. Unsupported
49h/4Ah remain low. The complete split reduces EMM386 from 6,496 to 6,320 bytes
and raises the paired VC block to 605,072, leaving a 13,664-byte retail gap.
Inactive `AUTO` explicitly exercises status, page counts, version, handle size,
and handle enumeration. The full EMS, frame, load-option, UMB/XMS transaction,
HIMEM lifecycle, `/NUMHANDLES=24..32`, and 286/386/486 hardware gates pass.

Function 58h mappable-address discovery now occupies a dedicated protected
object with its dense-segment lookup helper. Both array-output and count-only
subfunctions run from inactive `AUTO`, and the complete lifecycle covers the
same calls after alter-map and move operations. Removing the service and the
otherwise-unused helper from the low query build reduces EMM386 from 6,320 to
6,208 bytes and raises the paired VC block to 605,184, leaving a 13,552-byte
gap. The full gate set above passes, including the shifted-load matrix. This
also resolves the earlier indirect function-58 suspicion: the prior combined
47h/52h/58h trial still failed after 58h was restored, whereas isolated 58h is
stable with the corrected protected bitmap.

Function 47h save-map now occupies its own protected object. The isolated build
passes duplicate-save rejection, deallocation refusal while a map is saved,
restore, no-map handling, the complete EMS lifecycle, shifted loads, modes,
rollback, reboot, and the hardware matrix. Removing it from the low query build
reduces EMM386 from 6,208 to 6,128 bytes and raises the paired VC block from
605,184 to 605,264 bytes. The earlier mixed-object failure did not isolate one
cause; the dedicated object and complete protected-dispatch bitmap are the
validated boundary.

The shared EMS support helpers now follow their only remaining callers into the
locked-XMS image. Removing `EMMSUP` from the low library moves its client-address
translation, copy, handle-validation, name, descriptor, and TLB helpers beyond
`IOTrap_Tab`; the low dispatcher and unsupported aliases remain conventional.
The low `_TEXT` prefix falls from 2,187 to 1,850 bytes. Paragraph rounding turns
that 337-byte code reduction into a 352-byte installed gain: EMM386 falls from
6,128 to 5,776 bytes and VC rises from 605,264 to 605,616 bytes, leaving a
13,120-byte retail gap. The EMS lifecycle, frames, load options, UMB/XMS
transactions, HIMEM/warm-reboot suites, `/NUMHANDLES=24..32` layouts, and
286/386/486 hardware matrix pass.

Function 5Dh (`OSDisable`) and its timer-derived access-key helper now form two
dedicated protected objects. Extending the protected bitmap through 5Dh removes
the last C service object and key generator from the low dispatcher image while
leaving invalid-function handling conventional. The low `_TEXT` prefix falls
from 1,850 to 1,670 bytes; EMM386 falls from 5,776 to 5,600 bytes and VC rises
from 605,616 to 605,792 bytes, leaving a 12,944-byte retail gap. The explicit
OS/E enable/disable/key probe, runtime and load-time modes, EMS lifecycle and
frames, UMB/XMS transactions, warm reboot, `/NUMHANDLES=24..32`, and the
hardware matrix pass.

All supported INT 67h services now use the protected dispatcher. The real-mode
gateway rejects out-of-range calls and the unsupported 49h/4Ah slots directly,
so the duplicate low dispatcher, vector, unsupported handler, and obsolete
service bitmap can move or disappear. This reduces the low `_TEXT` prefix from
1,670 to 1,497 bytes and EMM386 from 5,600 to 5,424 bytes; VC rises from 605,792
to 605,968 bytes, leaving a 12,768-byte retail gap. Explicit unsupported-call
checks, inactive `AUTO`, all EMS and frame paths, modes, transactions, warm
reboot, `/NUMHANDLES=24..32`, and the hardware matrix pass.

The return-trap initializer now follows its initialization-only lifetime into
the locked-XMS image. This reduces the low `_TEXT` prefix from 1,497 to 1,477
bytes and crosses an allocation boundary: EMM386 falls from 5,424 to 5,408
bytes and VC rises from 605,968 to 605,984 bytes, leaving a 12,752-byte retail
gap. A broader trial that also moved the live 84h/85h handlers failed a repeated
`OFF`-to-`ON` transition and was rejected. Those handlers, `RRProc`, and the
return-to-real continuation therefore remain low until C5 supplies an explicit
position-independent gateway. EMS, modes, frames, load options, UMB/XMS
transactions, warm reboot, and the 286/386/486 hardware matrix pass locally.

The protected-only `RRP_Handler` dispatcher now follows the initializer into
the locked-XMS object, while the port-specific handlers remain in the low
gateway. Its 18-byte low reduction releases another paragraph: EMM386 falls
from 5,408 to 5,392 bytes and VC rises from 605,984 to 606,000 bytes, leaving a
12,736-byte retail gap. A separate attempt to move `RRProc` failed the explicit
OFF API transition and was rejected. The failure proves that the instructions
after its trapped `OUT 85h`, together with the low-offset `_AutoUpdate` return,
are the real-mode continuation rather than protected-only code. Moving them
requires a new continuation contract, not another linker split. The full local
EMS, mode, frame, option, transaction, reboot, shifted-load, and hardware gates
pass with only the dispatcher high.

`RetReal` now has an explicit protected/real boundary. A three-byte retained
entry shim jumps, through the locked-XMS copy, to `RetRealHigh`; that body saves
state, prepares real-mode descriptors, clears paging and PE, then far-jumps to
the retained `RetRealResume` offset and conventional segment. Only the real IDT
record and post-switch restoration remain low. This reduces the retained
`RETREAL` object from 104 to 42 bytes and releases four paragraphs: EMM386 falls
from 5,392 to 5,328 bytes and VC rises from 606,000 to 606,064 bytes, leaving a
12,672-byte retail gap. The low offsets deliberately preserve the trapped
`RRProc` and `_AutoUpdate` return contract identified by the rejected probe.
The complete mode grammar, EMS 4.0, frames, options, transactions, warm reboot,
shifted loads, and 286/386/486 hardware gates pass locally.

The 84h handler and 85h validation now also execute from the locked-XMS
`RRTRAPHI` object. A retained `P85Switch` owns only the emulated port write and
the existing return-to-real continuation, so the first instruction after the
mode switch still has a conventional offset. This reduces retained `RRTRAP`
from 61 to 35 bytes; paragraph rounding reduces EMM386 from 5,328 to 5,312
bytes and raises VC from 606,064 to 606,080 bytes, leaving a 12,656-byte gap.
A combined attempt to split `RRProc` around its trapped output still hung on
`EMM386 OFF` and was rejected: its saved caller return is part of the low ABI,
not just its post-output instruction. The complete local compatibility and
shifted-load matrices pass with `RRProc` retained intact.

The A20 module now follows the same ownership model. `A20_Handler`, trap
initialization, virtual-state queries, and the protected page-table toggle live
in `A20TRAPHI`; only physical 8042 enable/disable and wait code remains low for
the real-mode transition path. Initialization-time A20 detection remains in
the discarded `LAST` object. Retained A20 text falls from 227 to 50 bytes;
paragraph rounding reduces EMM386 from 5,312 to 5,136 bytes and raises VC from
606,080 to 606,256 bytes, leaving a 12,480-byte gap. Fast port-92 and 8042 A20
virtualization, move-block toggles, modes, transactions, warm reboot, all
frames/options, shifted loads, and the hardware matrix pass locally.

The next apparent OEM split is not an independent byte harvest. Moving parity
handling together with the OEM mapping hooks, or leaving parity low while
moving only `Map_Lin_OEM`, `UMap_Lin_OEM`, and the move-block hooks, makes the
extended EMS 4.0 probe stop completing. Both trials are rejected. Revisit this
range only as a coupled mapping/parity gateway with an explicit cross-boundary
contract; keep the intact OEM range as the proven baseline meanwhile.

`SelToSeg`, used only while `RetRealHigh` translates the fixed ring-0 stack
selector, no longer tests for an LDT entry. `GoVirtual` explicitly loads a null
LDT and installs `VDMS_GSEL`, so that branch was unreachable. Removing nine low
bytes crosses a paragraph boundary: EMM386 falls from 5,136 to 5,120 bytes and
VC rises from 606,256 to 606,272 bytes, leaving a 12,464-byte gap. Relocating
the helper itself failed the extended EMS lifecycle and was rejected, so its
low-offset identity remains part of the return contract. The complete local
mode, EMS, frame, option, UMB/XMS, reboot, shifted-load, and hardware matrices
pass with the compact low helper.

The protected NMI shutdown helper now lives in `OEMNMIHI`; unlike the parity
gate, it is reached only by the paged protected trap handler and has no
conventional-selector entry. The retained parity path also uses immediate
selector pushes and combines identical adjacent mask operations. These changes
remove 19 low bytes while adding 7 protected bytes; paragraph alignment reduces
EMM386 from 5,120 to 5,104 bytes and raises VC from 606,272 to 606,288 bytes,
leaving a 12,448-byte gap. The fixed and all nine shifted VC captures, complete
EMS/mode/frame/options suites, XMS/UMB transactions, warm reboot, and the
286/386/486 hardware matrix pass locally.

The `NOHIMEM` build now omits four OEM hook bodies and their calls because each
compiled to an unconditional `RET`; the full OEM paths remain available to a
build that owns high memory. Parity-vector copies use two explicit dword moves
instead of a counted repeat, and the fixed GDT stack conversion returns `BX`
directly. The combined change removes 14 low bytes and 16 protected bytes.
Paragraph alignment reduces EMM386 from 5,104 to 5,088 bytes and raises VC from
606,288 to 606,304 bytes, leaving a 12,432-byte gap. The residency checker
rejects reintroducing the no-op hooks. Fixed and shifted VC captures, all EMS,
mode, frame, option, XMS/UMB, reboot, and hardware gates pass locally.

The OEM physical/linear mapping pair, parity-vector install/restore, and parity
handler now form `OEMPROTHI`, linked at the end of the locked-XMS `_TEXT` copy.
They are entered only by the protected move and mapping engine; interrupt-mask
wrappers, NMI descriptors, and installation state remain low. Keeping the new
object after the existing protected dispatcher is deliberate: inserting it
ahead of functions 55h/56h reproduced their known offset-sensitive lifecycle
stall, while end placement preserves those offsets. The split removes 109 low
bytes and crosses seven paragraphs, reducing EMM386 from 5,088 to 4,976 bytes.
VC gains the full 112 bytes, reaching 606,416 and leaving a 12,320-byte gap.
The residency checker requires all five protected OEM symbols above
`IOTrap_Tab`; a new local gate boots every HIMEM `/NUMHANDLES=24..32` address
phase. EMS 3.2/4.0 including non-empty alter-map calls and moves, runtime modes,
frames, options, XMS/UMB transactions, HMA integration, and the 286/386/486
hardware matrix pass locally.

`GoVirtual` now retains only its real-mode setup and explicit far transfer in
the low image. Its protected-mode continuation and DMA hardware snapshot run
from the locked-XMS `_TEXT` copy. Moving that boundary exposed a pre-existing
layout accident in EMS function 56h: its callback returned through a protected
label represented as a real-mode far address, and happened to work only while
discarded loader bytes still contained the old image. An explicit retained
`AMC_return_gateway` now traps from virtual mode and resumes at the protected
`AMC_return_high` continuation. This removes 456 static low bytes, crosses 28
paragraphs, and reduces EMM386 from 4,976 to 4,528 bytes. The paired VC block
gains the full 448 bytes, reaching 606,864 and leaving an 11,872-byte gap;
free UMB remains 49,104 bytes. EMS 3.2/4.0 including functions 55h/56h,
runtime modes, frames, options, shifted address phases, XMS/UMB transactions,
HMA integration, and the 286/386/486 hardware matrix pass locally.

The fixed protected stack-selector conversion `SelToSeg` now lives beside its
only caller, `RetRealHigh`, in locked XMS instead of the retained low prefix.
The earlier relocation attempt failed only because EMS 56h still returned
through an accidental low-offset alias; the explicit callback gateway above
removes that hidden dependency. No new gateway is required. Moving the helper's
23 linked bytes also removes nine bytes of
stack alignment, reducing EMM386 by two paragraphs from 4,528 to 4,496 bytes.
The paired VC block gains the full 32 bytes, reaching 606,896 and leaving an
11,840-byte gap; free UMB remains 49,104 bytes. The residency checker requires
`SelToSeg` above `IOTrap_Tab`; EMS 3.2/4.0, runtime modes, frames, options,
shifted address phases, XMS/UMB transactions, HMA integration, and the
286/386/486 hardware matrix pass locally.

The standalone `EMM386.EXE ON|OFF|AUTO` client, installed-manager probe, and
far-link helper now build as `MEMMUTIL`, after the retained `_TEXT` boundary;
CONFIG.SYS installation retains only the device header and runtime gateway.
The public command behavior is unchanged and the existing parser was already
non-low.
The two-function installed control entry also replaces its far-pointer table
and indexed call with one relocated far call and a compact selector, while six
unreachable author-initial bytes after the device interrupt are gone. The
static low image falls by 97 bytes and EMM386 crosses six paragraphs, from
4,496 to 4,400 bytes. The paired VC block gains the full 96 bytes, reaching
606,992 and leaving an 11,744-byte gap; free UMB remains 49,104 bytes. The
residency checker requires all four command-client symbols above `IOTrap_Tab`.
Command modes and reporting, duplicate-load detection, EMS 3.2/4.0, frames,
options, shifted address phases, XMS/UMB transactions, HMA integration, and
the 286/386/486 hardware matrix pass locally.

Production `NoBugMode` builds now omit the five Deb386 working descriptors and
its full-address descriptor, plus their `INT 68h` initialization. All following
internal selectors are derived from the compact `RCODEA_GSEL` base; the EMM
service and monitor objects now receive the same build definition so the shared
selector header cannot produce two layouts. Debug-enabled builds retain the
original descriptors and numbers. The production GDT falls from 272 to 224
bytes, reducing EMM386 from 4,400 to 4,352 bytes. The paired VC block gains the
full 48 bytes, reaching 607,040 and leaving an 11,696-byte gap; free UMB remains
49,104 bytes. The residency checker enforces both the 224-byte GDT and the
4,352-byte installed ceiling. Command modes, EMS 3.2/4.0, frames, options,
shifted address phases, XMS/UMB transactions, HMA integration, and the
286/386/486 hardware matrix pass locally.

Every physical window is aligned on a 16 KiB boundary, but the dense mappable
table still retained its full 16-bit segment. It now stores the lossless
`segment >> 10` index in one byte and reconstructs the segment or physical
address at the API, mapping, unmapping, partial-map, and DMA boundaries. The
52-byte `_DATA` reduction crosses three paragraphs after alignment: EMM386
falls from 4,352 to 4,304 bytes, VC rises by the full 48 bytes to 607,088, and
the gap becomes 11,648 bytes. The complete LIM 4.0 lifecycle, all frame and
banking forms, sparse `Pn=`, maximum `H=` and `A=`, DMA reserves, runtime modes,
shifted loads, UMB transactions, warm reboot, and 286/386/486 hardware gates
pass; free UMB remains 49,104 bytes. The residency checker enforces the new
4,304-byte ceiling.

The caller-visible physical-page ID array also need not scale with all 52
windows. Initialization still constructs the complete mapping in discardable
`LAST`, but the resident VDATA tail now keeps only two-byte `(internal, public)`
pairs for explicit `Pn=` assignments: zero bytes normally and at most 40 bytes
for the supported 20 assignments. Unassigned IDs are derived in the same
lowest-unused order at the function 44h/50h and function 58h boundaries. This
removes 49 static bytes after the exception pointer and count are included,
crossing three paragraphs: EMM386 falls from 4,304 to 4,256 bytes, VC reaches
607,136, and the gap becomes 11,600 bytes. Sparse `P200=`, all frame and banking
forms, LIM 4.0, maximum `H=`/`A=`, DMA reserves, runtime modes, shifted loads,
UMB transactions, warm reboot, and the 286/386/486 matrix pass. The census
models all 0..20 exception pairs and enforces the 4,256-byte default ceiling.

The DMA relocation page list likewise no longer reserves all 16 words in
resident `_DATA` for every configuration. It is now a pointer to a VDATA range
sized from the selected `D=` capacity: two bytes for the default `D=16`, up to
the complete 32 bytes for `D=256`. The two unused extended-operation fields at
the end of the DMA snapshot are also gone. Static `_DATA` falls by 32 bytes;
after the two-byte default table and alignment, EMM386 falls from 4,256 to
4,224 bytes. The paired VC block gains the full 32 bytes, reaching 607,168 and
leaving an 11,568-byte gap; free UMB remains 49,104 bytes. Default and maximum
DMA reserves, all EMS modes and maps, shifted loads, UMB transactions, HMA,
warm reboot, and the 286/386/486 hardware gates pass. The census accepts
`--dma-pages 1..16`, rejects a fixed embedded table, and enforces the new
4,224-byte default ceiling without reducing the `D=256` capacity.

The dense mappable-window index table is now runtime-sized as well. EMM386
builds its complete 52-entry-capable list in discardable `LAST`, copies only
the detected entries to VDATA, and retains a two-byte pointer instead of 52
static bytes. Protected assembly and C consumers follow that pointer, and
`CompactVData` rebases it with the other dynamic structures. The fixed `RAM M5`
comparison has six mappable windows, so its VDATA grows by six bytes while
static `_DATA` shrinks by 50; downstream alignment yields a 16-byte installed
gain. EMM386 is now 4,208 bytes, VC reaches 607,184, and the retail gap is
11,552 bytes. All frame and banking layouts—including the maximum window
range—EMS 4.0 mapping forms, sparse IDs, DMA reserves, runtime modes, shifted
loads, UMB transactions, warm reboot, and the 286/386/486 matrix pass. The
census now models the six-window fixed comparison and enforces the 4,208-byte
default ceiling.

The saved and replacement NMI descriptors used by the parity handler now live
beside their only consumers in the writable locked-XMS protected image. The
set/restore paths select that image explicitly and restore the caller's DGROUP
selector before returning. This removes 16 bytes from resident `_DATA`, taking
it from 454 to 438 bytes and the fixed installed allocation from 4,208 to 4,192
bytes. The paired capture gives VC the full 16-byte gain: 607,200 bytes remain
free, 11,536 below retail, while free UMB remains 49,104 bytes. The complete
EMM386/EMS, XMS/UMB, HMA, warm-reboot, and 286/386/486 local gates pass. The
census requires both NMI descriptors to remain beyond the low `_TEXT` split
and enforces the new 4,192-byte ceiling.

The next metadata tranche narrows values whose documented maxima fit in one
byte: physical and mappable window counts (52), page-frame pages (4), alternate
register sets (254), and handle capacity/count (255). Function 59h now builds
its five-word hardware-information response from those values and constants,
instead of retaining a ten-byte response image. The transient DMA return byte
shares the interrupt-mask byte because DMA client traps cannot overlap the
masked mode-transition interval, and the formerly tested machine identifier
was a fixed `0FCh`; compiling the same AT-class conversion directly preserves
the existing behavior. These changes remove 14 bytes from `_DATA`, from 438 to
424 bytes, and cross the next allocation paragraph: EMM386 is 4,176 bytes, 48
above retail. VC gains the full 16 bytes, reaching 607,216 with an 11,520-byte
gap; free UMB remains 49,104 bytes. Function 59h, the maximum `H=255` and
`A=254` capacities, all frame/banking/DMA and EMS mappings, runtime modes,
shifted loads, XMS/UMB/HMA behavior, warm reboot, and the 286/386/486 matrix
pass locally. The census enforces each byte layout, absence of the derived
response and machine-state copies, the 424-byte `_DATA` ceiling, and the
4,176-byte installed ceiling.

The production GDT no longer reserves the unused EGA-low, EGA-high, and
LOADALL descriptors; debugger builds retain the historical slots and selector
ABI. Production selectors after the colour-display entry now derive from the
new `RCODEA_GSEL` base. This removes 24 linked GDT bytes, of which alignment
absorbs eight, reducing the static low image from 1,751 to 1,735 bytes and the
installed allocation from 4,176 to 4,160 bytes. The paired capture gives the
entire released paragraph to VC: 607,232 bytes remain free, 11,504 below
retail, while free UMB remains 49,104 bytes. The clean EMM386/EMS, XMS/UMB,
HMA, option, warm-reboot, and 286/386/486 local gates pass; the census enforces
the 200-byte GDT and 4,160-byte installed ceilings.

The final retail-matching descriptor tranche removes three more production
slots with no runtime consumer: the LDT descriptor is unnecessary because
`GoVirtualHigh` explicitly loads a null LDTR, while the ROM-data and monochrome
display selectors are never referenced. Debugger builds keep their historical
table and numbers. Rebasing the remaining production selectors reduces the GDT
from 200 to 176 bytes and also removes eight bytes of following alignment, so
the static low image and installed allocation fall by 32 bytes to 1,703 and
4,128 bytes. The paired result is 607,264 bytes, 11,472 below retail, with the
same 49,104 free UMB bytes. The full EMM386/EMS option matrix, XMS/UMB/HMA
lifecycle, warm reboot, and 286/386/486 gates pass locally; the census enforces
the new boundaries. EMM386 size parity is complete, though its remaining
gateway work is still useful as better-than-retail margin toward the system goal.

The supported-mode audit then exposed two independent DOS-high failures hidden
by RAM-only coverage. DMA mapping still declared the byte-sized physical,
mappable, and page-frame counts as 16-bit C values; the page-frame read consumed
the adjacent context count and corrupted default EMS mappings. The alternate
register-set setter and deallocator likewise retained word reads after
`_frs_size` became byte-sized. Finally, inactive `AUTO` and `OFF` returned to
real mode by unconditionally disabling physical A20 even when their logical
client state was on, making the return into an HMA-resident kernel wrap below
1 MiB. Correct declarations and logical-state restoration close both defects.
Default, `AUTO`, `RAM`, and `NOEMS` now boot with `DOS=HIGH`; EMS 4.0, UMB,
HIMEM, command-mode, address-phase, and warm-reboot gates pass. The seven-byte
low return check crossed one paragraph at that checkpoint: EMM386 was 4,144
bytes and the VC largest block was 607,760 bytes. Compacting each internal fast
register set's allocation flag from a word to a byte saves eight bytes in the
default eight-set layout and removes eight alignment bytes. The public function
5Bh save-area format and every `A=` capacity remain unchanged. Byte-aligning
the contiguous `R_CODE` contributions then removes 38 bytes of contribution and
terminal padding. Active EMM386 is now 4,096 bytes, the current VC largest block
is 607,808 bytes, and the retail gap is 10,928 bytes. The maximum-capacity probe
now allocates all 254 optional
sets, checks exact exhaustion, and verifies reuse of low, middle, and high IDs.
OFF and `AUTO` retain their pre-compaction absolute boundary because their
inactive initialization path does not run VDATA compaction. This establishes
that their earlier failure followed downstream placement, not internal
`R_CODE` offsets, and preserves all supported modes without charging the active
fixed comparison.

The next paragraph is not yet safe to release. Shortening three independent
low-gateway branches by 16 bytes moves the selected active layout from 4,096 to
4,080 bytes; the basic API and address-phase probes pass, but the EMS 4.0
function 56h segment-map-and-call case does not. An instruction trace shows
the failed protected request returning to EMM386's own trapped `INT 67h`
opcode, then recursively dispatching `AX=5601h` while the client stack falls by
ten bytes per iteration. The physical-map form immediately before it completes.
Changing the common trapped-return IP advances execution but breaks earlier
directory results, so that is not a valid fix. Before releasing this paragraph,
identify why the segment-form map takes its normal error return, then make the
internal gateway unwind that result without changing successful EMS register
contracts. Retain 4,096 bytes until the complete EMS 4.0, mode, mapping,
capacity, shifted-load, warm-reboot, and hardware gates pass at 4,080 bytes.

Selected-BIOS compaction removes the now-unused century/year globals, keeps the
temporary CMOS day count in preserved `BP` and century/year in the returned
`CL`/`CH` registers, makes the division remainder one-based, records the leap
month in `BH`, and relies on normalized counts to bound the year and month loops.
The BCD helper uses the 8086 `AAM`/`AAD 16` identity, and SYSINIT copies both
helpers contiguously before one final paragraph alignment while retaining their
separate entry pointers. The helpers shrink from 210 and 15 bytes to 121 and 5
bytes; the fixed BIOS image falls from 8,912 to 8,800 bytes. All seven released
paragraphs join VC's largest block, raising it to 607,376 bytes and reducing the
retail gap to 11,360 bytes. DATE handling, SYS, interrupt, HMA, and 286/386/486
local gates pass; the residency check enforces the new 8,800-byte ceiling.

The DOS dispatcher formerly maintained `SETVECTFLAG`, but its setup required
`AH` to equal both 25h and 35h, so the nonzero path was unreachable and EMS
map save/restore always ran. Removing the dead byte and its writes/tests keeps
that behavior while reducing retained DOS CODE from 1,640 to 1,601 bytes. The
paragraph-rounded low allocation falls from 6,992 to 6,960 bytes; the HMA image
falls from 39,632 to 39,584 bytes and leaves 17,932 bytes of initial tail slack.
The paired VC result rises by 32 bytes to 607,408, with the same 49,104 free UMB
bytes. DOS, EMS, HMA, interrupt, and 286/386/486 local gates pass.

The following dispatcher pass preserves the already-tested DOS 6 compatibility
contract for `INT 21h/AH=33h`: unsupported code-page-switch subfunctions 03h
and 04h remain no-ops, 05h still returns the boot drive, 06h still returns the
true version, and larger values still fail. Collapsing the disabled historical
branches and using the bounded 05h/06h split removes seven linked bytes. This
lands `DOS_LOW_GATE_END` exactly on a paragraph boundary at 6,944 bytes, so the
entire 16-byte allocation joins VC's largest block. The paired result is
607,424 bytes with 49,104 free UMB bytes; the focused CONFIG/API probes, DOS,
EMS, HMA, and 286/386/486 gates pass locally.

The BIOS warm-reboot path now restores its fourteen saved hardware vectors with
one 8086-compatible table-driven loop instead of fourteen emitted copies of the
same sentinel checks and IVT writes. The saved-vector storage and exact
`FFFF:FFFF` skip contract are unchanged. Adding a 14-byte vector-number table
while removing the unrolled code reduces the fixed selected BIOS from 8,800 to
8,512 bytes. The old PCjr model check following an unconditional jump was also
unreachable; removing it and branching directly around restoration reduces the
selected BIOS again to 8,496 bytes. All nineteen released paragraphs join VC's
largest block, raising it to 607,728 bytes without changing the 49,104 free UMB
bytes. SYS-created floppy and FAT16 boot, normal and dirty-cache `INT 19h`
reboot, repeated IBM AT 286 reboot, and the 286/386/486 memory matrix pass
locally.

Packing each saved pointer with its interrupt number lets the same loop consume
one five-byte record at a time, eliminates its second index, and preserves the
sentinel result across `LODS`. Direct SYSINIT references to every public saved
pointer remain valid. The selected BIOS falls another paragraph to 8,480 bytes,
and VC rises to 607,744 bytes with unchanged UMB capacity. Both reboot gates and
the 286/386/486 matrix pass again.

The next BIOS pass removes an unreferenced private four-byte scratch slot,
reuses the already-zero `AX`/`DS` warm-boot state, narrows vector-index
conversion, and applies the same BDS flag masks directly instead of constructing
them in `BX`. The selected image falls to 8,464 bytes and VC rises to 607,760
bytes. External-driver installation, every `DRIVER.SYS` geometry, multitrack
I/O, dirty-cache and IBM AT 286 reboot, and the hardware matrix pass locally.

The external-disk interface now walks to the final BDS in place instead of
maintaining a parallel pointer stack, returns the BDS head with one far load,
shares the reserved-function `IRET`, and installs the `INT 2Fh` vector while
capturing its old offset directly. Removing the unreferenced disk-speed byte
brings `ENDONEHARD` to exactly 8,320 bytes and the selected BIOS to 8,448.
The released paragraph reaches VC, raising its largest block to 607,776 bytes
without changing the 49,104-byte free-UMB result. SYS floppy and FAT16 boots,
external-driver installation, every `DRIVER.SYS` geometry, multitrack I/O,
dirty-cache and IBM AT 286 reboot, and the hardware matrix pass locally.

The 95-byte DOS binary-identification record had no runtime consumer but still
occupied the permanent `TABLE` segment. It remains in the distributed binary,
now after `SYSBUF` in discardable initialization storage. This reduces
`DOS_LOW_GATE_END` from 6,944 linked bytes to 6,849 and its paragraph allocation
from 6,944 to 6,864; the HMA image also falls by 96 bytes because of downstream
alignment. The paired VC result gains the complete 80 conventional bytes,
reaching 607,888 with the same 49,104 usable UMB bytes. HMA ownership/fallback,
undocumented internal structures, synchronous and asynchronous interrupts,
286/386/486 hardware, and every EMM386 address phase pass locally.

The extended-attribute cluster scratch word and condition byte were retained
DOS 4-era state with no active consumer: DELETE and ROM kept declaration-only
references while every former instruction was disabled. Removing those stale
requests and three table bytes moves `DOS_LOW_GATE_END` to 6,846 bytes and its
allocation to 6,848. The crossed paragraph reaches VC in full, raising the
largest block to 607,904 bytes; EMM386 remains 4,096 bytes and usable UMBs remain
49,104 bytes. The same residency, HMA, internal-structure, interrupt,
asynchronous, hardware-matrix, and EMM386 address-phase gates pass locally.

EXEC's 26-byte copied MZ header is now overlaid on the existing 128-byte
`OpenBuf` workspace. The relocation count is preserved across the seek that
begins reusing that buffer. This moves `DOS_LOW_GATE_END` from 6,846 to 6,820
linked bytes and its allocation from 6,848 to 6,832 bytes. The HMA image falls
from 39,488 to 39,456 bytes, leaving 18,060 bytes of DOS-owned tail space. The
complete paragraph reaches VC, raising the largest block to 607,920 bytes while
usable UMBs remain 49,104 bytes. INT 21h EXEC, LOADHIGH, HMA, internal
structures, synchronous and asynchronous interrupts, the 286/386/486 hardware
matrix, and every EMM386 address phase pass locally.

CLOSE no longer retains a global word solely to compare the old and new first
clusters for FASTOPEN. The directory entry remains the old-value owner until
classification; a changed nonzero value is exchanged into place while the old
value is passed to FASTOPEN, and the truncation path installs zero before
repurposing the directory pointer. This removes two low TABLE bytes and eight
high code bytes. Moving two existing DOSINIT-alignment NOPs to the high side of
`DOS_LOW_GATE_END` preserves every subsequent offset while ending the low image
at exactly 6,816 bytes, reducing its allocation by one paragraph. The HMA image
falls to 39,440 bytes with 18,076 bytes of tail space. Paired VC rises to
607,936 bytes and retains 49,104 free UMB bytes. FASTOPEN invalidation, INT 21h
file/memory/path behavior, HMA, internal structures, asynchronous interrupts,
and the 286/386/486 hardware matrix pass locally.

A prior whole-library linker reorder was rejected because it moved the service
dispatcher without first giving real-mode and inactive-`AUTO` callers an
explicit protected gateway. That service boundary now exists, but transition,
fault, DMA, and return code still has real-mode ownership. Those modules require
an explicit gateway redesign; link order alone remains insufficient.

This work must preserve EMS 3.2/4.0 services, non-empty function 56h maps,
alternate register sets, DMA, page frames, `RAM`/`NOEMS`, runtime
`ON`/`OFF`/`AUTO`, warm reboot, and maximum `H=`/`A=` capacities. Moving a
module solely because its normal path appears protected-only is unsafe; entry,
return, fault, inactive, and transition paths must all be identified first.

### 3. Reduce HIMEM's low allocation

HIMEM occupies 2,592 bytes versus retail's 1,104. Its resident break is tracked
at each `/NUMHANDLES=` capacity and distinguishes fixed code/data from
option-sized records. Incremental work is paused; if the measured residual later
justifies resuming it, candidates include:

- pack UMB ownership records further where the full numeric ranges and
  transactional rollback can be retained;
- merge duplicate range validation, A20, request-header, and error paths;
- discard all detection, parser, diagnostic, and memory-test state after
  initialization, verifying the paragraph-rounded break directly;
- relocate immutable data or safe state into the HMA after DOS has reserved it,
  without consuming space needed by the DOS-high image and buffers; and
- reduce the permanent device stub only if the XMS entry point, request chain,
  third-party coexistence, and all A20 backends remain compatible.

The default and 128-handle configurations, all 32 UMB extents, XMS 2/3 calls,
HMA ownership, nested A20 state, transactional UMB behavior, and legacy-driver
bounce path are non-negotiable gates.

### 4. Reduce COMMAND's resident allocation

COMMAND now occupies 3,840 bytes versus retail's 2,960. Its DOS-high allocation
ends before the relocated catalogs and `HMACODE`; the opportunity is inside
resident code and data, not an accidentally retained transient tail. Inspect
`CODERES`, `DATARES`, the resident message blocks, batch/environment
bookkeeping, reload code, and their alignment separately.

`tests/report_command_residency.py` checks the linker map and binary on every
local `make test`. The permanent DOS-high break is 3,632 bytes, already
paragraph-aligned: a 256-byte PSP, 2,451 bytes of resident code, a 125-byte
resident stack, 562 bytes of mutable shell state, and 238 bytes of mutable
message-runtime data.
The contiguous 806-byte utility catalog and 475-byte critical-error catalog are
copied to HMA. DOS=LOW, allocation failure, child shells, and `/MSG` keep them
low; that fallback break is 6,079 bytes, rounded to 6,080. The deliberate
64-byte fallback increase pays for reusable low/HMA gateways and their far
entry state without removing DOS=LOW behavior. The 1,000-byte parse/extended
catalog tail is
resident only with `/MSG`; initialization/templates and the reloadable command
body remain outside the normal break. This closes the current relocation tranches,
but D1 still requires symbol ownership for the remaining resident ranges.

The checked census now divides every byte after the PSP and before the high
catalog boundary into eight symbol-anchored ownership ranges: 1,496 bytes of
entry/EXEC/reload paths, 955 bytes of remaining low error and message services,
a 125-byte stack, 179 bytes each of substitution/critical state and interpreter
control state, 164 bytes of pipe state, 40 bytes of EXEC/environment state, and
238 bytes of mutable message runtime. This prevents a gain from being credited
to an unmeasured gap. It also identifies the next investigation precisely:
split the remaining service range by callers and asynchronous-entry
requirements; the mutable pipe and EXEC ranges are not cold-placement
candidates merely because they are small.

That split is now machine-checked. The range consists of a 29-byte batch prompt,
646-byte installed `INT 24h` handler, 3-byte CR/LF entry, 57-byte resident print
wrapper, 18-byte DBCS gateway, 16-byte exit-time pointer reset, 174-byte
registered disk-message callback, and two 6-byte HMA gateways. The interrupt
handler dominates but enters asynchronously with DOS-supplied segments, calls
multiple low resident services, and uses resident data; moving it is a handler
and data-ownership redesign rather than another cold-code copy. The disk
callback must stay low because its attempted relocation failed the disk-backed
extended diagnostic. Moving the remaining tiny helpers independently would
spend comparable low gateway bytes. Therefore incremental COMMAND relocation
pauses at an 880-byte excess and the execution road advances to EMM386's
remaining 224-byte component excess and potential better-than-retail gateway
opportunity. Revisit COMMAND only as a coherent
interrupt/data redesign or if later layout evidence makes the sub-paragraph
helpers decisive.

The first caller audit removes eight bytes from `reset_msg_pointers`. That
resident helper is reached only from the two fatal/exit paths that immediately
overwrite its `AX`, `DX`, `DI`, and `ES` work registers before terminating, so
its four pushes and four pops preserved no observable state. The raw high break
falls from 4,742 to 4,734 bytes and crosses the paragraph boundary, adding 16
bytes to VC's largest block. The low/failure break falls by the same paragraph.

The first resident-code relocation establishes a bounded `HMACODE` segment and
keeps only two low gateways plus far-entry state. The self-contained country
character translator and DBCS lead-byte checker, including their HMA far-entry
wrappers, form a 76-byte payload copied with the catalogs into DOS-owned HMA.
The low source remains available to DOS=LOW, allocation-failure, child-shell,
and `/MSG` paths. This reduces the DOS-high break from 4,736 to 4,720 bytes and
raises the paired VC block to 603,056 bytes. The low fallback grows from 6,016
to 6,080 bytes; larger code families can amortize that fixed gateway cost.
Startup, critical-error, batch-step, HMA/A20, DOS-low, `/MSG`, 286 86Box, and
the 386/486 memory-manager matrix pass.

The follow-up relocation moves the generated GET, DISPLAY, character, and
numeric message engine as one 1,166-byte HMA range while leaving its disk
callback low. Early conditional and wrapped gateways returned into message
data in `COMMAND /Y /C`: child and fallback entry must preserve the exact
legacy near-call frame and flags. The final six-byte gateway is a direct near
jump in child, DOS-low, allocation-failure, and `/MSG` paths. Only successful
permanent relocation atomically patches the copied exits to far returns and
the gateways to far calls followed by a near return. The DOS-high break falls
from 4,720 to 3,632 bytes, the paired VC block rises from 603,056 to 604,144
bytes, and COMMAND's excess falls to 880 bytes. Startup, critical-error,
batch-step, HMA/A20, DOS-low, `/MSG`, real-286 86Box, and 286/386/486 matrix
tests pass. The registered disk callback remains low because moving it broke
the disk-backed extended diagnostic and `INT 24h` path.

The complete normal utility-plus-critical catalog relocation is retained.
`MSGDATA` is emitted before the immutable classes, leaving the writable
formatter and five far class slots low. After `SYSLOADMSG` initializes those
slots, startup copies the contiguous 1,281-byte resident catalog range into
DOS-owned HMA, and rebases the two classes in that range. The three
initialization or optional `/MSG` class slots retain their existing reload
semantics. Startup also publishes the relocated critical class through the DOS
message interface. DOS=LOW and allocation failure retain the original near
image; child shells and `/MSG` consume no monotonic HMA-tail storage.

The prior prototype's binary output was not evidence that COMMAND observed A20
disabled. It was the independent high-driver `DX` corruption described below.
With that fixed, ordinary display, substitutions, real critical errors, the
deliberate A20-off callback, DOS=LOW, `/MSG`, child shells, and the real-286
gate pass. The paired VC capture measures a 784-byte additional gain over the
critical-only baseline; the far-access support consumes the other paragraph.

The resident message builder installs exactly five utility classes (A through
E), although the generated control file counts all eight classes used across
resident and transient COMMAND modules. A resident-only table bound now removes
the three unreachable far-pointer slots without changing the generated control
file or transient layout. This removes 12 bytes, crosses the allocation
boundary, and adds 16 bytes to VC's largest block. The paired result is 601,920
bytes; COMMAND occupies 5,840 bytes and its excess over retail is 2,880 bytes.

COMMAND now uses a 48-byte message workspace instead of the generic 64-byte
utility default. The residency census reads every compiled critical, parse,
and extended catalog record and enforces their 40-byte maximum against that
bound. Formatter output flushes at the configured boundary. The earlier
experiment's A20-off failure was the independent `DEVIOCALL` register defect
described below; with that fixed, startup, `/MSG`, critical-error, A20-off,
batch-step, and mixed-command suites pass. The change reclaims one paragraph.

The 81-byte output-redirection pathname and append flag now live in initialized
`TRANDATA`, where all their users execute. External EXEC/reload followed by
both `>` and `>>` is regression-tested. This reduces COMMAND's paragraph-rounded
allocation by 80 bytes without retaining reloadable state accidentally.

That move exposed a pre-existing DOS-high character-device defect. The high
`DEVIOCALL` path used `DX` for the device interrupt offset even though its
documented internal contract preserves every register except `DS:SI` and `AX`.
Redirected character output then reused the leaked interrupt offset as its next
source pointer and emitted bytes from COMMAND's transient body. Preserving
`DX` across the strategy and interrupt calls fixes the baseline and the
relocated layout. The HMA test now requires the complete pre-marker output to
be exactly CR/LF, so any future binary or control-byte prefix fails instead of
only NUL output being detected.

The compile-time `A20_DEBUG` fixture remains available for this boundary. It
records strategy/interrupt entry without using the stack; every sampled entry
had A20 enabled and a low `SS`, ruling out delayed gate recovery, an HMA stack,
and the XMS multiplex trampoline as causes of this defect.

Reproduce the checked census with:

```sh
make test-command-residency
```

The fixed HMA census is also checked from the DOS map. DOS owns the complete
HMA for its high-mode lifetime and leaves A20 globally enabled; its retained
driver trampoline restores that state after legacy callbacks. The DOS image
occupies `0010h..9A20h` (39,440 bytes). With the fixed 15-buffer, 512-byte-sector
configuration, the hash and slots occupy `9A20h..B954h` (7,988 bytes), leaving
`B954h..FFF0h` (18,076 bytes) of initially unassigned but still DOS-owned space
and a deliberately unused 16-byte safety tail. Thus a DR-DOS-sized 4,992-byte high
COMMAND payload fits without displacing buffers. It must use a DOS-controlled
allocation/entry contract rather than treating that slack as independently
allocatable XMS memory.

That contract is now implemented as private `INT 2Fh` functions 1235h/1236h.
SYSINIT publishes the actual post-buffer boundary only after constructing the
cache; DOS then provides monotonic, overflow-checked reservations below
`FFFF:FFF0`. DOS=LOW and an unpublished or exhausted range fail without state
change; zero-sized requests and attempts to republish the boundary are also
rejected. The code adds 112 bytes to the HMA image; subsequent discardable-data,
dead-state, shared-workspace, and paragraph-boundary work reduces the current
low gateway allocation to 6,816 bytes.
`tests/hma_tail_probe.asm` proves writable high
storage, overflow rollback, and high/low-mode gating during `make
test-hma-qemu`. This is an internal implementation boundary, not a new public
DOS API; COMMAND remains the intended consumer.
The probe's expected first address is generated from the current `SYSBUF` map
offset and the fixed buffer equation, so it also rejects an overlapping or
stale published boundary. QEMU high/low cases, the 386/486 EMM386 matrix, and
the cycle-accurate IBM AT 286 path pass; the DOSBox-X matrix uses a 60-second
limit because the complete fixed-cycle boot exceeds its former 30-second cap
on current hosts.

The permanent root shell now reserves 2,447 bytes from that tail and copies the
normal resident utility and critical-error catalogs plus the 1,166-byte
generated message engine to `FFFF:BA14h`. The
writable formatter table remains low and holds two far class pointers rebased
after the copy; the three initialization or optional pointers keep their
existing reload behavior. The critical pointer is also registered
through the existing DOS message service. Message-table scanning recognizes
only `FFFF:FFFF` as its terminator, so valid `FFFF:offset` HMA pointers cannot
fall through to recursive disk loading during an `INT 24h` failure. The next
free tail address is `C373h`, leaving 15,485 bytes. Local QEMU startup, child
batch/pipe, HMA, 286 86Box, and 286/386/486 hardware-matrix tests pass. The latest
paired VC capture before the function 59h move measured 604,352 bytes in the
largest block and an 880-byte COMMAND excess over retail.

Potential approaches are:

- move rarely used commands, messages, and error formatting to the reloadable
  transient part;
- consolidate resident message descriptors, duplicated strings, scratch areas,
  and compatibility variables;
- shrink reload, `INT 2Eh`, critical-error, pipe, batch, and termination paths
  after proving which portions must survive transient overwrite; and
- consider an optional UMB-resident permanent shell only after the identical
  comparison configuration can select it deterministically. It must not hide a
  regression by consuming UMBs or changing the public default.

The shell must still reload after external programs, preserve batch and pipe
state, handle critical errors and Ctrl+C, maintain its environment and
`COMSPEC`, and support the complete internal-command surface.

### 5. Recover the layout and ceiling difference

After every component change, compare MCB start/end addresses rather than
inferring layout from component totals. The current 8,592-byte row may contain
several independent effects. Investigate:

- the top-of-conventional-memory value and every BIOS reservation below it;
- the location and order of DOS, device, shell, environment, and free MCBs;
- paragraph rounding, MCB headers, alignment gaps, and zero-sized or stranded
  blocks between resident allocations;
- whether DOS relocation leaves any additional low copy, compatibility anchor,
  transfer area, table, or arena bridge that can safely move to the HMA;
- whether eligible post-EMM386 allocations can use existing UMBs without
  reducing the largest UMB below retail or changing the startup files; and
- whether free blocks can be reordered or coalesced so recovered bytes actually
  extend the largest conventional block.

The ceiling probe explains the first item. This system leaves the QEMU EBDA at
`9FC0h`; both `INT 12h` and BDA word `40h:13h` therefore report 639 KiB. Retail
DOS 6.22 moves the EBDA pointer to `035Ch` and changes both reports to 640 KiB.
That accounts for exactly 1,024 bytes of the ceiling row, but changing the
reported values alone would corrupt the live EBDA. A retained implementation
must copy the EBDA into explicitly owned low memory, update `40h:0Eh` only after
the copy, preserve BIOS users of the area, and prove that its destination does
not consume the same 1 KiB from the largest block. Reusing verified slack in an
existing resident system allocation can yield the full gain; adding a new 1 KiB
allocation cannot.

Do not reclaim ROM, video, page-frame, exclusion, provider-gap, or real-mode
near-pointer space merely to improve the number. Preserve the current 1,216-byte
usable-UMB advantage unless an explicit trade yields a larger conventional
block and still leaves at least retail UMB capacity.

### 6. Lock in the target

Implement small, independently measured changes, starting with table and
alignment reductions before transition-path redesigns. After each retained
change, run the focused component suite and the paired memory capture; run the
full local release suite at workstream boundaries. Once the result reaches
618,736 bytes, add that value as a regression floor for the fixed comparison
image, retain the component ceilings, and record any margin above retail.

CI remains disabled by project decision. These gates run locally until CI is
explicitly restored.

Paired `MEM /D` captures account for the conventional system block as follows:

| Component | This system | Retail 6.22 | Excess |
| --- | ---: | ---: | ---: |
| HIMEM | 2,592 | 1,104 | 1,488 |
| EMM386 | 4,096 | 4,128 | -32 |
| FILES | 896 | 896 | 0 |
| FCBS | 256 | 256 | 0 |
| BUFFERS | 512 | 512 | 0 |
| LASTDRIVE | 2,288 | 2,288 | 0 |
| STACKS | 1,840 | 1,856 | -16 |
| Total | 12,480 | 11,040 | 1,440 |

`MEM` reports 12,592 and 11,168 bytes after each block's arena overhead. Both
systems use `BUFFERS=15` and now retain only one 512-byte conventional transfer
area. A direct retail probe found its buffer hash at `FFFF:B3D4`, confirming
that DOS 6.22 also places the normal buffer state in the HMA.

### Stage 1: HMA buffers with legacy-driver safety — complete

A retained implementation reserves the HMA before final-table construction and
packs the normal hash and buckets above the resident DOS image. Configured
sets that do not fit retain the original conventional allocation path, so the
supported `BUFFERS=` range is unchanged.

One maximum-sector transfer area is allocated through the normal SYSINIT layout.
After `RW_SC` has had the opportunity to select its own low cache, `DEVIOCALL`
redirects a remaining one-sector HMA read or write to that area. Writes are
copied down before the strategy/interrupt calls; successful reads are copied up
after the retained-low return trampoline has restored A20. The original request
pointer is restored before `VIRREAD` and before any outer critical-error retry.

The failed prototype used `SC_SECTOR_SIZE` as its copy length. That field belongs
to the optional secondary-cache path and may be zero even for a successful
ordinary buffer request, leaving stale HMA data after a driver returned `DONE`.
The retained path uses SYSINIT's maximum sector size, which is the allocation
bound shared by every HMA slot and the low transfer area.

Before relocation compaction, the DOS-high/A20 suite, INT 21h filesystem and
exhaustion suites, and MEM/UMB suite pass locally. The exact VC comparison gains
7,120 bytes in its largest block; the system component itself drops by the
expected 7,488 bytes, while the larger retained DOS path changes the surrounding
fragmented layout by 368 bytes.

### Stage 2: make the reclaimed DOS relocation hole safe — complete

The retained implementation relocates DOS into the HMA, synchronizes SYSINIT's
final exchange block to its low copy, publishes the reclaimed arena, and stores
up to six initial DPBs in resident BIOS memory. It boots the A/B/C comparison
image through `AUTOEXEC.BAT` and VC, recovering 32,928 bytes.

The retained-low driver trampoline requests A20 after each native strategy and
interrupt entry point without changing public XMS nesting counts. The focused
probe sees A20 enabled after the complete calls, but the redirected-ECHO audit
above shows that this end-state check does not yet prove a clean return
boundary; immediate post-entry instrumentation remains required.

External hardware-breakpoint traces reject an allocation-overlap explanation.
The HMA-buffer callback publishes an active 512-byte low transfer area at
`0571:0000`; its device mark extends through `0591`, while the preceding test
driver remains intact at `053A`. A no-op `REM` line after HIMEM is sufficient
to trigger the same failure, so another driver's behavior is not required.
The first failing-operation FAT read and root-directory `GETBUFF` were correct.
The actual mismatch was `THISCDS`: path parsing updated the retained-low SDA to
`0588:0000`, while `TestNet` used an implicit `CS:` override and read the stale
HMA duplicate `0000:043C`. Reading this mutable state through `SS:` gives it one
owner and restores directory, file, and free-space operations after any
post-HIMEM CONFIG line.

The DOS-high/A20, filesystem and exhaustion, internal-structure, HIMEM-option,
and MEM/UMB suites pass locally. A VC 4.05 capture before Stage 3 left 590,768
bytes in the largest conventional block, confirming the reclaimed 32 KiB
remains usable.
CI remains disabled until explicitly restored.

Structures addressed by real-mode near offsets must remain below 1 MiB. Do not
use broad pointer scans or heuristic segment rewriting; every new ownership
transition needs a focused regression.

### Stage 3: reduce and account for resident components — complete

The measured system-component excess is 11,104 bytes. The current paired VC
capture reports COMMAND at 3,840 bytes versus retail's 2,960, a separate
880-byte excess. The retained boundaries are:

- narrow the EMM386 low/high split only at entry points whose reflected,
  protected-only, or dual-mapped ownership is understood. EMS function 56h
  now uses the retained-low `_TEXT` segment for its real-mode return gateway
  rather than truncating the relocated protected-code address. Its physical-
  and segment-map call paths are regression-tested with non-empty maps. The
  `ARPL` gateway still resumes at the same logical offset in the high copy, so
  moving the complete EMS library remains a code-transition redesign rather
  than a linker-only change. Ordinary EMS calls also enter `int67_Entry` in
  the retained real/virtual copy, while only mapping-sensitive calls use the
  protected dispatcher. Moving even the C-only services therefore reclaims
  live code. A future split must preserve inactive `AUTO` queries and activate
  virtual mode only when allocation requires it;
- keep the DMA register snapshot in the retained prefix, but keep the DMA trap
  engine protected-only. This retained split saves 1,072 conventional bytes
  and passes normal, `ON`/`OFF`/`AUTO`, EMS 4.0, frame, `D=`, and capacity
  coverage;
- keep `RRProc` and its return-to-real trap module together until their shared
  virtual-mode continuation is replaced; moving only the handler prevents the
  first runtime `OFF` transition from completing;
- defer the remaining 1,488-byte HIMEM excess while the larger EMM386 and
  DOS/BIOS ranges are investigated, and resume only for a paragraph-scale,
  map-supported opportunity without reducing supported
  option capacity. HIMEM's 32 UMB records have no pad or allocation byte; the
  allocation state uses the otherwise impossible high bit of their paragraph
  size. XMS handle records contain only lock count, base, and size; a zero base
  is the free sentinel because the HMA prevents any live base from being zero.
  This removes three bytes from the original records without losing zero-length
  handles. HMA ownership likewise
  uses `/HMAMIN=`'s unavailable high bit, and the global/local A20 paths share
  identical success tails. XMS 3 wrappers also share identical error exits.
  The installation-only highest-page detector now follows the resident break.
  Together these retain the full extent and 128-handle limits while reducing
  the normal HIMEM allocation by 512 bytes;
  STACKS now uses one nested-safe common dispatcher while each
  vector retains its compatibility header and successor pointer; the default
  9-by-128 pool occupies 1,840 bytes, 16 fewer than retail, and is budget-gated;
- COMMAND's 3,840-byte footprint remains above retail's 2,960 bytes. Its
  DOS-high root break is 3,632 paragraph-aligned program bytes after moving the
  normal resident catalogs and generated message engine to HMA, bounding
  the class table, moving redirection state into initialized transient data,
  and bounding the message workspace; low/failure fallback is 6,080 bytes.
  Closing the remaining 880 bytes
  requires further
  targeted resident-shell work, not correction of an accidentally retained
  transient tail.

Retain the full documented option ranges. Each footprint reduction needs a
component budget assertion and the relevant maximum-capacity test.

Stage 3 evidence is complete:

- EMS functions, including function 56h, pass after any EMM386 split change;
- the normal EMM386 and HIMEM footprints remain budget-gated without reducing
  maximum supported capacities;
- COMMAND's resident excess is explained; and
- the fresh paired VC and `MEM /D` captures provide the figures above.

### Stage 4: reconcile UMB reporting — complete

Goal: explain the remaining arena-layout and reporting differences after the
large conventional losses have been removed.

With the public UMB chain linked, this system exposes free regions of 16,352
bytes at `CC00h` and 32,752 bytes at `E000h`. Retail exposes 15,152 bytes near
`CC4Bh` and 32,736 bytes near `E002h`, so this system provides 1,216 more usable
upper-memory bytes. VC hides the first local region only while the public chain
is unlinked; this is reporting state, not lost memory.

The current 607,936-byte largest block is 10,800 bytes (1.7%) below retail and
every material difference is assigned to a measured component or layout
workstream above. This is an explained baseline, not completion: the fixed
comparison must reach at least 618,736 bytes without reducing option capacity
or retail-equivalent usable upper memory. After every retained-memory change,
repeat the paired VC capture and relevant local suites. CI stays disabled during
active development; local tests remain authoritative until it is restored.

## Evidence

The release suite covers allocator lifecycle and rollback, XMS transactions,
HMA residency and fallback, high loaders, MEM reporting, EMM386 modes and
mapping stability, A20 backends, filesystem/redirector traffic, interrupts,
warm reboot, and provider absence. The machine-readable inventories under
`tests/` and [tests/COVERAGE.md](tests/COVERAGE.md) are authoritative for
current test names and counts. `test_mem_umb_qemu.sh` enforces the 14 KiB
EMM386 and 3 KiB HIMEM conventional-memory budgets. Load-option tests cover
the maximum EMM386 `H=`/`A=` and HIMEM `/NUMHANDLES=` capacities.
