; Command-side controller for the resident POWER.EXE driver.

CODE SEGMENT PUBLIC
        ORG     100h
        ASSUME  CS:CODE,DS:CODE,ES:NOTHING,SS:CODE

start:
        cld
        push    cs
        pop     es                      ; argument buffer lives with command code
        mov     si,81h
        xor     cx,cx
        mov     cl,byte ptr ds:[80h]
skip_space:
        or      cx,cx
        jnz     short have_argument_byte
        push    cs
        pop     ds
        jmp     query
have_argument_byte:
        lodsb
        dec     cx
        cmp     al,' '
        je      short skip_space
        cmp     al,9
        je      short skip_space
        mov     di,OFFSET argument
copy_arg:
        cmp     al,'a'
        jb      short store_arg
        cmp     al,'z'
        ja      short store_arg
        sub     al,20h
store_arg:
        cmp     di,OFFSET argument+15
        jae     syntax_error
        stosb
        jcxz    short arg_done
        lodsb
        dec     cx
        cmp     al,' '
        je      short trailing
        cmp     al,9
        jne     short copy_arg
trailing:
        jcxz    short arg_done
        lodsb
        dec     cx
        cmp     al,' '
        je      short trailing
        cmp     al,9
        je      short trailing
        jmp     syntax_error
arg_done:
        xor     al,al
        stosb
        push    cs
        pop     ds                      ; switch from PSP to command data
        mov     si,OFFSET argument
        mov     di,OFFSET help_arg
        call    string_equal
        je      show_help
        mov     di,OFFSET off_arg
        call    string_equal
        je      short set_off
        mov     di,OFFSET std_arg
        call    string_equal
        je      short set_std
        mov     di,OFFSET adv_arg
        call    string_equal
        je      short set_reg
        mov     di,OFFSET min_arg
        call    string_equal
        je      short set_min
        mov     di,OFFSET reg_arg
        call    string_equal
        je      short set_reg
        mov     di,OFFSET max_arg
        call    string_equal
        je      short set_max
        jmp     syntax_error
set_off:
        mov     bl,0
        xor     dl,dl
        jmp     short set_mode
set_std:
        mov     bl,2
        xor     dl,dl
        jmp     short set_mode
set_min:
        mov     bl,3
        mov     dl,7
        jmp     short set_mode
set_reg:
        mov     bl,3
        mov     dl,6
        jmp     short set_mode
set_max:
        mov     bl,3
        mov     dl,5
set_mode:
        mov     bh,1
        mov     ax,05401h
        int     2fh
        or      ax,ax
        jnz     not_installed
query:
        xor     bx,bx
        mov     ax,05401h
        int     2fh
        or      ax,ax
        jne     not_installed
        mov     byte ptr cs:current_code,bl
        mov     dx,OFFSET status_msg
        call    print
        cmp     byte ptr cs:current_code,0
        je      short print_off
        cmp     byte ptr cs:current_code,2
        je      short print_std
        cmp     byte ptr cs:current_code,3
        jne     not_installed
        xor     bx,bx
        mov     ax,05403h
        int     2fh
        cmp     bx,5
        je      short print_max
        cmp     bx,7
        je      short print_min
        jmp     short print_reg
print_off:
        mov     dx,OFFSET off_text
        call    print
        jmp     print_done
print_std:
        mov     dx,OFFSET std_text
        call    print
        jmp     short print_power_source
print_min:
        mov     dx,OFFSET min_text
        jmp     short print_advanced
print_reg:
        mov     dx,OFFSET reg_text
        jmp     short print_advanced
print_max:
        mov     dx,OFFSET max_text
print_advanced:
        call    print
        mov     ax,0e803h              ; implementation diagnostics counters
        int     2fh
        mov     bx,dx                  ; idle notifications
        mov     ax,si                  ; actual CPU-idle actions
        or      bx,bx
        jz      short idle_percent_ready
        mov     cx,100
        mul     cx
        div     bx
        cmp     ax,100
        jbe     short idle_percent_ready
        mov     ax,100
idle_percent_ready:
        mov     word ptr cs:current_percent,ax
        mov     dx,OFFSET cpu_idle_msg
        call    print
        mov     ax,word ptr cs:current_percent
        call    print_decimal
        mov     dx,OFFSET percent_msg
        call    print
