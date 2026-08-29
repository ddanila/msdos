# UMB compatibility matrix

This matrix freezes the observable MS-DOS 5.0/6.22 contract before kernel
implementation. Documentation establishes the public contract and focused
clean-room probes resolve ambiguous details against local reference media.

No proprietary image, executable, or byte-derived fixture belongs in this
repository. Normalized textual observations may be recorded here with the DOS
version, configuration, emulator or hardware, and probe commit.

## Reference configurations

| ID | System | CONFIG.SYS state | Purpose | Status |
| --- | --- | --- | --- | --- |
| `dos50-low` | MS-DOS 5.0 | no XMS/UMB provider | API fallback and invalid inputs | basic API captured |
| `dos50-umb` | MS-DOS 5.0 | HIMEM, EMM386, `DOS=UMB` | Original UMB contract | API and allocator lifecycle captured |
| `dos622-low` | MS-DOS 6.22 | no XMS/UMB provider | 6.22 fallback comparison | basic API captured |
| `dos622-umb` | MS-DOS 6.22 | HIMEM, EMM386, `DOS=UMB` | Final compatibility oracle | API and allocator lifecycle captured |

Capture a prepared image without modifying the original:

```sh
tests/capture_umb_reference.sh /path/to/boot.img /tmp/dos622-umb.log
tests/capture_umb_lifecycle_reference.sh /path/to/boot.img /tmp/dos622-life.log
tests/capture_umb_register_reference.sh /path/to/boot.img /tmp/dos622-regs.log
tests/capture_umb_loader_sequence.sh /path/to/boot.img /tmp/dos50-loader.log
tests/capture_xms_reference.sh /path/to/boot.img /tmp/dos622-xms.log
tests/capture_loadhigh_reference.sh /path/to/dos622.img /tmp/dos622-loadhigh.log
```

The prepared UMB images retain their own legally obtained HIMEM/EMM386 files
and CONFIG.SYS. The harness copies the image, replaces only AUTOEXEC.BAT in the
copy, runs the probe, and emits the normalized serial section.

The captures above used QEMU's `pc` machine with a 486 CPU and 16 MiB RAM.
The local media came from Internet Archive items `en_msdos50.zip` and
`msdos6_22`. The MS-DOS 5.0 archive SHA-256 is
`ad6c6a7556ba4b38bf6d98b96b6eb64a2bb8777a1bac12394579ed83f4084f3d`.
The three MS-DOS 6.22 disk SHA-256 values, in disk order, are
`e02d9c046f3b0108fc20252844ae305029a35a1d887c4b57b43193fcc074783d`,
`b7fcafd3b635066af121d9d0f46fadc597eb7b3cd1ab7f838fac55f0fb3b4f79`,
and `e2c0ede60d5de23f77c35de371de9ba9df60905af3fe9a695dc270c8a0e8e380`.

## INT 21h allocation control

| Contract | Documented result | DOS 5.0 | DOS 6.22 | This tree initially |
| --- | --- | --- | --- | --- |
| `5800h` default | `AX=0000h`, carry clear | confirmed | confirmed | first fit |
| `5801h`, `0000h..0002h` | accept and round-trip | confirmed | confirmed | accepts |
| `5801h`, `0040h..0042h` | accept and round-trip | confirmed | confirmed | incorrectly treated as last fit |
| `5801h`, `0080h..0082h` | accept and round-trip | confirmed | confirmed | incorrectly treated as last fit |
| `5801h`, other value or `BH!=0` | carry set, `AX=0001h`, state unchanged | confirmed | confirmed | incorrectly accepts |
| `5802h` | carry clear, `AL=0` or `1` | confirmed | confirmed | invalid function |
| `5803h`, `BX=0` or `1` | carry clear with provider; otherwise error and unchanged | confirmed | confirmed | invalid function |
| `5803h`, other `BX` | carry set, `AX=0001h`, state unchanged | confirmed | confirmed | invalid function |
| unknown `58xxh` subfunction | carry set, `AX=0001h`, state unchanged | confirmed | confirmed | invalid function |
| strategy/link independence | neither setter changes the other state | confirmed | confirmed | no UMB state |
| state across EXEC | child sees global state; caller restores it | confirmed | confirmed | confirmed |

