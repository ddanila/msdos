; SETVER.EXE CONFIG.SYS loader.  The command-side SETVER.COM updates the
; embedded table below; initialization copies it into DOS's resident table.

CODE SEGMENT PUBLIC
        ORG     0
        ASSUME  CS:CODE,DS:NOTHING,ES:NOTHING,SS:NOTHING

device_header:
        dw      0ffffh,0ffffh
        dw      8000h                   ; character device
        dw      strategy
        dw      interrupt
        db      'SETVERXX'

request_ptr dd  0

strategy PROC FAR
        mov     word ptr cs:request_ptr,bx
        mov     word ptr cs:request_ptr+2,es
        ret
strategy ENDP

interrupt PROC FAR
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        push    ds
        push    es
        lds     bx,cs:request_ptr
        cmp     byte ptr [bx+2],0       ; initialize request
        jne     unsupported

        mov     ax,1200h
        int     2fh
        cmp     al,0ffh
        jne     init_failed
        mov     ax,1231h
        int     2fh
        cmp     cx,640
        jne     init_failed
        push    cs
        pop     ds
        mov     si,OFFSET version_table
        mov     cx,640
        cld
        rep     movsb

        lds     bx,cs:request_ptr
        mov     word ptr [bx+14],OFFSET resident_end
        mov     word ptr [bx+16],cs
        mov     word ptr [bx+3],0100h
        jmp     short interrupt_done

init_failed:
        lds     bx,cs:request_ptr
        mov     word ptr [bx+14],0
        mov     word ptr [bx+16],cs
        mov     word ptr [bx+3],810Ch
        jmp     short interrupt_done

unsupported:
        mov     word ptr [bx+3],8103h

interrupt_done:
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
        ret
interrupt ENDP

resident_end LABEL BYTE

table_marker db 'SVTAB6',0,1
version_table:
        INCLUDE ..\..\INC\SETVER62.INC
        db      (1024-($-version_table)) dup(0)

CODE ENDS
        END
