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
old_int10       dd      0
old_int13       dd      0
old_int16       dd      0
old_int21       dd      0
power_mode      db      MODE_ADV_REG
retail_mode_code db     3
apm_available   db      0
idle_divider    db      0
poll_streak     db      0
idle_calls      dw      0
halt_calls      dw      0
apm_calls       dw      0
poll_calls      dw      0
busy_calls      dw      0

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
        mov     ax,3510h
        int     21h
        mov     word ptr cs:old_int10,bx
        mov     word ptr cs:old_int10+2,es
        mov     ax,3513h
        int     21h
        mov     word ptr cs:old_int13,bx
        mov     word ptr cs:old_int13+2,es
        mov     ax,3516h
        int     21h
        mov     word ptr cs:old_int16,bx
        mov     word ptr cs:old_int16+2,es
        mov     ax,3521h
        int     21h
        mov     word ptr cs:old_int21,bx
        mov     word ptr cs:old_int21+2,es

        mov     ax,5300h                ; APM installation check
        xor     bx,bx
        int     15h
        jc      short no_apm
        cmp     bx,504dh                ; 'PM'
        jne     short no_apm
        mov     ax,5301h                ; connect real-mode interface
        xor     bx,bx
        int     15h
        jc      short no_apm
        mov     byte ptr cs:apm_available,1
        call    set_apm_enabled
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
        mov     dx,OFFSET video_handler
        mov     ax,2510h
        int     21h
        mov     dx,OFFSET disk_handler
        mov     ax,2513h
        int     21h
        mov     dx,OFFSET keyboard_handler
        mov     ax,2516h
        int     21h
        mov     dx,OFFSET dos_handler
        mov     ax,2521h
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
        cmp     ax,05400h
        je      retail_install_query
        cmp     ax,05401h
        je      retail_mode
        cmp     ax,05403h
        je      retail_level
        cmp     ax,05481h
        je      retail_statistics
        cmp     ax,0e800h
        je      multiplex_query
        cmp     ax,0e801h
        je      multiplex_set
        cmp     ax,0e803h
        je      multiplex_diagnostics
        jmp     dword ptr cs:old_int2f
retail_install_query:
        mov     ax,0100h
        mov     bx,504dh                ; genuine POWER manager signature
        iret
retail_mode:
        or      bh,bh
        jnz     short retail_mode_set
        xor     bx,bx
        mov     bl,cs:retail_mode_code
        mov     bh,bl
        xor     ax,ax
        iret
retail_mode_set:
        cmp     bh,1
        jne     short retail_mode_bad
        cmp     bl,3
        ja      short retail_mode_bad
        mov     bh,cs:retail_mode_code
        mov     cs:retail_mode_code,bl
        cmp     bl,0
        je      short retail_set_off
        cmp     bl,2
        je      short retail_set_std
        ; Retail modes 1 and 3 are advanced. DL optionally selects the
        ; conservation level returned by function 5403h (5/6/7).
        mov     al,MODE_ADV_REG
        cmp     dl,5
        jne     short retail_check_reg
        mov     al,MODE_ADV_MAX
        jmp     short retail_store_mode
retail_check_reg:
        cmp     dl,7
        jne     short retail_store_mode
        mov     al,MODE_ADV_MIN
        jmp     short retail_store_mode
retail_set_off:
        mov     al,MODE_OFF
        jmp     short retail_store_mode
retail_set_std:
        mov     al,MODE_STD
retail_store_mode:
        mov     cs:power_mode,al
        call    set_apm_enabled
        xor     ax,ax
        iret
retail_mode_bad:
        mov     ax,0087h
        iret
retail_level:
        mov     al,cs:power_mode
        mov     bx,6
        cmp     al,MODE_ADV_MAX
        jne     short retail_level_min
        mov     bx,5
        jmp     short retail_level_done
retail_level_min:
        cmp     al,MODE_ADV_MIN
        jne     short retail_level_done
        mov     bx,7
retail_level_done:
        xor     ax,ax
        iret