The strategy values and public link-state behavior come from the Microsoft
MS-DOS 5 Programmer's Reference and are retained by 6.22. A focused black-box
capture confirms that `CX`, `DX`, `SI`, `DI`, `BP`, `DS`, and `ES` survive all
four calls and invalid subfunctions on both references. `BX` also survives;
the setters leave successful `AX` unchanged, `5802h` changes only `AL`, and
invalid calls return `AX=0001h` with carry set. The synthetic-provider test
asserts the same contract in this tree.

## Allocation and arena behavior

| Contract | Required observation | DOS 5.0 | DOS 6.22 |
| --- | --- | --- | --- |
| standard `00h..02h` | scan the complete linked public arena chain | confirmed | confirmed |
| upper-only `40h..42h` | fail rather than fall back low | confirmed | confirmed |
| upper-then-low `80h..82h` | allocate upper first, then conventional | confirmed | confirmed |
| unlinked UMB arena | high strategy allocates conventionally without changing either setting | confirmed | confirmed |
| link with no provider | exact link state and error behavior | confirmed | confirmed |
| `48h` failure | exact `AX` and largest-domain block in `BX` | confirmed | confirmed |
| `49h`/`4Ah` on UMB | same ownership, resize, and errors as low blocks | confirmed | confirmed |
| unlink with live UMB | allocation survives unlink/relink | confirmed | confirmed |
| process termination | owned UMB blocks are freed | confirmed | confirmed |
| MCB traversal | exact bridge, gap-owner, and `M`/`Z` layout | confirmed | confirmed |

The linked-chain layout capture establishes both the reserved bridge and the
terminal UMB. DOS 5.0 exposes a DOS-owned `M` block at `9FFFh`, size `2B01h`,
followed by a free `Z` block at `CB01h`, size `14FEh`. DOS 6.22 exposes the same
shape with the bridge size `2C4Ah` and terminal free block at `CC4Ah`, size
`1BB5h`. The lifecycle capture separately verifies signature and size changes
through allocation, resize, unlink/relink, exact exhaustion, and free.

With the UMB arena linked, a 16-paragraph allocation using either strategy
`0040h` or `0080h` landed above `A000h` in both references (`CB02h` on 5.0;
`CC4Bh` on 6.22). After explicitly unlinking a populated UMB arena, strategy
`0040h` allocated conventionally on both references (`12AEh` on 5.0 and
`11CBh` on 6.22), without changing the strategy or link setting. With no
provider and no link, the same calls also allocated conventionally. Exhaustion
then confirmed the domain distinction: one paragraph beyond the largest UMB
failed under `0040h` with `AX=0008h` and the UMB maximum in `BX`, while `0080h`
allocated the same request conventionally. Fragmentation ordering across
multiple genuine regions remains a reference uncertainty.

The refreshed API capture also makes the independence rules explicit. Linking
left strategy `0000h` unchanged and setting strategy `0040h` left link state 1.
Strategies `0000h..0002h` scan the linked public chain rather than imposing a
conventional-only domain: first fit selected the earlier conventional block
(`12BFh` on 5.0 and `11DCh` on 6.22), while best fit selected an upper block
(`CB02h` and `CC4Bh`) and last fit selected the last upper block (`DFF0h` and
`E7F0h`). On provider-free boots both references rejected link and unlink with
`CF=1`, `AX=0001h`, while `5802h` continued to report zero.

The focused lifecycle capture also confirms shrink and growth, failed growth's
maximum-size result, free, exact exhaustion, and unlink/relink with a live data
word. On both references a failed `4Ah` growth coalesced the block to the
reported maximum and left its MCB marked `Z`. With the same DOS 5 provider this
tree now matches the reference's `14FEh` largest UMB exactly; the earlier
test-only terminal guard had reduced it by one paragraph.

A deterministic 1,000-operation shadow-model stress now selects all three UMB
fit policies while randomly allocating, resizing, and freeing blocks across a
split provider map. After every operation it checks interval non-overlap, MCB
owner and size, and sentinels at both ends of every live allocation. Failed
growth adopts DOS's reported maximum block size in the model, so subsequent
operations also exercise the reference-compatible coalescing side effect.

The same independent parent/child probe succeeds on DOS 5.0, DOS 6.22, and
this tree. The child inherits linked upper-only allocation state, allocates a
64-paragraph UMB, and exits with status `2Ah`; the parent observes its strategy
and link settings unchanged and immediately reallocates the reclaimed upper
block. The recovered reference segments were `CB4Eh` on 5.0 and `CC98h` on
6.22; the address itself is provider-layout dependent.

