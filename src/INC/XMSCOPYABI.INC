; Repository-private development copy discovery, not allocator ownership or
; a public XMS ABI. Query works without enabling EMS or dereferencing ES:SI.
; INT 15h AX=query returns AX=reply, BX=signature, CX=version, DX=features.
; Test peers require an exact version and every required feature; CF is not
; the discovery result. No private copy packet may be sent on rejection.
XCP_QUERY equ 0e7c0h
XCP_REPLY equ 0e7cfh
XCP_SIGNATURE equ 05843h
XCP_VERSION equ 1
XCP_PHYSICAL equ 1
XCP_CLIENT equ 2
XCP_INACTIVE equ 4
XCP_OWNER_QUERY equ 8 ; optional read-only allocator snapshot query
XCP_OWNER_ACTIVE equ 16 ; paired experimental authoritative handle owner
XCP_OWNER_RECEIPT equ 32 ; read-only XAUT operation 00h supported
XCP_REQUIRED equ XCP_PHYSICAL OR XCP_CLIENT OR XCP_INACTIVE
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
