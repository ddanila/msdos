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
XCP_REQUIRED equ XCP_PHYSICAL OR XCP_CLIENT OR XCP_INACTIVE
; OWNER_QUERY uses AH=87h, ES:SI -> 'XOWN', then word version=1, handle
; limit, pool KiB, output largest/total KiB, then up to 128 five-byte records.
; The trusted development peer backs the full 654-byte packet below its
; segment limit and snapshots stable state. This grants no allocation or
; handoff authority. Failure sets CF/AH=2; success clears CF/AH=0.