A focused loader-sequence probe links the arena, selects strategy `0040h`,
requests `7FFFh` and `FFFFh` paragraphs, and allocates the maximum returned in
`BX`. Genuine DOS 5.0 reports `14FEh` for both failed requests and allocates it
at `CB02h`. This tree reports the provider-specific maximum for both requests
and allocates that exact block in its UMB arena. As a separate black-box
interoperability check, unmodified FreeDOS DEVLOAD 3.25 `/H` loads the original
clean-room test driver high (`D801h`) on the current tree; no FreeDOS source or
binary is part of the repository or CI.

## XMS provider contract

The independent XMS capture identifies DOS 5 HIMEM 2.78 as XMS 2.00 and DOS
6.22 HIMEM 3.10 as XMS 3.00. Both successfully exercise HMA ownership, local
A20 enable/query/disable, and the XMS 2.00 extended-memory allocate, handle-information,
lock, unlock, resize, and free lifecycle. After `DOS=UMB` has acquired the
provider map, a largest-UMB request fails with `BL=B1h` and `DX=0000h`, and an
invalid release fails with `BL=B2h`. Both references return `BL=80h` for UMB
reallocation function `12h` and the following unknown function. This makes a
complete XMS 2.00 implementation with optional `10h`/`11h` the repository
provider's compatibility target; it must not advertise XMS 3.00.

The repository provider now passes the captured XMS success-path lifecycle and
boots together with the repository EMM386. EMM386 owns the paging translations
and removes permanent UMB backing pages from its EMS pool; HIMEM owns the
public XMS allocation state. A combined test confirms DOS-visible UMBs and a
functioning EMS API in one boot. Error-path parity now covers the principal
XMS 2.00 handle, move, HMA, and A20 failures. Physical A20 alias detection and
independently forced fast-gate, BIOS, and 8042 control paths pass under QEMU.
Registration rejection rolls back to EMS-only operation, and a live patterned
UMB survives repeated EMS remapping. Ten deterministic initialization fault
variants cover discovery, acquisition, mapping, registration, finalization,
and rollback boundaries without leaving partial UMB state. A monitor-driven warm-reset test now performs
two complete `DOS=HIGH,UMB` boots from the same image and requires HMA
ownership, UMB lifecycle, EMS isolation, and the EMS API to pass on both.

The pre-386 fallback is also exercised outside QEMU. DOSBox-X boots the same
image as both an 8086 and an 80286 with HIMEM, EMM386, and `DOS=HIGH,UMB`
requested. EMM386 rejects the processor before executing any 386 instruction;
the boot continues with no EMM386 UMB provider, link requests fail cleanly,
and ordinary allocations remain conventional. This caught an original
`Is386` call site that tested restored zero state instead of the routine's
documented carry result.

The expanded DOS 5.0/6.22 error capture agrees on invalid-handle `A2h`, locked
block `ABh`, unlocked-block `AAh`, odd or out-of-range move `A7h`, invalid
source/destination handle `A3h`/`A5h`, exhausted-memory `A0h`, duplicate HMA
ownership `91h`, unowned HMA release `93h`, and A20 nesting error `82h`.
Both reference managers accept overlapping moves in either direction. Zero-KiB
extended-memory allocations consume a real handle and report a zero-sized
block. With EMM386 already owning one handle, both references allow the probe
to obtain 31 further handles and then return `A1h`; the repository manager
allows all 32 when run without that peer allocation. A 256th lock returns
`ACh`, and an unlock below zero returns `AAh`. These observed results are
asserted against the repository manager.

## Boot and command interfaces

| Surface | Required observation | DOS 5.0 | DOS 6.22 |
| --- | --- | --- | --- |
| `DOS=UMB` without provider | silent, remains usable low | confirmed | confirmed |
| `DOS=NOUMB` | disables DOS UMB management | confirmed | confirmed |
| `DOS=HIGH` failure | exact message, loads DOS low | confirmed | confirmed |
| `DOS=HIGH,UMB` | DOS owns HMA, A20 on; UMB state remains independent | confirmed | confirmed |
| `DEVICEHIGH` no fit | falls back to `DEVICE` | not separately captured | confirmed |
| `DEVICEHIGH SIZE=` | DOS 5 legacy placement semantics | confirmed (basic placement/tail) | confirmed (basic placement/tail) |
| `DEVICEHIGH /L /S` | region/minimum/shrink behavior | n/a | partial; single-region placement confirmed |
| `LOADHIGH`/`LH` | largest UMB, conventional fallback | confirmed | confirmed |
| `LOADHIGH /L /S` | child region visibility and restoration | n/a | confirmed |
| `INSTALLHIGH` | existence, syntax, and fallback | not recognized | confirmed (basic execution high) |
| `MEM /C /D /F /M` | region numbering and accounting | not separately captured | confirmed |

