# UMB allocator audit

This is the source map for converting the DOS 4 single MCB arena into the DOS
5 conventional-plus-UMB model. It records paths that must be revisited as each
delivery phase connects another UMB surface.

## Kernel call graph

```text
INT 21h dispatch
|- AH=48h -> $ALLOC
|  |- Check_Signature / arena_next
|  |- Coalesce
|  `- first, best, or last candidate split
|- AH=49h -> $DEALLOC -> Check_Signature
|- AH=4Ah -> $SETBLOCK -> Check_Signature -> Coalesce -> allocator split
|- AH=4Bh -> $EXEC
|  |- $ALLOC (environment and image discovery/allocation)
|  |- ChangeOwner (environment and image MCBs)
|  `- exec_dealloc / exec_alloc (temporary owner transitions)
|- AH=58h -> $AllocOper
`- process exit -> arena_free_process -> Check_Signature / arena_next
```

`DOS/ALLOC.ASM` owns all normal scan, split, coalesce, resize, free, and
process-cleanup operations. `DOS/EXEC.ASM` calls `$ALLOC`, then directly edits
the owner and eight-byte name fields of returned MCBs. `DOS/CTRLC.ASM` invokes
`arena_free_process` during normal process teardown. These paths therefore have
to recognize UMB-owned blocks even when the public UMB chain is unlinked.

## Initialization and observable layout

- `DOS/MSINIT.ASM` creates the conventional head at `CurrentPDB-1`; its single
  free block ends at `ENDMEM` with a `Z` signature.
- `DOS/MSCONST.ASM` exports `arena_head` through the DOS data layout.
- `BIOS/SYSINIT1.ASM` derives conventional limits from `MEMORY_SIZE` and
  `ALLOCLIM`; its boot allocations cannot be allowed to mistake UMA addresses
  for conventional capacity.
- `CMD/MEM/MEM.C` obtains `arena_head` through `INT 21h/AH=52h`, walks MCBs by
  `segment + Paragraphs + 1`, and specially decodes DOS-owned system-data
  subsegments. It currently stops at the first `Z` and has no UMB accounting.
- Third-party tools see the same List-of-Lists pointer and MCB signatures, so
  a private descriptor-only chain is insufficient.

## Arena invariants

The implementation keeps `arena_head` as the conventional head and records a
separate `UmbArenaHead`. `UmbLinkMcb` identifies the exact conventional-chain
MCB whose `M`/`Z` signature controls public traversal into the persistent UMB
chain. `UmbLinked` describes that signature state; it does not describe whether
the provider or UMB descriptors exist.

- Conventional scans stop before `UmbArenaHead`, even when the chain is linked.
- Upper scans start at `UmbArenaHead` and never infer arena identity from a
  segment threshold.
- An `80h..82h` scan retries conventional memory only after the upper scan has
  no fitting block. A `40h..42h` scan does not retry.
- Gap MCBs are system-owned, so ordinary coalescing cannot cross them.
- Process cleanup visits both descriptors even if the visible link is off.
- Link and unlink validate the saved bridge, its next segment, and its current
  signature before changing anything.

## Remaining direct assumptions

| Source | Assumption to remove or verify |
| --- | --- |
| `DOS/EXEC.ASM` | Largest-block discovery and both image/environment allocations must follow the selected domain and preserve EXEC rollback. |
| `DOS/MSHALO.ASM` | Direct owner writes must only receive a validated conventional or UMB MCB. |
| `BIOS/SYSINIT1.ASM` | Boot allocator limits are conventional-only until scoped high loading is active. |
| `CMD/MEM/MEM.C` | Traversal stops at one `Z`; reporting has only base/EMS/extended categories and DOS 4 switches. |
| List of Lists | DOS 5 link state, first-UMB pointer, and allocation scan-start fields still need their reference-confirmed exported layout. |

SYSINIT now discovers a provider through `INT 2Fh/4300h` and `4310h`, retains
each extent returned by XMS function `10h`, and registers it with the kernel.
The kernel carves a RAM-resident bridge immediately below `A000h`, represents
the video/ROM gap as DOS-owned `SC`, and terminates every provider extent with
an `SM` guard so coalescing cannot cross provider boundaries. The public chain
remains unlinked after boot. With no provider the descriptors stay zero,
`5802h` reports unlinked, and both valid `5803h` requests fail with
`ERROR_INVALID_FUNCTION`.

The private `5804h` path is callable only with SYSINIT's three-register
signature and is not part of the public API; ordinary `5804h` calls still take
the required invalid-function path. This handoff does not expose or consume a
private EMM386 interface: all provider discovery, allocation, and release calls
remain standard XMS.
