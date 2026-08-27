bits 16
org 100h

; Focused contracts for the legacy FCB API retained by MS-DOS 4.0.

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

    mov dx, io_dta
    mov ah, 1ah
    int 21h

    mov dx, file_fcb
    mov ah, 16h                    ; Create/truncate through an FCB.
    int 21h
    fail_unless_zero 16
    cmp word [file_fcb + 14], 128
    je record_size_ok
    mov dx, fail_16
    jmp fail
record_size_ok:

    mov si, initial_record
    mov di, io_dta
    mov cx, 64
    rep movsw
    mov dx, file_fcb
    mov ah, 15h                    ; Sequential write of record zero.
    int 21h
    fail_unless_zero 15

    mov dx, file_fcb
    mov ah, 10h
    int 21h
    fail_unless_zero 10

    mov dx, file_fcb
    mov ah, 0fh
    int 21h
    fail_unless_zero 0f

    mov word [file_fcb + 12], 0
    mov byte [file_fcb + 32], 0

    mov di, io_dta
    mov cx, 64
    xor ax, ax
    rep stosw
    mov dx, file_fcb
    mov ah, 14h                    ; Sequential read advances current record.
    int 21h
    fail_unless_zero 14
    cmp byte [io_dta], 'S'
    je sequential_data_ok
    mov dx, fail_14
    jmp fail
sequential_data_ok:

    mov dx, file_fcb
    mov ah, 23h                    ; File length in 128-byte records.
    int 21h
    fail_unless_zero 23
    cmp byte [file_fcb + 33], 1
    je length_ok
    mov dx, fail_23
    jmp fail
length_ok:

    mov dx, file_fcb
    mov ah, 24h                    ; Current block/record becomes random record.
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
    mov ah, 21h                    ; Random read record zero.
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
    mov ah, 22h                    ; Random write record zero.
    int 21h
    fail_unless_zero 22

    mov byte [io_dta], 0
    mov byte [file_fcb + 33], 0
    mov byte [file_fcb + 34], 0
    mov byte [file_fcb + 35], 0
    mov cx, 1
    mov dx, file_fcb
    mov ah, 27h                    ; Random block read of one record.
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
    mov ah, 28h                    ; Random block write of one record.
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
    mov ah, 29h                    ; Parse an 8.3 name and advance SI.
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

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

pass_message db 'INT21_FCB_PASS', 13, 10, '$'
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
