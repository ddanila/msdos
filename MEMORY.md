# DOS 6.22 memory model

This document records the durable HMA, UMB, XMS, and EMS constraints. Detailed
delivery history belongs in Git; current evidence belongs in the test manifests.

## Current architectural priority

Maximize the largest conventional block by relocating complete resident
allocations, not by continuing isolated instruction or paragraph reductions.
The DR-DOS runtime maps show kernel, BIOS services, shell, and buffers in HMA,
with other DOS state in UMBs. Enabling `HIDOS=ON` alone recovers 12,800
conventional bytes in the controlled DR-DOS 6 matrix. This is placement
evidence, not a further 12,800-byte local opportunity: our buffers and kernel
are already high.

The normal fixed image leaves 610,256 conventional bytes and 49,104 free UMB
bytes. Development BIOS/table relocation leaves 614,448 and 47,904, versus
retail's 618,736 and 47,888. Its 4,192-byte gain comprises 3,008 bytes of BIOS
reclamation and 1,184 bytes of FILES/FCB placement; promotion remains gated by
compatibility tests. The framed DR-DOS FILES=20 capture leaves 628,352
conventional bytes but only 16,032 free UMB bytes. Resource and device-topology
differences remain; that result does not prove our two floors achievable by
copying its UMB policy.

The newer combined fine-UMB development fixture retains 614,448 conventional
bytes and exposes 52,000 free UMB bytes. Its 4,112-byte margin over retail is
now a measured destination budget for complete DOS-data placement, not a
conventional-memory gain. It remains development-only; see the combined VC
checkpoint below for evidence and scope.

Adding complete CDS placement to that fine-mapping fixture now leaves
**616,752 conventional bytes and 49,680 free UMB bytes**. The conventional gap
to retail is 1,984 bytes, with a 1,792-byte UMB margin. This is a measured
development result, not production promotion or completion of the DR-DOS-style
layout. The COMMAND critical-body reclamation variant remains separate.

Execution order (supersedes older implementation queues below):

**Blocking ownership defect:** SETVER's 640-byte table is not intact in the
normal low fixture, and its high-mode public pointer aliases the development
BIOS HMA payload. Repair and qualify this owner before further reclamation or
promotion; the passing high ASSIGN run omitted its compatibility mapping.
See the SETVER ownership investigation below. Existing memory totals are
measurements, not proof that all requested features survived placement.

1. Complete the joint resident-layout checkpoint below before extending any
   individual relocation prototype. Preserve pending access-boundary work as
   preparation, not as a memory-saving result. Include measured fine-UMB and
   CDS placement in the joint budget; do not count the newly consumed UMB
   capacity again or replace remaining compatibility gates with size checks.
2. Finish acceptance of the bulk BIOS/table relocation, including SHARE and
   redirector consumers. Distinguish pre-existing low-mode failures from
   relocation regressions; neither is a passing acceptance result.
3. Budget the remaining BIOS services and DOS state together. Assign each
   allocation one authoritative owner, low/HMA/UMB destination, access contract,
   fallback, and net reclaimable conventional span. Development retains 5,152
   BIOS bytes and a 4,992-byte kernel prefix; these inventories are not promised
   savings. Public A20-off pointers cannot automatically become HMA pointers.
4. Share HMA capacity between BIOS, state, buffers, and COMMAND. At fifteen
   buffers, the calculated normal post-COMMAND tail is 15,533 bytes and the development
   BIOS reservation costs 5,220 more. Coarse development has only 16 bytes of
   free-UMB margin; combined fine mapping raises this to 4,112, and CDS placement
   consumes 2,320 of those bytes, leaving 1,792. Charge new
   allocations and their arena overhead against the selected variant's budget.
5. Revisit COMMAND as a complete resident-handler/state and reload-interface
   redesign after the system placement budget. Keep isolated HIMEM/EMM386
   harvesting paused; EMM386 is already 240 bytes below retail. EBDA recovery
   remains a bounded 1 KiB finishing step.

Use the controlled transitions and raw ownership maps in the DR-DOS sections
below. No DR-DOS source or disassembly is permitted. Older incremental results
are historical evidence, not the execution queue.

The next design checkpoint is a single post-boot resident layout and net budget
covering BIOS, DOS state, COMMAND, and the memory-manager interfaces. It must
account for at least the remaining 1,984-byte development-to-retail conventional
gap while preserving the UMB floor and requested resources; candidate inventory
alone does not meet that budget. Count gateway, alignment, cache displacement,
and retained-copy costs, and prove that released low ranges join the largest
block. The pending UMB/DMA work is a correctness prerequisite, not a new
memory-saving tranche. Do not replace this checkpoint with further isolated
routine compaction.

The targeted OpenDOS 7.01 follow-up now reproduces a 628,080-byte conventional
block with an EMS frame and 47,584 free UMB bytes, just 304 below the retail UMB
floor. Its small manager UMB allocation survives the frame. This makes the
combined XMS/EMS resident interface a serious architectural candidate alongside
DOS/COMMAND placement, not a reason for further EMM386 instruction shrinking.
The cold-boot comparison is usable placement evidence; the new warm-reset
comparison fails and remains explicitly unqualified (details below).

The combined fine-UMB/CDS development-to-retail residual reconciles as follows;
these are accounting
differences, not independently reclaimable allocations:

| Contribution | Conventional deficit, bytes |
| --- | ---: |
| DOS/BIOS and remaining system layout, excluding the two memory managers | -1,168 |
| HIMEM | 1,488 |
| EMM386 | -240 |
| COMMAND owner span | 880 |
| Conventional ceiling / EBDA | 1,024 |
| **Total** | **1,984** |

Do not turn this into five byte-harvesting quotas. A bulk placement change can
outperform a retail component and cover another owner's excess. The next
design must identify actual released intervals, their replacement gateways,
and where each live allocation goes. The current development HMA capacity is
10,313 bytes after COMMAND and the BIOS reservation, whereas
free UMB has 1,792 bytes of margin after CDS placement. Capacity is not a predicted saving:
moving a public table into HMA may be invalid, and a retained low duplicate
saves nothing. An additional 1,984 net bytes would meet retail; exceeding it
requires a further measured placement budget.

The DR-DOS comparison also needs the combined HIMEM/EMM386 ownership, not
EMM386 alone. OpenDOS's integrated provider is a measured placement lead, not proof
that merging our providers removes their summed allocations. Keep third-party
XMS support and the 286 path when evaluating a shared-provider design.

### DR-DOS reassessment: explain the resident boundary, not the byte deficit

The saved framed OpenDOS 7.01 map places 28,464 kernel bytes, 3,968 BIOS
service bytes, 5,296 COMMAND bytes and 7,980 buffer bytes in HMA. It reports
9,092 HMA bytes still free. Its low BIOS region is 2,304 bytes and its COMMAND
program allocation is 496 bytes; the complete COMMAND owner span is 1,312.
These are runtime-reported categories, not reconstructed implementation details.

The controlled HIDOS transition moves a whole DOS-state allocation: 12,800
conventional bytes in DR-DOS 6, including buffers, versus 5,008 in OpenDOS,
where buffers are already high. Do not count those gains again locally: our
kernel and buffers are high, and the combined development fixture already
relocates BIOS services, FILES/FCBs and CDS.

| Matched accounting boundary | Combined development | Framed OpenDOS 7.01 | Difference |
| --- | ---: | ---: | ---: |
| System start to COMMAND start | 19,072 | 10,416 | 8,656 |
| COMMAND start to VC start | 3,984 | 1,312 | 2,672 |
| Largest conventional block | 616,752 | 628,080 | -11,328 |
| Free UMB | 49,680 | 47,584 | 2,096 |

Both captures retain the 639 KiB ceiling and the same VC footprint between
owner boundaries. Thus the 11,328-byte conventional difference is below VC,
not video recovery or EBDA relocation. Matching accounting boundaries does
not imply equivalent device topology or resource semantics. OpenDOS also
misses the retail UMB floor by 304 bytes and its framed reset gate failed.
Normalize those conditions before treating its largest block as an acceptance
target. The retail floor remains mandatory, not the architectural endpoint.