This tree now accepts case-insensitive `DOS=HIGH`, `LOW`, `UMB`, and `NOUMB`
tokens, comma-separated pairs, and repeated `DOS=` lines. The HMA and UMB
effects remain delivery-gated; without a provider, `DOS=UMB` is silent and the
kernel remains unlinked.

The clean-room `devicehigh_reference_driver.asm` oracle records its actual
load segment and the INIT command tail. With genuine HIMEM and EMM386 loaded,
DOS 5.0 placed plain `DEVICE` at `0E63h` and `DEVICEHIGH` at `CB03h`; DOS 6.22
placed them at `0D6Fh` and `CC4Ch`. Both releases honored a `DEVICEHIGH` line
that precedes `DOS=UMB`, proving that the requested DOS state is established
independently of textual order. Both accepted the DOS 5
`DEVICEHIGH SIZE=200` spelling, loaded the driver high, and removed the loader
option from the driver's command tail. DOS 6.22 likewise accepted
`DEVICEHIGH /L:1=`. The observed `DEVICEHIGH /L:1,200 /S=` case loaded low;
the minimum is a decimal byte count, whereas the legacy `SIZE=` value is
hexadecimal. A split-map capture confirms that `/L:1` and `/L:2` place the
driver in different regions (`CC4Ch` and `D803h`), while `/L:1;2` selects the
first suitable region. Every listed minimum is validated: the
`1,40000;2,10000 /S` profile fell low, whereas `1,10000;2,40000 /S` loaded
high. This tree reproduces those single- and multiple-region behaviors:
`/L` limits the allocator to the named provider region, an unavailable region
or an unsatisfied minimum falls back to conventional memory, and `/S` limits
each region to its own stated minimum before falling back low if the complete
driver image does not fit. Region selection is scoped to the load and all caps,
the public allocation strategy, and link state are restored afterward.

The matching program oracle establishes that DOS 6.22 recognizes
`INSTALLHIGH=` and executed the test program at `CC4Eh`. DOS 5.0 did not execute
the same directive, so `INSTALLHIGH` is a 6.22 compatibility extension rather
than part of the initial 5.0 surface. Normalized captures are kept outside Git
beside the locally owned reference images; only probe source and the capture
harness are committed.

This tree now implements that confirmed extension through the existing
`INSTALL=` EXEC/TSR lifecycle. A scoped upper-first allocation transaction is
restored on return, and the integration test proves high TSR placement,
argument-tail preservation, `DOS=` ordering independence, and conventional
fallback when no provider is installed.

The focused 6.22 LOADHIGH capture confirms that DOS keeps the UMB arena
publicly unlinked at the prompt even with `DOS=UMB`. During a successful high
load the child observes strategy `0080h` and link state 1; both return to
strategy `0000h` and link state 0 afterward. With a split UMA map,
`/L:1`, `/L:2`, and `/L:1;2` select the numbered regions. A nonexistent region
prints `A bad UMB number has been specified` and does not execute the child.
Every listed minimum must be satisfiable before the scoped high-load state is
entered; otherwise 6.22 executes the child through the ordinary low path.
`/S` caps regions that have minima, which can force conventional placement,
while `/S` without `/L` is accepted and behaves like plain LOADHIGH. The
normalized capture is produced by `tests/capture_loadhigh_reference.sh` and is
kept beside the external reference media.

This tree now parses and removes those LOADHIGH/LH options before normal
command resolution, validates every named region and minimum against the live
arena, and installs a scoped region profile around EXEC. The kernel allocator
reports each region's largest coalescible free block and can temporarily cap
the allocatable prefix of each region, so `/S` governs the environment, PSP,
and image allocations rather than merely checking the final PSP address. A
failed minimum uses the ordinary low EXEC state, an invalid region emits the
captured diagnostic without running the child, and filters, caps, strategy,
and link state are restored after successful and failed EXEC calls. Synthetic
split-region tests cover individual regions, lists, per-region minima, forced
low placement, and recovery after a missing executable. The command-path test
also proves that the child environment MCB is owned by its PSP, LOADHIGH's own
options are absent from quoted argument tails, redirected output is recovered
from the target file, batch `ERRORLEVEL` preserves the child's value, and a
Ctrl-C termination restores allocator state before another successful high
load.

