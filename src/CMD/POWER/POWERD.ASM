; DOS 6 POWER.EXE installable driver. The command-side POWER.COM controls this
; resident through the repository's E8xx multiplex contract.

CODE SEGMENT PUBLIC
        ORG     0
        ASSUME  CS:CODE,DS:NOTHING,ES:NOTHING,SS:NOTHING

MODE_OFF        EQU     0
MODE_STD        EQU     1
MODE_ADV_MIN    EQU     2
MODE_ADV_REG    EQU     3
MODE_ADV_MAX    EQU     4

device_header:
        dw      0ffffh,0ffffh
        dw      8000h
        dw      strategy
        dw      interrupt
        db      'POWER$  '

request_ptr     dd      0
old_int2f       dd      0
old_int28       dd      0
power_mode      db      MODE_ADV_REG
apm_available   db      0
idle_divider    db      0
idle_calls      dw      0
halt_calls      dw      0
apm_calls       dw      0

strategy PROC FAR
        mov     word ptr cs:request_ptr,bx
        mov     word ptr cs:request_ptr+2,es
        ret
strategy ENDP

interrupt PROC FAR
        push    ax
        push    bx
        push    dx
        push    ds
        push    es
        lds     bx,cs:request_ptr
        cmp     byte ptr [bx+2],0
        jne     unsupported

        mov     ax,352fh
        int     21h
        mov     word ptr cs:old_int2f,bx
        mov     word ptr cs:old_int2f+2,es
        mov     ax,3528h
        int     21h
        mov     word ptr cs:old_int28,bx
        mov     word ptr cs:old_int28+2,es

        mov     ax,5300h                ; APM installation check
        xor     bx,bx
        int     15h
        jc      short no_apm
        cmp     bx,504dh                ; 'PM'
        jne     short no_apm
        mov     byte ptr cs:apm_available,1
        mov     ax,5301h                ; connect real-mode interface
        xor     bx,bx
        int     15h
no_apm:
        push    ds
        push    cs
        pop     ds
        mov     dx,OFFSET multiplex_handler
        mov     ax,252fh
        int     21h
        mov     dx,OFFSET idle_handler
        mov     ax,2528h
        int     21h
        pop     ds

        lds     bx,cs:request_ptr
        mov     word ptr [bx+14],OFFSET resident_end
        mov     word ptr [bx+16],cs
        mov     word ptr [bx+3],0100h
        jmp     short interrupt_done
unsupported:
        mov     word ptr [bx+3],8103h
interrupt_done:
        pop     es
        pop     ds
        pop     dx
        pop     bx
        pop     ax
        ret
interrupt ENDP

multiplex_handler PROC FAR
        cmp     ax,0e800h
        je      short multiplex_query
        cmp     ax,0e801h
        je      short multiplex_set
        jmp     dword ptr cs:old_int2f
multiplex_query:
        mov     ax,0e8ffh
        xor     bx,bx
        mov     bl,cs:power_mode
        mov     bh,cs:apm_available
        mov     cx,cs:idle_calls
        mov     dx,cs:halt_calls
        mov     si,cs:apm_calls
        mov     di,5057h                ; 'WP', POWER contract signature
        iret
multiplex_set:
        cmp     bl,MODE_ADV_MAX
        ja      short multiplex_bad
        mov     cs:power_mode,bl
        mov     ax,0e8ffh
        xor     bh,bh
        iret
multiplex_bad:
        xor     ax,ax
        mov     bh,1
        iret
multiplex_handler ENDP

idle_handler PROC FAR
        pushf
        call    dword ptr cs:old_int28
        push    ax
        push    bx
        push    ds
        push    cs
        pop     ds
        inc     idle_calls
        mov     al,power_mode
        or      al,al
        jz      short idle_done
        cmp     al,MODE_STD
        jne     short idle_advanced
        cmp     apm_available,0
        je      short idle_done
        mov     ax,5305h                ; APM CPU-idle notification
        xor     bx,bx
        int     15h
        inc     apm_calls
        jmp     short idle_done
idle_advanced:
        inc     idle_divider
        cmp     al,MODE_ADV_MAX
        je      short idle_halt
        cmp     al,MODE_ADV_REG
        jne     short idle_min
        test    idle_divider,1
        jnz     short idle_done
        jmp     short idle_halt
idle_min:
        test    idle_divider,7
        jnz     short idle_done
idle_halt:
        inc     halt_calls
        sti
        hlt
idle_done:
        pop     ds
        pop     bx
        pop     ax
        iret
idle_handler ENDP

resident_end LABEL BYTE
CODE ENDS
        END