Evidence: `out/umb-fine-composition-btuoykt7/results.json` and
`out/opendos-framed-placement-evidence/emm-frame-{mem,vc}.txt`; reproduction
commands and pinned inputs are in the development CDS and OpenDOS sections.
This reconciliation reuses those captures; it is not a fresh runtime matrix.
The vendor [optimization guide](https://bitsavers.computerhistory.org/pdf/novell/dr_dos/DR_DOS_6.0_Optimization_and_Configuration_Tips_199109.pdf)
documents DOS-state relocation, and [Novell's configuration guidance](https://support.novell.com/techcenter/articles/ana19930406.html)
confirms that DR-DOS EMM386 includes the XMS manager. No DR-DOS source or
disassembly is permitted.

The next investigation must answer three architectural questions together:

1. Why does our development BIOS retain 5,152 low bytes against OpenDOS's
   reported 2,304? Use the existing local census to distinguish required
   device/interrupt/DMA state from complete movable services. The difference
   is a research lead, not 2,848 promised reclaimable bytes.
2. What actually requires conventional residency in our combined 6,480-byte
   XMS/EMS interface? OpenDOS exposes a 1,200-byte low installed-device range
   and an 800-byte UMB allocation, but these do not locate all manager state.
   Attribute the remaining storage through public runtime evidence and audit
   our own ownership contracts. Provider integration alone proves no saving;
   keep the standalone HIMEM, third-party XMS and 286 paths.
3. What is the minimum complete resident COMMAND interface? Design the high
   service body, low asynchronous entry/state and reload contract together,
   not as repeated critical-handler paragraph reductions.

Budget these with remaining DOS state in one layout before another relocation
tranche. HMA capacity is shared; scarce UMB is needed by public real-mode data.
Each moved object must release a coalescing low interval after charging gates,
alignment and retained state. Reject designs that merely copy payload high or
meet retail by reducing requested resources. EBDA remains a finishing step.

### Required checkpoint: one complete resident layout

DR-DOS's portable lesson is a small conventional interface backed by complete
high-resident objects. Its ordinary measured advantage does not require video
memory recovery or EBDA relocation. HMA is shared among kernel, BIOS, shell
and buffers; UMB holds eligible real-mode data. Later OpenDOS demonstrates a
much smaller manager UMB allocation than DR-DOS 6, but its runtime device rows
do not locate the complete manager. Do not infer its hidden implementation.

Before choosing the next code change, produce one proposed layout covering all
of the following owners, not a sequence of independently attractive savings:

| Owner | Starting evidence | Required design decision |
| --- | --- | --- |
| DOS BIOS | Development retains 5,152 low bytes; disk body already moved | Partition stable device/interrupt/DMA state from high service bodies; identify exact released intervals |
| DOS kernel and dynamic state | 4,992-byte low prefix; FILES/FCB and CDS relocation already counted | Repair the 640-byte SETVER table owner; qualify upper CDS consumers and budget interrupt stacks and remaining public/private state |
| Combined memory managers | 6,480 low bytes; first split has 3,576 gross candidate bytes | Specify low A20/real-mode gates, high service/data objects, transition stacks and third-party-XMS fallback |
| COMMAND | 3,984-byte owner span versus OpenDOS's 1,312 | Separate environment/PSP and asynchronous entry state from movable resident handlers; preserve reload contracts |
| Shared high storage | 10,313 calculated development HMA bytes; 1,792-byte UMB margin after CDS | Reserve destinations once across all owners; account for locked XMS, alignment and displaced buffers |

For each proposed object, record its current range, destination, live callers,
address and A20 contract, low gateway cost, initialization/rollback behavior,
and final low allocation boundary. Sum **net coalesced conventional gain**,
not copied payload sizes. Include UMB and XMS costs in the same budget. Public
tables cannot be moved merely because high space exists; retained low mirrors
do not count as reclamation.

The checkpoint passes only when the combined net budget covers at least 1,984
bytes while retaining the 47,888-byte free-UMB floor and configured resources.
That is the retail acceptance threshold, not a ceiling on the design: identify
further whole-object opportunities toward the OpenDOS result without promising
its 11,328-byte lead over combined development as locally reclaimable storage. Resolve
boot-medium/device-topology differences before adopting its totals as a target.

Then implement and validate complete object moves. Indexed accessors are a
necessary dependency where near-pointer ownership prevents relocation, but
accessor-only commits neither satisfy this checkpoint nor improve the memory
score. Keep correctness repairs separate from savings claims. The checkpoint
is currently **open**; the existing candidate census is not a complete layout.

#### Reproducible shared HMA capacity

`tests/report_dos_bios_residency.py` now composes the successful early BIOS
reservation, fixed cache and permanent COMMAND allocation from the build
manifest and linker maps. The current sequence is `0010h..9A80h` DOS,
`9A80h..AEE4h` BIOS, `AEE4h..CE18h` cache, and `CE18h..D7A7h` COMMAND.
The unassigned tail is **10,313 bytes**, ending at the `FFF0h` safety boundary.
The former 10,169-byte estimate was 144 bytes too small; this correction
creates no new free conventional memory and is not a runtime HMA probe.

```sh
python3 tests/report_dos_bios_residency.py --check --tail-body \
  --boot-manifest out/umb-fine-composition-btuoykt7/bios-cds/low.json \
  --command-map src/CMD/COMMAND/COMMAND.MAP \
  src/DOS/MSDOS.MAP out/umb-fine-composition-btuoykt7/bios-cds/msBIO.map
```

Use maps from the selected build, not another prototype. The manifest is
checked against its IO.SYS; linked capacity still assumes successful boot
activation and shell relocation. The model deliberately supports only the
fifteen-buffer, 512-byte-sector profile; mixed-cache capacity needs runtime
accounting. Tail-body boot fixtures include this composed census for the fixed
profile. Seven local budget tests cover ordering, single charging, exact fit,
overflow, invalid sizes and the current composed boundary.
Local `test_hma_qemu.sh` passes its normal high/low, tail-address, A20-return
and EXEC checks. The early/rebased/compacted high-CDS `emm-high` fixture also
passes with the composed census (`out/bios-low-boot-_iwk9bjx/`). This validates
report integration, not a new development HMA runtime-address probe or the
still-open whole-resident-layout checkpoint.

#### Blocking SETVER ownership investigation

The DOS-low ASSIGN failure is not stale media: IO.SYS, MSDOS.SYS, COMMAND.COM
and ASSIGN.COM on `out/floppy.img` match their local build hashes. The retail
compatibility table includes `ASSIGN.COM 5.00`; ASSIGN's rebuilt message loader
instead compares AH=30h's reported version against 6.22. A byte-identical
version probe returns 6.22 as REFVER.COM and 5.00 as ASSIGN.COM in DOS-low.
Deleting the compatibility entry would hide the conflict, not fix parity.

There is a more serious placement defect. `capture_setver_placement.py` makes
a private image copy, runs identical read-only probes under those two names,
and compares the public table's complete 640 bytes against compiled defaults.
It performs no SETVER edits. Current observations:

| Fixture | AX=1231h table | First differing table byte | REFVER / ASSIGN version |
| --- | --- | --- | --- |
| Normal DOS-low | `0268:9AC2`, capacity `0280h` | `00FDh` | 6.22 / 5.00 |
| Development high-CDS | `FFFF:9AC2`, capacity `0280h` | `0000h` | 6.22 / 6.22 |

The high address lies inside the live BIOS reservation `FFFF:9A80..AEE4`.
The existing editing suite on that high fixture stops at its first edit with
`General failure writing drive A`; its normal low run reports a full table
and prints corrupt tail entries. These editing runs are separate evidence
from the read-only comparison. Neither configuration qualifies SETVER.

The source exposes the ownership mismatch: `MSINIT.ASM` places and initializes
the table beyond SYSBUF; `DOS_HMA_RELOCATE` copies only offsets below SYSBUF;
`DOSGetVersionTable` returns CS plus the old near offset; and EXEC's scanner
also assumes the table belongs to CS. This explains the high alias. The exact
writer/lifetime boundary corrupting the low tail remains to be isolated.

Next: identify the complete table's live allocation and first overwriter;
give all 640 bytes one retained low/UMB owner, or another explicitly safe
public-pointer contract; update EXEC, SETVER and its startup driver together.
Account for its destination and reclamation in the joint budget rather than
pretending these bytes were already preserved. Then resolve native ASSIGN's
version check without removing the retail mapping, and rerun default-table,
edit, persistence, nested EXEC, high/low and reset cases. The earlier high-CDS
utility results cover those paths but not equivalent SETVER behavior.

```sh
python3 tests/capture_setver_placement.py --check out/floppy.img
python3 tests/capture_setver_placement.py --check --preserve-config \
  out/bios-low-boot-_iwk9bjx/emm-high.img
```

Both checks currently reject the layout. Reports, input hashes, startup config
and serial traces are retained in `out/setver-placement-4toy98_w/` and
`out/setver-placement-p8fjjsrk/`; the editing failures are in
`out/high-cds-c9ogjjfw/setver-{low,high}-failure.log`. The recorder exits zero
without `--check` when evidence capture completes; this is not a passing gate.

#### Candidate layout A: manager objects plus the whole shell service body

This candidate was budgeted against the earlier 614,448-byte BIOS/table
fixture, before fine UMB and CDS placement. Its component ceilings remain
unvalidated; use the current joint budget above for subsequent decisions.

This is a **retail-floor candidate**, not the complete DR-DOS-style layout.
Its proposed 4,816-byte gain would still leave 8,816 bytes between development
and the observed framed OpenDOS result. Do not stop the architecture audit at
these two component ceilings or treat them as validated implementation sizes.

The current checked COMMAND map provides a concrete complement to manager
relocation: `0100h..0A93h` contains 2,451 resident code bytes. Keep its 256-byte
PSP, 125-byte stack and 800 bytes of mutable state low initially. Repack that
low state before the movable body rather than preserving a 2,451-byte hole.
Environment, batch allocations and arena overhead are separate and unchanged.
This is a code/data-interface redesign, not a claim that the current body is
position-independent.

The following are proposed **design ceilings**, not measured new allocations:

| Allocation | Current low bytes | Proposed low ceiling | Required net release |
| --- | ---: | ---: | ---: |
| Combined HIMEM/EMM386 | 6,480 | 3,248 | 3,232 |
| COMMAND permanent image, including PSP | 3,632 | 2,048 | 1,584 |
| **Combined** | **10,112** | **5,296** | **4,816** |

Meeting both ceilings would put development's largest block at 619,264 bytes,
528 above retail, without counting EBDA or another BIOS/table move. The manager
ceiling allows 345 bytes above the first split's 2,903-byte retained inventory;
the shell ceiling allows 867 above its 1,181-byte PSP/stack/state inventory.
Those allowances must absorb gateways, bindings, alignment and any retained
service code. If the contracts require more, revise the joint layout rather
than silently spending the 528-byte margin twice.

Proposed destinations are the existing DOS-owned HMA for HIMEM's 1,672-byte
service/data candidate and COMMAND's 2,451-byte body, and locked extended memory
behind a protected selector for EMM386's complete 1,904-byte selected table
object. The 4,123-byte additional HMA payload fits the current calculated 10,313-byte
tail before relocation support costs; size the final linked high objects and
XMS/page alignment separately. Existing high BIOS, kernel, buffers and shell
catalogs remain where they are. No new UMB allocation is budgeted.

Source-audited implementation constraints still preventing acceptance:

- COMMAND needs separate code, PSP/data and stack identities, not just a far
  entry. `COMMAND2.ASM:LODCOM1` currently loads SS and DS from CS and resets SP
  to `RSTACK`. Its parent/exit and JFN accesses also address the PSP through
  CS. Copying this body to HMA unchanged would redirect stack and PSP accesses
  into high code. Retain a low PSP/data binding, switch SS only to the low
  stack owner, and rebase stack/data offsets when repacking the resident image.
- `COMMAND1.ASM` uses CS-relative LOADHIGH state even when DS belongs to the
  transient. Do not mechanically replace CS overrides with DS. Supply an
  explicit low-owner access path preserving the caller's segment registers.
  `COMMAND2.ASM:SETVECT` must continue publishing low INT 22h/23h/24h entries
  and the PSP exit pointer. `RUCODE.ASM:DSKERR` writes CS-relative remote-message
  state and returns through IRET; its high body needs a low interrupt return
  path, including nested critical errors and failed A20 recovery.
- Keep the registered disk-message callback low initially: its prior high
  move failed a real disk-backed diagnostic. Charge its 174 bytes against
  the shell's 867-byte allowance, not as additional savings. Audit nested
  INT 24h, INT 2Eh, Ctrl+C, EXEC and reload stack/return frames before moving
  other asynchronous bodies. Firmware/DOS callbacks can change A20.
- Use the early reservation contract below, not `DOS_HMA_TAIL_ALLOC` from
  HIMEM initialization or a late COMMAND-triggered manager move.
- Manager OFF/AUTO, real-mode continuation and third-party-provider contracts
  remain as specified below. Releasing low table storage must change the
  installed allocation boundary, not merely its pointers.

Next evidence needed: linked gate/body sizes against both ceilings, a complete
call/return and boot-publication design, then paired runtime maps proving
coalescing. The arithmetic makes this a viable budget to investigate; it does
not pass the joint checkpoint or any runtime acceptance gate by itself.

#### Decision gate: shell interrupt placement determines layout A

`make test-command-residency test-himem-residency` reproduces the linked
inventories above. The shell's current stack is `0A93h..0B10h` (125 bytes),
mutable state is `0B10h..0E30h` (800), critical-error body is
`06F5h..097Bh` (646), and disk-message callback is `09D9h..0A87h` (174).
These are nested ranges, not additional allocations.

The proposed 2,048-byte low shell ceiling implicitly requires moving most of
the critical-error body. Retaining it together with the disk callback, PSP,
stack and mutable state already costs **2,001 bytes**, leaving only **47** for
every other low entry, A20 gate, binding and alignment. Retaining the existing
18-byte DBCS and two six-byte message gates would leave just 17. A design that
quietly keeps all asynchronous services low therefore has not justified this
ceiling. Either prove the complete high INT 24h service/low-return contract or
increase the shell ceiling and supply a replacement net gain from another
owner; do not continue using 4,816 as an established combined saving.

The next architectural implementation decision is this shell contract, not
another EMM accessor tranche. Review EXEC/reload, INT 2Eh, Ctrl+C and critical
errors as one service object, with the explicit PSP/data/stack bindings above.
Use a development-only complete-object prototype to measure its linked gates;
keep the normal layout and failed-relocation fallback intact. Production
promotion remains behind the joint budget and compatibility gates.

The returning critical-error gate is now passing after correcting catalog
ownership. `test-command-critical-abi-qemu` runs a child COM
program with stdout redirected, opens the unformatted B: twice, and chains the
inherited INT 24h handler. Separate Fail and Retry runs require the selected
first response in AL, unchanged
SS:SP, DS, ES, SI and CX, a stack outside the handler's code segment, and exact
stdin/stdout JFN restoration after each open. It does not demand a callback on
the second open: DOS can reject it without prompting after the first error.

`SYSLOADMSG` caches the critical catalog in `$M_CRIT_COMMAND`, separately from
the five utility-class slots. Relocation previously rebased those slots and
DOS's public pointer but left that cache pointing into released low memory.
After EXEC overwrote the old catalog, critical lookup could fall through to
`READ_DISK_PROC`, entering disk I/O during the original disk error and stalling.
`/MSG` masked the stale pointer by retaining the low catalog; it was a diagnostic
control, not the fix. Initialization now atomically updates the cached far
pointer before releasing the old catalog. No extra catalog, resident bytes or
HMA payload are allocated.

`command_critical_hma_probe.asm` checks the cached pointer against DOS's published
HMA pointer in both the QEMU HMA and 86Box platform fixtures. That assertion
failed before the fix and passes afterward; the external-program disk-error
gate also changes from failure to success without enabling `/MSG`. Keep both:
pointer equality identifies the ownership defect, while the real disk case
checks the returning handler after EXEC has made stale low storage unsafe.

Reproduce against a deployed image (each run replaces the same test fixtures):

```sh
make test-command-critical-abi-qemu
COMMAND_CRITICAL_ABI=1 COMMAND_CRITICAL_MESSAGES=resident \
  bash tests/test_command_startup_qemu.sh
```

Both configurations pass. Optional
`COMMAND_CRITICAL_NO_HOOK=1` removes the observer for diagnosis only and cannot
satisfy the ABI gate. The unchanged `test-command-startup-qemu` remains the
passing built-in-error baseline. This closes the stale-cache regression, not
general disk-call reentrancy or the complete high-shell contract. Include cached
message and callback bindings in the whole-object publication audit, not only
DOS's public pointers. The gate covers returning Fail and Retry, not successful
recovery of the bad medium, Ignore/Abort, nested INT 24h, A20-off recovery, or
the non-returning reload path. `COMMAND_CRITICAL_ACTION=retry` selects Retry
when running the script directly; the make target runs both cases sequentially.

The complete high critical-error object must preserve these distinct exits;
one generic far-return wrapper is not sufficient:

| Current exit | Stack/control contract for the high-body split |
| --- | --- |
| `EEXIT` / `RESTHD`, including `FATERR` | Restore redirected handles and saved CX/SI/ES/DS, then IRET on the incoming interrupt stack; preserve the selected AL action |
| `BLKERR` with `LOADING` set | Restore handles, transfer to `GETCOMDSK2`, then let `LODCOM1` reset SS:SP and reload the transient; do not return through the abandoned interrupt frame |
| `JustExit` during interrupted initialization | Restore message ownership and parent PSP, then terminate through DOS; never resume the high body after process termination |
| `DeadInTheWater` | Preserve the existing non-returning initialization-error behavior; do not turn it into an ordinary critical-error return |

Abort also updates batch, pipe and FOR state before the ordinary IRET exit.
Keep those authoritative low-state effects in the design; verifying AL alone
would miss them.

##### Cross-segment execution fixture

`make test-command-critical-split-qemu` builds the development-only
`COMMAND_CRITICAL_SPLIT` variant in a separate artifact directory. It separates
all four exits from the complete handler body and uses the saved low DS, not
CS, for remote-message state and for restoring data access after string lookup.
The normal COMMAND binary is unchanged. The prototype currently measures:

| Linked range | Bytes | Placement |
| --- | ---: | --- |
| Entry, service wrappers and four exits, `06F5h..075Dh` | 104 | Low interface; no writes into the retired body |
| Complete critical body and bridges, `075Dh..09F2h` | 661 | Executed in HMA by the test loader; low allocation retained |
| Binding constructor in INIT | 40 | Discarded after initialization |
| Permanent image after paragraph rounding | 3,760 | 128 more than normal before reclamation |

Eight copy-local near-call bridges perform far calls to low wrappers for
printing, message lookup, DBCS/character conversion, pipe cleanup, INT 21h and
INT 2Fh. Four far jumps implement the non-returning low exit transfers. Their
immediate segment operands are explicit bindings, independent of the caller's
DS. The census checks all twelve encodings, targets and binding offsets plus
the five-byte dispatch publication window.

The fixture now runs Fail and Retry with the body low, then with the complete
661-byte object in HMA. `CONPROC` initializes all twelve bindings immediately
after establishing its stack, before any DOS call or vector publication. The
constructor preserves incoming AX and resides entirely in discardable INIT.
`command_critical_body_loader.asm` verifies the dispatch window, reserves
DOS-owned HMA, copies the initialized body and verifies its bindings against
the low owner, then poisons the old body
with INT 3 bytes, and atomically publishes a far entry. Both high cases pass
with the old body unusable, including foreign-stack and JFN restoration.
This proves high execution, **not reclamation**: the test loader leaves the
conventional allocation intact. A final `/CHECK` verifies every old-body byte
remains poisoned after errors and child-shell cleanup. This check failed with
per-entry binding and passes with the constructor: neither execution nor
runtime binding writes now depend on the retired body in these cases.

The checked census permits a bounded 128-byte development support increase;
the production 3,632-byte limit is unchanged and the normal binary remains
byte-identical. Reload, initialization termination, Abort side effects and
A20 failure are not qualified by these cases. In particular the low service
wrappers do not yet recover A20 before returning to high code.

##### Startup reclamation fixture

`make test-command-critical-reclaim-qemu` adds `COMMAND_CRITICAL_RECLAIM` to
the split variant. The complete 661-byte body is linked at the start of
HMACODE, after permanent low data and catalogs. Initialization copies it in the
same allocation as the existing HMA code, rebases character/message entry
offsets, and publishes the critical far dispatch before lowering the permanent
break. No test loader is needed. Child, /MSG and failed-allocation paths retain
the complete low fallback with its constructor-initialized bindings.

Matched QEMU probes, with identical 2 KiB child allocations and resource
settings, measure this result both before and after disk errors/child cleanup:

| Measurement | Normal COMMAND | Startup variant | Difference |
| --- | ---: | ---: | ---: |
| Permanent parent image | 3,632 | 3,104 | 528 released |
| Largest free block while the probe runs | 627,504 | 628,032 | 528 gained |

These are **not VC figures**. The probe checks the parent MCB, the live HMA
dispatch and that the old body lies beyond the parent's allocation boundary.
Both Fail and Retry cases match the released paragraphs to the largest-block
gain, before and after the error sequence. The additional HMA payload is 661
bytes; this is whole-object relocation, not an equal reduction in total code.

The fixture also checks the retained body and low dispatch under /MSG and
DOS=LOW. A DOS=HIGH/BUFFERS=46 case forces payload-allocation failure: a small
tail allocation succeeds but the full payload does not fit, and the low
fallback still passes the critical-error and parent-layout checks. Secondary
interpreter and /F cleanup paths run in the startup suite as well.

This remains development-only. The normal binary and fixed VC baseline are
unchanged; composition with the BIOS/table development profile is not yet
measured. A20-safe high returns, nested critical errors, Abort side effects,
reload/termination exits, warm reset and 286 high-body qualification remain
promotion gates. At 3,104 bytes, another 1,056 net bytes plus any new retained
support would be needed to reach the proposed 2,048-byte shell ceiling. This
tranche is part of the previously inventoried whole shell body, not an extra
528 bytes to add to that candidate's predicted saving. Keep the combined
manager/shell budget open until final gates and intervals are proved.

The eventual reclamation commits have three distinct owners:

| Object | Destination and publication | Conventional reclamation point |
| --- | --- | --- |
| HIMEM services and selected handles | Early shared HMA cursor; stable low XMS/A20 entries | Repacked `BREAK_ADDR` before `Set_Break` and later drivers |
| EMM option-sized table object | Locked XMS and a separate protected data selector; all roots published together | `INITTAB.ASM:CompactVData` replacement must repack the retained low transition stack and lower `driver_end` before INIT returns |
| COMMAND resident service body | DOS-owned HMA; low external gates and authoritative low PSP/data/stack | Repacked permanent image end before shell initialization releases its allocation |

Current `CompactVData` copies tables within DGROUP and retains them below the
transition stack. Current `INIT.ASM:relocate_resident_catalogs` lowers the shell
break only to `resident_catalog_start` (`0E30h`). Neither mechanism implements
the proposed additional whole-object release. Require before/after owner maps
and VC's largest block for each replacement; pointer publication alone is not
reclamation. Preserve the already-counted development BIOS/FILES gains and
charge all three objects against one HMA/XMS/UMB budget.

#### Boot reservation and reclamation contract

The source order supplies an early integration point; a late HMA copy would
not supply the promised contiguous reclamation:

1. `SYSCONF.ASM` calls the driver's INIT, then `CompactFirstHimem`, before
   `BREAKOK` calls `Set_Break` for the character driver. The hook recognizes
   repository HIMEM, moves DOS high, compacts HIMEM downward and refreshes
   DOS's cached XMS entry (`1234h`). Later resident drivers are not yet loaded
   in the fixed HIMEM-first profile.
2. Development `BiosBootActivate` already runs at the end of that hook. It
   reserves the area above DOS's `SYSBUF` using a private SYSINIT-owned end
   cursor (`HmaBiosEnd`), before buffers or the public tail allocator exist.
3. End-of-CONFIG processing uses that end cursor as `HmaBufferBase`.
   Completed buffer construction publishes the remaining tail through
   `1235h`; permanent COMMAND subsequently reserves through `1236h`.

Proposed implementation: generalize the early cursor to a shared boot HMA
reservation, with ordered BIOS and HIMEM objects. Retain the current BIOS
reservation when manager preflight fails. Preflight the manager's complete
code/data object and low gateways, copy and fix up without publishing it,
then atomically publish its service bindings and commit the cursor. Only
after success reduce `BREAK_ADDR` to the repacked low HIMEM end, before
`Set_Break` can place another resident above it. Refresh any affected cached
entries while their low addresses are still owned. No post-publication path
may fall back into the released service body.

Do not shrink HIMEM at shell startup or after loading EMM386: later resident
objects can separate that hole from the largest free block. Do not repurpose
`1236h` as an early allocator: its floor is deliberately unset until cache
placement finishes. The new cursor must feed both high-buffer and low-buffer
fallback publication paths and protect requested buffer capacity; HMA space
consumed by a service is not free if it pushes buffers back low.

The first manager split is eligible only on the audited 386+ repository
HIMEM/DOS-high path. Keep the 286, third-party-provider, failed-HMA and
unrecognized-load cases unchanged. Standalone 386 HIMEM must remain functional
after the split even if no EMM386 is subsequently loaded; do not assume a
future protected-mode provider will make its HMA services callable. EMM386's
own table relocation must separately complete before its INIT break is final.
Warm-reset reconstruction and retry-without-reservation-leak remain gates.

### Development placement budget: remaining BIOS is not another disk body

#### Whole-system accounting and the missing placement tier

The combined fine-UMB/CDS capture
(`out/umb-fine-composition-btuoykt7/results.json`, `fine-cds`)
puts COMMAND at 0518h, after a 19,072-byte span starting at 0070h. Combining
the linked BIOS/kernel inventories with the installed resource sizes gives:

| Low owner | Bytes | Architectural treatment to evaluate |
| --- | ---: | --- |
| Selected BIOS | 5,152 | Stable device/DMA entries and state low; complete service bodies high |
| Kernel prefix | 4,992 | Public-pointer interfaces low; explicitly owned private state high |
| HIMEM and EMM386 | 6,480 | Small low interfaces; service bodies in HMA and protected tables in locked XMS |
| Interrupt stacks | 1,840 | Separate asynchronous entry/stack contract; do not move SS into HMA |
| Sector transfer area | 512 | Retain low for firmware/legacy-device transfers |
| Unassigned reconciliation remainder | 96 | Arena/alignment accounting to locate; no saving assumed |
| **System-to-COMMAND span** | **19,072** | No overlapping component rows |

FILES/FCBS and the complete CDS allocation are already upper and must not be
added again. COMMAND's separate owner span is 3,984 bytes; its permanent
program allocation is 3,632. The 96-byte remainder is a subtraction from
the measured span, not a newly discovered disposable allocation.

The 1,840-byte interrupt-stack allocation remains low. That is a safe initial
prototype boundary, **not proof that this storage must remain conventional
in the final design**. It exceeds the current 1,792-byte free-UMB margin even
before new arena overhead, so moving it requires another jointly budgeted
destination or release. CDS has already consumed 2,320 upper bytes; its
2,304-byte conventional gain is not available again. UMB addresses preserve
ordinary real-mode segment addressing without an A20 dependency; HMA does not.
Moving stacks and accepting high CDS still require their public-pointer, interrupt,
DMA/backing and fallback contract. Never reduce LASTDRIVE or stack capacity
to make the comparison fit.

The following records the original UMB-discovery hypothesis; the development
fine-mapping and CDS results below supersede its untested status and old
capacity limits. It remains useful for the ownership and exclusion contract.

The framed OpenDOS raw map
starts upper RAM at CB00h, including an 800-byte manager allocation, and places
the EMS frame at CC00h. Our fixed `EMM386 RAM M5` image starts its upper arena
at CC00h and places the frame at D000h. In our sources,
`ROM_SRCH.ASM` excludes overlapping 16 KiB windows, and
`INIT.ASM:Prepare_UMB` accepts only complete safe 16 KiB windows from that same
EMS-oriented map. Therefore a safe 4 KiB tail at CB00h..CC00h cannot become a
UMB through the current path if its enclosing C800h..CC00h window contains ROM.
This is a source-proven granularity constraint, not proof that the tail is safe
on the fixed hardware or an inference about OpenDOS's internal algorithm.

Investigate a **separate 4 KiB UMB eligibility map**, retaining 16 KiB EMS
semantics, before declaring our present 16-byte UMB margin immutable:

1. Capture physical ROM signatures/lengths, RAM/reservation boundaries and
   effective exclusions on identical QEMU device topology for both systems.
   The existing floppy-versus-IDE comparison is insufficient for eligibility.
2. Record why each 4 KiB page is accepted or rejected; exclude any page touched
   by ROM, video, hardware reservations, explicit X=, EMS frames or Pn= owners.
   Do not force I= over a rejected window or recover video memory for the score.
3. If a safe tail exists, design sub-page backing ownership, HIMEM registration,
   allocation rollback and EMS/DMA coexistence together. Current Commit_UMB
   reserves whole EMS backing pages; finer discovery alone is not a working
   allocator. Include backing waste and maximum-option capacity in the budget.
4. Measure net free-UMB growth before spending it on complete public DOS-data
   allocations. A full 4 KiB recovery would be only 4,096 gross bytes, already
   32 fewer than CDS plus the current stack block, before any new overhead.

This is an architectural discovery/placement workstream, not another EMM386
instruction reduction. It may supply the missing real-mode destination tier;
until physical eligibility and end-to-end allocation are proved, credit zero
conventional or UMB bytes. Keep the retail floor and OpenDOS comparison distinct.

The first physical-topology check now supports the granularity lead without
qualifying allocation. `tests/capture_uma_topology.py` boots a snapshot of a
supplied image under QEMU `pc`, 486, 8 MiB, stops the CPU, and records physical
ROM headers/checksums, each 4 KiB page's hash, PCI devices and the memory tree.
It does not modify the input image or enable guest mappings. All pages without
an overlapping ROM header are deliberately labelled **unproven**, including
uniform zero/FF pages; invalid-checksum headers are retained as warnings.

Local and retail IDE-image captures on QEMU 11.1.1 both show valid ROM payloads
at C0000h..C99FFh and CA000h..CADFFh. CB000h..CBFFFh is all zero, with no
overlapping ROM header. The memory tree maps that address to read-only
`pc.ram` shadow storage, not directly writable RAM or a named MMIO region.
Thus the source's 16 KiB exclusion loses a header-free 4 KiB tail beside real
ROMs on the actual comparison hardware. Making it usable still needs separate
paged backing and a complete reservation/ownership audit; an empty physical
page is not an approved UMB. A timed snapshot is not proof of successful DOS
boot or a replacement for the paired VC acceptance run.

A local floppy-image control (`--interface floppy`) reproduces the IDE cases'
ROM inventory, PCI topology and CB000h page hash. This narrows the boot-medium
uncertainty for this particular region; it does not normalize all DR-DOS
resource semantics or establish runtime mapping safety.

Reproduce the read-only topology capture and its parser safety tests:

```sh
python3 tests/capture_uma_topology.py out/msdos622-original-vc405.img > out/uma-topology-retail.json
python3 tests/capture_uma_topology.py out/msdos622-vc405-current-memory.img > out/uma-topology-local.json
make test-drdos-capture
```

Reports include input hashes and effective QEMU arguments. Physical endpoints
above are byte addresses, unlike the segment addresses used in the VC maps.
No DR-DOS memory dump or disassembly is needed for this host-topology check.

##### Source-audited sub-page allocation contract

Use one four-bit eligibility mask per existing 16 KiB UMA window, with separate
commit state. Keep the EMS window map and backing allocator at 16 KiB. The
first design reserves a **whole backing page even for one eligible slice**;
unused slices never return to the EMS free list while that UMB is live. For
CB000h this costs 16 KiB of backing for 4 KiB of gross upper address space.
Do not claim that those 12 KiB of unused backing are free XMS/EMS capacity.

The complete change boundary is:

| Source owner | Required change and invariant |
| --- | --- |
| `ROM_SRCH:upd_seg` / `PPAGE:exclude_segments` | Record intersecting 4 KiB slices before rounding to EMS windows. Preserve detected RAM and hardware exclusions, not just valid ROM signatures. A side map cannot reconstruct these reasons after the coarse scan. |
| `INIT:record_umb_range`, `Apply_User_UMA_Ranges` | Preserve current I=/X= option behavior separately. X= must veto the new slices regardless of argument order; automatic finer discovery must never act as implicit I=. |
| `PPAGE:Apply_Requested_Pages`, `INIT:Prepare_UMB` | Exclude the selected frame and explicit Pn= owners. A parent containing any UMB slice must never remain available as an ordinary EMS window. Resolve ownership before EMM_Init builds window tables. |
| `INIT:Choose_UMB_DMA_Group` | Treat each nonempty mask as one backing-page request. Preserve the existing below-16-MiB, same-offset-modulo-128-KiB selection across neighboring windows. No private 4 KiB free list in the first implementation. |
| `INIT:Map_UMB_Page` | Write only selected PTEs; retain each slice's offset within its backing page. Keep adjacent ROM/identity PTEs untouched, including a mixed C800h window. |
| `INIT:Commit_UMB` | Coalesce only consecutive mapped 4 KiB slices, publishing paragraph-sized extents after all mapping succeeds. Preflight extent capacity before writing the publication buffer. |
| `INIT:Restore_UMB_Page`, `Rollback_UMB` | Restore only committed slices to their pre-install mappings; return each reserved backing page exactly once. On live-provider teardown, successful HIMEM unregister must precede unmapping, as today. |
| `INITTAB:InitTab` | Copy the completed page tables before discarding initialization masks and publication workspace; no retained consumer may depend on that workspace. |

Capacity audit: C000h..EFFFh contains 48 possible 4 KiB slices and at most
24 disjoint runs. Current `umb_registration` has only 20 extent slots, whereas
HIMEM's `private_register` accepts up to 32 paragraph-addressed extents without
a 16 KiB alignment requirement. Increase the **discardable** publication
workspace to the proved maximum and keep HIMEM's allocation/splitting limit
unchanged. Never coalesce across an excluded page to make a plan fit.

`MAPDMA.C` already translates permanent UMBs from their 4 KiB PTEs, requiring
contiguous physical pages and the correct ISA boundary before using a direct
transfer. Its fallback swapping path requires EMS-window ownership. Fine UMBs
must stay out of that path; same-offset backing is a correctness requirement,
not merely an allocation preference.

The development gate must check the actual installed fine masks and unchanged
neighbor PTEs, explicit exclusions/frame/Pn= conflicts, 24-run publication,
registration rejection and failures after partial mapping, EMS free-page
accounting, reversed backing, DMA/UMB I/O and warm reset. If finer planning
fails, retry the original coarse plan transactionally so the new feature does
not turn an otherwise working UMB installation into no UMBs. Only after those
gates measure the paired VC/UMB result and spend new capacity on DOS state.
Normal discovery remains unchanged. The development census below implements
the precise exclusion input, and the separate mapping variant implements the
transaction with the qualification limits recorded after it.

##### Development guest discovery census

`make test-umb-subpage-discovery-qemu` uses existing built objects and deployed
floppy media, recompiling only INIT and PPAGE in an isolated fixture. With
`UMB_SUBPAGE_DISCOVERY`, the common exclusion entry records precise intersecting
4 KiB slices before rounding for EMS. The diagnostic then applies I=/X=,
frame and explicit Pn= ownership and emits twenty four-bit masks on debug port
E9h, one per 16 KiB parent from A000h through EFFFh. The mapper does **not**
consume these masks. All census state/code is in discardable initialization.

The normal fixture rebuild is required to match the existing EMM386 binary
byte for byte. Seven QEMU boots pass: RAM M5, NOEMS, frame M4, P4=CC00, X=CB00-CBFF,
and both orderings of I=CB00-CBFF with X=CB00-CBFF. Each requires successful
AUTOEXEC completion and checks masks for video, real ROM and firmware RAM.
The fixed RAM M5 mask is `00000000008F0000FF00`: parent C800h has mask 8,
meaning only CB00h..CBFFh survives; CC00h and E000h..E7FFh remain full parents.
X= removes the partial candidate in both argument orders. Changing the frame
or explicitly owning CC00h removes that parent from the proposed UMB masks.

This ties the host ROM observation to the driver's real discovery path. It
does not qualify the partial page for live allocation or prove new savings.
The separate mapping variant below consumes these masks; this census target
still tests discovery alone.

##### Development partial-UMB transaction

`UMB_SUBPAGE_MAPPING` (with `UMB_SUBPAGE_DISCOVERY`) reserves whole EMS backing
pages for nonempty masks, captures original PTEs, writes only selected slices,
and coalesces those slices into a checked 24-slot publication buffer. Explicit
Pn= windows rejected by the UMB plan remain EMS-owned, including on fallback.
All new masks, saved PTEs and publication workspace are initialization-only.
Failure restores committed slices and backing-page ownership, then retries the
coarse plan without republishing or reusing discarded initialization state.
The normal binary remains byte-identical; this is not a distribution default.

`make test-umb-subpage-mapping-qemu` runs both cold and controlled hardware-reset
fixtures. A normal-object control, fine mapping, reversed backing, failures
after one/three parent mappings and failure just before publication all pass.
Each performs 12 KiB upper-buffer file I/O across page/parent boundaries while
rotating live EMS mappings and programming the DMA test phases. Fine allocation
starts at CB01h instead of CC01h, so the test actually uses the new slice.

| Fixed RAM M5 probe | Coarse | Fine | Difference |
| --- | ---: | ---: | ---: |
| Free UMB before I/O | 49,104 | 53,200 | +4,096 |
| Free UMB after buffer release and child exit | 49,088 | 53,184 | +4,096 |
| Free EMS pages out of 16 configured pages | 13 | 12 | -1 (16 KiB backing) |

Before/after values and the C8000h..CAFFFh rolling ROM hash repeat across reset.
Injected failures reproduce the coarse values and original EMS free-page count,
not just a successful boot. Both layouts report one less free paragraph after
the existing I/O lifecycle; compare matching phases and keep that baseline
arena/coalescing observation open. It is not a fine-mapping loss or saving.

This proves **4 KiB of additional usable UMB in the isolated fixture**, not a
conventional-memory gain or a new fixed VC score. Still open: actual provider
registration rejection/teardown, 24-run publication stress, maximum-option and
broader hardware gates, and exact untouched-neighbor PTE checks beyond the ROM
hash. Composition with BIOS/table placement and the fixed VC image is recorded
below. The staged
pre-publication failure is not a test of HIMEM rejecting a real registration.
Only after composition may this capacity fund complete CDS/stack placement;
do not add it to conventional savings or spend the UMB margin twice.

##### Combined BIOS/table and fixed VC checkpoint

`make test-umb-subpage-composition` now builds fresh development BIOS/table
placement and both EMM386 variants, installs current DOS/HIMEM/COMMAND binaries
in private copies of the fixed disk image, verifies unchanged CONFIG.SYS and
VC, and captures coarse, fine and retail layouts. Input hashes, raw captures
and reports remain together under `out/umb-fine-composition.*`.

| Fixed VC image | Largest conventional block | Free UMB |
| --- | ---: | ---: |
| BIOS/table development, coarse mapping | 614,448 | 47,904 |
| Same, fine mapping | 614,448 | 52,000 |
| Retail 6.22 | 618,736 | 47,888 |

The additional capacity survives composition: **4,112 bytes of free-UMB margin
above retail**, with no conventional regression. This supersedes the 16-byte
margin only for the combined fine-mapping development variant; normal builds
and the existing coarse development baseline are unchanged. The critical-body
COMMAND reclamation variant is not included in these figures.

The existing combined BIOS boot test also passes with fine EMM386, 12/32 KiB
upper-buffer I/O, interleaved EMS/DMA phases, system/FCB probes and reset:

```sh
python3 tests/test_bios_low_boot_qemu.py --early --tail-body --rebase --compact \
  --mode emm-high --umb-read --umb-ems --warm-reset --emm386-image FINE-EMM386.EXE
```

Repeat with `--umb-span 32` for the larger allocation.

That boot fixture uses automatic frame placement; the separate VC checkpoint
retains the fixed `RAM M5` configuration. Keep those scopes distinct.

CDS placement uses SYSINIT1:BUF1's existing transition from temporary CDSs to
its final FOOSET-initialized array, before stack allocation. The implementation
and measured ownership costs follow.

##### Development whole-CDS placement

`BIOS_HIGH_CDS` implements this transition after FOOSET initializes the final
array. It validates the newly allocated span, obtains an upper-only allocation,
restores the caller's allocation policy and UMB-link state, then copies the
complete array and DEVMARK. Publication updates SYSI_CDS and a THISCDS cache
that still addresses this array, marks the upper arena system-owned, and
rewinds the low allocation cursor before stacks are constructed. No live low
duplicate is retained. The builder obtains the THISCDS offset from the current
DOS map rather than hard-coding an internal address.

DOS=LOW, absent UMBs and rejected allocation retain the normal low array and
its boundary. `BIOS_CDS_FAIL_ALLOC` exercises allocation failure. The normal
BIOS image remains byte-identical without the development flag.

| Fixed fine-UMB VC image | Before CDS placement | With CDS placement |
| --- | ---: | ---: |
| Largest conventional block | 614,448 | 616,752 |
| Free UMB | 52,000 | 49,680 |
| Conventional gap to retail | 4,288 | 1,984 |
| UMB margin above retail | 4,112 | 1,792 |

The **2,304-byte conventional gain** comprises the 2,288-byte LASTDRIVE=Z array
and its 16-byte DEVMARK. Upper placement costs 2,320 bytes including its MCB.
Thus the whole old allocation joins the largest block; the payload is not
being mistaken for net savings. The system-to-COMMAND span is now 19,072 bytes,
only 80 above retail; COMMAND's separate 880-byte span difference and the
1,024-byte ceiling difference explain the remaining 1,984 bytes. These are
accounting differences, not three byte-harvesting quotas.

Reproduce with `make test-high-cds-qemu test-high-cds-composition`. The first
target checks every LASTDRIVE letter A..Z (respecting the physical-drive
minimum), public CDS count/location and exact system-owned allocation size,
system/FCB and public DPB/device-graph probes, 12/32 KiB upper I/O with EMS/DMA
and reset, allocation failure across reset, and bare-low/HIMEM-low/HIMEM-high
fallbacks. It also runs ASSIGN/SUBST/JOIN on fresh upper-CDS and forced-low
fallback images. `--quick` on its Python runner skips A..Y, not compatibility gates.
The VC target retains both no-CDS controls and retail with unchanged startup
configuration and VC binary.

The utility suite's opt-in `ASJ_CDS_MODE=upper|low` configuration loads HIMEM,
EMM386 and DOS high instead of silently overwriting CONFIG.SYS with DOS-low
defaults. Its source-layout-derived probe checks a configured count of 26,
a zero-offset array pointer, and upper segment/system MCB size
and ownership when requested. Four probes bracket startup, active SUBST,
active JOIN and final removal. The existing path/data and rejected-option
checks still run; merely reaching the end of AUTOEXEC is insufficient.
The matrix also deliberately requests upper placement on the forced-low
fixture and requires only the location check to fail, with all four probes
rejecting it. Serial traces are retained separately because the utility
suite uses shared `asj-*` paths and must run sequentially.
The quick matrix passes all eight cases in `out/high-cds-hvojqf8q/`, including
50 utility checks for each positive placement and the expected negative
control. This accepts these utility consumers, not arbitrary redirectors;
the separate seeded cache checks below cover the publication boundary.
The default DOS-low suite against the existing `out/floppy.img` instead
returns 44 passes and five ASSIGN failures (`Incorrect DOS version`). The
committed pre-change script reproduces the same five failures on that image;
both serial traces are retained with the matrix. This baseline failure is not
a newly introduced CDS regression. The SETVER investigation above now explains
the version mismatch and identifies why the high run was not equivalent;
both findings remain blocking correctness work.

`--cds-cache-case first|last|past-end|foreign` adds a test-only SYSINIT fixture
immediately before CDS publication, after allocation/policy calls. It seeds
THISCDS and checks its offset and segment immediately after relocation or
allocation fallback, before a pathname operation can overwrite the cache.
Valid first/last pointers must follow the public SYSI_CDS owner; the one-past
offset and foreign-segment pointer must remain unchanged. After the assertion,
the fixture invalidates the injected cache using DOS's offset `FFFFh` null
convention so invalid test pointers cannot leak into subsequent boot work.
The fixture is discarded with SYSINIT and absent from normal builds.

The high-CDS matrix includes all four cases, last-entry allocation fallback,
and two negative controls that omit the actual cache-segment write. The
negative controls must emit `CDS_CACHE_FAIL` while the subsequent boot probes
still pass; a missing marker, timeout or unrelated failure is not acceptance.
Last-entry success, fallback and missed-fixup rejection also run across warm
reset. This tests the cache at publication, not every possible redirector-held
pointer or an interrupted allocation transaction.
The 15-case quick matrix passes in `out/high-cds-c9ogjjfw/`; the final
first-entry fixture also passes in `out/bios-low-boot-l23p3eqq/`. Normal IO.SYS
retains SHA-256 `c30988e41ce895a07693d34cd93b0aad6d39ff84a8f3924e9dd914746161c78d`.
No conventional or upper-memory saving is claimed by these test-only hooks.

Promotion remains open: qualify redirector consumers on the actual high-CDS
image, test policy-restoration failure, and complete the fine-UMB and BIOS compatibility
gates. The observed framed OpenDOS block is still 11,328 bytes larger, subject
to the comparison caveats above. Continue the whole-system architecture work;
retail is the acceptance floor, not proof of a DR-DOS-equivalent resident layout.

#### Retained BIOS partition

Use `report_dos_bios_residency.py --check --tail-body DOS.MAP BIOS.map` for
the development tail-body layout. Each tail-body boot test now retains this
checked census as `residency.md` beside its image. The normal census remains
separate: its disk-service symbols cannot delimit the development low image,
because the fallback disk body has moved past initialization code.

The development selected low BIOS is 5,152 bytes, fully partitioned as follows:

| Retained allocation group | Bytes | Placement constraint |
| --- | ---: | --- |
| Loader, core device/data state and format descriptors | 1,841 | Device headers, DMA-facing buffers and mutable request state need stable low owners |
| Strategy, request dispatch and existing high gates | 649 | External device entries and A20-safe returns must remain accessible |
| Console, serial, printer and clock service bodies | 837 | Candidate high code; ROM/driver returns need low A20 gates |
| Disk media constants | 44 | Inventory only, not a separate optimization tranche |
| Media/BPB services and high-service bindings | 911 | Mixed code, helpers and bindings; not wholly movable |
| BIOS model and saved-vector state | 264 | Interrupt and boot restoration ownership |
| Disk initialization/reinitialization | 356 | Cannot discard based on its name; runtime reinitialization must survive |
| Clock swap state and first hard-disk descriptor | 108 | Live state, not disposable boot storage |
| Copied CMOS conversion helpers | 126 | Candidate code; include clock call/return contracts |
| Alignment | 16 | Count only after the entire layout is repacked |
| **Total** | **5,152** | No new saving claimed |

The 3,578-byte fallback disk body is already outside this total. Counting it
again as a new opportunity would double-count the completed disk placement.
Even the 837-byte character/clock body plus 126-byte CMOS helpers cannot close
the remaining 1,984-byte retail gap. Their 963-byte gross inventory precedes gateway
and alignment costs; it is not a sufficient next architectural milestone.

The placement design must therefore include another substantial owner: eligible
DOS state, COMMAND's complete resident interface/state split, or the combined
XMS/EMS low interface. Do not defer those ownership decisions behind serial
small BIOS moves. CDS is already upper in the combined development fixture;
qualify its public-pointer consumers before promotion. Keep the interrupt-stack
block low until its asynchronous contract has a jointly budgeted destination;
the remaining 1,792-byte UMB margin cannot hold its 1,840 bytes plus overhead.
The next design checkpoint remains open until exact net released intervals
cover the gap; the census supplies bounds, not that proof.

### Combined manager split: source-audited prototype boundary

The fixed profile installs 2,592 HIMEM plus 3,888 EMM386 bytes. The checked
HIMEM listing now partitions every fixed byte by service; reproduce with
`make test-himem-residency`. EMM386's existing census supplies the other half:

| Current low group | Bytes | Proposed treatment |
| --- | ---: | --- |
| HIMEM device/vector/private-peer entries and initial state | 406 | Retain low in the first split; XMS callers can cache the entry pointer |
| HIMEM HMA ownership and A20 control | 335 | Retain low; high service entry must not recursively require itself to enable A20 |
| Other HIMEM service bodies, excluding BIOS descriptors | 1,512 | Candidate high service object; explicit state and BIOS-return contracts required |
| HIMEM BIOS move descriptors | 48 | Retain low initially; firmware receives ES:SI and can change A20 |
| HIMEM UMB records | 130 | Retain authoritative low owner for private register/unregister and high UMB services |
| HIMEM selected XMS handle records | 160 | Candidate authoritative high service data, not a second unsynchronized copy |
| HIMEM rounding | 1 | Recompute after layout |
| EMM386 static low image | 1,471 | Retain initially; contains descriptors, transition state and low gateways |
| EMM386 selected dynamic tables | 1,904 | Candidate high-data object behind a separate protected data selector |
| EMM386 stack alignment and transition stack | 513 | Retain until the real-mode continuation has its own safe stack |
| **Total** | **6,480** | No new saving yet |

This first split has **3,576 linked candidate bytes** before new gateways,
selectors, alignment and retained state. It is larger than the current retail
deficit but not a net savings proof, and it cannot explain the 11,328-byte
OpenDOS difference. Keep COMMAND and BIOS in the joint design; do not equate
manager integration or meeting retail with completing the resident layout.

Source constraints that determine the prototype:

- `INITTAB.ASM:CompactVData` already packs all option-sized tables contiguously
  and updates their roots. Relocate that whole object, preserving H=/A=/D=/Pn=
  capacities, rather than compacting individual records further.
- Assembly roots are words in `EMMDATA.ASM`; remaining DMA/window and
  alternate-map consumers still use the low data segment. Converted services
  also resolve DGROUP internally. A high allocation cannot be substituted
  until all consumers and initialization share explicit selector ownership;
  removing escaped near pointers is necessary but insufficient.
- `RETREAL.ASM:RetRealHigh` calls `UTIL.ASM:SelToSeg`, which converts the
  protected stack descriptor base into a 16-bit real segment. The retained
  continuation then pops the frame from that stack after clearing PE/PG.
  Moving the existing stack above 1 MiB would truncate its address; retain it
  initially. A later split must transfer the entire live continuation frame to
  a bounded low stack before disabling protection, including fatal exits.
- `HIMEM.ASM:xms_control` sets DS from CS, while move and allocator helpers use
  shared mutable state. Separate code from its authoritative data owner before
  redirecting services. Cached XMS entries, private E703h rebasing and E705h A20
  recovery remain stable low interfaces. The INT 15h copy backend also needs a
  low return path if firmware changes A20.

The checked HIMEM census separates the 48-byte `move_gdt` table from the
285-byte move-backend inventory; those bytes were previously included in the
high candidate. Keep that table and the 130-byte UMB records low in the first
split. `private_register` and `private_unregister` access UMB records with
DS=CS; relocating the records would also require converting those entry paths.
High handle helpers instead need an explicit authoritative high-data segment,
while pool bounds and move state remain low. `copy_move_blocks` currently
returns directly from INT 15h into its caller's code segment: replace the
firmware call with a low return/A20-recovery gate before moving its body.
Preserve BIOS status across recovery, and never return high after failed A20
restoration. The revised 345-byte manager support allowance is still unproven.

`tests/hma_low_return_probe.asm` provides a runtime witness for the return
mechanism in `test_hma_qemu.sh`: copied nested HMA code calls a low simulated firmware
service, verifies that two previously distinct physical locations alias after
A20 is disabled, then uses low E705h recovery before returning high. It checks
the firmware's EAX, EDX and carry result survive. A second call suppresses
recovery after disabling A20: the low gate resets SP to its dispatch frame,
discards nested high return addresses and workspace, and returns AX=0/BL=82h
to the low caller without resuming high code. The probe checks CX/SI/DI/BP,
stack balance and restoration of the previous frame anchor, then completes a
fresh successful call. This is a 386+ QEMU mechanism test, not installed HIMEM
relocation or actual hardware recovery failure. Production dispatch, interrupt
reentrancy, SS changes, real BIOS clobbers and the complete low budget remain
open; the witness uses a single unchanged stack segment.

After the joint layout checkpoint passes, the manager prototype order is:
establish the EMM high-data access ABI, then allocate and
publish the complete dynamic block transactionally in locked XMS. Keep the old
layout on failed allocation or validation. Prove EMS lifecycle, DMA, OFF/AUTO
transitions, reset and third-party-provider behavior before releasing low
storage. In parallel in the design budget, split HIMEM's service/data ownership
and identify the required shell contribution; standalone 286 HIMEM remains
unchanged. High copies without reclaimed and coalesced low spans earn no credit.

**Access-boundary implementation:** the 512-byte selected handle-name table
is reached through indexed `ReadHandleName`, `WriteHandleName`,
`ClearHandleName` and `MatchHandleName` services in `EMMSUP.ASM`. No C consumer
retains a near pointer to that table. The services preserve C's distinct DS/SS
contract and accept far client buffers without exporting a table address.
The 512-byte selected saved-map table now has indexed read/write/peek/clear
services too; C deallocation asks `SavedMapInUse` instead of inspecting a near
pointer. Save passes the current four-slot context to its owner. Restore takes
an eight-byte snapshot on the existing low stack, applies only those four LIM
slots, and releases the saved slot only after successful restoration. Empty
and corrupt-map exits unwind the same ten-byte snapshot/handle frame.
The current owner is still DGROUP; these are prepared interfaces, not high
allocations or savings.

Handle-record C consumers now use bounded index/count getters and setters;
`HandleValid` returns a boolean rather than a near record pointer. Allocation,
freeing, growth/shrink rollback and both directory enumerators no longer
retain pointers into the 256-byte selected handle-record table. `free_pages`
takes the handle index, snapshots its fields as values, and rebases other
records through the owner services. Assembly validation now preserves DX as
the handle index and returns validity through CF. Logical mapping and
move/exchange validation fetch fields by index; `Handle2HandlePtr` and the
legacy `_valid_handle` pointer result are removed.

Page/free-array transfers now use indexed services, including overlap-safe
growth/shrink copies and zero-count handling. Mapping reads page and PFT
entries through their owner; built `MAPDMA.C` uses indexed PFT reads and a
full-dword exchange returning the old first entry in DX:AX. No table pointer
escapes those services. A source guard confines the converted table roots to
EMMSUP and their initialization/layout consumers. Historical `MAPDMA.ASM` is
excluded only with a check that the build selects `MAPDMA.C`.
The remaining C DMA-page and dense-window pointers are now replaced by indexed
read/write services too, with a guard against direct C access. All services
still resolve DGROUP. Assembly dense-window reads now use `ReadWindowIndex`,
preserving other registers and flags; the complete sparse `Pn=` translation
routine resides with its table owner in EMMSUP. Frame tests cover M1-M14,
FRAME=/P, banking boundaries and explicit sparse assignments.
Single current-map reads/writes now use indexed owner services in mapping,
unmapping and partial-map operations; ELIMTRAP's DMA `GetCRSEntry` delegates
to the same reader. A source guard rejects current-map root access outside
EMMSUP, EMMP's remaining bulk operations and initialization/layout code.
The partial-map regression switches to a differently populated page between
save and restore, then verifies the original contents, not just return status.
Ordinary full-map export now snapshots through `ReadCurrentMap`; full-map and
saved-handle restoration compare indexed current values, leaving unchanged
UMB mappings alone. Saving a handle's four frame entries stays entirely inside
the table owner. Rebuilding mapped windows also reads values by index.
Move/exchange now saves/restores its two scratch windows as a packed value,
preserving the original four-byte stack order. Register-set zero buffer
export/import also uses the bulk owner services. Tests compare the complete
map before/after move/exchange and restore page contents through a non-null
register-zero buffer, including the exported buffer address.
Alternate-set allocation, selection and deallocation still resolve FRS record
pointers in EMMP. These must move behind the owner before the complete block
can move. No high copy or reclamation exists.

Count boundary: EMMINIT rounds `_cntxt_pages` up to an
even word count; `_cntxt_bytes` adds a two-byte public header. Internal FRS
records have a one-byte allocation flag followed by only the mapping words.
Alter-map-and-call now copies only `_cntxt_pages` words through owner services,
with two initialized padding bytes preserving its advertised stack reservation.
Its former `_cntxt_bytes` raw copy read/wrote into the adjacent FRS record.
The regression allocates that neighboring alternate set inside each callback
and deallocates it after return: it failed before the fix and passes for both
physical-page and segment-address call forms afterward. The alternate-map
dword copy does not lose an odd word under the current rounded-count rule.

The expanded EMS lifecycle probe checks two independent saved contexts and
their restored page contents, repeated-save/no-save errors, rejection of
deallocation while saved, and set/get/directory name lookup, duplicate
rejection, names differing only in their eighth byte, clearing on handle reuse,
and survival of an unrelated name. It and the EMM386 API and address-phase
suites pass locally. The census checks the indexed services are in protected-only
code and retains the 3,888-byte installed allocation. The 32 KiB interleaved
EMS/UMB read/write probe also passes with development BIOS/table placement
across warm reset, including its later DOS system/FCB checks.
The handle-record regression additionally grows and shrinks an earlier
allocation while checking that a later live handle retains its page contents
after both index-rebasing directions. That probe and the interleaved warm-reset
case pass after the C and assembly conversions. High-byte handle aliases are
rejected by mapping, saved-map, attribute and C query paths without changing
the live page's contents. The ownership guard and protected-service census pass.
The page/PFT conversion also passes all 19 development UMB I/O cases, including
reversed backing, interleaved EMS transfers, reservation fallback and warm
reset. These tests do not close the separate DMA capacity/fatal-exit gaps or
qualify a high table owner; the installed low allocation remains 3,888 bytes.

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

## Open compatibility observation: Windows 95 setup with HIMEM / DOS=HIGH

The 2026-09-05 Windows 95 OEM installation trial exposed an unresolved loader
observation. With `FILES=60`, `BUFFERS=30`,
`DEVICE=A:\HIMEM.SYS /TESTMEM:OFF`, and `DOS=HIGH`, `SETUP /IS` reported
`Insufficient extended memory to run Windows in standard mode.` Removing both
the HIMEM device line and `DOS=HIGH` allowed the graphical loader to start;
the no-HIMEM path subsequently completed installation.

This is **not a confirmed HIMEM or DOS=HIGH root cause**, nor a resolved memory
issue. The observation used base `e148ff1` before the failed-open cleanup fix
in `07fe16d` and before the intervening BIOS/HMA changes through `e1d9bdf`.
Passing the focused DOS regressions on the newer state did not retest this
Windows loader case. The successful no-HIMEM installation does not qualify
the HIMEM/HMA path.

The memory-work follow-up is to compare no HIMEM, HIMEM with DOS=LOW, and
HIMEM with DOS=HIGH on pristine clones with the corrected kernel, recording
XMS discovery/version, free memory, allocation, and locking before invoking
the same loader. See [Windows 95 setup findings](tests/WINDOWS95-SETUP.md)
for the environment, configuration, evidence boundaries, and retest plan.

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
10,800-byte gap. Four successive EMM386 paragraphs raise the current result to
608,000 bytes and reduce the gap to 10,736 bytes. Moving the real IDTR load to
the protected transition and replacing duplicated real-return tails with one
packed atomic `IRET` reach 608,096 bytes. Linking the complete system-call
dispatcher above the DOS-high boundary then reaches 608,864 bytes and a
9,872-byte gap. Relocating the contiguous absolute-disk, system-return, and
INT 2Fh gateway tranche raises the current result to **609,520 bytes** and
reduces the gap to **9,216 bytes**. Compacting the BIOS INT 13h vector exchange
then raises the current result to **609,536 bytes** and leaves **9,200 bytes**.
Using zero-based head-wrap arithmetic raises it again to **609,552 bytes** and
leaves **9,184 bytes**. Applying the same sector arithmetic and direct BDS
field selection raises it to **609,568 bytes** and leaves **9,168 bytes**.
Removing the selector state entirely raises it to **609,600 bytes** and leaves
**9,136 bytes**. Keeping the PS/2 Model 25/30 disk-parameter result on the
active BIOS stack instead of in ten resident words raises the measured result
to **609,696 bytes** and leaves **9,040 bytes**. The ordinary disk-vector and
286/386/486 gates pass. A focused injected-underlay test forces the Model 25/30
path and proves that both `INT 13h/AH=08h` and `AH=15h` preserve every returned
register and the first call's carry while issuing exactly one status call.
Reusing DOS's existing two-record low DPB reserve for the first two of six
possible built-in drives raises the result again to **609,760 bytes** and leaves
**8,976 bytes**. Using each saved interrupt vector's existing segment sentinel
for warm-boot restoration removes the redundant completion byte and offset
sentinel test; the selected BIOS falls to 8,192 bytes, VC rises to **609,776
bytes**, and the remaining gap is **8,960 bytes**.
Keeping the optional K09 `INT 6Ch` far return on its existing stack frame and
deriving preceding-month lengths from an immediate bit mask remove 30 linked
BIOS bytes and cross two allocation boundaries. The selected BIOS is now 8,160
bytes, VC rises to **609,808 bytes**, and the remaining gap is **8,928 bytes**.
Shortening the duplicated privileged-operation recovery prompt removes 28
linked low-data bytes while preserving its error number and Continue/Reboot
choices. EMM386 falls to 3,920 bytes, VC rises to **609,824 bytes**, and the
remaining gap is **8,912 bytes**.
Making explicit `ON` and `OFF` clear `AUTO` before testing the current active
state removes their shared cleanup tail without changing command semantics.
EMM386 falls to 3,904 bytes, VC rises to **609,840 bytes**, and the remaining
gap is **8,896 bytes**.
Sharing validation and state selection across explicit `ON` and `OFF` removes
15 more linked low-code bytes while retaining pre-transition state publication.
EMM386 falls to 3,888 bytes, VC rises to **609,856 bytes**, and the remaining
gap is **8,880 bytes**.
Relocating the 403-byte private error-table group into `HIGH_TABLE` releases
400 paragraph-rounded bytes from the DOS prefix. VC now reports **610,256
bytes**, leaving **8,480 bytes** to retail with the same 49,104 free UMB bytes.
Exact byte parity is not required, but a large unexplained loss is not
acceptable.

The VC owner-to-owner spans now reconcile the complete difference rather than
treating it as an undifferentiated target:

| Status | Accounted difference | Bytes |
| --- | --- | ---: |
| Advantage | EMM386 resident allocation | -240 |
| Open | HIMEM resident excess | 1,488 |
| Advantage | FILES/FCBS/BUFFERS/LASTDRIVE/STACKS aggregate | -16 |
| Open | Retained DOS/BIOS pre-shell payload and layout | 5,344 |
| Open | COMMAND owner-to-owner span | 880 |
| Equal | VC owner-to-free span | 0 |
| Open | Conventional ceiling/EBDA | 1,024 |
| **Total** | **VC largest-block gap** | **8,480** |

The earlier 32,928-byte DOS relocation-hole recovery remains closed. Remeasure
the rows above after each retained change instead of assuming that every byte
is another oversized component. The 5,344-byte DOS/BIOS row is an exact
owner-level remainder. Phase A3 now accounts for every byte of both the
4,992-byte DOS low prefix and the selected 8,160-byte BIOS image. E1 must turn
those ownership ranges into proved address and lifetime contracts.

## Road to retail-or-better conventional memory

The target is a largest conventional block of at least **618,736 bytes** in the
fixed VC 4.05 comparison, without reducing supported memory-manager options or
usable UMB space. The current result is 610,256 bytes, so 8,480 more bytes must
join the largest free block. Total free memory is supporting evidence, not a
substitute for this metric: saving bytes below a resident island may leave the
largest block unchanged.

The present accounting identifies the whole target but not yet every individual
symbol responsible for it:

| Workstream | Current excess or opportunity | Cumulative result if fully recovered |
| --- | ---: | ---: |
| EMM386 resident allocation | -240 bytes | 610,256 bytes |
| HIMEM resident allocation | 1,488 bytes | 611,744 bytes |
| COMMAND resident allocation | 880 bytes | 612,624 bytes |
| Layout and conventional ceiling | 6,112 bytes | 618,736 bytes |

Matching the two oversized named components recovers at most 2,368 bytes
and therefore cannot meet the goal; layout work is mandatory unless a component
becomes smaller than retail by the remaining amount.

### Success equation and critical path

Treat the 8,480-byte gap as a portfolio, not as four independent size targets.
For every retained change record:

```text
remaining gap = 8,480 - EMM386 gain - HIMEM gain - COMMAND gain
                         - DOS/layout gain - ceiling gain
```

Only growth of the largest VC block counts as a gain. Component shrinkage that
lands in a separate free island is pending layout work until that island is
joined to the largest block. No workstream is required to match retail's
private size: one may beat retail and cover an irreducible difference elsewhere.

The currently proved upper bound from matching the remaining oversized named
components is 2,368 bytes. Moving the 1 KiB EBDA without allocating a
replacement block raises that to 3,392 bytes, still leaving **5,088 bytes**.
Even after those recoveries, bulk placement or better-than-retail component
footprints must supply another 5,088 bytes. Retain the current EMM386 advantage
and avoid counting any saving twice.

The current execution order is defined only in **Current architectural
priority** and the **Required checkpoint: one complete resident layout** above.
The completed kernel, buffer, BIOS and shell tranches are evidence for that
checkpoint, not an instruction to repeat their old optimization sequence.

The next audit must include the full 21,376-byte development system span and
the separate COMMAND owner. In particular, distinguish genuinely low-only
interfaces from public real-mode data that could use UMBs, and investigate the
16 KiB UMB-discovery constraint before freezing the available destination
budget. Matching retail is the acceptance floor; layout A alone does not
explain or reproduce the larger OpenDOS block.

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
| Complete | Census fixed HMA ownership and COMMAND's top-level resident ranges | The checked maps identify 18,028 initially free bytes of DOS-owned HMA tail and exact ownership ranges for the DOS low prefix and selected BIOS image | attribution complete | Deeper COMMAND work is paused; E1 must prove relocation contracts |
| Paused | Move more COMMAND cold state high or transient | The 1,281-byte normal catalog and 1,166-byte code range are high; 820 of the remaining 955 low service bytes belong to the installed interrupt handler and registered disk callback | under one kilobyte, then better-than-retail opportunities | Resume only as a coherent interrupt/data redesign, not for gateway-scale helpers |
| Paused | Complete the small EMM386 low gateway backed by locked XMS | Local active EMM386 is 240 bytes below retail after the real IDTR move, VM-frame scratch compaction, low fatal-dialog compaction, and shared control dispatch | further better-than-retail headroom | Reopen only for a coherent relocation or measured post-DOS residual; inactive `AUTO` and all EMS maps remain gates |
| Paused | Compact EMM386 runtime-sized metadata and alignment | Physical-page IDs, DMA pages, and mappable-window indexes now scale with the selected layout | tens to hundreds of bytes per item | Reopen only after the bulk DOS placement result; full option and EMS 4.0 formats remain gates |
| 1 | Relocate eligible DOS low state as one packed block | The dispatcher and 652-byte absolute/system/INT 2Fh tranche are high; the local system-to-COMMAND span now costs 6,576 bytes more than retail and leaves 5,344 bytes of measured DOS/BIOS remainder | low kilobytes | Start with tables and constants, then eligible mutable workspaces; some low addresses are ABI/BIOS fixed |
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
| Complete A2 | Measurement | Reconcile the full VC gap through system, COMMAND, VC, free-block, and ceiling spans, isolating the retained DOS/BIOS remainder | The current report proves `6,576 + 880 + 0 + 1,024 = 8,480`; the component census isolates 5,344 bytes for E1 |
| Complete A3 | Measurement | Add reproducible HIMEM, EMM386, COMMAND, DOS, and BIOS resident-range reports from their linker maps | HIMEM, EMM386, COMMAND top-level lifetimes, fixed HMA layout, and every byte of the 4,992-byte DOS low prefix and selected 8,160-byte BIOS image are accounted |
| B1 | HIMEM | Continue the map-guided audit of dispatch, validation, move, lock, A20, HMA, request-header, and error paths; share tails only where outputs and reentrancy agree | Exact XMS 2/3 errors, all A20 backends, HMA, moves, warm reboot, and 286 execution pass |
| B2 | HIMEM | Audit the move descriptor, UMB transaction records, handle records, counters, sentinels, immutable values, and alignment for narrower or derived representation | Zero-length and 128 handles, 32 UMB extents, rollback, locks, reallocations, and legacy bounce pass |
| B3 | HIMEM | Move every remaining parser, CPU/memory detection, destructive test, message, and installation temporary beyond the rounded resident break | Map proves no runtime reference crosses the break; normal and maximum option footprints are budgeted |
| B4 | HIMEM | If compaction stalls, investigate storing immutable tables or cold state in DOS-owned HMA slack, or a relocation-safe XMS area | Ownership is explicit, third-party XMS coexistence works, and no DOS buffer/HMA capacity is lost |
| Complete C1 | EMM386 | Maintain byte-range accounting for the current 375-byte low `_TEXT` prefix and 396-byte `_DATA`, including local labels, anonymous gaps, VDATA overlay, discarded loader stack, and paragraph padding | Every retained byte is real-only, dual-mapped, mutable runtime, compatibility state, discarded initialization state, or unresolved |
| C2 paused | EMM386 | Compact descriptors, flags, counters, map owners, DMA state, GDT entries, option-sized arrays, VDATA stride, and mutually exclusive workspaces | Reopen only after DOS placement establishes a residual; normal and maximum option layouts remain gates |
| C3 paused | EMM386 | Move further immutable tables, exception support, protected dispatch, and protected-only routines into the existing locked XMS image | Reopen only as a coherent architectural relocation; faults, DMA, mappings, modes, UMBs, and warm reboot remain gates |
| C4 paused | EMM386 | Split ordinary EMS service dispatch from mapping-sensitive activation so services that do not require virtual mode can live in the relocated image | EMS 3.2/4.0, non-empty function 56h maps, alternate sets, and inactive queries remain gates |
| C5 paused | EMM386 | Replace `RRProc` and the return-to-real continuation with a small position-independent low gateway, then relocate the remaining transition module | Init-only `RR_Trap_Init` is high; resume only if a post-DOS byte budget justifies redesigning the active 84h/85h continuation |
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

The immediate execution order is now E1-E4: apply the DR-DOS-style bulk DOS
placement ladder and coalesce layout. The DOS-owned HMA tail has 15,437 bytes
left after COMMAND, but capacity alone does not prove that the 5,344-byte
DOS/BIOS remainder is relocatable. C2-C5 are
paused because EMM386 is already smaller than retail and further paragraph
harvesting does not address the dominant owner. E5 is a bounded 1,024-byte
finishing step. Revisit HIMEM and COMMAND only against the measured residual;
F1 remains the fallback if the placement work cannot close it.

The EMM386 census is reproducible from a clean linker map:

```sh
python3 tests/report_emm386_residency.py --check \
  src/MEMM/MEMM/EMM386.MAP
```

The current map divides `_TEXT` at `IOTrap_Tab`: 375 low bytes precede the
boundary and 17,589 non-low bytes follow it. The report now accounts for
the complete 1,471-byte static low-image address range: a 336-byte real-mode
gateway, 176-byte GDT, 396-byte `_DATA`, 177-byte constants, 10-byte BSS,
1 byte of alignment, and the 375-byte dual-mode `_TEXT` prefix. The full
1,024-byte initialization stack follows `LAST` and is discarded. The report
also divides the retained prefix by linked module and
`_DATA` into driver/messages, EMS tables, A20/OEM transition state, DMA, and
move-state ranges.
For the fixed configuration it then accounts for the complete 1,904-byte VDATA:
512 bytes of saved maps, 256 bytes of handle records, 512 bytes of names,
512 bytes of page arrays, six mappable-window indexes, a two-byte default DMA
page list, and 104 bytes of normal/alternate register sets. The dynamic data
ends on a paragraph boundary before the 512-byte protected stack, bringing the
computed and live retained-layout end to 3,888 bytes, 240 bytes below retail.
Command-line counts
allow the same layout equation to be checked for other supported configurations.
C1 is complete; C2-C5 remain measured fallback work after DOS placement.

### Decision gates

| Gate | Required evidence | Decision |
| --- | --- | --- |
| Layout independence | Complete: one-paragraph reductions exposed `SS`-relative accesses to `CURADD` in the released low copy of DOS's relocated tail; a disk read overwrote COMMAND's entry at `A061h` | The accesses now follow `CS` into the HMA, the binary layout test rejects the old encodings, and `/NUMHANDLES=24..32` boots after a real paragraph reduction |
| Attribution | All conventional ranges and every EMM386, HIMEM, and COMMAND resident symbol have an owner, lifetime, and size | EMM386 symbol ownership and HIMEM allocation-range accounting are complete; COMMAND plus deeper DOS and BIOS ownership remain |
| Placement budget established | BIOS bodies, dynamic DOS allocations, and kernel data have explicit destinations and low-required interfaces | Select a coherent multi-kilobyte relocation; exhausting small compactions is not a prerequisite |
| Layout route chosen | EBDA destination and all low islands are proved safe, or their gains are rejected explicitly | Implement only gains that join the largest block |
| Architecture justified | DR-DOS measurements identify bulk kernel, shell, buffer, and DOS-state placement; local EMM386 is already below retail | Build the packed DOS high-state block first, then size COMMAND, HIMEM, EBDA, or gateway work from the residual |
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

The earlier attempt to inline the single-use `MaskIntAll` and `RestIntMask`
wrappers was rejected when the extended EMS 4.0 lifecycle hung. The explicit
EMS return gateway and maximum-VDATA fix now make that boundary independent,
and the retained retry uses a stronger ownership model: the saved mask is a
word on `GoVirtual`'s preserved client frame rather than shared transition
state. The complete extended sequence, shifted modes, maximum options, reboot,
and hardware matrix pass at the smaller boundary.

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

The current milestone reproduces 610,256 versus 618,736 bytes, the component
figures below, a conventional ceiling of `9FC0h` versus retail's `A000h`, and
the 1,216-byte local UMB advantage. This completes the repeatable measurement
foundation; generated reports remain build evidence rather than tracked
documentation.

The report also records every VC row's address, block count, grouped payload,
and owner. These rows belong to the VC snapshot after `MEM` exits; the raw
`MEM /D` rows were captured while MEM itself was allocated. The two views are
therefore displayed separately and must not be added together. In the current
VC snapshot, the grouped `DOS 6.22` payload is 25,536 bytes versus retail's
18,480, a 6,656-byte difference that includes the memory managers and retained
DOS layout. COMMAND contributes another 880 bytes, while the one-kilobyte
ceiling difference acts at the opposite end of the largest block. Phase A2
must decompose that DOS aggregate without mixing in the earlier MEM process
image.

The generated owner-to-owner spans provide an exact top-level reconciliation:

| Span | Difference |
| --- | ---: |
| System start through COMMAND start | 6,576 bytes |
| COMMAND start through VC start | 880 bytes |
| VC start through conventional free block | 0 bytes |
| Conventional ceiling | 1,024 bytes |
| **Total** | **8,480 bytes** |

The pre-COMMAND system span contains EMM386's 240-byte advantage, a 1,488-byte
HIMEM excess, and a 16-byte advantage in the other configured system tables.
Subtracting those measured components leaves **5,344 bytes** of retained
DOS/BIOS payload and layout. Owner-level accounting and A3 are closed; E1 must
now prove which exact ranges can move or shrink without changing their public,
interrupt, device, disk, or A20-off contracts.

The first A3 map census is reproducible with:

```sh
make test-dos-bios-residency
```

For the current build, `DOS_LOW_GATE_END` is 4,978 linked and 4,992
paragraph-rounded bytes below the HMA. The HMA copy contains 39,488 bytes
after its fixed `0010h` entry offset, and DOS's `LAST` initialization segment is
1,795 discardable bytes. The BIOS has 15,598 linked bytes of resident-code
capacity and 20,161 discardable SYSINIT bytes; its possible hardware-selected
resident boundaries range from 7,936 bytes for floppy-only through 12,096 bytes
when all optional legacy blocks are retained. The fixed QEMU comparison selects
one hard disk, no 96-TPI or legacy AT-ROM extension, a CMOS clock, and no K09
extension. `ENDONEHARD` contributes 8,030 bytes and rounds to 8,032 bytes; the
contiguous relocated 121-byte day converter and 5-byte BCD converter establish
the exact `1FE0h` or 8,160-byte resident BIOS boundary.

The DOS low prefix consists of 3 bytes of loader entry, 1,072 bytes of
constants, 1,783 bytes of mutable data, 1,962 bytes of tables, 157 bytes of
code, and one alignment byte. The checked report assigns every byte of the
constants, data, tables, and code to an ownership range. Exact coverage is not
permission to move a range: near pointers, asynchronous entries, device
callbacks, and A20-off paths must first be classified.

The constants census isolates 301 bytes of bootstrap SFT, 261 bytes of console
buffers, 119 bytes of UMB/lock state, 200 bytes of nucleus and SHARE-compatible
state, and smaller request, error, process, and identity ranges. The table
census now keeps 220 bytes of INT 21 dispatch low and records 403 bytes of
private error metadata separately in `HIGH_TABLE`, alongside 795 low bytes of
country/case-folding/messages, 283 bytes of swap/fake-version state, 256 bytes
of FCB character classes, and the remaining communication and lookup tables.
These are ownership budgets only; E1 must still prove each range's address and
lifetime contract before selecting HMA, relocation-safe XMS, or UMB storage.

The selected BIOS census likewise covers all 8,160 bytes. Its largest ranges
are 1,753 bytes of generic disk IOCTL/INT 2F services, 1,575 bytes of core data
and device headers, 1,356 bytes of disk transfer/error paths, 751 bytes of
media-change/BPB services, and 733 bytes of sector/low-level I/O. The remaining
1,992 bytes cover console, auxiliary, printer, clock, model/vector, disk-init,
descriptor, helper, loader, and alignment ranges. BIOS work should start with
the large disk paths, but only after separating always-addressed entry points
and callback state from compactable helpers.

The checked CODE census now covers every byte below `DOS_LOW_GATE_END`: 70
bytes of HMA driver request entry, 76 bytes of low DPB pointer workspace, and
11 bytes of HMA driver/XMS and null-device tail. The contiguous 652-byte range
after it contains 387 bytes of absolute-disk services, 199 bytes of shared
system/FCB return and error handling, and 66 bytes of INT 2F handling. Its
externally entered paths use HMA gates, its internal returns are called from
the relocated image, and the separate low trampoline restores A20 after legacy
driver callbacks. It is now released under DOS=HIGH and retained under
DOS=LOW. The complete 808-byte system-call dispatcher contribution, including
its 12-byte EMS map, remains linked above that tranche and copied to HMA.

The fixed VC image's grouped pre-MCB payload is 13,152 bytes: the exact
4,992-byte paragraph-rounded DOS gateway plus the exact 8,160-byte selected
BIOS image. The following system MCB contains 12,384 bytes; enumerated
components occupy 12,272 bytes, leaving 112 bytes. Together with 32 bytes of
group-level MCB/gap overhead, these ranges account for the current 13,296-byte
non-component system footprint. Retail's corresponding remainder is 7,952
bytes, producing the already measured 5,344-byte excess. The likely
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
| Paused | Complete the EMM386 low gateway | The active 3,888-byte allocation is 240 bytes below retail after loading the real IDTR before clearing PE, compacting VM-frame scratch around a packed atomic `IRET`, shortening the duplicated low fatal-dialog wording, and sharing explicit `ON`/`OFF` dispatch while retaining pre-transition state publication | Reopen only for a coherent relocation or post-DOS residual; preserve inactive `AUTO` and every EMS map |
| Paused | Compact EMM386 metadata while changing that boundary | The loader stack is discarded, duplicate PTE offsets and inverse segment index are gone, physical-window segments, public `Pn=` identifiers, DMA pages, mappable-window indexes, bounded counters, and parity-vector state are runtime-sized, narrowed, derived, shared, or protected-high | The selected tail ends at `0D2Fh`; retain this boundary until a later byte budget justifies reopening it |
| 1 in progress | Relocate eligible DOS low state as one packed block | The dispatcher and contiguous 652-byte absolute/system/INT 2Fh tranche are HMA-resident under DOS=HIGH, reducing the DOS gateway to 4,992 bytes and the DOS/BIOS remainder to 5,344 bytes | Move tables and constants as a group, then eligible mutable state through HMA, relocation-safe XMS, and bounded UMB tiers |
| 2 in progress | Relocate complete BIOS services and reclaim their old low allocation | Normal BIOS is 8,160 bytes; development retains 5,152 after reclaiming 3,008 | Finish relocation acceptance, then budget remaining services jointly with DOS state; do not resume isolated routine compaction |
| 7 | Remove MCB, allocation-order, and paragraph fragmentation | 112 bytes inside the system MCB plus 32 bytes group-level overhead are bounded; further islands need a live map | Make every recovered paragraph grow VC's largest block rather than a separate hole |
| 8 | Place eligible permanent allocations in existing UMBs | Local free UMB exceeds retail by only 1,216 bytes | Accept only deterministic placement that leaves at least 47,888 usable UMB bytes |
| 9 | Recover the EBDA ceiling paragraph | Exactly 1,024 bytes | Use already-owned proved-safe storage, update the BDA atomically, then test BIOS, DMA, interrupts, and reboot |
| 10 | Revisit HIMEM only if the measured residual requires it | 1,488-byte excess over retail; incremental work paused | Resume only with a paragraph-scale, map-supported opportunity and preserve every existing gate |
| 11 | Redesign the DOS-low or COMMAND boundary further | Architectural fallback | Choose the smallest design with a byte budget that covers the remaining measured gap and compatibility margin |

The focused clean-room DR-DOS revalidation reproduces the prior owner and API
results exactly. Re-analysis against the current build reverses the earlier
implementation order: apply the DOS placement ladder now and stop incremental
EMM386 work. The `M5` plus `DOS=HIGH`
transition regression is closed and remains a mandatory gate for later
boundary changes. The initial COMMAND/HMA gain is retained, but deeper shell
work is paused. Recover the bounded EBDA paragraph only near the end, and
revisit HIMEM only for a measured residual. Recalculate the success equation
after every retained step and keep both the conventional and UMB floors
visible.

#### Architectural re-analysis: stop chasing EMM386 paragraphs

The earlier priority over-weighted OpenDOS's small memory-manager gateway.
That work established the right architecture and brought local EMM386 to 3,888
bytes, already 240 bytes below retail, but it no longer explains the remaining
gap. Reconcile DR-DOS 6 against the current fixed image instead:

| Owner-to-owner span | Current | DR-DOS 6 | DR-DOS advantage |
| --- | ---: | ---: | ---: |
| System start through COMMAND start | 25,568 | 10,720 | 14,848 |
| COMMAND start through VC start | 3,984 | 1,264 | 2,720 |
| VC start through free block | 12,720 | 12,720 | 0 |
| Conventional ceiling loss | 1,024 | 1,024 | 0 |
| **Largest-block difference** | **610,256** | **627,824** | **17,568** |

This is an architectural placement result. The controlled DR-DOS transitions
attribute it to four bulk moves: roughly 38 KiB of kernel and 3.5 KiB of BIOS
code to HMA, about 5 KiB of COMMAND to HMA, 28 KiB of EMM386 to a UMB, and
12.8 KiB of buffers plus other DOS state out of conventional memory. DR-DOS is
not winning by making each retained routine a few bytes shorter. Our kernel,
buffers, part of COMMAND, and almost all protected EMM386 code are already
high. The remaining architectural work is high BIOS service placement,
authoritative high placement of eligible DOS state, and boot-time compaction
that returns their old ranges to the largest conventional block. The 4,992-byte
local kernel prefix and DR-DOS's 4,528-byte low DOS system region are already
of similar scale; their different boundaries do not imply another kernel-sized
gain. DR-DOS instead reports only 2,768 low BIOS/device bytes against our
8,160-byte selected BIOS inventory. Treat that as placement evidence, not a
promise that the implementations can use identical low boundaries.

The old DR-DOS 6 placement cannot be copied literally. With an EMS frame it
leaves only 15,568 free UMB bytes, below the 47,888-byte retail floor. The local
fixed image has only a 1,216-byte UMB advantage to spend, but has 15,437 bytes
of unassigned DOS-owned HMA tail after the completed COMMAND move. Therefore
the portable local design is:

1. finish the high BIOS service split with explicit low interfaces and early
   HMA reservation, then actually reclaim its old conventional range;
2. group eligible DOS state by access contract, packing immutable tables and
   HMA-safe mutable workspaces with bases fixed once during initialization;
3. keep only address-stable interrupt/device gateways and state needed while
   A20 may be disabled in the 4,992-byte low prefix;
4. use relocation-safe XMS storage only for state reached through an explicit
   copy or protected gateway, and spend at most 1,216 UMB bytes unless another
   change first increases the free-UMB margin; and
5. fall back transactionally to the current low layout for `DOS=LOW`, HMA
   failure, or an unsupported ownership contract.

The completed kernel inventory covers the 1,962-byte `TABLE` contribution and the
1,072-byte `CONSTANTS` contribution, then eligible portions of the 1,783-byte
`DATA` contribution. These are ownership inventories, not movable-byte budgets:
both TABLE and CONSTANTS contain mandatory low interfaces. The decisive gate
is not the linked size of any one
routine: the DOS low prefix and owner-to-COMMAND span must fall by whole
paragraphs, the gain must join VC's largest block, and filesystem, device,
redirector, EXEC, asynchronous interrupt, A20, DOS-low, and warm-reset tests
must all pass. The 5,344-byte DOS/BIOS remainder is the target budget for this
workstream, not a proved saving. Even releasing the entire 4,992-byte DOS
prefix could not cover that remainder; BIOS relocation or another owner must
contribute, and the required low interfaces reduce that upper bound further.

After this tranche, measure the residual before choosing among COMMAND's
880-byte retail excess, HIMEM's 1,488-byte excess, and the bounded 1 KiB EBDA
step. Further EMM386 compaction is explicitly deferred unless it is a coherent
gateway relocation or the post-placement residual proves it necessary.

##### Next milestone: whole-system placement design

###### Development DOS-state tranche: bounded FILES/FCB UMB placement

The first stable-address candidate is the contiguous extra SFT and FCB
allocation built by `EndFile` in `SYSINIT1.ASM`. With the fixed `FILES=20`,
`FCBS=4,0` settings, `SF.INC` defines 59-byte entries and a six-byte header:

| Allocation | Payload calculation | Rounded payload | Marker | Low span |
| --- | --- | ---: | ---: | ---: |
| Additional FILES entries | 6 + (20 - 5) × 59 | 896 | 16 | 912 |
| FCB entries | 6 + 4 × 59 | 256 | 16 | 272 |
| Combined | | 1,152 | 32 | 1,184 |

One UMB owner containing both existing marked allocations costs 1,200
bytes including its MCB. Against the fixed 49,104-byte free-UMB baseline this
leaves **47,904 bytes**, just 16 above the 47,888-byte floor. The development
transaction now reclaims the complete 1,184-byte low span. The embedded first five SFT
entries remain in the kernel prefix. This budget does not include LASTDRIVE.

`TABLEUMB.INC`, enabled only with the development BIOS rebase build, runs after
FCB initialization and before buffer allocation. Its transaction contract is:

1. Record the paragraph-aligned start before the extra FILES marker. Verify
   the completed range, table counts, terminal links, and absence of live
   entries; do not infer a movable range from the budget alone.
2. Acquire/register UMBs through `AcquireUmbs`, which already supports early
   DEVICEHIGH allocation. Allocate one upper-only block transactionally,
   restoring the caller's allocation strategy and UMB link state on every path.
3. Copy the marked tables, rebase their marker segments, set a permanent system
   MCB owner, and publish the extra-SFT link plus the authoritative FCB pointer.
   Account for the later high/low SYSINIT-variable synchronization; do not leave
   either public or kernel consumers pointing at the released copies.
4. Rewind the low allocation cursor only after successful publication, so
   subsequent buffers/CDS reuse the full range. Failure must leave the original
   tables and low cursor intact, with no leaked table allocation. UMB provider
   registration itself remains the normal shared `AcquireUmbs` operation.

The development policy limits the combined allocation to 74 paragraphs before
the MCB, derives the actual span from the completed allocations, and leaves
larger tables low. Public graph tests verify the extra SFT/FCB counts, their
shared upper owner, relative positions, permanent MCB ownership, and size.
`make test-bios-upper-tables-qemu` tests FILES=8 placement, FILES=30 budget
fallback, and forced allocation failure; the rebase suite also covers the fixed
FILES=20 layout, DOS=LOW, absence of UMBs, returned A20-off device callbacks,
reset, and stale-pointer rejection. System and FCB probes run before the public
graph check, including failed-open cleanup in the additional SFT entries.

The FCB probe initially failed with DOS=HIGH even without UMB relocation.
`LRUFCB`, `ResetLRU`, and `SetOpenAge` in `FCBIO.ASM` assumed SS had no DOS
ownership, so implicit mutable-state references could select the high copy via
CS. They now declare the DOS-stack SS owner, consistent with FCB dispatch and
the existing explicit SS accesses. The FCB suite passes with low and upper
tables; the normal HMA suite now runs it independently of BIOS relocation.
This kernel correctness fix also applies to normal builds. All 43 combined
table-placement, rebase/reset, and buffer-capacity cases pass locally, together
with the normal HMA, FCB, system-contract, and residency gates.

Fresh fixed captures `out/tables-upper-vc.md` and `out/tables-normal-vc.md` show
**614,448** development conventional bytes versus **610,256** normal, with
47,904 and 49,104 free UMB bytes respectively. The development gap to retail is
now **4,288 bytes**. The 3,008-byte BIOS gain and 1,184-byte table gain are
additive in this measured configuration; HMA image size remains 39,488 bytes.

The upper-table access gate occupies the remaining embedded SFT slots and
requires LOWTEST's active entry to reside in the UMB. It snapshots the entire
marked allocation, proves A20 is disabled through a distinct HMA/low alias,
and compares every table byte without entering DOS while the gate is off.
It then maps two allocated EMS pages into the first frame window, writes and
reads distinct page patterns, and compares the tables after each mapping.
Cleanup restores the saved EMS map, releases the handle, and verifies the
original free-page count. A deliberately corrupted expected snapshot must fail
only after reporting successful cleanup. These are fixed-profile accessibility
checks, not proof of arbitrary redirector or memory-manager compatibility.

SHARE acceptance exposed a pre-existing FCB pointer-ownership bug, including
in DOS=LOW. Creation returned success (`AX=1600h`), but the caller's record-size
field was not initialized. The earlier `INT21_16_FAIL` label conflated the
return-code and record-size checks; extended error `0008h` was stale, not proof
of allocation failure. `SaveFCBInfo` and `CheckFCB` changed DS to DOS ownership
before calling SHARE's `ShSave` and `ShChk`, whose contract requires the
caller's DS:SI FCB. They now preserve that pointer; SHARE's DOS state remains
SS-relative. This correctness fix applies to normal and development builds.

The dedicated local acceptance target is:

```sh
make test-bios-share-tables-qemu
```

It covers four memory modes with each of two cache policies. With `FCBS=4,0`,
SHARE replaces the boot cache with its own resident 16,8 cache, and the public
graph checks that replacement. With `--fcb-keep 1` (`FCBS=4,1`), SHARE retains
the boot cache, including its upper location in the eligible EMM386 case.
Both run the complete FCB probe before and after the SHARE/NLSFUNC compatibility
and system probes, require SHARE's installation response, and retain the
ordinary four-entry and upper-owner checks for the retained-cache case.
The FCB diagnostic now distinguishes record-size corruption and reports the
observed AX alongside the possibly stale extended error.
All eight SHARE/cache cases and thirteen existing upper-table cases pass
locally, as do the normal HMA, standalone FCB, and compatibility suites.

Before promotion, test redirector consumers, additional EMS mapping profiles,
and real high-resident competition. The SHARE matrix does not establish those
broader contracts or a new fixed-image memory gain.

The real-resident diagnostic now uses repository ANSI.SYS, not a synthetic
allocation. `--ansi-high` adds `DEVICEHIGH=ANSI.SYS`; `--ansi-low` is the
otherwise-identical `DEVICE` control. Its probe verifies the active CON
location, a system-owned containing MCB for upper placement, ANSI generic
IOCTL state, and cursor positioning through an explicitly opened CON handle
(serial CTTY must not bypass ANSI). The existing DOS-table and filesystem
checks follow it.

The initial DEVICEHIGH/EMM386 case stalled before AUTOEXEC, including with
normal IO.SYS and forced table-allocation fallback. Loader-boundary tracing
found an all-zero ANSI header at the intended upper entry address; even its
strategy routine could not be called. Raw overlays used one large DOS read,
whereas MZ overlays already used sector-sized transfers for mapped UMA safety.
`EXEC.ASM` now also reads raw overlays in at-most-512-byte chunks, stopping at
EOF and retaining the original exact-65535-byte rejection. Ordinary COM
execution keeps its existing path. Temporary loader tracing is removed.

```sh
# Low-placement control and complete real-resident matrix.
python3 tests/test_bios_low_boot_qemu.py \
  --early --tail-body --rebase --compact --ansi-low --mode emm-high
make test-bios-ansi-tables-qemu
```

The ten matrix cases pass: four memory modes, the same four with SHARE and
its retained boot cache, forced table-allocation fallback with high ANSI,
and high ANSI across warm reset. This establishes real-resident coexistence,
not natural upper-memory exhaustion handling or arbitrary-driver compatibility.
The direct `--umb-read` probe originally confirmed ordinary file-I/O corruption:
a 512-byte UMB read passed, but 513 bytes returned the requested count with a
mismatch at byte zero. Conventional targets passed 512/513/4096/8192 bytes.
Two EMS-only assumptions caused the UMB failure: `SwapDMAPages` rejected
non-EMS windows before translating them, and `GetPteFromIndex` synthesized
identity mappings for those windows instead of reading their real PTEs.

`MAPDMA.C` now reads the real UMA PTEs and permits already-contiguous physical
transfers before checking EMS ownership. It checks present mappings, the ISA
16 MiB address ceiling, and physical 64/128 KiB boundaries. Only the existing
EMS swapping path may modify EMS mappings; permanent UMB backing pages are
not passed to that ownership machinery. This is a partial translation fix,
not a complete arbitrary-UMB DMA policy.

The expanded probe tests reads and writes of 512/513/4096/8192 bytes at offsets
0, 31, and 4095 in a 12 KiB allocation. It flushes/closes files, compares every
requested byte, checks read guards, and reads written data back into low memory.
All four memory modes pass, as does upper last-fit; observed upper targets are
`DC4Ch` and `E500h`. Extended EMS lifecycle and EMM386 API/mode suites also pass.
The focused target also passes high ANSI/SHARE coexistence and warm
reset, requiring the I/O success marker on both boots. No passing case alone
establishes physical-boundary coverage.
`make test-himem-qemu` also passes XMS, concurrent UMB/EMS isolation, provider
activation/rollback, and warm reboot. Its patterned-UMB remapping check does
not replace the interleaved I/O test below or asynchronous DMA coverage.

```sh
make test-bios-umb-io-qemu
```

The DMA fallback to a linear address is unsafe for arbitrary non-identity
mappings. Repository UMB creation now prevents the fragmented, boundary-shifted,
and above-ISA layouts that previously reached it; this does not make that
fallback a general transfer/error policy. Keep the bounded overlay workaround
until the remaining combined DMA/EMS and broader transfer gates are verified.

The 32 KiB probe adds offsets 8191, 12287, 16383, 20479, and 24575 to cross
multiple 16 KiB backing pages. Before the selector fix, the ordinary four-mode
matrix passed, but reversing only the available EMS page stack reproduced an
8,192-byte read failure at offset 24,575, target `DC4Ch`, first mismatch zero.
It preserves the set of free pages, counts, and ownership; the only changed
input is allocation order. System/FCB and upper-table checks still pass after
the I/O failure. The same regression now passes with the new selector:

```sh
python3 tests/test_bios_low_boot_qemu.py \
  --early --tail-body --rebase --compact --umb-read --umb-span 32 \
  --mode emm-high --reverse-umb-backing
```

The harness builds the diagnostic EMM386 in its temporary output directory;
`UMB_TEST_REVERSE_FREE` is absent from distribution builds. `--emm386-image`
also accepts a separately built local diagnostic binary. The focused target
passes seventeen cases: the original twelve, reversed-backing first-fit and
reversed last-fit across warm reset, and three interleaved EMS/I/O cases below.
Both boots must pass the I/O probe.

`Commit_UMB` now selects below-16-MiB backing that is physically contiguous
within each virtual 128 KiB DMA region and preserves the virtual address modulo
128 KiB. This also preserves byte-channel 64 KiB boundaries: a valid logical
DMA span wholly inside registered UMB storage translates without page swapping
or completion-time copying. Each region's requested pages must all be free
before reservation begins. Only actual UMB pages are removed from the EMS free
stack; excluded UMA holes cost no backing. Selected entries are swapped onto
the stack's reserved prefix, preserving set ownership despite reordered input.

If any region cannot obtain safe backing, the entire unpublished UMB
transaction rolls back: restore identity PTEs, return the reserved prefix, and
leave EMS available without publishing an unsafe UMB provider. Initialization
code and the six-byte selector workspace are discarded. The residency census
and fresh fixed-image VC capture retain EMM386 at 3,888 bytes, conventional free
memory at 610,256, and free UMB at 49,104; no new low-memory saving is claimed.
The paired development capture also retains 614,448 conventional and 47,904 UMB
bytes against retail's 618,736 and 47,888.
The expanded HIMEM suite passes, including fault builds for failure after an
earlier region was mapped and candidate addresses above the ISA ceiling, along
with provider absence, EMS API, UMB isolation, and warm-reset checks. These do
not substitute for testing naturally
fragmented/limited pools, word-channel DMA, or DMA concurrent with EMS remaps.
General EMS DMA and third-party mapping contracts remain separate acceptance
requirements; the full BIOS/table promotion gate is not yet closed.

`--umb-ems` holds four patterned EMS pages while rotating all four frame slots
before each UMB read and write. It verifies the complete 64 KiB EMS payload and
the requested UMB data, saves/restores the caller's frame context with AH=47h/
48h, and releases the handle. These are interleaved synchronous operations,
not EMS calls from a DMA interrupt. The normal 32 KiB case, reversed last-fit
across warm reset, and high ANSI/SHARE retained-cache case pass. The harness
requires both EMS/I/O and subsequent DOS system/FCB/table success markers.

This exposed a separate AH=48h restore bug: `_RestorePageMap` copied four saved
words, then rebuilt every physical window via `_set_windows`, resetting
unrelated mappings. The probe printed its I/O success but could not return to
the later DOS checks; omitting context save/restore isolated the failure. The
restore now compares/applies only the four LIM frame slots and flushes the TLB,
leaving unrelated windows untouched. The combined test and extended EMS/API
suites pass, and the residency census remains at 3,888 bytes.

**DMA programming-sequence trigger fixed; broader DMA acceptance remains open:**
the same interleaved test with forced high-BIOS reservation failure previously
stalled after the first 8,192-byte, offset-zero
read. EMS verification/remapping completes, but AH=3Ch file creation does not
return: the application has not yet issued the corresponding write. The
`UMB_EMS_WRITE_READY`/`WRITE_OPEN` markers delimit this boundary. Reproduce with:

```sh
python3 tests/test_bios_low_boot_qemu.py \
  --early --tail-body --rebase --compact --umb-read --umb-span 32 \
  --umb-ems --mode emm-high --fail-reservation
```

A hardware breakpoint at `_FatalError` in a fresh QEMU reproduction catches
`SwapDMAPages` rejecting insufficient DMA pages. Its caller stack contains
linear address `D7460h`, length `2000h`, and byte-channel mode. The mixed address
uses the old `0Dh` page byte with new `7460h` low address bits; the old 8 KiB
count spans two EMS windows. Its DMA-buffer start index is 1, requiring entries
1 and 2 beyond the default one-entry buffer. This is a transient
register-programming state, not the application's actual transfer request.
`DMABaseN`, count, and page handlers previously translated after individual writes,
without tracking mask-register ports. The UMB backing selector cannot
prevent an intermediate address from landing in the EMS frame.

The handlers now track explicit single/all-mask writes, mask clear, and master
reset on both controllers. While masked, register writes update the snapshot
without remapping EMS; enabling a channel translates and programs the completed
address/count before the hardware enable. Mask bits share the existing
controller flip-flop bytes, with all byte-index consumers masking off those
bits. No additional low resident storage is required; the checked EMM386
allocation remains 3,888 bytes.

`tests/dma_mask_sequence.inc` exercises the old-page/new-address/old-count
collision, readback, mask commands, and master reset on idle byte and word
channels in the isolated QEMU fixture. It passes with the fix and rejects the
pre-fix binary before the I/O loop. It does not perform device-requested
word-channel DMA. All nineteen `test-bios-umb-io-qemu` cases pass, including
low-BIOS fallback and reversed last-fit UMB backing across warm reset, as do
HIMEM, extended EMS, EMM386 API, and address-phase suites.
Fresh fixed-image VC captures with this EMM386 retain 610,256 conventional /
49,104 free UMB bytes normally and 614,448 / 47,904 with development BIOS/table
placement. The fix removes a correctness blocker without changing either
memory floor; it does not qualify promotion by itself.

Only observed mask commands are tracked. Initial hardware masks are not
inferred from chipset-specific readback; automatic terminal-count masking and
global controller-disable programming remain unqualified. Actual word-channel
payloads, auto-initialize transfers, and constrained EMS pools still need
acceptance coverage. The reset/mask distinction follows the
[Intel 8237A datasheet](https://www.pcjs.org/documents/datasheets/intel/INTEL_8237A_DMA.pdf).
Check DMA buffer bounds before indexing `DMA_Pages` (the current swap path
reads the selected entry before checking capacity). Do not increase `D=` or
return an unsafe linear address merely to hide the transient request.

The fatal path has a second residency defect: after switching to real mode it
continues in the old low `_TEXT` image, now reused for file data. The paused
guest executes at `0696:3DB2` with paging/PE off; the physical instruction bytes
are the probe's incrementing-word pattern. Audit `ErrHndlr`/`_FatalError`
continuations across `RetRealHigh` separately; fixing the DMA trigger does not
qualify fatal-error handling. Keep these failures and the remaining word-channel/
naturally constrained-pool checks open before removing the raw-overlay
workaround or promoting the relocated layout.

The process suite independently checks raw overlays of 0, 1, 511, 512, 513,
9,109, 65,534, and 65,535 bytes in conventional storage. It checks every loaded
byte and the entire untouched destination tail, including bad-format rejection
for an empty file and the existing insufficient-memory error at exactly 65,535
bytes. ANSI supplies the real UMB-overlay case; these are not exhaustive
overlay-format or arbitrary transfer tests.
The same boundary probe passes against the pre-fix kernel. Local verification
also passes the fourteen DEVICEHIGH region/minimum/fallback cases, normal HMA
and process suites, and sixteen buffer-capacity cases including 38 and 39.

The current linker puts SYSBUF at 9A80h: the HMA image is 39,536 bytes, 48
above the older 39,488-byte capture (including the preceding SHARE fix).
With unchanged fifteen-buffer and COMMAND allocations, calculated normal
post-COMMAND slack is 15,533 bytes before the 5,220-byte development BIOS
reservation. The composed linked census corrects the former 15,389-byte
estimate; the discrepancy is accounting, not reclaimed memory. Older
15,437-byte budget figures below are superseded. This compatibility fix claims
no new conventional-memory gain.
The development all-high cache boundary consequently drops from 39 buffers to
38: 39 now uses mixed buckets. The requested count and I/O remain intact, but
this is a conventional-memory cost in that non-default profile, not a free
compatibility improvement. The capacity suite checks both sides of the new
boundary. Joint BIOS/cache/COMMAND placement remains a promotion requirement;
do not generalize the fifteen-buffer memory result to larger caches.
Larger tables or preloaded high residents need an explicit placement budget
and fallback; the 16-byte
fixed-profile margin is not general spare capacity. Stable UMB addresses avoid
HMA's A20 exposure but do not remove pointer-ownership or compatibility gates.

The acceptance unit is a released resident allocation, not an instruction-size
reduction. Keep isolated HIMEM/EMM386 compaction paused. Complete BIOS acceptance
against the development image's 3,008-byte BIOS and 1,184-byte table gains.
Further DOS-state placement must respect its remaining 16-byte UMB margin.
A test-only BIOS image is not the normal shipped layout.

Before another relocation, give every candidate one authoritative owner,
destination, lifetime, fallback, and conventional/UMB budget:

- BIOS: retain low hardware-facing state and A20-safe entry/return interfaces;
  reserve the high service body before publishing any pointers and reclaim the
  discarded low body through boot-time compaction.
- Dynamic DOS data: FILES, FCBS, and LASTDRIVE currently allocate through the
  low `MEMHI:MEMLO` arena in `SYSINIT1.ASM`. Their combined 3,440 bytes are the
  first grouped placement inventory. Trace public SFT/CDS/FCB and redirector
  access before choosing HMA or a stable UMB; the inventory is not a savings
  guarantee. Keep interrupt stacks and the disk transfer area low until their
  asynchronous/hardware access contracts prove otherwise.
- Kernel state: retain genuinely address-stable low interfaces, but give
  eligible private state one authoritative high home. A duplicate high copy
  alone saves nothing. Check fast calls and callbacks as well as normal dispatch.
- COMMAND: retain the current high payload; address the remaining resident
  shell as an interrupt/interface redesign after the larger system placements.

HMA and UMB are not interchangeable. DR-DOS's measured `HIDOS` data placement
uses UMBs, which remain accessible with A20 disabled. A local HMA-first policy
must prove that each exposed pointer remains safe for its consumers. Public
structures cannot simply be moved into inaccessible XMS storage. Our framed
configuration has only 1,216 spare UMB bytes above the retail floor, so a bulk
UMB migration needs compensating reclamation or a different placement design.

Budget HMA jointly for BIOS, DOS state, COMMAND, and the requested disk cache.
The normal post-COMMAND slack is 15,437 bytes; the development BIOS payload
consumes another 5,220 bytes. Those are fixed-15-buffer figures, not independent
budgets for each subsystem. `Set_HMA_Buffers` now places whole buckets high
while they fit and spills the remaining buckets low. Bucket granularity and
COMMAND competition can still displace more low memory than BIOS relocation
releases. Define and test the joint capacity policy before
promoting the high BIOS or adding high data. Preserve requested resource counts,
DOS=LOW, A20-off callers, third-party providers, and reset behavior; verify that
all released paragraphs join the largest conventional block.

Pause further isolated table/instruction compaction after the 403-byte error
table checkpoint. The next deliverable is one placement budget covering these
three owners, before selecting the next implementation tranche:

| Owner | Current conventional inventory | Required investigation |
| --- | ---: | --- |
| DOS BIOS | 8,160 bytes | Split low device headers, entry/return and DMA-facing state from high-capable service bodies; DR-DOS's 3,552-byte high BIOS body is a precedent, not a promised local gain |
| Dynamic DOS state | FILES 896; FCBS 256; LASTDRIVE 2,288 bytes | Audit SYSINIT allocations and all public/redirector pointers for authoritative high placement; separately classify the 512-byte transfer area and 1,840-byte interrupt-stack allocation as low-required until proved otherwise |
| Kernel low prefix | 4,992 bytes | Separate low stack and compatibility anchors from private data ownership; reuse the existing high copy where valid rather than allocate another duplicate |

Matching retail's allocation sizes is not a reason to exclude dynamic state:
DR-DOS's measured HIDOS gain is chiefly an allocation-placement transition.
Conversely, its 12,800-byte gain includes buffers already high locally and
cannot be counted again. The 5,344-byte retail DOS/BIOS remainder is an
accounting difference, not the full candidate inventory or a movable block.

The candidate is isolated in `src/BIOS/MSDSKHIG.INC`, included by MSDISK in its
original segment. `BIOS_SERVICE_START/END` now bound `0E8Ah..1C84h`: 3,578 bytes
of sector I/O, transfer/error handling, and IOCTL/INT 2F services. Both reports
use these symbols. Audit entry points, CS-relative operands, and request/buffer
access before activation; contiguity alone does not prove relocatability or
release the low allocation.

The initial 3,841-byte body included 263 bytes of mutable disk/IOCTL state. These
now belong to `MSIOLDAT.INC` in the retained low prefix: the 252-byte format
descriptor array, sector count, three flags, saved DPT pointer, and PS/2 saved
drive word. Shared
limits retain all 63 sector descriptors. The census rejects state inside the
high candidate and checks that the IOCTL code-dispatch tables remain inside
it. Build dependencies cover both new includes. Total conventional BIOS
allocation remains 8,160 bytes; this is ownership separation, not a saving.
The paired fixed-image capture remains 610,256 conventional bytes and 49,104
free UMB bytes, leaving the same 8,480-byte retail gap.
The fifteen data-segment materializations in this body and MSIOCTL now use
`BIOS_PUSH_DATA_SEG` from MSBSEG.INC: disk/track transfer buffers, BDS walks,
error-table scanning, and boot-record copies all name low-data ownership.
The installed form emits the original PUSH CS; the separately compiled form
pushes `CS:[BIOS_SERVICE_LOW_SEGMENT]` without changing flags or scratch
registers. Native tests verify both 8086 encodings and all fifteen consumers.
The additional MOV-based materialization uses `BIOS_LOAD_DATA_SEG DI`; its
IOCTL transfer pointer now selects low data too, not the relocated CS.
A future high module must supply and relocate
the owner word and its references. IOCTL's code jump table must remain high
while its mutable track table stays low; do not apply a global CS substitution.

The 162 binary low-state accesses now use `BIOS_LOW_READ/MEM`. Their
separate-data forms borrow an explicitly chosen DS or ES and restore it without
changing the operation's flags. LDS/LES outputs and segment-register operands
are handled by borrowing the other segment. Unsafe borrowed-result overlap,
SS/CS borrowing, and SP operands are assembly errors. A native DOS probe with
distinct code/data segments checks loads, stores, carry propagation, CMP/XCHG,
LDS/LES, segment-valued stores, preserved segments/BP, and balanced SP; six
invalid contracts are rejected. Five unary INC/DEC operations and two indexed
track-descriptor reads now have explicit low owners too, with carry, direction
flag, forward/backward SI movement, and caller DS checked. Dedicated stack
operations save the original SP and unwind the same conventional stack without
overwriting live target words; these are not arbitrary stack-switch helpers.
The complete separate-data MSDISK object also assembles, using a flag-preserving
long LOOP trampoline where its enlarged track loop requires one. Its body is currently 5,160
bytes versus the installed 3,578-byte body; the added code spends HMA capacity,
not low-memory savings, once relocation exists. The default build still emits
byte-identical IO.SYS. A source guard permits only the two IOCTL code-dispatch
operands as raw CS-relative operations; both tail chains use explicit low gates.
This is not yet a linked or activated high BIOS: control-flow gateways,
implicit pointer contracts, owner/offset fixups, and the early reclaim
transaction remain mandatory work.

Local media-ID, multitrack, LOW/HIGH read-only-media, warm-reboot, fixed-disk
format, floppy FORMAT /U, and the 286 HIMEM/386/486 memory-manager matrix
checks pass after low-state separation. The
combined `/U` then `/F:720` test rejects the latter with `Parameters not
supported`; substituting the pre-change IO.SYS reproduces the same two failed
assertions. This baseline format/profile issue remains unresolved and is not
claimed as a passing gate.

For each candidate record the exact range, readers/writers, external pointer
contract, A20/interrupt requirements, proposed destination, fallback, retained
gateway cost, and paragraph-rounded net gain. Select a coherent multi-kilobyte
tranche from that evidence. HMA is the first destination for eligible state;
15,437 bytes remain DOS-owned after COMMAND. Public pointers or DMA access may
rule out HMA even when capacity is sufficient. XMS needs an explicit access
gateway; UMB spending remains bounded by the 1,216-byte retail margin.

The DR-DOS EMS-enabled capture still leaves 627,824 conventional bytes but
only 15,568 free UMB bytes. Our target retains both retail floors, so copying
its UMB-heavy placement literally is not acceptable. COMMAND remains the next
coherent redesign candidate after this budget; manager byte harvesting and
EBDA recovery are not substitutes for the placement work.

##### Source contract audit: reuse the existing high copy

The BIOS audit selects a **low-data/high-service split** as the next design
to prototype, rather than moving the existing mixed segment unchanged:

- `MSBIO1.ASM:ENTRY1` loads the request through low `PTRSAV`, sets DS from CS,
  and dispatches through near offsets. Preserve low strategy/device entry
  points and request completion; add explicit high dispatch only for the
  selected service body.
- `MSDSKHIG.INC:READ_SECTOR` constructs `ES:BX = CS:DiskSector` for INT 13h;
  `READFAT` also promises a CS-relative result. The transfer buffer must stay
  low, and both producer and consumer must use its explicit low segment.
  Mutable `DPT`, retry state, `ORIG13`, and other CS-relative data need the
  same ownership audit. DS is already used for BDS and caller data, so a global
  DS replacement is not a valid conversion.
- Near calls/jumps cross to low helpers and error exits. Keep internal high
  relative branches together; enumerate and replace every crossing with an
  explicit gateway. Loading code at an allocated HMA offset also requires
  fixups for absolute code offsets and dispatch pointers, not just a segment
  change.
- ROM/third-party INT 13h returns must land low and restore A20 before
  resuming high code. Keep INT 2Fh/AH=13h vector exchange and INT 19h restoration
  low with their authoritative saved vectors; direct interrupt callers do not
  necessarily arrive through DOS's existing A20 gate.
- The low resident image is selected and compacted before final SYSINIT
  allocations, while HMA-tail publication occurs after buffer construction.
  Resolve this ordering before installation: either reserve the BIOS body
  early in a unified HMA layout or implement a late low-layout compaction
  transaction. Copying late while retaining the original hole is no gain.

Dynamic-state audit: `SYSINIT1.ASM:ENDFILE`, `DOFCBS`, and `BUF1` already publish
far SFT/FCB/CDS pointers; `UTIL.ASM:SFFromSFN` follows far SFT links. This removes
one internal addressing obstacle, not the external compatibility obligation.
These are exposed structures, so an HMA destination needs an A20-off
external-reader test and redirector/SHARE coverage. UMB placement avoids HMA's
A20 alias but the complete 3,440-byte inventory exceeds the current margin.
Do not silently relocate these public structures into HMA just because normal
DOS calls pass. Interrupt stacks and transfer buffers remain low in the first
BIOS-body design.

`make test-dos-bios-residency` now prints the map-derived BIOS service candidate,
kernel low inventory, and initial HMA capacity separately from achieved
residency. Next implementation gate: bind the isolated body and its incoming
entries/fixups, choose the initialization transaction, then exercise the whole body
with low-mode fallback. No positive net saving is claimed until gateways,
padding, ownership, and the released low boundary are measured together.

Reproduce the emitted-code crossing inventory with:

```sh
make test-bios-service-crossings
```

The tool assembles our MSDISK module into a temporary listing, verifies that
its object matches the built module, and applies the linked READ_SECTOR bias.
It includes MSIOCTL's emitted instructions and excludes inactive source rows.
The current body has 16 direct outward branch sites to 12 operation/target
pairs, 11 indirect call/jump sites, and 10 interrupt/IRET sites. These include
low completion/error exits, GETBP, media-ID handling, disk swap, the mutable
ORIG13 chain, and INT 2F chaining. The report deliberately does not claim
coverage of incoming pointers or data fixups. Parser tests cover address bias,
included-source markers, inactive rows, internal branches, and unresolved
targets.

Some linked outward targets lie beyond the selected BIOS boundary because
`MSINIT.ASM:PURGE_96TPI` NOPs conditional call sites and patches command-table
entries before discarding that extension. Preserve this transformation before
copying/rebasing the body, and validate both extension-present and purged
images. A linked-call census must not be mistaken for the active runtime graph.

Boot transaction decision: prototype activation at the existing
`SYSCONF.ASM:CompactFirstHimem` boundary, after a working XMS provider and before
later resident allocations. It already moves DOS high and rebases HIMEM's
boot arena. However, DOS's low prefix is above BIOS, so shrinking BIOS also
requires moving/rebasing that prefix or changing the initial loading layout;
expanding the boot MCB alone cannot reclaim an interior BIOS hole. Reserve the
high body before publishing the buffer/tail layout, with one capacity check
and a low-mode fallback. Keep this optimization conditional on a proved early
provider transaction; late/foreign providers must retain the valid low layout
until an equivalent contract is implemented. This is the next prototype's
scope, not an implemented activation path.

Executable boundary prototype: `src/BIOS/HIGHROM.INC` supplies the low far-call
INT 13h return gate for the planned split. It saves ROM result registers and
flags, invokes the repository HIMEM E705h physical-A20 restoration contract,
and returns to its caller. It is deliberately **not installed in IO.SYS yet**;
provider validation, BIOS dispatch/data fixups, early allocation, and low-prefix
reclamation must land together before activation.

```sh
make test-bios-high-rom-qemu
```

The local QEMU 486 probe compiles the shared gate with both JWasm and NASM.
DOS=HIGH reserves real DOS-owned HMA storage, copies a caller there, and patches
its far gate segment. A real boot-sector read runs through a low INT 13h hook
that disables A20 before returning. A read-only high/low alias comparison
confirms the physical disable; the continuation must execute high afterward.
Two synthetic ROM results then check AX/BX/CX/DX/SI/DI/BP/DS/ES, balanced SP,
both carry outcomes, and OF/IF/SF/ZF/AF/PF preservation. DOS=LOW proves allocator
rejection and exercises the same call contract conventionally. Both pass.
An otherwise identical high probe with restoration omitted reaches its startup
marker but cannot pass, confirming sensitivity to the missing gate operation.
This validates one executable boundary, not the complete BIOS relocation,
foreign-provider behavior, a real 286, or any additional conventional saving.

`BIOS_HMA_VECTOR` accepts a target segment/offset and constructs an interrupt
frame from live FLAGS. The production saved-ORIG13 call sites instead use
`BIOS_HMA_SAVED_VECTOR`: callers retain their previously pushed frame FLAGS,
push the segment/offset of the authoritative low vector slot, and far-call
the gate. It fetches the current target on every call while preserving live
input FLAGS separately from the supplied frame word, including DOINT's saved
`[BP.OLDF]`. Both gateways accept IRET or RETF 2, restore physical A20 before
returning high, and keep temporary state on the conventional stack. Neither
is a generic RETF-only device gateway or an interrupt-chain tail-jump adapter.

All eight direct INT 13h sites and the single INT 1Ah site now use ROM-call
operations. The normal build emits the original interrupts; the separate-data
object calls imported far gate pointers. HIGHROM includes the matching low
timer gate. All eight saved ORIG13 calls also use the explicit low-vector
operation. Eighteen LOW/HIGH disk, vector, timer, supplied-frame, tail-chain,
and ordinary-near-helper cases pass
with physical A20 disruption and result preservation; supplied-frame cases
check differing live/frame flags and a changed vector target between calls.
The missing-A20-restore negative control remains sensitive. A source guard
rejects raw direct ROM interrupts and CALL ORIG13 in the candidate. The complete
separate-data object assembles; default IO.SYS remains byte-identical.

`BIOS_HMA_CHAIN_VECTOR` handles the ORIG13 and NEXT2F_13 tail exits. It resolves
the low slot, discards its own far-call return and slot arguments, preserves
registers/live FLAGS, and transfers with the original caller frame untouched.
The target never returns to the high tail site. Four tail cases check both
return forms, a changed target, differing frame/live FLAGS, balanced SP, and
A20-off target returns into the original low caller; that caller restores A20
before its next high entry. An original caller in HMA still needs its own low
return gateway: this adapter does not make arbitrary high interrupt frames safe.
Normal builds preserve the old operand widths, including NEXT2F_13's near
same-segment jump. The relocated path consumes its stored far pointer instead.

Six ordinary helper calls (GETBP, Mov_Media_IDs, HasChange, two SET_CHANGED_DL
sites, and SWPDSK) now use `BIOS_HMA_NEAR_CALL`. It invokes a near helper in
the retained-low segment, preserves its results, and restores A20 before
returning high. The LOW/HIGH probes check real disk reads, both synthetic carry
outcomes, all result registers, changed targets, and balanced stacks. These
tests validate the gateway, not the six production helper bodies executing in
a relocated system; recursive low-to-high calls still need entry bindings.

Two legacy entries are deliberately excluded from that contract:

- `CHECKLATCHIO` reaches `RET_NO_ERROR_MAP`, which pops its caller's return
  address into SI and returns to the next frame. A generic gateway's saved
  registers would be mistaken for that frame.
- `CHECKIO` can jump to `HARDERR`/`HARDERR2` in the service body, which restores
  the saved `SPSAV` stack and exits non-locally. It cannot return through an
  ordinary wrapper on those paths.

The assembler rejects both legacy targets in `BIOS_CALL_LOW`. The separate
high body now calls `BIOS_CHECKLATCH_RESULT` and `BIOS_CHECKIO_RESULT` instead:
CF=0 continues, CF=1 returns an already mapped DOS error in AL. The caller
returns from DISKIO or enters HARDERR2 to restore SPSAV; neither low helper
discards frames. `MSCHKRSL.INC` supplies these result entries in MSBIO2 when
`BIOS_SERVICE_RESULT_HELPERS` is enabled. Normal builds retain the existing
entries and byte-identical IO.SYS; the result helpers are not installed yet.

Twelve native branch scenarios execute the shared result-helper instructions
with controlled subordinate-service outcomes, checking CF/AL, mapping counts,
media-ID reporting, retry BP, and balanced SP. Both high MSDISK and optional
result-helper MSBIO2 objects assemble, and the high listing rejects remaining
calls to the legacy non-local entries. This does not prove a linked high BIOS
or recursive calls through GETBP/MAPERROR and their future entry gates.
The payload preparation contract below translates the existing DISKIO_PATCH
and DSKERR purge decisions; the installer still needs to apply it. Do not infer
floppy compatibility from the fixed image's removed 96-TPI calls.

##### Isolated service object and completion exits

`BIOS_SERVICE_ISOLATED=1` assembles MSDISK's service body alone in a separate
`BIOSHIGH` segment, `0000h..1428h` (5,160 bytes), with explicit imports for the
low disk prefix. The source/operand suite builds both this and the earlier
same-segment separate-data form. Its emitted-branch check rejects direct
external targets; indirect gates and dispatch tables still require binding.
Isolation exposed and corrected the remaining MOV-CS transfer pointer, two
implicit low-data accesses, and two retry-counter decrements. Default IO.SYS
remains byte-identical to the validated low-drive-state image.

Eight request-completion exits use imported low far-entry pointers without a
CALL. Their targets must consume the original MSBIO1 device-entry frame, not
a gateway frame. A native cross-segment probe executes the macro with all nine
saved register words and checks SP, registers, and flags on return. Together
with the low-segment operand probe and twelve result-helper scenarios, the
thirteen source/operand tests pass. This does not validate real device status
completion under high relocation.

The isolated body now links against low-map absolute symbols and a 60-byte
runtime import table. Reproduce with:

```sh
make test-bios-high-payload
```

`out/bios-high-payload/bios-high.bin` contains 5,220 bytes; its JSON manifest
pins IO.SYS and low-map hashes, records exported entry offsets, and names all
twenty runtime slots with their widths and intended low targets. All runtime
slots are zero: this is an uninstalled development payload, not callable code.
The builder infers 270 internal offset16 fixups from links at origins zero
and one, then verifies exact rebased bytes against independent links at 16,
`0123h`, and `4000h`. This checks the current payload's relocation model, not
a general OMF format implementation. Low absolute offsets remain fixed; code
and import-slot references move together. Four tests cover the real build,
word carries, malformed differences, overlap, and segment/offset overflow.

The manifest also records original low bytes and labeled high spans for the
four boot patches inside the payload. DISKIO_PATCH, DSKERR, and CHANGED_PATCH
expand from 3/3/10 low bytes to 13/15/24 high bytes; the pre-386 copy patch
remains three bytes. `boot_policy` accepts only complete original or NOP
patterns from a low BIOS snapshot and rejects partial or inconsistent 96-TPI
patching. `prepare` verifies payload identity, rebases internal offsets first,
then NOPs the selected full spans. Runtime bindings must be filled afterward.
Tests cover all four 96-TPI/CPU policy combinations, malformed snapshots,
identity mismatch, and an intentionally reversed patch/fixup order. This is
host-side preparation, not yet a boot-loader implementation or runtime proof
of the optional high paths. Other low BIOS patches remain the low loader's
responsibility; these four are only the patches inside the selected body.

The first real payload execution gate is:

```sh
make test-bios-payload-qemu
```

The QEMU 486 probe obtains DOS-owned HMA storage, verifies segment FFFFh,
copies and rebases the linked payload, and calls its actual READ_SECTOR entry
through the shared high-side near-entry adapter and a test driver. It binds the data owner and
INT 13h/1Ah gateways; unused far imports trap. Private low data and a probe-owned
BDS avoid using live BIOS data as experimental workspace. BDS offsets come from the assembler's
MSBDS.INC definitions, not duplicated numeric layout assumptions. A fixed-media
flag bounds retry behavior without modifying the ROM disk-parameter table.

Three runs pass: a real floppy boot-sector read with signature verification,
success after two injected read failures, and three failed attempts returning
BIOS error 20h. They check read/reset counts, returned CF, SP/BP/ES, and low
last-drive state. The disk hook physically disables A20 before every return;
a read-only alias check confirms the disable, and the shared low gate restores
A20 before high execution resumes. Omitting all payload offset fixups reaches
the allocated/bound READY marker but cannot pass. This validates actual payload
execution and retry paths, not installation or conventional-memory reclamation.

The same runtime gate now calls the payload's real MOVE routine after the
read. Normal dword copy and the fully patched pre-386 word-copy path each move
exactly 512 bytes, preserve CX, advance SI/DI by 512, and preserve destination
guard words. Entry DF is deliberately set; MOVE must clear it. Removing only
the operand-size prefix leaves the count-halving instruction active and copies
too little; that negative control must reach an explicit FAIL result. Both
copy paths execute on QEMU 486 here: this is not real-286 acceptance. The fourteen
runtime cases include the three read outcomes, word copy, partial-copy-patch
rejection, missing-fixup rejection, missing-entry-A20 rejection, non-local
error unwind, the four device-entry cases, and the two interrupt cases below. The normal
IO.SYS remains byte-identical.

`HIGHNEAR.INC` supplies the 40-byte high-side ordinary-near-call adapter. A low
caller restores A20, pushes a relocated target offset, and far-calls the
adapter; the service returns with near RET, and the adapter preserves results
while returning low and consuming the target word. The runtime probe confirms
physical A20-off entry and restores it before calling; omitting restoration
reaches READY but cannot pass. This contract excludes interrupt and device
entry frames, which need separate entry paths.

The six SETDRIVE/MAPERROR/READ_SECTOR calls in MSDISK's retained prefix now use
`BIOS_CALL_HIGH` when `BIOS_SERVICE_LOW_CALLS` is enabled. That object assembles
and its call inventory is checked; default expansions remain the original
near calls. Runtime import storage and publication are not installed yet,
and the MSBIO2/96-TPI ordinary calls now use the same operation: two SETDRIVE,
one CHECKSINGLE, and two MAPERROR sites, plus the result helpers' mapping
adapter. The combined low-call/result-helper object assembles. Legacy CHECKIO
error exits use `BIOS_JUMP_HIGH`, which restores A20 and tail-transfers without
adding a frame; HARDERR/HARDERR2 must own the saved high disk stack. This must
not be enabled while mixing an old low DISKIO frame with a high error target.

With `BIOS_SERVICE_LOW_CALLS`, these call/continuation sites now select their
original low targets until the retained-low `BIOS_SERVICE_ACTIVE` byte is set.
The guard preserves input flags and adds no surviving stack word. Inactive
calls do not invoke the A20 restorer or read unbound high targets, so preparing
bindings cannot prematurely redirect startup. Activation must join device/IVT
publication in one validated, interrupt-disabled commit with no live low disk
frame. It is one-way after reclamation; clearing the flag alone is not rollback.
Native macro execution checks zero, partial, and fully prepared inactive
bindings, then active near calls and non-local jumps, including carry, result,
stack balance, and restoration counts. This is a call-selection test with a
mock restorer, not a booted installer. The guards add low code and one state
byte that the eventual linked reclaim budget must include; default IO.SYS is
unchanged. The combined development image below supplies import storage; filling
it and committing the boot transaction remain open.

The HMA probe also exercises actual HARDERR2: it saves the original high
service return SP in private low SPSAV, adds temporary frames, calls a low
helper that disables A20, then restores A20 and jumps high. HARDERR2 restores
SPSAV, returns the saved sector count and mapped error through the high near
adapter, and reaches the original low caller with balanced SP/BP/ES. Private
format state suppresses ROM DPT edits in this focused test. This validates the
non-local boundary, not production DISKIO/media-change integration.

`HIGHDEV.INC` declares the seven device-command tail entries (4, 8, 9, 15, 19,
23, 24). With `BIOS_SERVICE_DEVICE_ENTRIES`, MSBIO1 emits 56 bytes of low stubs
and 28 bytes of far target slots. Each restores A20 and far-jumps high without
adding a surviving return frame. Compilation leaves DSKTBL unchanged: a future
installer must bind the selected high targets and completions before publishing
the low stub offsets, preserving the 96-TPI purge policy. Failed preparation
keeps the original table; reverting pointers after low-body reclamation is not
a valid rollback. The 84-byte entry cost excludes shared A20/ROM gates and
other imports, so the 3,578-byte low body is only a gross reclaim budget.

Native execution checks all seven production stubs with distinct code segments,
original incoming registers/flags, and the exact nine-word saved device frame.
The HMA payload gate checks real DSK$REM for removable/fixed media and real
GENERIC$IOCTL for an invalid category. Each tests low fallback before private
table publication, physically disables A20 before high entry, and validates
request status plus restored registers and SP. The error case also checks the
remaining sector count. Omitting entry A20 restoration cannot pass. These use
private BDS/request storage and a matching low completion fixture, not the
installed DSK$IN dispatcher or all seven service implementations. Production
device/interrupt publication and the complete installed low/high cycle remain.

`LOWINT.INC` supplies the retained-low interrupt entries under
`BIOS_SERVICE_INTERRUPT_ENTRIES`: 41 bytes for the INT 2Fh/AH=13h vector exchange
and low successor chain, plus 12 bytes for the INT 13h tail stub and high target
slot. The multiplex filter must never call the A20 restorer: E705h itself must
chain through it to HIMEM without recursive high entry. Both exchanged vectors
remain authoritative low state; the disk stub preserves the original interrupt
frame while restoring A20 and tail-jumping to high BLOCK13. The default build
keeps its original vectors. With interrupt entries enabled, RE_INIT installs
the permanently low multiplex filter before HIMEM hooks the chain, avoiding
later edits to memory managers' saved successors. Device and interrupt entries together cost 137
low bytes before shared return/restoration gates and other binding storage.

The runtime probe temporarily publishes these low entries in its own segment.
With A20 physically off, INT 2Fh/AH=13h exchanges distinct runtime/warm-boot
pointers, preserves other registers and the original carry/direction flags,
then permits E705h restoration through its low successor. Actual INT 13h calls
reach the linked high BLOCK13 for a successful boot-sector read and an injected
AH=20h error. The saved-vector target disables A20 again; the low return gate
restores it before high execution resumes. Results, guard words, SP/BP/ES,
physical A20-off counts, and restoration-chain traversal are checked. Private
BIOS state is used and the original IVT vectors are restored on normal exit;
this does not install the boot-time BIOS relocation or cover all BLOCK13 paths.
Repeat just these runtime cases with `python3 tests/test_bios_payload_qemu.py
--mode interrupt-read --mode interrupt-error`; the default still runs every case.

Next, reclaim/coalesce the old low range after early activation, including
relocation of the DOS low prefix above BIOS. Preserve code-table offsets,
selected/purged code policy, and ROM-return contracts through that transaction.

The combined low-side development image now links MSBIO1, MSDISK, and MSBIO2
with bindings, guarded calls, device/interrupt entries, and result helpers all
enabled. `LOWBIND.INC` provides the actual low ROM/A20 gates and zeroed high
import storage. `tests/build_bios_low_image.py` links against the remaining
normal BIOS objects into a separate output directory; it does not replace the
normal IO.SYS. All twenty high-payload import contracts are accounted for:
nineteen named low symbols and the resident owner segment supplied by the loader.
The high builder's `--low-directory` binds offsets and boot-patch bytes against
this matching map/binary/image set and records that image's hash.

`make test-bios-low-boot-qemu` boots the combined inactive BIOS on QEMU 486 in
four configurations: bare DOS=LOW, HIMEM with DOS=LOW, HIMEM with DOS=HIGH, and
EMM386 RAM with DOS=HIGH,UMB. The probe verifies ACTIVE and all high target words
remain zero, checks high-tail allocation succeeds only in high mode, and
creates, writes, seeks, reads, closes, and deletes a file. All four pass. This
proves inactive startup integration, not active high execution or reclamation.
The fixed one-hard-disk linker census budgets 8,720 selected BIOS bytes for this
prototype versus 8,160 normally: 560 bytes of current support overhead before
releasing the 3,578-byte service body. That is a gross/net design constraint,
not a VC saving. The normal image remains byte-identical and all generated
development images/maps stay under ignored `out/`.

The same gate now adds live activation under HIMEM alone and EMM386. A generated
COM fixture validates the provider, current INT 13h owner, command-table
targets, and original-or-purged boot patches before reserving HMA. It copies and
rebases the matched payload, applies the observed patch policy, binds every high
import and low target, then publishes DSKTBL, INT 13h, and ACTIVE with interrupts
disabled. INT 2Fh already uses the permanently low filter installed at boot.
This exercises the actual resident dispatcher and low/high cycle, not private
BDS or completion fixtures.

After publication the fixture overwrites the old 3,578-byte service body with
CLI/HLT pairs. File create/write/seek/read/close/delete, a forced disk flush, and
a raw INT 13h boot-sector read still pass with both managers; the sector
signature and buffer guards are checked. A stale-entry control reserves/copies
the payload but omits publication before poisoning the old body: it reaches the
pre-I/O marker but cannot pass. These are seven QEMU 486 cases in total (four
inactive, two live, one negative), not complete media, EXEC, reboot, or hardware
acceptance. The probe is development-only, uses late HMA allocation, and leaves
the old allocation in place. It must not be used as a production loader.

The early development installer is now in `BOOTBIOS.INC`, called at the end of
`CompactFirstHimem` after DOS relocation and HIMEM entry refresh. It performs
preflight before writing high memory, copies/rebases the embedded 5,220-byte
payload immediately after DOS's HMA image, binds the call cycle, and publishes
the entries and ACTIVE with interrupts disabled. `HmaBiosEnd` records the
SYSINIT-owned reservation; subsequent cache construction starts there instead
of SYSBUF, so the published tail cannot overlap the BIOS. DOS=LOW, an unavailable
early-provider contract, or failed capacity/preflight checks retain low entries.
This remains a development flag, not normal-build activation.

`make test-bios-early-boot-qemu` checks four configurations with normal capacity
and repeats them with a deliberately failing reservation ceiling. Normal high
boots activate before further CONFIG processing, buffer construction, and
COMMAND startup; low boots and forced-rejection high boots retain zero high
targets and a clear ACTIVE byte. The successful high probe verifies the entire
old service body still contains CLI/HLT pairs, then tests HMA tail allocation,
file I/O, forced flush, and raw disk reads. All eight QEMU 486 cases pass. The
builder links a seed low/high pair, embeds generated operands in the discardable
init segment, relinks, and rejects any changed low binding or high payload.

Embedding exposed a loader limit: MSINIT staged MSDOS.SYS after a fixed 20 KiB
SYSINIT allowance, overwriting the larger init tail even in DOS=LOW. The early
build now derives both DOS staging calculations from the linked SYSINIT segment
and rounded SYSSIZE. The normal build retains its existing bytes. Tests must
continue covering inactive boot when changing embedded payload size.

The old body must actually be released and its low hole coalesced before
counting gain. Early high execution and capacity-rejection fallback are now
established for these paths; low-prefix rebasing, other transactional failure
cases, and the complete memory/filesystem/device/hardware regression gates
remain. Large-buffer pressure and foreign/late-provider policies still need
acceptance before this development installer can become the normal path.

The optional `--tail-body` development layout makes that compaction boundary
explicit. MSDISK builds as a retained prefix plus a same-segment fallback body
linked after all other BIOS CODE contributions. Selected permanent BIOS state
and services consequently precede the fallback; reclaiming it need not rebase
those BIOS addresses. MSINIT records the paragraph-relative selected boundary
in `BIOS_PERMANENT_END`, but still reserves through `BIOS_SERVICE_END` before
placing DOS. Both inactive and early builds stage DOS beyond the actual linked
SYSINIT segment, since the old `END$ + SYSIZE` estimate excludes this body.

`make test-bios-tail-boot-qemu` covers inactive and late activation, early
activation, forced reservation rejection, and a stale-entry negative control.
The boot probe checks the selected permanent boundary is below the fallback;
active paths also poison the old body and exercise file and raw disk I/O.
Seed/final linking must preserve the embedded bindings and high payload.
This remains a layout prerequisite: it temporarily retains intervening init
space as well as the fallback, so development low-memory usage grows. The
normal IO.SYS and its 610,256-byte VC result are unchanged. Next, rebase the DOS
low prefix and affected boot allocations into the released interval, updating
every public/private low pointer before coalescing the arena. Count only the
net application-block gain after retained gateway and alignment costs.

Use `make test-bios-rebase-scan-qemu` to
capture the actual activation boundary without invoking DOS during collection.
The development-only `BOOTSCAN.INC` writes raw HMA/low DOS, permanent BIOS,
occupied boot allocation, SYSINIT, and initial CDS regions to QEMU's debug
port. The host report checks the DOS owner and linker extents and attributes
every aligned or unaligned word equal to the old DOS segment. Reports and raw
snapshots stay in ignored `out/`; low and rejected boots must emit nothing.
These are candidate references, not an automatic fixup list: instruction
operands and dead stack words also match, and normalized aliases are not found.

The first floppy-profile captures establish these additional rebase contracts:

| Owner | Required treatment |
| --- | --- |
| `DPBHEAD`, the first two `hma_low_dpbs` records, initial CDS `curdir_devptr` fields | Rebase links to moved DOS records; retain BIOS overflow targets and terminal sentinels |
| `DSKCHRET+3` | Rebase the request-buffer segment initialized by DOSINIT and consumed by the Ctrl-C device-read path; this is absent from the existing HMA code-relocation fixup list |
| `SysInitTable.SYSI_InitVars`, `hma_low_segment`, `hma_driver_trampoline_entry` | Publish the new low owner in the authoritative high image and relevant low fields; subsequent SYSINIT synchronization must target the moved prefix |
| `CurHashEntry`, `THISSFT`, `THISDPB`, SFT device pointers and request workspaces | Classify live versus completed-operation state and low-prefix versus discarded-tail targets; do not rebase every old-segment value indiscriminately |
| BIOS `PTRSAV` and SYSINIT saved state | Prove no old request or stack frame remains live across publication; refresh legitimate retained pointers before allowing another callback |

Both high configurations reach this point before EMM386 loads: their identical
early ownership does not prove post-EMM relocation. The captured initial CDS
table is outside all three resident DOS/BIOS regions, confirming that a kernel
image-only fixup cannot cover external references. The existing 19-entry HMA
fixup table moves code/high-data targets, not this complete low-owner graph.
Rebasing must use declared fields and chain walkers, then move
the occupied HIMEM boot prefix, refresh its IVT/XMS references, and coalesce the
arena. A poisoned/reused old prefix, Ctrl-C, public DPB/CDS/device traversal,
file I/O, and warm reset are required acceptance gates. No saving is credited
by the recorder itself.

##### Development low-prefix rebase and arena compaction

`BOOTREBASE.INC` now moves the paragraph-rounded DOS prefix immediately after
the selected permanent BIOS. It requires disjoint ranges, SYSINIT's stack, no
active DOS call, and one-time publication. Generated operands identify 35
declared far-pointer fields; only fields naming the old segment with a target
inside the retained prefix change. The high owner/trampoline, two low DPB
records, external CDS links, and BIOS request pointer receive explicit updates.
The old prefix is poisoned. `--rebase` alone keeps the old arena reserved;
`--compact` additionally moves the first HIMEM boot allocation down, adjusts
its device mark and SYSINIT bookkeeping, publishes the enlarged arena in both
DOS owners, and refreshes HIMEM's INT 15h/2Fh and cached XMS entry segments.

The CONFIG parser must invalidate its cached DBCS/case-table addresses after
the move. Leaving the old DBCS pointer produced CONFIG errors and silently
retained five CDS entries instead of `LASTDRIVE=Z`. The apparent 615,104-byte
VC result was invalid. The corrected development image leaves **613,264 bytes**
versus retail's 618,736: **3,008 bytes gained**, **5,472 bytes remaining**, with
free UMB unchanged at **49,104 bytes**. The fixed BIOS boundary falls from
8,160 to 5,152 bytes; the DOS prefix remains 4,992 bytes. HIMEM, EMM386, COMMAND,
configured DOS state, and the conventional ceiling retain their prior budgets.
The normal image remains at 610,256 until the acceptance work below is complete.

Reproduce the development build and local proof:

```sh
make test-bios-rebase-qemu
python3 tests/build_bios_low_image.py out/bios-compacted --early --tail-body --rebase --compact
```

The gate checks low/rejected boots, poisoned-prefix rebasing without reclaim,
compacted low-owner/arena boundaries, 26 CDS entries after CONFIG, file I/O,
and raw disk I/O. Compacted boots cannot require poison to remain after COMMAND
starts: those ranges are now legitimately reused. The comparison parser also
rejects visible CONFIG failures before awarding memory credit. The corrected
paired evidence is `out/bios-compacted-final-vc.md`; generated images remain
untracked and CI remains disabled.

This is not normal-build or complete compatibility acceptance. Still required:
Real-console/third-party callbacks, software reboot paths, larger sector/buffer settings
and optional media paths, 286 execution, redirector/SHARE consumers, and
foreign/late-provider fallback. The current rebase explicitly excludes
overlapping low-prefix moves and later resident allocations. Complete those
contracts before promotion; do not extrapolate the first-HIMEM proof to a
general runtime compactor. Then recalculate the residual and return to packed
DOS-state placement, not isolated HIMEM/EMM386 instruction savings.

The rebase gate now walks the public INT 21h/52h graph while the temporary
disk file is open. It checks the new low list owner, bounded DPB and device
chains, 26 CDS entries with matching drive-to-DPB links, and the live file's
SFT-to-DPB link. Structure offsets are assembled from the repository headers,
not duplicated in the NASM probe. Rebasing without coalescing still verifies
the poisoned old prefix; compacted tests permit legitimate reuse. A negative
control restores one external CDS segment to the retired owner and must reach
an explicit failure after its mutation marker. This detects exact stale-owner
references, not every normalized segment alias or third-party cached pointer.

HIMEM-only and EMM386 configurations also repeat the complete public-graph,
CONFIG, file, and raw-disk checks across one QMP hardware reset in the same
guest. The first pass flushes a marker file and waits at a reported boundary;
the host verifies a live guest before resetting it, and the second pass removes
the marker before success. This is controlled reset coverage, not INT 19h,
Ctrl-Alt-Del, real-286, or arbitrary driver reset acceptance. These checks add
no resident code and leave the development 613,264-byte VC result unchanged.

The Ctrl-C gate supplies one character through a temporary console device and
executes the real `DSKSTATCHK` request, not a direct INT 23h invocation. It checks
the one-byte transfer's low owner, exactly one consume and callback, balanced
user SP, and continuation of the original DOS call. In high mode the device
physically disables A20, verifies the alias, and returns through the relocated
low trampoline; DOS must restore A20 before continuing. The console pointer,
BREAK setting, and INT 23h vector are restored before subsequent graph/file
checks. This runs in the low, high, fallback, compacted, and reset cases.

That test exposed an existing fast-call ownership error: AH=33h accessed its
high copy of `CNTCFLAG` while the ordinary dispatcher read the low copy, so
BREAK=ON did not enable disk-call checks in DOS=HIGH. The fast path now selects
the authoritative low owner without changing caller DS/ES/BX (except the
documented version result). Tests cover read/set/exchange and input masking,
the retained 3/4 no-ops, boot/true-version queries, invalid subfunctions, and
register, CF, and SP preservation. The returning INT 23h handler uses IRET;
A20-off user INT 23h returns and terminating handlers remain separate gates.
Continue auditing other fast state calls when changing low ownership.

The dispatcher grows from 783 to 808 bytes; alignment limits the HMA-image
growth to 16 bytes (39,472 at that checkpoint). The conventional prefix remains 4,992 bytes.
At that checkpoint normal HMA tail capacity was 18,044 before COMMAND and 15,453 afterward,
before any development BIOS reservation. Fresh paired captures in
`out/break-owner-normal-vc.md` and `out/break-owner-development-vc.md` retain
610,256 and 613,264 conventional bytes respectively, both with 49,104 free UMB
bytes. This is a correctness fix, not an additional memory saving.

##### HMA capacity and low-cache fallback

The development high BIOS retains all 39 requested buffers in HMA. Previously,
40 buffers exceeded its remaining capacity and took the whole-cache low
fallback. Before correction, that image failed to reach the probe: SYSINIT had
not published an HMA tail on that path, and the allocator accepted requests
with both floor and next equal to zero. COMMAND could consequently write its
payload over live DOS HMA contents.

The allocator now rejects an unpublished floor. After successful low-cache
construction, SYSINIT publishes the unused tail starting at `HmaBufferBase`,
which already excludes any live BIOS reservation. The existing high-cache
path still publishes only after its final buffer; DOS=LOW publishes nothing.
The guard increases the aligned high image to 39,488 bytes, leaving 18,028
bytes before COMMAND and 15,437 afterward with the normal 15-buffer layout.

`make test-bios-buffer-capacity-qemu` counts actual buffers through the public
hash/bucket rings at 1, 39, 40, and 99 buffers, exercises low/high providers,
and checks file/device/returned-Ctrl-C paths. The HMA suite separately injects
an unpublished allocator state, requires rejection, restores it, and verifies
normal allocation and bounds.

The cache now uses its existing far bucket heads to support mixed placement;
the near next/previous links never cross segments. SYSINIT preflights the hash
plus the largest bucket, retains the hash high, places each whole bucket high
when it fits, and allocates only the rest low. The single low transfer area
remains available for high buffers. Low arena markers include the spill buckets;
the high allocator starts after the final high bucket, not the last low one.
If even the initial bucket cannot fit, the original all-low path remains.
EMS-buffer placement and DOS=LOW are unchanged.

The capacity gate requires mixed placement at 40 and 99 buffers, not merely a
successful boot or the configured count. Each case also writes 64 distinct
511-byte records, flushes, seeks, and verifies all 32,704 bytes, exercising
unaligned cached edges across sectors. The 40-buffer fixed VC image grows from
592,480 to 602,624 conventional bytes: **10,144 bytes reclaimed**, with all 40
buffers retained and 49,104 UMB bytes still free. The before/after captures are
`out/split40-before-vc.md` and `out/split40-after-vc.md`; both compare against
retail with the same 40-buffer CONFIG.SYS. Retail remains at 618,736 bytes.

Mixed placement removes the all-or-nothing cliff but not the full capacity
tradeoff: before BIOS promotion, budget BIOS, buffers, and COMMAND together so
relocation cannot displace more conventional memory than it releases. Preserve
the requested count and assess whole-bucket granularity; do not claim the
40-buffer result meets the retail floor.

The 14-case capacity matrix, 16-case rebase/reset/negative-control matrix,
residency census, and HMA suite pass locally. Fresh fixed-15-buffer captures
`out/split15-normal-vc.md` and `out/split15-development-vc.md` retain 610,256 and
613,264 conventional bytes, respectively, with 49,104 free UMB bytes in both.

The normal boot loader has not bound or activated these pointers. The ownership
audit moved `Prev_DX` into the authoritative low owner; the map checks its
range and a source guard rejects additional named storage in the service body
apart from the two code-dispatch tables (stack-frame structure fields allocate
no storage). Gateway tests prove these boundaries, not an installed
high BIOS or any new conventional-memory gain.
The low-drive ownership change passes the seven source/operand tests, linked
census, media-ID, DOS-low/high write-protection, multitrack, and HIMEM/EMM386
rollback/warm-reboot suite. `out/bios-low-drive-state-vc.md` records the unchanged
610,256-byte conventional block and 49,104 free UMB bytes; its image contains
the rebuilt IO.SYS, verified byte-for-byte.

`DOS_HMA_RELOCATE` in `src/DOS/MS_CODE.ASM` already copies the entire DOS image
from offset `0010h` through `SYSBUF` to the same offsets in segment `FFFFh`.
The 39,488-byte HMA image therefore includes the tables and data below
`DOS_LOW_GATE_END`. A new copy in the HMA tail is not automatically necessary.
The retained low duplicate is still used deliberately:

| Owner or path | Current contract | Required design decision |
| --- | --- | --- |
| Main dispatcher (`DISP.ASM`) | Selects `hma_low_segment` for DS and SS; reentry restores DS from SS | Separate the data base from the low interrupt-stack base before migrating mutable workspaces |
| Process state (`DISP.ASM`, `UTIL.ASM`) | Current PSP is read from the low copy; setters synchronize both copies | Choose one authoritative owner and update every reader, including fast calls and initialization |
| SYSINIT exchange (`HMA_SYNC_SYSINIT`) | Copies the final exchange block from high DOS back into the low image | Preserve device-chain, SFT/CDS, and initialization pointers through the new boundary |
| `CONSTANTS` | Contains fixed DataVersion fields, SYSINIT layout, NUL header, device request packets, and compatibility dispatch | Keep externally addressed fields low or prove each external pointer can be rebased; the segment name does not imply immutability |
| `TABLE` | Contains error/dispatch tables alongside the A20-restoring driver-return trampoline and other mutable state | Separate private high-safe tables from the low trampoline and exposed tables before releasing a contiguous range |

The first implementation gives the 403-byte private error tables an explicit
high owner and routes their readers through CS, while `ETAB_LK` and `CAL_LK`
retain DS for mutable error state. Dispatch tables remain a later candidate.
The initial audit found that changing only a pointer would still read the
wrong segment. Preserve
the existing symbol offsets where possible so the already copied high image
can be reused. Reclaim the low range only after moving mandatory low stubs out
of its way and updating `DOS_LOW_GATE_END`, BIOS loading, and initialization
contracts together. A duplicate high copy with the old low allocation intact
earns no memory credit.

Treat BIOS as a separate bulk-placement candidate: its selected 8,160-byte
resident image includes disk transfer and IOCTL bodies as well as device
headers and BIOS-facing state. The DR-DOS capture places 3,552 BIOS-code bytes
in HMA and retains 2,768 bytes of conventional device drivers. This establishes
a placement precedent, not a local savings forecast. A local BIOS split must
leave a low entry/return path that restores A20 and preserves request pointers,
DMA access, interrupts, and warm reset.

##### First high-state tranche: private error tables

`HIGH_TABLE` follows CODE and precedes LAST in DOSGROUP. It owns the complete
403-byte group: the allowed INT 21 error map, INT 21/24 class/action/locus
tables, and device-error translation map. Their readers use CS for immutable
metadata and keep DS/SS on low mutable state. DOS=HIGH reclaims the old low
storage; DOS=LOW uses the same tables in the conventional image. The driver
trampoline, public data fields, and interrupt stacks remain low.

At that checkpoint the low prefix fell from 5,392 to 4,992 paragraph-rounded bytes. Added segment
overrides and alignment grow the HMA image by 16 bytes to 39,456; the initially
free tail is 18,060 bytes, or 15,469 after the existing COMMAND allocation.
Paired VC grows from 609,856 to 610,256 bytes, with 49,104 free UMB bytes and
unchanged HIMEM/EMM386 owners. The remaining retail gap is 8,480 bytes, including
5,344 bytes of DOS/BIOS payload and layout.

The build now rebuilds every kernel contribution when DOSSEG changes: a stale
first object can otherwise place HIGH_TABLE after LAST, outside the HMA copy.
The layout and residency checks reject this order. A forced full build passed.
Error/path and write-protected-media probes now run in both DOS=LOW and HIGH;
HMA ownership/fallback/A20/EXEC, internal structures, asynchronous callbacks,
FILESYS/IFSFUNC, system/process APIs, memory-manager address phases, warm reboot,
and the 286/386/486 hardware matrix pass locally.

The combined SHARE/NLSFUNC/EXE2BIN test passes its SHARE/NLSFUNC checks but has
seven EXE2BIN failures after the forced rebuild (`Incorrect DOS version`).
The same rebuilt utilities fail identically with the pre-change kernel copied
from `out/emm-control-dispatch.img`; this is a separate unresolved utility/build
issue, not a claimed passing gate for this milestone.

### DR-DOS clean-room adoption register

Published DR-DOS manuals define the externally promised placement policies;
the controlled measurements below quantify their effects. No DR-DOS source
code is permitted. Runtime inspection is limited to public interfaces,
allocation maps, addresses, and lifetimes and must not be used to reconstruct
proprietary instruction sequences.

**Status:** the focused follow-up is complete. A fresh nine-variant run with
the pinned archival DR-DOS 6 startup disk and VC 4.05 image reproduced every
recorded aggregate exactly under QEMU 11.1.1. The capture tool now treats those
figures as executable expectations whenever all artifact identities match, so
a later revalidation fails instead of silently publishing a changed baseline.
Move eligible DOS state through the measured placement ladder as the next
architectural tranche; EMM386 is paused below retail size. Reopen DR-DOS
investigation only for a named
unresolved owner, lifetime, placement policy, or public API question.

Do not repeat the broad survey. If implementation work exposes a named
unresolved owner, lifetime, placement-policy, or public-API question, reopen
the clean-room investigation in this order:

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

A targeted reopening must answer these questions in order:

1. which documented DR-DOS configuration produces the best ordinary,
   compatibility-safe largest block on the fixed comparison machine;
2. how much of its advantage belongs to COMMAND/kernel HMA placement, resident
   memory-manager gateways, buffers, UMB policy, allocation order, and the
   conventional-memory ceiling;
3. which gains remain when low-memory, text-video, relocated-EBDA, and other
   optional compatibility tradeoffs are excluded; and
4. which remaining techniques map to a named local owner and a public contract
   that can be tested without knowledge of proprietary implementation details.

Start with the checked-in measurements, vendor manuals, existing capture
tooling, and pinned media. Run the smallest configuration delta that can answer
the named question. Add a probe only when the existing public-interface record
cannot resolve it; record commands, hashes, deltas, and conclusions, but keep
generated images and captures untracked. DR-DOS source, disassembly intended to
reconstruct its implementation, and copied instruction sequences remain out of
scope.

The revalidated ordinary compatibility-safe maximum is 627,824 bytes. Its
10,720-byte pre-COMMAND span, 1,264-byte COMMAND span, 84,688 free UMB bytes,
10,880-byte unused HMA tail, 639 KiB conventional ceiling, HMA ownership, and
warm-reset public API state all match the recorded checkpoint. Low-memory and
text-video recovery remain excluded from the parity route; `/XBDA` alone still
provides no gain on the fixed BIOS. This confirms the ranked adoption table
below without introducing a new technique or compatibility exception.

The checkpoint is complete when the ordinary-mode advantage is accounted for
well enough to choose our next design, optional compatibility tradeoffs are
separated from the main score, and every proposed adoption has a local owner
and testable contract. Additional DR-DOS runs then return to being targeted
fallbacks for unresolved owner, lifetime, or public API questions.

| Priority | Externally evidenced technique | Local budget and owner | State and decisive gate |
| --- | --- | --- | --- |
| 1 | Relocate complete high-capable subsystems; DR-DOS demonstrates BIOS, shell, and dynamic DOS-state placement | Normal BIOS is 8,160 bytes; development compaction retains 5,152. Kernel prefix is 4,992; normal HMA slack after COMMAND is 15,437 bytes and UMB margin is 1,216 | Finish BIOS acceptance, then packed DOS-state placement; filesystem, device, redirector, EXEC, A20-off, DOS-low, rollback, and warm-reset paths remain gates |
| Paused | Keep more permanent shell payload in HMA; documented for 286-class HIDOS and measured on both DR-DOS generations | COMMAND is only 880 bytes above retail, though 2,720 bytes above DR-DOS in the current owner span | First tranche complete: catalogs and the 1,166-byte relocatable code range recover 2,480 paragraph-rounded bytes. Resume only after DOS placement, as a coherent interrupt/data redesign with reload, `INT 2Eh`, `INT 24h`, A20, DOS=LOW, `/MSG`, and real-286 gates |
| Paused | Retain only a small conventional/UMB gateway for the 386 memory manager; OpenDOS reports a 1,200-byte conventional device range and an 800-byte UMB owner | Active EMM386 is already 240 bytes below retail; services and most transition machinery are high | Reopen only for a coherent gateway relocation or a measured post-placement residual; preserve all EMS maps, modes, shifted loads, and warm reboot |
| Config | Omit the EMS page frame when applications do not require it | Supported as `NOEMS`; the fixed retail/local VC images actually use `RAM M5` | Preserve as a configuration choice and test both framed and frameless EMS; it is not an implementation saving |
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

**Comparison scope:** the archived DR-DOS matrices establish within-release
placement effects, not identical-configuration parity with our retail/local
images. They use `FILES=30`, `STACKS=9,256`, an explicit 512-byte shell
environment, floppy boot, and mainly no EMS frame. The fixed retail/local disk
images use `FILES=20`, default stacks, default shell settings, and `RAM M5`.
The cross-system differences below are observed snapshot arithmetic, not a
normalized implementation deficit. The local-versus-retail paired comparison
remains independently matched. See the resource-control check below before
using DR-DOS totals as a target.

**Status and priority:** the clean-room baseline and focused mechanism
checkpoint are complete. The first coherent COMMAND/HMA relocation and the
small EMM386 gateway are complete enough to remove them from the critical path.
Apply the central validated lesson now: introduce a packed HMA/XMS/UMB
placement ladder for movable DOS state, with HMA as the primary tier.

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

The ordinary OpenDOS result is 8,752 bytes above retail MS-DOS 6.22 and 17,232
bytes above this implementation. Its advantage over retail reconciles exactly:

| Owner-to-owner contribution | OpenDOS 7.01 | Retail MS-DOS 6.22 | OpenDOS gain |
| --- | ---: | ---: | ---: |
| System start through COMMAND start | 11,008 | 18,992 | 7,984 |
| COMMAND start through VC start | 1,312 | 3,104 | 1,792 |
| VC start through free block | 12,720 | 12,720 | 0 |
| Conventional ceiling loss | 1,024 | 0 | -1,024 |
| **VC largest-block advantage** | **627,488** | **618,736** | **8,752** |

The current implementation has the same 1 KiB ceiling loss as OpenDOS, so its
17,232-byte deficit to OpenDOS is entirely below COMMAND: 14,560 bytes in the
pre-shell system span and 2,672 bytes in COMMAND's span.

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

#### OpenDOS 7.01 framed follow-up: cold placement, reset failure

The pinned OpenDOS binary distribution and VC 4.05 were booted under QEMU
11.1.1, `pc`, 486, 8 MiB. Both cases use FILES=20, FCBS=4,0, LASTDRIVE=Z,
STACKS=9,128, `/E:512`, DOS=HIGH, HIDOS=ON and HIBUFFERS=15. Only
EMM386's `/FRAME=NONE` versus `/FRAME=AUTO` changes. These documented policies
disable versus enable EMS in the
[Novell DOS 7 User Guide](https://bitsavers.computerhistory.org/pdf/novell/dr_dos/DR_DOS_7_User_Guide_1993.pdf),
chapter 10; the probe independently verifies actual EMS availability.

| Cold boot | VC largest block | System span | COMMAND span | Free UMB | Free HMA |
| --- | ---: | ---: | ---: | ---: | ---: |
| No frame | 628,080 | 10,416 | 1,312 | 114,128 | 9,092 |
| EMS frame at CC00h | 628,080 | 10,416 | 1,312 | 47,584 | 9,092 |

Both retain a 639 KiB ceiling and EBDA at 9FC0h. MEM reports a 1,200-byte
installed manager device range inside the low system allocation and an
800-byte EMM386 UMB allocation in both cases. These are nested ownership rows,
not the complete manager footprint: do not add them to their containing DOS
span or assume all protected state has been located. The frame costs 66,544
free UMB bytes after the associated DOS layout changes, without changing
conventional memory. EMS 4.0 and XMS 3.0 are present in the framed probe.

This narrows an important design uncertainty: a DR-DOS-family system can
retain its large ordinary conventional block with EMS and nearly the retail
UMB floor, without DR-DOS 6's 28 KiB manager UMB cost. The local development
system-to-COMMAND span is 10,960 bytes larger and its COMMAND span is 2,672
bytes larger, exactly accounting for the 13,632-byte conventional difference.
Boot medium, device topology and resource semantics remain incompletely
normalized; this is not a promise of 13,632 local reclaimable bytes.

**Warm-reset gate failed in both new cases.** The whole-HMA request changes
from error 91h before reset to 81h afterward. The largest XMS UMB query loses
37,744 bytes: 114,128 to 76,384 without a frame, and 47,584 to 9,840 with one.
A20, XMS free totals and framed EMS status/page counts remain unchanged in the
recorded probes. The cause is not yet isolated between guest behavior and the
reset fixture; do not describe the new matrix as reset-stable. The capture tool
now retains the cold report and both reset outputs, marks the comparison
FAILED, and still exits unsuccessfully. Its parser tests reject false stable
labels; earlier default-resource evidence is a separate configuration.

Reproduce (currently expected to exit nonzero at the reset gate):

```sh
python3 tests/capture_drdos_memory.py DODL701.EXE \
  out/msdos622-original-vc405.img out/opendos-framed-placement.md \
  --variant emm-hibuffers --variant emm-frame --files 20 --stack-size 128 \
  --evidence-dir out/opendos-framed-placement-evidence
```

Next local design task: partition the combined 6,480-byte HIMEM/EMM386 low
allocation into mandatory real-mode/A20 interfaces and protected-only state.
Evaluate moving the latter as complete objects into already-owned locked XMS,
not a new UMB allocation. Enumerate real-mode/off/auto transitions, XMS entry
and A20 recovery calls, EMS table consumers, initialization rollback and third-
party-provider fallback before assigning any net saving. Retain the standalone
286 HIMEM path. Integration alone is not a saving; low copies must actually be
released and joined to the application's largest block.

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

DR-DOS 6 therefore leaves 9,088 bytes more than retail MS-DOS 6.22 and 17,568
bytes more than the normal implementation snapshot. The ordinary-mode snapshots
reconcile without counting recovered low or video memory:

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
  1,264 bytes for COMMAND. The current implementation uses 25,568 and 3,984,
  respectively; these two differences exactly explain its 17,568-byte deficit
  to DR-DOS because both have the same `9FC0h` ceiling.

#### Resource-control check before cross-system targeting

The capture tool accepts `--files`, `--stack-size` (nine stacks), and
`--environment`; defaults preserve the historical matrix. Reports contain the
complete effective CONFIG.SYS, and `--evidence-dir` retains both startup files.
Media/VC hash checks remain mandatory; historical numeric expectations apply
only with the original resource settings.

Fresh framed DR-DOS 6 boots with the pinned media and QEMU 11.1.1 isolate these
effects; all use `HIDOS=ON`, `HIBUFFERS=15`, and `/E:512`:

| FILES | STACKS | VC largest block | Pre-COMMAND span | Free UMB |
| ---: | --- | ---: | ---: | ---: |
| 30 | 9,256 | 627,824 | 10,720 | 15,568 |
| 20 | 9,256 | 628,352 | 10,192 | 16,032 |
| 20 | 9,128 | 628,352 | 10,192 | 16,032 |

Reducing FILES produces the entire 528-byte conventional and 464-byte UMB
change. Changing the stack directive produces no further measured allocation
delta; this does not prove identical internal stack provisioning. COMMAND stays
1,264 bytes, unused HMA stays 10,880, and the ceiling stays 639 KiB.

Reproduce with the baseline command above plus `--variant emm-frame`, then add
`--files 20`, then `--stack-size 128`, using distinct report/evidence paths.
This narrows the comparison mismatch but does not normalize shell environment,
boot medium, device topology, or resource semantics. The framed DR-DOS result
still misses our 47,888-byte UMB floor by 31,856 bytes; use it to study placement,
not as proof that the same conventional result satisfies both local floors.

#### Adoption priorities from the measured design

The measurements change emphasis but do not justify copying DR-DOS placement
blindly:

1. **Give DOS state a packed high-placement ladder.** DR-DOS gains 12,800
   conventional bytes by putting DOS state in a UMB, then moves buffers to HMA
   to recover most of that UMB. Locally, place HMA-safe state in proved DOS-owned
   HMA slack first, use relocation-safe XMS storage where callbacks permit it,
   and use deterministic UMB placement only within the measured 1,216-byte UMB
   advantage over retail. Fall back transactionally when a tier is unavailable.
2. **Keep COMMAND as a measured secondary tranche.** DR-DOS 6 proves a shell
   can retain 4,992 bytes in HMA and operate with a 1,264-byte conventional
   span. The first local relocation is complete, leaving only 880 bytes above
   retail; resume the harder asynchronous handler redesign after DOS placement.
3. **Keep the small-gateway EMM386 architecture, but stop harvesting it.**
   Spending DR-DOS 6's 28,672 UMB bytes would violate the retail free-UMB floor.
   The local 3,888-byte EMM386 owner is already smaller than retail, so further
   work needs an architectural relocation or a measured post-placement reason.
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
and regression boundary. Further work is implementation-led: build the packed
DOS high-state block against the existing HMA and UMB floors; EMM386 remains
paused below retail size.

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

Active EMM386 now occupies 3,888 bytes, 240 below retail. Potential further
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

An earlier attempt to release the next paragraph by shortening three
independent low-gateway branches was rejected. The basic API and address-phase
probes passed, but the EMS 4.0 function 56h segment-map-and-call case did not.
An instruction trace shows
the failed protected request returning to EMM386's own trapped `INT 67h`
opcode, then recursively dispatching `AX=5601h` while the client stack falls by
ten bytes per iteration. The physical-map form immediately before it completes.
Changing the common trapped-return IP advances execution but breaks earlier
directory results, so that is not a valid fix. Do not retry changes that move
`EMM_rLink` or the return-to-real trap merely to reach an allocation boundary.

A clean-build audit exposed and closed a separate maximum-capacity defect that
an incremental build had falsely reported as passing. `A=254` correctly
received a 20,400-byte EMM386 MCB, but its runtime FRS array crossed the linked
16 KiB `VDATA` reserve and overwrote the following protected segment before it
could be relocated. Allocation 229 consequently returned success with set 232,
skipping three damaged allocation flags. `VDATA` now reserves 48 KiB at link
and initialization time. That covers the complete 48,383-byte simultaneous
`H=255`, 2,048-page, 52-window, 20-`Pn=`, 16-DMA-page, and `A=254` dynamic
maximum; the residency report enforces this bound. The reserve is discarded or
overlaid during installation, so the default resident allocation remains
4,096 bytes. A forced clean build now allocates, exhausts, releases, and reuses
all 254 alternate sets. Clean forced builds remain required for every future
boundary claim.

The next installed paragraph is now safely released by changes after the
phase-sensitive gateways. Enable and disable A20 share a fall-through common
tail. The PIC-mask helpers had one caller each; `GoVirtual` now keeps the saved
mask as one word on its already-preserved client frame and restores it after
the virtual-mode return. This removes the helpers and their global transition
dependency while retaining the exact general-register and `Active_Status`
timing contracts. The retained `_TEXT` prefix falls from 490 to 474 bytes, the
stack begins at `0DF0h` after two alignment bytes, and EMM386 occupies 4,080
bytes. The forced-clean maximum-capacity, runtime-mode,
address-phase, EMS 4.0, frame/banking, MEM/UMB, warm-reboot, and 286/386/486
gates pass. The paired VC block gains all 16 bytes, reaching 607,952 with
49,104 free UMB bytes.

The following paragraph removes three redundant five-byte status writes from
the retained EMM link. `GoVirtual` already publishes `Active_Status=1` after
installing its traps, and `RetReal` publishes zero before returning, so the
AUTO activation and release callers no longer repeat those same writes. The
retained `_TEXT` prefix falls from 474 to 459 bytes; one byte of stack alignment
remains, EMM386 falls to 4,064 bytes, and VC rises to 607,968 bytes with 49,104
free UMB bytes. A rejected data-first version exposed an important placement
contract: moving `_TEXT` one paragraph earlier put the function 56h return and
low EMM-link continuation inside the `D000h..D3FFFh` window that the segment
form may remap. Future prefix work must keep that continuation outside every
mappable window or redesign it as a mapping-independent gateway. Forced-clean
capacity, mode, address-phase, EMS 4.0 including both function 56h forms,
frame/banking, MEM/UMB, reboot, and 286/386/486 gates all pass.

The next paragraph is released without moving the phase-sensitive function 56h
gateway from its safe `D400h` boundary. AUTO mode now compares its handle and
active state once and tail-calls an AX-preserving `RRProc`; the 386 transition
saves one complete 32-bit general-register frame; `Active_Status` reuses the
PIC-mask value; and the real-mode continuation omits a redundant CR3 reload
because clearing `CR0.PG` has already invalidated the TLB and the next entry
reloads CR3. The retained `_TEXT` prefix falls to 444 bytes, the 1,904-byte
dynamic area ends on a paragraph boundary, and EMM386 falls to 4,048 bytes.
The paired VC block gains all 16 bytes, reaching 607,984 with unchanged 49,104
free UMB bytes. Forced-clean default and maximum-capacity censuses, modes,
address phases, EMS 4.0/function 56h, frames, MEM/UMB, SMARTDrive reboot, and
the 286/386/486 hardware matrix pass locally.

The following return-to-real boundary releases another exact paragraph without
moving the function 56h gateway. The protected port-85 handler disables NMI
before entering the low continuation, and `RetRealHigh` publishes inactive
status while DGROUP is still selected. The port handler and protected error
handler call that high continuation directly, removing the retained `RetReal`
trampoline; the obsolete post-switch short jump is also gone because the far
mode-switch jump already flushes instruction prefetch. The retained `_TEXT`
prefix falls to 428 bytes and EMM386 to 4,032 bytes. The paired VC block reaches
608,000, leaving a 10,736-byte retail gap and the same 49,104 free UMB bytes.
Forced-clean default and maximum censuses, EMS 4.0/function 56h, all modes and
address phases, frame/banking options, MEM/UMB, SMARTDrive reboot, and the
286/386/486 matrix pass locally.

The next compaction uses existing layout slack without moving the
phase-sensitive gateway. Five post-switch unwind bytes occupy the unused
`R_CODE` alignment tail; the A20 settling loop retains its 256 iterations using
the already-saved AX; and `RetRealHigh` preserves one complete 386 register
frame. The six-byte real IDTR descriptor and its load move to the protected
continuation immediately before PE is cleared, while interrupts and NMI are
disabled. The required FS/GS reload and caller-owned interrupt-state contracts
remain intact. `_TEXT` falls from 428 to 404 bytes. The virtual-to-real trap
return now restores the client stack before enabling NMI and uses one `IRET` to
restore IP:CS and flags atomically, eliminating the duplicated IF/CLI tails.
Keeping DS on `R_CODE` until that frame is built removes redundant segment
overrides and packs contiguous IP:CS into one 32-bit push. Reordering the six
scratch words then lets one preserved-register string loop capture the regular
VM-frame fields, and removes a dead mask of the discarded fault frame.
`R_CODE` falls to 336 bytes and the static image to 1,528 bytes. The map's
retained-layout end is 3,952 bytes, while the paired live image reports a
3,936-byte EMM386 payload and a 608,096-byte VC block: six reported paragraphs
gained across this combined tranche and a 10,640-byte retail gap. A shared
far-return convention for `GoVirtual` hung the full function 56h probe and was
rejected; do not retry it without a mapping-aware return design. The complete
EMS, option, address, frame, UMB, reboot, and 286/386/486 hardware gates pass
locally.

The privileged-operation dialog now says `EMM386 privileged error #xx` and
`Continue (C) or reboot (B)?`. It removes repeated wording while preserving the
runtime error number and both recovery choices; the exception dialog is
unchanged. The 29-character source reduction removes 28 linked `_DATA` bytes,
moves the selected raw tail from `0D68h` to `0D4Ch`, and crosses one installed
paragraph after alignment. EMM386 falls from 3,936 to 3,920 bytes, VC rises
from 609,808 to 609,824 bytes, and the retail gap becomes 8,912 bytes with the
same 49,104 free UMB bytes. Driver commands, all DOS-high address phases,
frames and banking, sparse mappings, `H=`/`A=`/`D=` capacity—including
`A=254`—EMS 4.0, XMS/UMB/EMS rollback and warm reboot, and the 286/386/486
hardware matrix pass locally. At that milestone the residency checker enforced
the 396-byte `_DATA` and 3,920-byte default-layout ceilings.

The ELIM `ON` and `OFF` paths now clear `AUTO` before testing whether EMM386 is
already in the requested active state. Both explicit commands always exited
automatic mode before, including their no-transition cases; placing the write
at the branch entry removes the shared cleanup tail while retaining that
contract and the original transition ordering. Low `_TEXT` falls from 404 to
390 bytes, the static low image from 1,500 to 1,486 bytes, and the raw selected
tail from `0D4Ch` to `0D3Eh`, which rounds to `0D40h`. EMM386 falls from 3,920
to 3,904 bytes, VC rises from 609,824 to 609,840 bytes, and the retail gap
becomes 8,896 bytes with the same 49,104 free UMB bytes. Explicit and inactive
`AUTO` modes, every load option and address phase, EMS 4.0, warm reboot, and
the 286/386/486 hardware matrix pass locally. The residency checker now
enforces the 396-byte `_DATA` and 3,904-byte default-layout ceilings.

The control dispatcher now validates `AL` once, clears `AUTO` once for either
explicit command, and selects the transition from the existing zero/nonzero
active flag. It publishes the canonical `FFh` or `00h` state before entering
`GoVirtual` or `RRProc`, preserving the interrupt-visible ordering of the old
paths. An initial 0/1 comparison was rejected immediately when the command
probe exposed the real `FFh` representation; a second form that deferred state
publication was also rejected during review, and no result from either build
was retained. The corrected form removes 15 linked low `_TEXT` bytes, reducing
the low prefix from 390 to 375 bytes and the static image from 1,486 to 1,471
bytes. The raw selected tail ends at `0D2Fh`, rounds to `0D30h`, and the checked
map and paired live image both report a 3,888-byte EMM386 owner. VC rises to
609,856 bytes, the retail gap becomes 8,880 bytes, and free UMB capacity stays
at 49,104 bytes. Command/API status and transitions, inactive `AUTO`, all load
options and DOS-high address phases, maximum alternate registers, EMS 4.0,
SMARTDrive warm reboot, and the 286/386/486 hardware and XMS lifecycle gates
pass locally. The residency checker enforces the 396-byte `_DATA` and
3,888-byte layout ceilings.

The first DOS placement-ladder tranche reorders the independent `MSCODE` and
`MSDISP` CODE contributions without changing the full image size or the fixed
`SYSBUF` and `DOSINIT` offsets. `DOS_CODE_START` remains anchored at the first
relocatable code byte, while the complete 808-byte dispatcher contribution is
linked after `DOS_LOW_GATE_END`. DOS=HIGH therefore reclaims it with the code
tail; DOS=LOW retains and executes the same conventional image. The low prefix
falls from 6,816 to 6,048 paragraph bytes. The paired VC block gains 768 bytes
at 608,864, leaving a 9,872-byte gap and the same 49,104 free UMB bytes. HMA
ownership/fallback/A20/EXEC, DOS=HIGH/LOW, COMMAND startup, INT 21h system,
file, compatibility and asynchronous callbacks, and the 286/386/486 hardware
matrix pass locally.

The second DOS placement tranche moves `DOS_LOW_GATE_END` immediately after
the conventional driver workspaces and null-device entry. The following
387-byte absolute-disk path, 199-byte system/FCB return and error path, and
66-byte INT 2Fh path already use HMA entry gates or are reached from relocated
DOS code; the separate low driver trampoline remains available for A20-off
callbacks. Retaining the four historical padding bytes leaves the 39,440-byte
HMA image and fixed `SYSBUF`/`DOSINIT` offsets unchanged. The linked low
boundary falls from 6,033 to 5,381 bytes and its paragraph allocation from
6,048 to 5,392 bytes. Paired VC grows by all 656 bytes to 609,520, leaving a
9,216-byte retail gap and the same 49,104 free UMB bytes. DOS=LOW/HIGH,
filesystem and FCB returns, INT 2Fh, asynchronous callbacks, raw INT 25h/26h
through RAMDRIVE and SMARTDRV, internal structures, and the 286/386/486 matrix
pass locally. The broader driver suite's four VDISK failures reproduce on the
previous pushed kernel and are not attributed to this boundary change.

The reset-vector path for BIOS `INT 2Fh/AH=13h` now exchanges the two pointer
offsets in place and rotates their segment words through one saved register,
preserving the documented DS:DX and ES:BX old-pointer results. `CHECK_WRAP`
uses balanced increments for its already zero-based physical-drive selector;
unlike immediate stores, these preserve the `SETDRIVE` carry result. Together
the changes remove 16 bytes from the generic disk/INT 2Fh range and move
`ENDONEHARD` from `2080h` to `2070h`, reducing the fixed selected BIOS from
8,448 to 8,432 bytes. A new probe installs distinct runtime and warm-boot
vectors, restores both old pointers through the same API, and verifies the
returned pair. Paired VC receives the paragraph at 609,536 bytes, leaving a
9,200-byte gap and the same 49,104 free UMB bytes. Multitrack I/O, SMARTDRV
write-behind and reboot, SYS fixed-disk transfer/boot, FORMAT fixed-disk modes,
and the 286/386/486 matrix pass locally.

`CHECK_WRAP` now keeps its sector and head totals zero-based throughout. For a
head count `N`, dividing `starting_head + head_wraps` directly yields the same
cylinder increment and final head as the former one-based division plus its
zero-remainder correction. The rewrite removes 18 linked bytes and SYSINIT's
existing paragraph rounding turns that into another 16-byte selected-BIOS
gain: 8,432 to 8,416 bytes. The residency census now reports rather than hides
the two bytes of static-boundary padding and enforces the complete rounded
result. Paired VC reaches 609,552 bytes, leaving a 9,184-byte gap and unchanged
49,104-byte free UMB capacity. The vector-exchange probe, multitrack and raw
disk paths, SMARTDRV, SYS, FORMAT, and 286/386/486 matrix pass locally.

The sector half of `CHECK_WRAP` now divides `sector - 1`, making the quotient
the head increment and the remainder the zero-based sector; incrementing only
the remainder restores the BIOS one-based sector. This removes the former
zero-remainder branch. `SETDRIVE` now stores the selected BDS field offset
rather than a boolean and compares either adjacent `DRIVENUM` or `DRIVELET`
through one indexed path; a build-time assertion protects that adjacency.
Together with fall-through head cleanup, the selected BIOS falls from 8,416 to
8,400 bytes. Paired VC receives all 16 bytes at 609,568, leaving a 9,168-byte
gap and the same 49,104 free UMB bytes. The direct vector exchange, logical and
physical disk selection, multitrack/raw I/O, SMARTDRV, SYS, FORMAT, and
286/386/486 gates pass locally.

The BDS scanner no longer communicates physical-versus-logical selection
through a resident mutable byte. `SETDRIVE` and its internal physical entry
choose the `DRIVELET` or `DRIVENUM` offset before sharing the same linked-list
scan, and the scan loads the next segment through the stack so that the indexed
field remains stable across multiple BDS records. Removing three pairs of
selector writes and the state byte reduces the selected BIOS from 8,400 to
8,368 bytes. Paired VC gains both paragraphs at 609,600 bytes, leaving a
9,136-byte gap and unchanged 49,104-byte free UMB capacity. Logical RAMDRIVE
I/O, physical fixed-disk paths, vector exchange, multitrack/raw I/O, SMARTDRV,
SYS, FORMAT, and the 286/386/486 matrix pass locally; the four pre-existing
VDISK failures remain unchanged.

The PS/2 Model 25/30 `INT 13h` parameter workaround now keeps the first BIOS
call's flags and returned registers on the active stack while issuing the
second status call, retaining only the original drive number in resident data.
This removes 20 data bytes and 80 code bytes, crosses six selected-image
paragraphs, and reduces the fixed BIOS from 8,368 to 8,272 bytes. The paired
VC capture receives all 96 bytes at 609,696, leaving a 9,040-byte gap and the
same 49,104 free UMB bytes. The DOS interrupt contract and 286/386/486 hardware
matrix pass locally. The focused test replaces the underlying BIOS handler,
forces the resident Model 25/30 branch without relying on the frontmost
`INT 13h` vector, and proves success and error carry, all nine returned
registers, and exactly one follow-up status call for both `AH=08h` and
`AH=15h`. The candidate is therefore closed.

The DOS-high DPB compactor now uses the two 33-byte records already reserved
in DOS's retained low prefix before spilling into BIOS storage. Only four
overflow records remain in the BIOS, preserving the six-drive maximum without
moving mutable DPBs into HMA or making legacy driver pointers depend on A20.
Removing the duplicate 66-byte BIOS reserve crosses four selected-image
paragraphs: the fixed BIOS falls from 8,272 to 8,208 bytes, the paired VC block
rises to 609,760 bytes, and the retail gap falls to 8,976 bytes with the same
49,104 free UMB bytes. A focused DOS-high image with two floppy letters and two
partitioned hard disks proves both low records, the cross-storage link, two
overflow records, drive order, and CDS pointers. DOS-low/high selection,
filesystem/FCB/exhaustion, multitrack I/O, DPB/CDS introspection, PS/2 disk
results, 286/386/486 HMA/UMB lifecycles, and real-286 warm reboot pass locally.

The warm-boot vector restore table already marks every uninstalled entry with
an `FFFFh` segment and writes complete pointers while interrupts are disabled.
`INT19SEM` and the second offset-word sentinel test therefore duplicated the
per-entry state. Removing them shrinks the selected BIOS from 8,208 to 8,192
bytes. The paired VC block receives the paragraph at 609,776 bytes, leaving an
8,960-byte retail gap and the same 49,104 free UMB bytes. The complete warm
reboot, SMARTDrive reboot, BIOS interrupt/vector exchange, multitrack disk, and
286/386/486 local gates pass.

The K09 suspend/resume handler no longer copies its far caller address into a
four-byte permanent global: it leaves that address on the existing stack frame
and returns with `RETF` after restoring the caller's flags. The CMOS date reader
derives month lengths from the immediate `0AD5h` 31-day-month mask instead of a
24-byte resident cumulative-day table; the unused `FEB29` byte is gone. This
removes 30 linked bytes and crosses two selected-image paragraph boundaries:
the fixed BIOS falls from 8,192 to 8,160 bytes, VC rises to 609,808 bytes, and
the gap falls to 8,928 bytes with the same 49,104 free UMB bytes. The BIOS
residency gate, fixed CMOS-date IBM AT boot, HIMEM/XMS/UMB/EMS and warm-reboot
suites, SMARTDrive reboot, interrupt/vector and PS/2 result checks, multitrack
disk I/O, and 286/386/486 hardware matrix pass locally. The contiguous
40-byte mini-disk BPB-pointer reserve remains: it is part of the `DSKDRVS`
indexed ABI and cannot be removed as an isolated data compaction.

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
occupies `0010h..9A50h` (39,488 bytes). With the fixed 15-buffer, 512-byte-sector
configuration, the hash and slots occupy `9A50h..B984h` (7,988 bytes), leaving
`B984h..FFF0h` (18,028 bytes) of initially unassigned but still DOS-owned space
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
low gateway allocation to 6,816 bytes at that checkpoint (now 4,992).
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

At the shell-relocation checkpoint, the permanent root shell reserved 2,447
bytes from that tail and copied the
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

Implement coherent subsystem relocations selected by the whole-system byte
budget, not a sequence of table or alignment reductions. Divide each design
into independently verified steps without substituting those steps for its
multi-kilobyte placement objective. After each retained
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
| EMM386 | 3,888 | 4,128 | -240 |
| FILES | 896 | 896 | 0 |
| FCBS | 256 | 256 | 0 |
| BUFFERS | 512 | 512 | 0 |
| LASTDRIVE | 2,288 | 2,288 | 0 |
| STACKS | 1,840 | 1,856 | -16 |
| Total | 12,272 | 11,040 | 1,232 |

`MEM` reports 12,384 and 11,168 bytes after each block's arena overhead. Both
systems use `BUFFERS=15` and now retain only one 512-byte conventional transfer
area. A direct retail probe found its buffer hash at `FFFF:B3D4`, confirming
that DOS 6.22 also places the normal buffer state in the HMA.

### Stage 1: HMA buffers with legacy-driver safety — complete

A retained implementation reserves the HMA before final-table construction and
packs the normal hash and buckets above the resident DOS image. Configured
sets that do not entirely fit spill complete buckets into conventional memory;
if no initial bucket fits, they retain the original all-low path. The
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

The current 610,256-byte largest block is 8,480 bytes (1.4%) below retail and
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
