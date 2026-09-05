bits 16
org 100h


%macro fail_unless_zero 1
    or al, al
    jz %%ok
    mov dx, fail_%1
    jmp fail
%%ok:
%endmacro

start:
    push cs
    pop ds
    push ds
    pop es

    ; Leave allocation space for resident services such as SHARE.
    mov sp, program_end
    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h
    jnc .resized
    mov dx, fail_resize
    jmp fail
.resized:
%ifdef REQUIRE_SHARE
    mov ax, 1000h
    int 2fh
    cmp al, 0ffh
    je .share_present
    mov dx, fail_share_missing
    jmp fail
.share_present:
%endif

    mov si, 18h
    mov di, initial_jfn_table
    mov cx, 20
    rep movsb

    mov dx, io_dta
    mov ah, 1ah
    int 21h

    mov dx, file_fcb
    mov ah, 16h
    int 21h
    fail_unless_zero 16
    call check_jfn_table
    jne jfn_failed
    cmp word [file_fcb + 14], 128
    je record_size_ok
    mov dx, fail_record_size
    jmp fail
record_size_ok:

    mov si, initial_record
    mov di, io_dta
    mov cx, 64
    rep movsw
    mov dx, file_fcb
    mov ah, 15h
    int 21h
    fail_unless_zero 15

    mov dx, file_fcb
    mov ah, 10h
    int 21h
    fail_unless_zero 10
    call check_jfn_table
    jne jfn_failed

    mov dx, file_fcb
    mov ah, 0fh
    int 21h
    fail_unless_zero 0f
    call check_jfn_table
    jne jfn_failed

    mov word [file_fcb + 12], 0
    mov byte [file_fcb + 32], 0

    mov di, io_dta
    mov cx, 64
    xor ax, ax
    rep stosw
    mov dx, file_fcb
    mov ah, 14h
    int 21h
    fail_unless_zero 14
    cmp byte [io_dta], 'S'
    je sequential_data_ok
    mov dx, fail_14
    jmp fail
sequential_data_ok:

    mov dx, file_fcb
    mov ah, 23h
    int 21h
    fail_unless_zero 23
    cmp byte [file_fcb + 33], 1
    je length_ok
    mov dx, fail_23
    jmp fail
length_ok:

    mov dx, file_fcb
    mov ah, 24h
    int 21h
    cmp byte [file_fcb + 33], 1
    je position_ok
    mov dx, fail_24
    jmp fail
position_ok:

    mov byte [file_fcb + 33], 0
    mov byte [file_fcb + 34], 0
    mov byte [file_fcb + 35], 0
    mov dx, file_fcb
    mov ah, 21h
    int 21h
    fail_unless_zero 21
    cmp byte [io_dta], 'S'
    je random_read_ok
    mov dx, fail_21
    jmp fail
random_read_ok:

    mov byte [io_dta], 'R'
    mov byte [file_fcb + 33], 0
    mov byte [file_fcb + 34], 0
    mov byte [file_fcb + 35], 0
    mov dx, file_fcb
    mov ah, 22h
    int 21h
    fail_unless_zero 22

    mov byte [io_dta], 0
    mov byte [file_fcb + 33], 0
    mov byte [file_fcb + 34], 0
    mov byte [file_fcb + 35], 0
    mov cx, 1
    mov dx, file_fcb
    mov ah, 27h
    int 21h
    fail_unless_zero 27
    cmp cx, 1
    jne block_read_failed
    cmp byte [io_dta], 'R'
    je block_read_ok
block_read_failed:
    mov dx, fail_27
    jmp fail
block_read_ok:

    mov byte [io_dta], 'B'
    mov byte [file_fcb + 33], 0
    mov byte [file_fcb + 34], 0
    mov byte [file_fcb + 35], 0
    mov cx, 1
    mov dx, file_fcb
    mov ah, 28h
    int 21h
    fail_unless_zero 28
    cmp cx, 1
    je block_write_ok
    mov dx, fail_28
    jmp fail
block_write_ok:

    mov dx, file_fcb
    mov ah, 10h
    int 21h
    fail_unless_zero 10
    call check_jfn_table
    jne jfn_failed

    mov dx, rename_fcb
    mov ah, 17h
    int 21h
    fail_unless_zero 17

    mov dx, search_dta
    mov ah, 1ah
    int 21h
    mov dx, wildcard_fcb
    mov ah, 11h
    int 21h
    fail_unless_zero 11
    mov dx, wildcard_fcb
    mov ah, 12h
    int 21h
    cmp al, 0ffh
    je find_next_done
    mov dx, fail_12
    jmp fail
