bits 16
org 100h

start:
    mov ax, 1500h
    xor bx, bx
    int 2fh
    cmp bx, 1
    jne fail
    cmp cx, 4
    jne fail

    mov bx, 4
    mov ax, 150bh
    int 2fh
    cmp ax, 0adadh
    jne fail
    mov bx, 3
    mov ax, 150bh
    int 2fh
    or ax, ax
    jne fail

    mov ax, 150ch
    int 2fh
    cmp bx, 0217h
    jne fail

    push ds
    pop es
    mov bx, drive_list
    mov ax, 150dh
    int 2fh
    cmp byte [drive_list], 4
    jne fail

    mov bx, device_list
    mov ax, 1501h
    int 2fh
    cmp byte [device_list], 0
    jne fail
    mov ax, [device_list + 1]
    or ax, [device_list + 3]
    jz fail

    push ds
    pop es
    mov bx, request_header
    mov cx, 4
    mov ax, 1510h
    int 2fh
    cmp word [request_header + 3], 0100h
    jne fail
    cmp byte [request_header + 0dh], 0a5h
    jne fail
    cmp byte [request_header + 1], 0
    jne fail
    mov word [request_header + 3], 0
    mov bx, request_header
    mov cx, 3
    mov ax, 1510h
    int 2fh
    cmp word [request_header + 3], 810fh
    jne fail

    push ds
    pop es
    mov bx, sector_buffer
    mov cx, 4
    mov dx, 1
    mov si, 1234h
    mov di, 5678h
    mov ax, 1508h
    int 2fh
    jc fail
    cmp word [sector_buffer], 'CD'
    jne fail
    cmp word [sector_buffer + 2], '22'
    jne fail
    mov cx, 3
    mov ax, 1508h
    int 2fh
    jnc fail
    cmp ax, 000fh
    jne fail

    push ds
    pop es
    mov bx, sector_buffer
    mov cx, 4
    xor dx, dx
    mov ax, 1505h
    int 2fh
    jc fail
    cmp ax, 1
    jne fail
    cmp word [sector_buffer + 1], 'CD'
    jne fail
    mov dx, 1
    mov ax, 1505h
    int 2fh
    jc fail
    cmp ax, 0ffh
    jne fail

    mov bx, name_buffer
    mov cx, 4
    mov ax, 1502h
    int 2fh
    jc fail
    mov si, name_buffer
    mov di, copyright_name
    mov cx, copyright_end - copyright_name
    repe cmpsb
    jne fail
    mov bx, name_buffer
    mov ax, 1503h
    int 2fh
    jc fail
    mov si, name_buffer
    mov di, abstract_name
    mov cx, abstract_end - abstract_name
    repe cmpsb
    jne fail
    mov bx, name_buffer
    mov ax, 1504h
    int 2fh
    jc fail
    mov si, name_buffer
    mov di, biblio_name
    mov cx, biblio_end - biblio_name
    repe cmpsb
    jne fail

    mov ax, 1506h
    int 2fh
    jc fail
    or ax, ax
    jne fail
    mov ax, 1507h
    int 2fh
    jc fail

    xor bx, bx
    mov cx, 4
    xor dx, dx
    mov ax, 150eh
    int 2fh
    jc fail
    cmp dx, 0100h
    jne fail
    mov bx, 1
    mov dx, 0201h
    mov ax, 150eh
    int 2fh
    jc fail
    xor bx, bx
    xor dx, dx
    mov ax, 150eh
    int 2fh
    jc fail
    cmp dx, 0201h
    jne fail
    mov bx, 1
    mov dx, 0202h
    mov ax, 150eh
    int 2fh
    jnc fail
    cmp ax, 1
    jne fail
    mov cx, 3
    xor bx, bx
    mov ax, 150eh
    int 2fh
    jnc fail
    cmp ax, 000fh
    jne fail

    mov dx, pass_message
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h

fail:
    mov dx, fail_message
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

drive_list  times 8 db 0ffh
device_list times 40 db 0
request_header db 32,0,3
               dw 0
               times 8 db 0
               db 0
               times 18 db 0
sector_buffer times 2048 db 0
name_buffer times 38 db 0
copyright_name db 'COPY.TXT;1',0
copyright_end:
abstract_name db 'ABSTRACT.TXT;1',0
abstract_end:
biblio_name db 'BIBLIO.TXT;1',0
biblio_end:
pass_message db 'MSCDEX_API_PASS',13,10,'$'
fail_message db 'MSCDEX_API_FAIL',13,10,'$'
