; Command-side controller for the resident POWER.EXE driver.

CODE SEGMENT PUBLIC
        ORG     100h
        ASSUME  CS:CODE,DS:CODE,ES:NOTHING,SS:CODE

start:
        cld
        mov     si,81h
        xor     cx,cx
        mov     cl,byte ptr ds:[80h]
skip_space:
        or      cx,cx
        jnz     short have_argument_byte
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
        jnz     short not_installed
query:
        xor     bx,bx
        mov     ax,05401h
        int     2fh
        or      ax,ax
        jne     short not_installed
        mov     dx,OFFSET setting_msg
        call    print
        cmp     bl,0
        je      short print_off
        cmp     bl,2
        je      short print_std
        cmp     bl,3
        jne     short not_installed
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
        jmp     short print_done
print_std:
        mov     dx,OFFSET std_text
        jmp     short print_done
print_min:
        mov     dx,OFFSET min_text
        jmp     short print_done
print_reg:
        mov     dx,OFFSET reg_text
        jmp     short print_done
print_max:
        mov     dx,OFFSET max_text
print_done:
        call    print
        mov     ax,4c00h
        int     21h
not_installed:
        mov     dx,OFFSET missing_msg
        call    print
        mov     ax,4c02h
        int     21h
syntax_error:
        mov     dx,OFFSET syntax_msg
        call    print
        mov     ax,4c01h
        int     21h
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

argument        db 16 dup(0)
help_arg        db '/?',0
off_arg         db 'OFF',0
std_arg         db 'STD',0
adv_arg         db 'ADV',0
min_arg         db 'ADV:MIN',0
reg_arg         db 'ADV:REG',0
max_arg         db 'ADV:MAX',0
setting_msg     db 'Power management setting = $'
off_text        db 'OFF',13,10,'$'
std_text        db 'STD',13,10,'$'
min_text        db 'ADV:MIN',13,10,'$'
reg_text        db 'ADV:REG',13,10,'$'
max_text        db 'ADV:MAX',13,10,'$'
missing_msg     db 'POWER.EXE is not installed.',13,10,'$'
syntax_msg      db 'Invalid POWER setting.',13,10,'$'
help_msg        db 'Turns power management on or off and selects conservation.',13,10
                db 'Syntax: POWER [ADV[:MAX|REG|MIN]|STD|OFF]',13,10,'$'
CODE ENDS
        END start