retail_statistics:
        cmp     cx,28
        jb      short retail_mode_bad
        push    es
        push    di
        push    cx
        push    ax
        push    ds
        pop     es
        mov     di,si
        xor     ax,ax
        mov     cx,14
        rep     stosw
        mov     word ptr [si],1        ; genuine 6.22 diagnostics block ID
        pop     ax
        pop     cx
        pop     di
        pop     es
        xor     ax,ax
        xor     bx,bx
        iret
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
        mov     byte ptr cs:retail_mode_code,3
        cmp     bl,MODE_OFF
        jne     short multiplex_set_std
        mov     byte ptr cs:retail_mode_code,0
        jmp     short multiplex_set_done
multiplex_set_std:
        cmp     bl,MODE_STD
        jne     short multiplex_set_done
        mov     byte ptr cs:retail_mode_code,2
multiplex_set_done:
        call    set_apm_enabled
        mov     ax,0e8ffh
        xor     bh,bh
        iret
multiplex_bad:
        xor     ax,ax
        mov     bh,1
        iret
multiplex_diagnostics:
        mov     ax,0e8ffh
        mov     bx,cs:poll_calls
        mov     cx,cs:busy_calls
        mov     dx,cs:idle_calls
        mov     si,cs:halt_calls
        mov     di,cs:apm_calls
        iret
multiplex_handler ENDP

set_apm_enabled PROC NEAR
        cmp     cs:apm_available,0
        je      short apm_enable_done
        push    ax
        push    bx
        push    cx
        mov     ax,5308h
        mov     bx,1                   ; all APM-managed devices
        xor     cx,cx
        cmp     cs:power_mode,MODE_OFF
        je      short apm_enable_call
        inc     cx
apm_enable_call:
        int     15h
        pop     cx
        pop     bx
        pop     ax
apm_enable_done:
        ret
set_apm_enabled ENDP

idle_handler PROC FAR
        pushf
        call    dword ptr cs:old_int28
        push    ax
        push    bx
        push    ds
        push    cs
        pop     ds
        call    perform_idle
        pop     ds
        pop     bx
        pop     ax
        iret
idle_handler ENDP

perform_idle PROC NEAR
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
        ret
perform_idle ENDP

keyboard_handler PROC FAR
        cmp     ah,01h
        je      short keyboard_poll
        cmp     ah,11h
        je      short keyboard_poll
        pushf
        mov     byte ptr cs:poll_streak,0
        inc     word ptr cs:busy_calls
        popf
        jmp     dword ptr cs:old_int16
keyboard_poll:
        pushf
        call    dword ptr cs:old_int16
        pushf                          ; retain the BIOS ZF for the caller
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     bp,sp
        test    word ptr ss:[bp+18],0040h
        jz      short keyboard_ready
        push    cs
        pop     ds
        inc     poll_calls
        inc     poll_streak
        mov     al,power_mode
        or      al,al
        jz      short keyboard_poll_done
        mov     ah,16
        cmp     al,MODE_ADV_MAX
        je      short keyboard_threshold
        mov     ah,64
        cmp     al,MODE_ADV_MIN
        je      short keyboard_threshold
keyboard_threshold:
        cmp     poll_streak,ah
        jb      short keyboard_poll_done
        mov     poll_streak,0
        call    perform_idle
        jmp     short keyboard_poll_done
keyboard_ready:
        mov     byte ptr cs:poll_streak,0
        inc     word ptr cs:busy_calls
keyboard_poll_done:
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        popf
        retf    2
keyboard_handler ENDP

video_handler PROC FAR
        pushf
        mov     byte ptr cs:poll_streak,0
        mov     byte ptr cs:idle_divider,0
        inc     word ptr cs:busy_calls
        popf
        jmp     dword ptr cs:old_int10
video_handler ENDP

disk_handler PROC FAR
        pushf
        mov     byte ptr cs:poll_streak,0
        mov     byte ptr cs:idle_divider,0
        inc     word ptr cs:busy_calls
        popf
        jmp     dword ptr cs:old_int13
disk_handler ENDP

dos_handler PROC FAR
        pushf
        mov     byte ptr cs:poll_streak,0
        mov     byte ptr cs:idle_divider,0
        inc     word ptr cs:busy_calls
        popf
        jmp     dword ptr cs:old_int21
dos_handler ENDP

resident_end LABEL BYTE
CODE ENDS
        END
