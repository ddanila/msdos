; Repository-private development copy discovery, not allocator ownership or
; a public XMS ABI. Query works without enabling EMS or dereferencing ES:SI.
; INT 15h AX=query returns AX=reply, BX=signature, CX=version, DX=features.
; Test peers require an exact version and every required feature; CF is not
; the discovery result. No private copy packet may be sent on rejection.
XCP_QUERY equ 0e7c0h
XCP_BIND_QUERY equ 0e7d0h ; same reply/capabilities, plus ES:DI guarded stable entry
XCP_REPLY equ 0e7cfh
XCP_SIGNATURE equ 05843h
XCP_VERSION equ 1
XCP_PHYSICAL equ 1
XCP_CLIENT equ 2
XCP_INACTIVE equ 4
XCP_OWNER_QUERY equ 8 ; optional read-only allocator snapshot query
XCP_OWNER_ACTIVE equ 16 ; paired experimental authoritative handle owner
XCP_OWNER_RECEIPT equ 32 ; read-only XAUT operation 00h supported
XCP_UMB_OWNER equ 64 ; opt-in independent XUMB publication/service boundary
XCP_UMB_RESULTS equ 128 ; XUMB v2 sequenced service result receipts
XCP_PUBLIC_MOVE equ 256 ; XMSM + 16-byte public descriptor snapshot, high validation
XCP_COMMON_FRAME equ 512 ; XAPI v2 steady-state context, independent of boot imports
XCP_REQUIRED equ XCP_PHYSICAL OR XCP_CLIENT OR XCP_INACTIVE
; BIND_QUERY succeeds only after final relocation/compaction and vector
; installation. ES:DI accepts PUSHF/CALL FAR with the usual INT 15h packet
; registers. The resident guard must remain allocated for the binding's
; lifetime; revoke it BEFORE releasing high backing. No active-image rebase,
; replacement-owner adoption or binding across an OS reset is permitted.
; Binding publishes transport, not allocator ownership. Import receipts still
; govern each owner. A rejected bound call cannot fall through to firmware.
; PUBLIC_MOVE is a transitional common-core adapter, not registration. XMSM
; occupies the existing 20-byte copy packet: tag plus an unchanged 16-byte
; public Move descriptor snapshot. Caller bounds and copies the descriptor
; from its real DS:SI while serialized; it does not resolve handles. The high
; adapter checks the packet extent, requires the authoritative handle owner,
; and returns AX/BX in the tag's two words (CF only describes transport).
; Low caller restores XCPY after consuming the result. No new scratch packet
; or low handle mirror is introduced. Public Move error/overlap validation
; executes high; result recovery does not undo partially completed hardware
; copies. COMMON_FRAME replaces these steady-state packets with XAPI v2:
; +4 version=2, +6 operation, +8 completion (input 0), +10 result AX,
; +12 DX, +14 BX, +16 input offset, +18 capacity, +20 dword sequence.
; Handle ownership must already be committed; only UMB operations additionally
; require the UMB owner. Move/handle calls remain available during deferred
; UMB import. Operations 08h..11h
; are public XMS, 12h/13h register/unregister UMBs, 14h private handle lookup.
; 08h/0Eh/14h require sequence zero; other services share the XUMB v2 journal.
; Operation 02h queries that journal without requiring a new mutation.
; Source bytes share the frame's client segment. Move requires 16 bytes;
; registration takes version/count plus up to 32 four-byte records. The low
; front uses one 156-byte frame (24-byte header + 132-byte input union), never
; the retired import table as peer scratch. Unknown mutation outcomes freeze
; all common public/peer calls before overwriting any pending frame bytes.
; Once common dispatch starts, legacy XAUT mutations are rejected. Bootstrap
; imports remain separate; frame independence is not permission to reclaim
; their bodies before final loader publication and last-use proof.
; Paired HIMEM-only layout discovery through INT 2Fh. Request AX=query,
; CX=signature, SI=version, DI=0. Success AX=reply, DX=resident segment,
; BX=paragraph-aligned permanent end, SI=bootstrap handle-table offset,
; DI=selected handle count, CX=paragraph-rounded boot end. BP is preserved.
; Wrong signature/version/reserved field returns AX=0. No storage is moved,
; frozen, released or granted to the caller. Commitment is a separate receipt.
; In the common layout the handle-import body is itself bootstrap code. Its
; permanent gate checks freeze before dereferencing the staged code pointer,
; passes the canonical low DS, and waits for a far return before poisoning the
; original tail. An unknown publication cannot re-enter that body or replay a
; mutation; confirmed calls use the registered native entry instead.
XCP_LAYOUT_QUERY equ 0e706h
XCP_LAYOUT_REPLY equ 0e7ffh
XCP_LAYOUT_SIGNATURE equ 584dh
XCP_LAYOUT_VERSION equ 1
; Opt-in boot staging: E707h binds an identical complete resident copy at DX:0
; above the original boot extent; E708h restores its current bootstrap tail.
; Both require CX=layout signature, SI=version, DI=0 and return AX=layout reply
; or zero on rejection. Caller owns the copy's allocation until successful
; high publication or explicit restore. No vectors/public entry are relocated.
XCP_STAGE_BIND equ 0e707h
XCP_STAGE_RESTORE equ 0e708h
; E709h retargets a staged owner after a trusted loader's validated copy.
; BX=expected old stage segment, DX=new segment; other request fields as above.
; Requires an unpublished owner and checks new conventional bounds and peer
; metadata. It does not copy/compare the old storage (which may be overwritten)
; or prove that the caller owns the destination. Requires the E70Ah freeze;
; failure leaves the root intact and allocator dispatch frozen.
XCP_STAGE_RETARGET equ 0e709h
; E70Ah freezes allocator dispatch before the loader copies a bound stage.
; Same signature/version/reserved fields; AX=reply/0. While frozen, allocator
; calls return 8Eh without accessing the stage or attempting high publication.
; Successful E709h retarget or pre-publication E708h restore clears the freeze.
XCP_STAGE_FREEZE equ 0e70ah
; Finish both common owners before the loader releases LAST. Same signature,
; version and DI=0 as layout discovery; AX=layout reply only after both owners
; are confirmed. Failed/unknown publication retains the stage and returns 0.
XCP_BOOTSTRAP_FINISH equ 0e70bh
; OWNER_QUERY uses AH=87h, ES:SI -> 'XOWN', then word version=1, handle
; limit, pool KiB, output largest/total KiB, then up to 128 five-byte records.
; The trusted development peer backs the full 654-byte packet below its
; segment limit and snapshots stable state. This grants no allocation or
; handoff authority. Failure sets CF/AH=2; success clears CF/AH=0.
;
; OWNER_ACTIVE is a separate, trusted paired experiment. XAUT packet words:
; +4 version=3, +6 handle limit, +8 pool KiB, +10 output AX, +12 in/out DX,
; +14 in/out BX, +16 operation (00h receipt or 08h..0Fh service),
; +18 word offset of bootstrap records
; in the same client segment. The header is 20 bytes, with no inline records.
; First request bounds-checks and imports the selected five-byte records once;
; later requests ignore their offset/storage and return only AX/BX/DX, never
; a low table view. Private operation
; 0Bh is handle lookup (DX=handle; AX=status, BX=base KiB, DX=length KiB), not
; public Move; it does not change locks. Low front-end mutations must be
; disabled before that first attempt and remain disabled on transport failure.
; XMS status is in packet AX/BX; transport CF does not describe XMS success.
; Calls are serialized and non-reentrant. No handback, foreign-provider
; transfer, HMA/A20/UMB transfer or low-memory reclamation is provided here.
; With OWNER_RECEIPT, operation 00h returns AX=committed (0/1), BX=import
; count, DX=committed handle capacity (zero before commit). It ignores input
; count/pool/record offset, never imports or mutates allocator state, and works
; without readable bootstrap records. Transport failure means unknown status,
; not uncommitted. This is a trusted paired-owner receipt, not authorization
; to free storage, replay a mutation, restore a stale owner, or adopt a foreign
; provider. OWNER_ACTIVE advertises capability, not actual commitment.
;
; XUMB v1 (EMM_UMB_OWNER_TEST only) is a trusted serialized test transport,
; not a public XMS ABI or a HIMEM ownership switch. ES:SI header words:
; +4 version=1, +6 operation, +8 reserved=0, +10 output AX,
; +12 in/out DX, +14 in/out BX, +16 source offset, +18 source capacity.
; All source bytes share the packet's client segment. Operations:
; 00 receipt (AX=active, BX=imports, DX=record count; no source read),
; 01 import count/records once, preserving allocated bits; never runs a service,
; 10 allocate, 11 release, 12 register version/count/free-range packet,
; 13 unregister. Services require an imported owner; register requires it empty.
; Import/register validate complete offset extents before accessing records.
; Receipt and later services ignore retired import storage. Duplicate import
; is rejected. Transport CF is independent of AX/BX service status. No handback,
; mutation replay, physical-backing ownership or low-memory release is granted.
;
; XCP_UMB_RESULTS adds optional XUMB v2 (24 bytes): v1 fields plus +20 dword
; service sequence. Input +8 remains zero; service/result output +8 is 1 for
; complete, 0 for proved non-execution. Ops 00/01 retain owner receipt/import
; semantics. Op 02 is a read-only result receipt; ops 10..13 accept only the
; next sequence (start at 1, skip zero on 32-bit wrap). Publish sequence with
; completion invalid before mutation, save AX/DX/BX, then mark complete.
; Duplicate/stale/skipped services are refused, never replayed. V1 mutations
; are refused after sequenced service begins; v1 owner receipts remain valid.
; Op 02 returns the matching completed result, or proves that the exactly-next
; request never began when no prior service is pending. All other queries fail;
; failure is unknown, not non-execution. A pending service blocks later services.
; The low front confirms the sequence before returning a recovered result;
; unknown receipts freeze later public/peer operations without overwriting the
; pending packet. This is a serialized one-result journal, not an unbounded
; deduplication history, reset-persistent log, handback or recovery from lost
; backing. Provider lifetime and channel integrity are trusted preconditions.