## HMA residency reference

An independent probe now compares otherwise identical `DOS=LOW,UMB` and
`DOS=HIGH,UMB` boots. In low mode, both HIMEM versions report A20 disabled and
allow the probe to acquire the HMA. In high mode, A20 is enabled and an HMA
request fails with `BL=91h`, proving DOS owns it. Under the captured 16 MiB
NOEMS configurations, DOS 5.0's largest conventional block increases from
`8D80h` to `9952h` paragraphs (48,416 bytes), while DOS 6.22 increases from
`8E63h` to `9A8Dh` paragraphs (49,824 bytes). These measurements are layout
oracles, not universal free-memory constants; the ownership and A20 state are
the portable contract.

As an independent provider check, this tree was booted with the locally held
MS-DOS 5.0 HIMEM 2.78 and EMM386 4.33.06X binaries under the reference QEMU
configuration. SYSINIT acquired the provider's `CB00h` UMB through XMS, public
link/unlink calls matched the 5.0 register results, and both `0040h` and `0080h`
16-paragraph allocations returned `CB02h`. Those Microsoft binaries remain
outside this repository and are not required by its build or CI.

The repository `DOS=HIGH` runtime now acquires the HMA through XMS, relocates
the persistent kernel image to `FFFF:0010h`, redirects DOS-owned vectors, and
returns the relocated conventional code tail to the MCB arena. Its QEMU test
compares otherwise identical HIGH and LOW boots, verifies HMA ownership and A20
state, requires at least `0700h` additional free paragraphs, and repeats the
measurement after EXEC and child cleanup. A deliberately hostile test driver
hooks INT 21h before relocation and disables A20 during device calls; the
retained low gateways and driver trampoline must recover without losing the
old interrupt chain. Asynchronous callbacks, redirectors, warm reboot, and MEM
residency output are exercised by the repository tests. The asynchronous test
runs INT 23h Ctrl-Break and INT
28h idle callbacks with DOS low and high; the IFSFUNC/FILESYS lifecycle runs in
both residency modes; the warm-reset test repeats the full HMA/UMB/EMS contract
on two boots; and `test_mem_umb_qemu.sh` checks the HMA residency view. The
exact unavailable-HMA wording is captured below.

The incremental UMB conventional-memory budget is enforced by
`tests/test_mem_umb_qemu.sh`. Two otherwise identical 16 MiB boots use HIMEM,
`DOS=HIGH,UMB`, an EMS page frame, and the same EMM386 build; the baseline uses
plain EMS mode and the comparison uses `RAM`. Publishing the UMB map reduces
free conventional memory by only 16 bytes (`533616` to `533600`), within the
accepted 1 KiB ceiling, while increasing usable free memory below 1 MiB by
49,088 bytes (`533616` to `582704`). The larger inherited EMM386 monitor is
common to both cases and is therefore not misclassified as UMB overhead.

The no-XMS video-memory captures resolve that final wording ambiguity. DOS 5.0
prints `HMA not available : Loading DOS low`, while DOS 6.22 prints
`HMA not available: Loading DOS low`. This tree follows the plan's 6.22-facing
contract and asserts the latter exact line from live video memory before the
low-resident AUTOEXEC path completes.

CI uses an original test-only XMS provider with writable synthetic backing. It
proves that out-of-order discontiguous extents are sorted and committed as one
arena. No UMB service, no free ranges, failed requests, partial failure,
overlap, undersized or wrapping ranges, conventional-memory conflicts, and a
map exceeding descriptor capacity all leave `5803h` unavailable and release
every extent DOS acquired. Repeated `UMB`/`NOUMB` lines also prove that disabled
management does not contact the provider. This fixture implements only the XMS
calls needed by the test and does not ship as an XMS manager.

## Remaining reference evidence

The four base configurations and the API, MCB, EXEC, resize, CONFIG.SYS,
DEVICEHIGH, LOADHIGH, MEM, and HMA surfaces have focused captures. The remaining
acceptance work is the plan's cycle-accurate 386+ run and broader fragmentation
ordering across multiple genuine provider regions; neither is inferred from
the synthetic provider tests.
