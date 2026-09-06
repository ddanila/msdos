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
XCP_REQUIRED equ XCP_PHYSICAL OR XCP_CLIENT OR XCP_INACTIVE
; OWNER_QUERY uses AH=87h, ES:SI -> 'XOWN', then word version=1, handle
; limit, pool KiB, output largest/total KiB, then up to 128 five-byte records.
; The trusted development peer backs the full 654-byte packet below its
; segment limit and snapshots stable state. This grants no allocation or
; handoff authority. Failure sets CF/AH=2; success clears CF/AH=0.
;
; OWNER_ACTIVE is a separate, trusted paired experiment. XAUT packet words:
; +4 version=1, +6 handle limit, +8 pool KiB, +10 output AX, +12 in/out DX,
; +14 in/out BX, +16 operation (08h..0Fh except Move/0Bh), +18 records.
; First request imports validated records once; later requests ignore incoming
; records and return the authoritative view. Low front-end mutations must be
; disabled before that first attempt and remain disabled on transport failure.
; XMS status is in packet AX/BX; transport CF does not describe XMS success.
; Calls are serialized and non-reentrant. No handback, foreign-provider
; transfer, HMA/A20/UMB transfer or low-memory reclamation is provided here.
