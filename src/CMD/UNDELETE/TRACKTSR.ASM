        .model  small, c
        .286

MUX_QUERY_ID    equ     0d500h
MUX_REMOVE_ID   equ     0d501h
MUX_REPLY_ID    equ     0d5ffh

        .data
resident_stack  db      2048 dup (?)
resident_top    label   byte

        .code
        extrn   tracker_capture_far:near
        extrn   tracker_capture_fcb:near
        public  tracker_install
        public  tracker_probe
        public  tracker_remove
        public  tracker_keep_paragraphs

old_21          dd      0
old_2f          dd      0
resident_psp    dw      0
busy            db      0
path_offset     dw      0
path_segment    dw      0
saved_ss        dw      0
saved_sp        dw      0
delete_function db      0

tracker_hook proc far
        cmp     ah, 41h
        je      hook_candidate
        cmp     ah, 13h
        jne     hook_chain
hook_candidate:
        cmp     cs:busy, 0
        jne     hook_chain
        mov     cs:busy, 1
        mov     cs:path_offset, dx
        mov     cs:path_segment, ds
        mov     cs:delete_function, ah
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     cs:saved_ss, ss
        mov     cs:saved_sp, sp
        cli
        mov     ax, @data
        mov     ss, ax
        mov     sp, offset resident_top
        sti
        mov     ds, ax
        push    cs:path_segment
        push    cs:path_offset
        cmp     cs:delete_function, 13h
        jne     capture_handle
        call    tracker_capture_fcb
        jmp     short capture_done
capture_handle:
        call    tracker_capture_far
capture_done:
        add     sp, 4
        cli
        mov     ax, cs:saved_ss
        mov     ss, ax
        mov     sp, cs:saved_sp
        sti
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        mov     cs:busy, 0
hook_chain:
        jmp     dword ptr cs:old_21
tracker_hook endp

tracker_mux proc far
        cmp     ax, MUX_QUERY_ID
        je      mux_query
        cmp     ax, MUX_REMOVE_ID
        je      mux_remove
        jmp     dword ptr cs:old_2f
mux_query:
        mov     ax, MUX_REPLY_ID
        mov     bx, cs:resident_psp
        iret
mux_remove:
        push    ds
        push    es
        push    dx
        xor     dx, dx
        mov     es, dx
        cmp     word ptr es:[21h*4], offset tracker_hook
        jne     remove_fail
        mov     dx, cs
        cmp     word ptr es:[21h*4+2], dx
        jne     remove_fail
        cmp     word ptr es:[2fh*4], offset tracker_mux
        jne     remove_fail
        cmp     word ptr es:[2fh*4+2], dx
        jne     remove_fail
        cli
        mov     dx, word ptr cs:old_21
        mov     word ptr es:[21h*4], dx
        mov     dx, word ptr cs:old_21+2
        mov     word ptr es:[21h*4+2], dx
        mov     dx, word ptr cs:old_2f
        mov     word ptr es:[2fh*4], dx
        mov     dx, word ptr cs:old_2f+2
        mov     word ptr es:[2fh*4+2], dx
        sti
        pop     dx
        pop     es
        pop     ds
        mov     ax, MUX_REPLY_ID
        mov     bx, cs:resident_psp
        iret
remove_fail:
        pop     dx
        pop     es
        pop     ds
        xor     ax, ax
        iret
tracker_mux endp

tracker_probe proc near
        mov     ax, MUX_QUERY_ID
        int     2fh
        cmp     ax, MUX_REPLY_ID
        jne     probe_no
        mov     ax, 1
        ret
probe_no:
        xor     ax, ax
        ret
tracker_probe endp

tracker_remove proc near
        mov     ax, MUX_REMOVE_ID
        int     2fh
        cmp     ax, MUX_REPLY_ID
        jne     remove_no
        mov     ax, bx
        ret
remove_no:
        xor     ax, ax
        ret
tracker_remove endp

tracker_install proc near
        mov     ah, 62h
        int     21h
        mov     cs:resident_psp, bx
        mov     ax, 3521h
        int     21h
        mov     word ptr cs:old_21, bx
        mov     word ptr cs:old_21+2, es
        mov     ax, 352fh
        int     21h
        mov     word ptr cs:old_2f, bx
        mov     word ptr cs:old_2f+2, es
        push    ds
        push    cs
        pop     ds
        mov     dx, offset tracker_hook
        mov     ax, 2521h
        int     21h
        mov     dx, offset tracker_mux
        mov     ax, 252fh
        int     21h
        pop     ds
        ret
tracker_install endp

tracker_keep_paragraphs proc near
        mov     ax, ss
        sub     ax, cs:resident_psp
        mov     dx, sp
        add     dx, 15
        mov     cl, 4
        shr     dx, cl
        add     ax, dx
        ret
tracker_keep_paragraphs endp

        end
