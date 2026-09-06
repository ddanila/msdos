; Existing UMB owner: word count, then segment/size-with-allocation-bit pairs.
; DS:SI supplies the source; CX is its caller-proved record capacity (0..32).
; Validates count, 64-KiB offset extent, nonzero lengths, A000h..F000h bounds
; and sorted nonoverlapping ranges. Allocated flags survive; adjacent ranges
; need not already be coalesced. Reads no unused records and changes no state.
; CF clear = valid. Preserves all 16-bit general/segment registers and DF.
; The caller owns backing/selector validity and serialization; this is not
; pointer probing, public XMS registration or ownership publication.
xms_validate_umb proc near
        pusha
ifdef HIMEM_UMB_ACCEPT_INVALID_TEST
        jmp umb_state_good
endif
        cmp cx,MAX_UMB_BLOCKS
        ja umb_state_bad
        cmp si,0fffeh
        ja umb_state_bad
        mov ax,[si]
        cmp ax,cx
        ja umb_state_bad
        mov cx,ax
        shl ax,1
        shl ax,1
        add ax,2
        add ax,si
        jnc umb_extent_valid
        or ax,ax              ; exclusive end 10000h is legal, wrapping is not
        jnz umb_state_bad
umb_extent_valid:
        add si,2
        xor bp,bp
        jcxz umb_state_good
umb_state_record:
        mov ax,[si]
        mov dx,[si+2]
        and dx,NOT UMB_ALLOCATED
        jz umb_state_bad
        cmp ax,0a000h
        jb umb_state_bad
        cmp ax,bp
        jb umb_state_bad
        add ax,dx
        jc umb_state_bad
        cmp ax,0f000h
        ja umb_state_bad
        mov bp,ax
        add si,UMB_BLOCK_SIZE
        loop umb_state_record
umb_state_good:
        popa
        clc
        ret
umb_state_bad:
        popa
        stc
        ret
xms_validate_umb endp

; DS:SI stable source, ES:DI private unpublished destination. CX/BX are the
; caller-proved source/destination capacities. Source and destination backing
; must be physically disjoint and inaccessible to concurrent mutation.
; Rejects before any write. Copies count and selected records, never unused
; slots or neighboring state. Preserves registers/DF. Does not set an active
; flag, retire the source, publish a pointer or permit replay after commit.
xms_stage_umb proc near
        pushf
        pusha
        cmp bx,MAX_UMB_BLOCKS
        ja umb_stage_bad
        cmp di,0fffeh
        ja umb_stage_bad
        call xms_validate_umb
        jc umb_stage_bad
        mov ax,[si]
        cmp ax,bx
        ja umb_stage_bad
        shl ax,1
        shl ax,1
        add ax,2
        mov cx,ax
        add ax,di
        jnc umb_stage_copy
        or ax,ax
        jnz umb_stage_bad
umb_stage_copy:
        cld
        rep movsb
        popa
        popf
        clc
        ret
umb_stage_bad:
        popa
        popf
        stc
        ret
xms_stage_umb endp
