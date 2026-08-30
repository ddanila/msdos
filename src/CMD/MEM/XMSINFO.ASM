; Standard XMS discovery used by MEM's DOS 6 reports.

        .286
        .model  small,c

        .data
        public  XmsVersion, XmsDriverVersion, XmsLargestFree, XmsTotalFree
XmsVersion       dw      0
XmsDriverVersion dw      0
XmsLargestFree   dw      0
XmsTotalFree     dw      0

        .code
        public  ReadXmsInfo
ReadXmsInfo proc near
        push    bx
        push    dx
        push    es
        mov     ax, 04300h
        int     02fh
        cmp     al, 080h
        jne     short xms_missing
        mov     ax, 04310h
        int     02fh
        mov     word ptr cs:[xms_entry], bx
        mov     word ptr cs:[xms_entry+2], es
        xor     ah, ah
        call    dword ptr cs:[xms_entry]
        mov     XmsVersion, ax
        mov     XmsDriverVersion, bx
        mov     ah, 08h
        call    dword ptr cs:[xms_entry]
        mov     XmsLargestFree, ax
        mov     XmsTotalFree, dx
        mov     ax, 1
        jmp     short xms_info_done
xms_missing:
        xor     ax, ax
xms_info_done:
        pop     es
        pop     dx
        pop     bx
        ret
xms_entry dd 0
ReadXmsInfo endp

        end
