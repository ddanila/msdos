; Emit the same BIOS copy implementation in the normal resident layout or in
; the authoritative-provider bootstrap tail. Each macro is emitted once.
HIMEM_BIOS_COPY macro
copy_move_next:
        mov     ax, word ptr [move_length]
        mov     dx, word ptr [move_length+2]
        or      ax, dx
        jz      short copy_move_done
        or      dx, dx
        jnz     short copy_move_large
        cmp     ax, 0fffeh
        jbe     short copy_move_final
copy_move_large:
        mov     cx, 0fffeh
        jmp     short copy_move_chunk
copy_move_final:
        mov     cx, ax
copy_move_chunk:
        mov     ax, word ptr [move_source]
        mov     dx, word ptr [move_source+2]
        mov     di, offset move_source_desc
        call    set_move_descriptor
        mov     ax, word ptr [move_dest]
        mov     dx, word ptr [move_dest+2]
        mov     di, offset move_dest_desc
        call    set_move_descriptor
        push    cx
        shr     cx, 1
        push    ds
        push    si
        push    cs
        pop     es
        mov     si, offset move_gdt
        mov     ah, 087h
        int     015h
        pop     si
        pop     ds
        pop     cx
        jc      short copy_move_fail
        add     word ptr [move_source], cx
        adc     word ptr [move_source+2], 0
        add     word ptr [move_dest], cx
        adc     word ptr [move_dest+2], 0
        sub     word ptr [move_length], cx
        sbb     word ptr [move_length+2], 0
        jmp     short copy_move_next
copy_move_done:
        clc
        ret
copy_move_fail:
        stc
        ret
endm

HIMEM_BIOS_DESCRIPTOR macro
; DX:AX=linear base, DI=descriptor. The BIOS move service uses 16-bit limits.
set_move_descriptor proc near
        mov     word ptr [di], 0ffffh
        mov     word ptr [di+2], ax
        mov     byte ptr [di+4], dl
        mov     byte ptr [di+5], 093h
        mov     byte ptr [di+6], 0
        mov     byte ptr [di+7], dh
        ret
set_move_descriptor endp
endm

HIMEM_BIOS_GDT macro
        align   2
move_gdt:
        dq      0
        dq      0
move_source_desc:
        dq      0
move_dest_desc:
        dq      0
        dq      0
        dq      0
endm
