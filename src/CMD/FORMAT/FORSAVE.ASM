        .286

data    segment public para 'DATA'
        extrn   PSP_Segment:word

mirror_path    db 128 dup (0)
mirror_drive   db 'A'
prior_drive    db 0
exec_block     dw 0
               dw 80h, 0
               dw 5ch, 0
               dw 6ch, 0
data    ends

code    segment public para 'CODE'
        assume  cs:code, ds:data
        public  Format_Save

; AL = zero-based target drive. Return AX=0 when no prior filesystem exists
; or MIRROR commits successfully; AX=1 on a required snapshot failure.
Format_Save proc near
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        cld

        xor     ah, ah
        push    ax
        mov     dl, al
        inc     dl
        mov     ah, 36h
        int     21h
        cmp     ax, 0ffffh
        pop     ax
        je      save_not_needed

        mov     mirror_drive, al
        add     mirror_drive, 'A'
        mov     es, PSP_Segment
        mov     es, es:[2ch]
        xor     si, si
save_find_environment_end:
        cmp     word ptr es:[si], 0
        je      short save_environment_end
        inc     si
        jmp     short save_find_environment_end
save_environment_end:
        add     si, 4
        mov     di, offset mirror_path
        mov     bx, di
save_copy_program_path:
        mov     al, es:[si]
        inc     si
        mov     [di], al
        inc     di
        cmp     al, '\'
        je      short save_mark_basename
        cmp     al, '/'
        je      short save_mark_basename
        cmp     al, ':'
        jne     short save_path_character
save_mark_basename:
        mov     bx, di
save_path_character:
        or      al, al
        jnz     short save_copy_program_path

        mov     di, bx
        mov     byte ptr [di+0], 'M'
        mov     byte ptr [di+1], 'I'
        mov     byte ptr [di+2], 'R'
        mov     byte ptr [di+3], 'R'
        mov     byte ptr [di+4], 'O'
        mov     byte ptr [di+5], 'R'
        mov     byte ptr [di+6], '.'
        mov     byte ptr [di+7], 'C'
        mov     byte ptr [di+8], 'O'
        mov     byte ptr [di+9], 'M'
        mov     byte ptr [di+10], 0

        mov     ax, PSP_Segment
        mov     es, ax
        mov     byte ptr es:[80h], 3
        mov     byte ptr es:[81h], ' '
        mov     dl, mirror_drive
        mov     byte ptr es:[82h], dl
        mov     byte ptr es:[83h], ':'
        mov     byte ptr es:[84h], 13
        mov     exec_block+4, ax
        mov     exec_block+8, ax
        mov     exec_block+12, ax
        mov     ah, 19h
        int     21h
        mov     prior_drive, al
        mov     dl, mirror_drive
        sub     dl, 'A'
        mov     ah, 0eh
        int     21h
        mov     dx, offset mirror_path
        mov     bx, offset exec_block
        mov     ax, 4b00h
        int     21h
        pushf
        push    ax
        mov     dl, prior_drive
        mov     ah, 0eh
        int     21h
        pop     ax
        popf
        jc      short save_failed
        mov     ah, 4dh
        int     21h
        or      al, al
        jnz     short save_failed
save_not_needed:
        xor     ax, ax
        jmp     short save_done
save_failed:
        mov     ax, 1
save_done:
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        ret
Format_Save endp

code    ends
        end
