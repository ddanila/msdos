; XMS discovery and status queries for MSD.

        .model  small,c
        .386

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

        public  MsdCpuClass
; Return the processor generation without executing a 386-only instruction
; until the FLAGS behavior has proved that the processor is at least a 386.
; The result is the familiar x86 model number used by the report (86, 286,
; 386, or 486; later processors intentionally report as 486-class).
MsdCpuClass proc near
        push    bx
        push    cx
        pushf
        pop     bx

        mov     ax, bx
        and     ax, 0fffh
        push    ax
        popf
        pushf
        pop     ax
        and     ax, 0f000h
        cmp     ax, 0f000h
        jne     short cpu_at_least_286
        mov     ax, 86
        jmp     short cpu_restore

cpu_at_least_286:
        mov     ax, bx
        or      ax, 0f000h
        push    ax
        popf
        pushf
        pop     ax
        and     ax, 0f000h
        jnz     short cpu_at_least_386
        mov     ax, 286
        jmp     short cpu_restore

cpu_at_least_386:
        ; The AC bit (EFLAGS bit 18) is immutable on a 386 and writable on a
        ; 486 or later. Save and restore the complete flags value around it.
        pushfd
        pop     eax
        mov     ecx, eax
        xor     eax, 00040000h
        push    eax
        popfd
        pushfd
        pop     eax
        xor     eax, ecx
        and     eax, 00040000h
        mov     ax, 386
        jz      short cpu_restore32
        mov     ax, 486
cpu_restore32:
        push    ecx
        popfd
        jmp     short cpu_done

cpu_restore:
        push    bx
        popf
cpu_done:
        pop     cx
        pop     bx
        ret
MsdCpuClass endp

        end
