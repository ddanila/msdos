; XMS discovery and status queries for MSD.

        .286
        .model  small,c

        .data
        public  MsdXmsVersion, MsdXmsDriverVersion, MsdXmsHma, MsdXmsA20
        public  MsdXmsLargestFree, MsdXmsTotalFree
MsdXmsVersion       dw      0
MsdXmsDriverVersion dw      0
MsdXmsHma           dw      0
MsdXmsA20           dw      0
MsdXmsLargestFree   dw      0
MsdXmsTotalFree     dw      0

        .code
        public  MsdReadXmsInfo
MsdReadXmsInfo proc near
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
        mov     MsdXmsVersion, ax
        mov     MsdXmsDriverVersion, bx
        mov     MsdXmsHma, dx
        mov     ah, 07h
        call    dword ptr cs:[xms_entry]
        mov     MsdXmsA20, ax
        mov     ah, 08h
        call    dword ptr cs:[xms_entry]
        mov     MsdXmsLargestFree, ax
        mov     MsdXmsTotalFree, dx
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
MsdReadXmsInfo endp

        end
