bits 16
cpu 8086
org 100h

%ifndef PAGE
%define PAGE 866
%endif
%ifndef COUNTRY
%define COUNTRY 7
%endif

    cld
    push cs
    pop ds
    push cs
    pop es
%ifdef SET_COUNTRY
    mov ax, 38ffh
    mov bx, COUNTRY
    mov dx, -1
    int 21h
    jc fail
%endif
%ifdef QUERY_ONLY
    jmp query_start
%endif
    mov byte [stage], 1
    mov ax, 6601h
    int 21h
    jc fail
    cmp bx, PAGE
    jne fail
    cmp dx, 437
    jne fail

    inc byte [stage]
    mov ax, 3800h
    mov dx, country_buffer
    int 21h
    jc fail
    cmp ax, COUNTRY
    jne fail
    cmp bx, COUNTRY
    jne fail
    mov si, country_buffer
    mov di, expected_info+4
    mov cx, 18
    repe cmpsb
    jne fail
    ; The runtime far-uppercase pointer replaces the four reserved bytes.
    add si, 4
    add di, 4
    mov cx, 12
    repe cmpsb
    jne fail

    inc byte [stage]
    xor bp, bp
.far_upper:
    mov ax, bp
    add al, 80h
    call far [country_buffer+18]
    mov bx, bp
    cmp al, [expected_upper+bx]
    jne fail
    inc bp
    cmp bp, 128
    jb .far_upper

query_start:
    mov byte [stage], 4
    mov ax, 6501h
%ifdef QUERY_ONLY
    mov bx, PAGE
    mov dx, COUNTRY
%else
    mov bx, -1
    mov dx, -1
%endif
    mov cx, 41
    mov di, extended_buffer
    int 21h
    jc fail
    cmp cx, 41
    jne fail
    cmp byte [extended_buffer], 1
    jne fail
    cmp word [extended_buffer+1], 38
    jne fail
    mov si, extended_buffer+3
    mov di, expected_info
    mov cx, 22
    repe cmpsb
    jne fail
    add si, 4
    add di, 4
    mov cx, 12
    repe cmpsb
    jne fail

    inc byte [stage]
    mov ax, 6502h
    mov bp, expected_upper
    mov word [table_length], 128
    call check_table
    jc fail
    inc byte [stage]
    mov ax, 6504h
    mov bp, expected_upper
    call check_table
    jc fail
    inc byte [stage]
    mov ax, 6505h
    mov bp, expected_filelist
    mov word [table_length], 22
    call check_table
    jc fail
    inc byte [stage]
    mov ax, 6506h
    mov bp, expected_collate
    mov word [table_length], 256
    call check_table
    jc fail
    inc byte [stage]
    mov ax, 6507h
    mov bp, expected_filelist
    mov word [table_length], 0
    call check_table
    jc fail

%ifdef QUERY_ONLY
    jmp success
%endif
    inc byte [stage]
    xor si, si
.one_upper:
    mov dx, si
    mov ax, 6520h
    int 21h
    jc fail
    cmp dl, [expected_all+si]
    jne fail
    inc si
    cmp si, 256
    jb .one_upper

    inc byte [stage]
    call fill_input
    mov ax, 6521h
    mov dx, input_buffer
    mov cx, 256
    int 21h
    jc fail
    call check_input
    jc fail

    inc byte [stage]
    call fill_input
    mov ax, 6522h
    mov dx, input_buffer+1 ; exclude initial NUL, stop at trailing NUL
    int 21h
    jc fail
    call check_input
    jc fail

success:
    mov dx, passed
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h

check_table:
    mov [table_kind], al
%ifdef QUERY_ONLY
    mov bx, PAGE
    mov dx, COUNTRY
%else
    mov bx, -1
    mov dx, -1
%endif
    mov cx, 5
    mov di, extended_buffer
    int 21h
    jc .return
    cmp cx, 5
    jne .bad
    mov al, [table_kind]
    cmp al, [extended_buffer]
    jne .bad
    push ds
    lds si, [extended_buffer+1]
    mov cx, [es:table_length]
    cmp [si], cx
    jne .restore_bad
    add si, 2
    mov di, bp
    jcxz .matched
    repe cmpsb
    jne .restore_bad
.matched:
    pop ds
    clc
.return:
    ret
.restore_bad:
    pop ds
.bad:
    stc
    ret

fill_input:
    mov di, input_buffer
    xor ax, ax
    mov cx, 256
.loop:
    stosb
    inc al
    loop .loop
    mov word [di], 5a00h
    ret

check_input:
    mov si, input_buffer
    mov di, expected_all
    mov cx, 256
    repe cmpsb
    jne .bad
    cmp word [input_buffer+256], 5a00h
    jne .bad
    clc
    ret
.bad:
    stc
    ret

fail:
    push cs
    pop ds
    mov dx, failed
    mov ah, 9
    int 21h
    mov al, [stage]
    aam 16
    mov bx, hex_digits
    push ax
    mov al, ah
    xlat
    mov dl, al
    mov ah, 2
    int 21h
    pop ax
    xlat
    mov dl, al
    mov ah, 2
    int 21h
    mov dx, newline
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

%ifdef QUERY_ONLY
passed db 'RU_QUERY_PASS',13,10,'$'
%else
passed db 'RU_COUNTRY_PASS',13,10,'$'
%endif
failed db 'RU_COUNTRY_FAIL stage ','$'
newline db 13,10,'$'
hex_digits db '0123456789ABCDEF'
stage db 0
table_kind db 0
table_length dw 0
country_buffer times 34 db 0
extended_buffer times 64 db 0
input_buffer times 258 db 0
expected_info: incbin 'info.bin'
expected_upper: incbin 'upper.bin'
expected_collate: incbin 'collate.bin'
expected_filelist: incbin 'filelist.bin'
expected_all: incbin 'all-upper.bin'
