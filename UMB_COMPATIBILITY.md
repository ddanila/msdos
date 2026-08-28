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
| `dos50-umb` | MS-DOS 5.0 | HIMEM, EMM386, `DOS=UMB` | Original UMB contract | basic API captured |
| `dos622-low` | MS-DOS 6.22 | no XMS/UMB provider | 6.22 fallback comparison | basic API captured |
| `dos622-umb` | MS-DOS 6.22 | HIMEM, EMM386, `DOS=UMB` | Final compatibility oracle | basic API captured |

Capture a prepared image without modifying the original:

```sh
tests/capture_umb_reference.sh /path/to/boot.img /tmp/dos622-umb.log
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
| `5801h`, other value or `BH!=0` | carry set, `AX=0001h`, state unchanged | error confirmed; preservation pending | error confirmed; preservation pending | incorrectly accepts |
| `5802h` | carry clear, `AL=0` or `1` | confirmed | confirmed | invalid function |
| `5803h`, `BX=0` or `1` | carry clear with provider; otherwise error and unchanged | confirmed | confirmed | invalid function |
| `5803h`, other `BX` | carry set, `AX=0001h`, state unchanged | confirmed | confirmed | invalid function |
| unknown `58xxh` subfunction | carry set, `AX=0001h`, state unchanged | confirmed | confirmed | invalid function |
| strategy/link independence | neither setter changes the other state | pending | pending | no UMB state |
| state across EXEC | child sees global state; caller restores it | pending | pending | strategy global |

The strategy values and public link-state behavior come from the Microsoft
MS-DOS 5 Programmer's Reference and are retained by 6.22. Invalid-input and
preserved-register details remain reference-gated where the manuals are silent.

## Allocation and arena behavior

| Contract | Required observation | DOS 5.0 | DOS 6.22 |
| --- | --- | --- | --- |
| low-only `00h..02h` | never allocate from a UMB | pending | pending |
| upper-only `40h..42h` | fail rather than fall back low | pending | pending |
| upper-then-low `80h..82h` | allocate upper first, then conventional | pending | pending |
| unlinked UMB arena | high strategy allocates conventionally without changing either setting | confirmed | confirmed |
| link with no provider | exact link state and error behavior | pending | pending |
| `48h` failure | exact `AX` and largest-domain block in `BX` | pending | pending |
| `49h`/`4Ah` on UMB | same ownership, resize, and errors as low blocks | pending | pending |
| unlink with live UMB | allocation survives unlink/relink | pending | pending |
| process termination | owned UMB blocks are freed | pending | pending |
| MCB traversal | exact bridge, gap-owner, and `M`/`Z` layout | pending | pending |

With the UMB arena linked, a 16-paragraph allocation using either strategy
`0040h` or `0080h` landed above `A000h` in both references (`CB02h` on 5.0;
`CC4Bh` on 6.22). After explicitly unlinking a populated UMB arena, strategy
`0040h` allocated conventionally on both references (`12AEh` on 5.0 and
`11CBh` on 6.22), without changing the strategy or link setting. With no
provider and no link, the same calls also allocated conventionally. Exhaustion
and fragmentation probes are still required to distinguish the upper-only and
upper-then-low fallback contracts empirically.

## Boot and command interfaces

| Surface | Required observation | DOS 5.0 | DOS 6.22 |
| --- | --- | --- | --- |
| `DOS=UMB` without provider | silent, remains usable low | pending | pending |
| `DOS=NOUMB` | disables DOS UMB management | n/a or pending | pending |
| `DOS=HIGH` failure | exact message, loads DOS low | pending | pending |
| `DOS=HIGH,UMB` | independent HMA and UMB state | pending | pending |
| `DEVICEHIGH` no fit | falls back to `DEVICE` | pending | pending |
| `DEVICEHIGH SIZE=` | DOS 5 legacy placement semantics | pending | pending |
| `DEVICEHIGH /L /S` | region/minimum/shrink behavior | n/a | pending |
| `LOADHIGH`/`LH` | largest UMB, conventional fallback | pending | pending |
| `LOADHIGH /L /S` | child region visibility and restoration | n/a | pending |
| `INSTALLHIGH` | existence, syntax, and fallback | pending | pending |
| `MEM /C /D /F /M` | region numbering and accounting | pending | pending |

This tree now accepts case-insensitive `DOS=HIGH`, `LOW`, `UMB`, and `NOUMB`
tokens, comma-separated pairs, and repeated `DOS=` lines. The HMA and UMB
effects remain delivery-gated; without a provider, `DOS=UMB` is silent and the
kernel remains unlinked.

As an independent provider check, this tree was booted with the locally held
MS-DOS 5.0 HIMEM 2.78 and EMM386 4.33.06X binaries under the reference QEMU
configuration. SYSINIT acquired the provider's `CB00h` UMB through XMS, public
link/unlink calls matched the 5.0 register results, and both `0040h` and `0080h`
16-paragraph allocations returned `CB02h`. Those Microsoft binaries remain
outside this repository and are not required by its build or CI.

CI uses an original test-only XMS provider with writable synthetic backing. It
proves that out-of-order discontiguous extents are sorted and committed as one
arena, while partial failure, overlap, undersized ranges, and ranges conflicting
with conventional memory release all provider allocations and leave `5803h`
unavailable. This fixture implements only the XMS calls needed by the test and
does not ship as an XMS manager.

## Evidence required to close Phase 0

- Capture all four reference configurations above.
- Extend the probe with MCB, EXEC, resize, and fragmentation scenarios after the
  basic results establish safe traversal rules.
- Add separate CONFIG.SYS, DEVICEHIGH, LOADHIGH, MEM, and HMA probes.
- Record exact flags, errors, preserved registers, messages, region numbers,
  memory placement, and MCB layouts.
- Resolve every `pending` entry needed by a delivery phase before that phase is
  declared complete.