print_power_source:
        mov     ax,530ah               ; APM get power status
        mov     bx,1
        int     15h
        jc      short source_unknown
        cmp     bh,1
        je      short source_online
        cmp     bh,0
        je      short source_offline
source_unknown:
        mov     dx,OFFSET source_unknown_msg
        jmp     short source_print
source_online:
        mov     dx,OFFSET source_online_msg
        jmp     short source_print
source_offline:
        mov     dx,OFFSET source_offline_msg
source_print:
        call    print
print_done:
        mov     ax,4c00h
        int     21h
not_installed:
        mov     dx,OFFSET missing_msg
        call    print
        mov     ax,4c01h
        int     21h
syntax_error:
        push    cs
        pop     ds
        mov     dx,OFFSET invalid_prefix
        call    print
        mov     si,OFFSET argument
        call    print_z_lower
        mov     dx,OFFSET newline
        call    print
        jmp     query
show_help:
        mov     dx,OFFSET help_msg
        call    print
        mov     ax,4c00h
        int     21h

string_equal PROC NEAR
        push    si
        push    di
compare_next:
        mov     al,[si]
        cmp     al,[di]
        jne     short compare_done
        inc     si
        inc     di
        or      al,al
        jne     short compare_next
compare_done:
        pop     di
        pop     si
        ret
string_equal ENDP
print PROC NEAR
        mov     ah,09h
        int     21h
        ret
print ENDP

print_z_lower PROC NEAR
print_z_next:
        lodsb
        or      al,al
        jz      short print_z_done
        cmp     al,'A'
        jb      short print_z_emit
        cmp     al,'Z'
        ja      short print_z_emit
        add     al,20h
print_z_emit:
        mov     dl,al
        mov     ah,02h
        int     21h
        jmp     short print_z_next
print_z_done:
        ret
print_z_lower ENDP

print_decimal PROC NEAR
        push    ax
        push    bx
        push    cx
        push    dx
        xor     cx,cx
        mov     bx,10
decimal_divide:
        xor     dx,dx
        div     bx
        push    dx
        inc     cx
        or      ax,ax
        jnz     short decimal_divide
decimal_emit:
        pop     dx
        add     dl,'0'
        mov     ah,02h
        int     21h
        loop    decimal_emit
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
print_decimal ENDP

argument        db 16 dup(0)
current_code    db 0
current_percent dw 0
help_arg        db '/?',0
off_arg         db 'OFF',0
std_arg         db 'STD',0
adv_arg         db 'ADV',0
min_arg         db 'ADV:MIN',0
reg_arg         db 'ADV:REG',0
max_arg         db 'ADV:MAX',0
status_msg      db 13,10,'Power Management Status',13,10
                db '-----------------------',13,10,'Setting =  $'
off_text        db 'OFF',13,10,'$'
std_text        db 'STD',13,10,'$'
min_text        db 'ADV: MIN',13,10,'$'
reg_text        db 'ADV: REG',13,10,'$'
max_text        db 'ADV: MAX',13,10,'$'
cpu_idle_msg    db 'CPU: idle $'
percent_msg     db '% of time.',13,10,'$'
source_online_msg db 13,10,'AC Line Status : ONLINE',13,10,'$'
source_offline_msg db 13,10,'AC Line Status : OFFLINE',13,10,'$'
source_unknown_msg db 13,10,'AC Line Status : UNKNOWN',13,10,'$'
missing_msg     db 13,10,'Power Manager (POWER.EXE) not installed.',13,10,'$'
invalid_prefix  db 'Invalid parameter - $'
newline         db 13,10,'$'
help_msg        db 'Reduces power used by your computer.',13,10,13,10
                db 'POWER [ADV[:MAX | REG | MIN] | STD | OFF]',13,10,13,10
                db '  ADV[:MAX | REG | MIN] --  Reduces power by monitoring applications',13,10
                db '      and hardware devices. MAX provides the most power conservation,',13,10
                db '      REG provides average power conservation, and MIN provides the',13,10
                db '      least conservation.',13,10
                db '  STD -- Reduces power by monitoring hardware devices.',13,10
                db '  OFF -- Turns off power management.',13,10,'$'
CODE ENDS

STACKSEG SEGMENT PARA STACK 'STACK'
        db      512 dup(0)
STACKSEG ENDS
        END start
