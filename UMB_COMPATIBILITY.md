# UMB compatibility matrix

This matrix freezes the observable MS-DOS 5.0/6.22 contract before kernel
implementation. Documentation establishes the public contract. Results marked
`reference pending` require execution of `tests/umb_api_probe.asm` against
local reference media before the affected implementation stage closes.

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
tests/capture_xms_reference.sh /path/to/boot.img /tmp/dos622-xms.log
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
| strategy/link independence | neither setter changes the other state | pending | pending | no UMB state |
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
| low-only `00h..02h` | never allocate from a UMB | pending | pending |
| upper-only `40h..42h` | fail rather than fall back low | confirmed | confirmed |
| upper-then-low `80h..82h` | allocate upper first, then conventional | confirmed | confirmed |
| unlinked UMB arena | high strategy allocates conventionally without changing either setting | confirmed | confirmed |
| link with no provider | exact link state and error behavior | pending | pending |
| `48h` failure | exact `AX` and largest-domain block in `BX` | confirmed | confirmed |
| `49h`/`4Ah` on UMB | same ownership, resize, and errors as low blocks | confirmed | confirmed |
| unlink with live UMB | allocation survives unlink/relink | confirmed | confirmed |
| process termination | owned UMB blocks are freed | confirmed | confirmed |
| MCB traversal | exact bridge, gap-owner, and `M`/`Z` layout | pending | pending |

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

The focused lifecycle capture also confirms shrink and growth, failed growth's
maximum-size result, free, exact exhaustion, and unlink/relink with a live data
word. On both references a failed `4Ah` growth coalesced the block to the
reported maximum and left its MCB marked `Z`. With the same DOS 5 provider this
tree now matches the reference's `14FEh` largest UMB exactly; the earlier
test-only terminal guard had reduced it by one paragraph.

The same independent parent/child probe succeeds on DOS 5.0, DOS 6.22, and
this tree. The child inherits linked upper-only allocation state, allocates a
64-paragraph UMB, and exits with status `2Ah`; the parent observes its strategy
and link settings unchanged and immediately reallocates the reclaimed upper
block. The recovered reference segments were `CB4Eh` on 5.0 and `CC98h` on
6.22; the address itself is provider-layout dependent.

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
UMB survives repeated EMS remapping. Broader initialization fault injection
and warm-reboot coverage remain open provider gates.

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
| `DOS=UMB` without provider | silent, remains usable low | pending | pending |
| `DOS=NOUMB` | disables DOS UMB management | n/a or pending | pending |
| `DOS=HIGH` failure | exact message, loads DOS low | pending | pending |
| `DOS=HIGH,UMB` | DOS owns HMA, A20 on; UMB state remains independent | confirmed | confirmed |
| `DEVICEHIGH` no fit | falls back to `DEVICE` | pending | pending |
| `DEVICEHIGH SIZE=` | DOS 5 legacy placement semantics | confirmed (basic placement/tail) | confirmed (basic placement/tail) |
| `DEVICEHIGH /L /S` | region/minimum/shrink behavior | n/a | partial; single-region placement confirmed |
| `LOADHIGH`/`LH` | largest UMB, conventional fallback | pending | pending |
| `LOADHIGH /L /S` | child region visibility and restoration | n/a | pending |
| `INSTALLHIGH` | existence, syntax, and fallback | not recognized | confirmed (basic execution high) |
| `MEM /C /D /F /M` | region numbering and accounting | pending | pending |

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
the exact minimum-size and shrink boundary still needs a parameter sweep before
that behavior is encoded.

The matching program oracle establishes that DOS 6.22 recognizes
`INSTALLHIGH=` and executed the test program at `CC4Eh`. DOS 5.0 did not execute
the same directive, so `INSTALLHIGH` is a 6.22 compatibility extension rather
than part of the initial 5.0 surface. Normalized captures are kept outside Git
beside the locally owned reference images; only probe source and the capture
harness are committed.

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
old interrupt chain. Exact unavailable-HMA diagnostics, asynchronous callback
coverage, redirectors, warm reboot, and MEM residency output are still open.

CI uses an original test-only XMS provider with writable synthetic backing. It
proves that out-of-order discontiguous extents are sorted and committed as one
arena. No UMB service, no free ranges, failed requests, partial failure,
overlap, undersized or wrapping ranges, conventional-memory conflicts, and a
map exceeding descriptor capacity all leave `5803h` unavailable and release
every extent DOS acquired. Repeated `UMB`/`NOUMB` lines also prove that disabled
management does not contact the provider. This fixture implements only the XMS
calls needed by the test and does not ship as an XMS manager.

## Evidence required to close Phase 0

- Capture all four reference configurations above.
- Extend the probe with MCB, EXEC, resize, and fragmentation scenarios after the
  basic results establish safe traversal rules.
- Add separate CONFIG.SYS, DEVICEHIGH, LOADHIGH, MEM, and HMA probes.
- Record exact flags, errors, preserved registers, messages, region numbers,
  memory placement, and MCB layouts.
- Resolve every `pending` entry needed by a delivery phase before that phase is
  declared complete.