find_next_done:

    mov dx, renamed_fcb
    mov ah, 13h
    int 21h
    fail_unless_zero 13

    push ds
    pop es
    mov si, parse_text
    mov di, parsed_fcb
    xor al, al
    mov ah, 29h
    int 21h
    fail_unless_zero 29
    cmp byte [parsed_fcb + 1], 'I'
    jne parse_failed
    cmp byte [parsed_fcb + 9], 'D'
    jne parse_failed
    cmp byte [si], ' '
    je parse_ok
parse_failed:
    mov dx, fail_29
    jmp fail
parse_ok:

    call check_jfn_table
    jne jfn_failed

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
%ifndef NO_DEBUG_EXIT
    out dx, ax
%endif
    mov ax, 4c00h
    int 21h

jfn_failed:
    mov dx, fail_jfn
    jmp fail

check_jfn_table:
    push es
    push si
    push di
    push cx
    push ds
    pop es
    mov si, 18h
    mov di, initial_jfn_table
    mov cx, 20
    repe cmpsb
    pop cx
    pop di
    pop si
    pop es
    ret

fail:
    mov [failure_return], ax
    push dx
    mov ax,5900h
    xor bx,bx
    int 21h
    mov bp,ax
    pop dx
    mov ah, 09h
    int 21h
    mov dx, extended_error_message
    mov ah, 09h
    int 21h
    call print_hex
    mov dx, return_message
    mov ah, 09h
    int 21h
    mov bp, [failure_return]
    call print_hex
    mov dx, newline
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

print_hex:
    mov cx,4
.error_hex:
    push cx
    mov cl,4
    rol bp,cl
    mov dx,bp
    and dl,0fh
    add dl,'0'
    cmp dl,'9'
    jbe .digit
    add dl,7
.digit:
    mov ah,2
    int 21h
    pop cx
    loop .error_hex
    ret

pass_message db 'INT21_FCB_PASS', 13, 10, '$'
fail_resize db 'INT21_FCB_RESIZE_FAIL', 13, 10, '$'
fail_record_size db 'INT21_FCB_RECORD_SIZE_FAIL', 13, 10, '$'
fail_share_missing db 'INT21_FCB_SHARE_MISSING_FAIL', 13, 10, '$'
extended_error_message db 'Extended error: $'
return_message db ' Return AX: $'
failure_return dw 0
newline db 13, 10, '$'
fail_0f     db 'INT21_0F_FAIL', 13, 10, '$'
fail_10     db 'INT21_10_FAIL', 13, 10, '$'
fail_11     db 'INT21_11_FAIL', 13, 10, '$'
fail_12     db 'INT21_12_FAIL', 13, 10, '$'
fail_13     db 'INT21_13_FAIL', 13, 10, '$'
fail_14     db 'INT21_14_FAIL', 13, 10, '$'
fail_15     db 'INT21_15_FAIL', 13, 10, '$'
fail_16     db 'INT21_16_FAIL', 13, 10, '$'
fail_17     db 'INT21_17_FAIL', 13, 10, '$'
fail_21     db 'INT21_21_FAIL', 13, 10, '$'
fail_22     db 'INT21_22_FAIL', 13, 10, '$'
fail_23     db 'INT21_23_FAIL', 13, 10, '$'
fail_24     db 'INT21_24_FAIL', 13, 10, '$'
fail_27     db 'INT21_27_FAIL', 13, 10, '$'
fail_28     db 'INT21_28_FAIL', 13, 10, '$'
fail_29     db 'INT21_29_FAIL', 13, 10, '$'
fail_jfn    db 'INT21_FCB_JFN_CORRUPTION_FAIL', 13, 10, '$'

initial_jfn_table times 20 db 0

file_fcb:
    db 0, 'I21FCB  ', 'DAT'
    times 25 db 0
rename_fcb:
    db 0, 'I21FCB  ', 'DAT'
    times 4 db 0
    db 0, 'I21REN  ', 'DAT'
    times 11 db 0
renamed_fcb:
    db 0, 'I21REN  ', 'DAT'
    times 25 db 0
wildcard_fcb:
    db 0, 'I21?????', 'DAT'
    times 25 db 0
parsed_fcb times 37 db 0
parse_text db 'I21PARSE.DAT tail', 0
initial_record times 128 db 'S'
io_dta times 128 db 0
search_dta times 128 db 0
    times 512 db 0
program_end:
