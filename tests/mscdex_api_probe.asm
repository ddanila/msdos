bits 16
org 100h

%macro check_ioctl_input 2
    mov byte [media_buffer], %1
    mov byte [request_header + 2], 3
    mov word [request_header + 3], 0
    mov word [request_header + 14], media_buffer
    mov word [request_header + 16], ds
    push ds
    pop es
    mov bx, request_header
    mov cx, 5
    mov ax, 1510h
    int 2fh
    jc fail
    cmp byte [media_buffer + 1], %2
    jne fail
%endmacro

%macro send_ioctl_output 2
    mov byte [media_buffer], %1
    mov byte [media_buffer + 1], %2
    mov byte [request_header + 2], 12
    mov word [request_header + 3], 0
    mov word [request_header + 14], media_buffer
    mov word [request_header + 16], ds
    push ds
    pop es
    mov bx, request_header
    mov cx, 5
    mov ax, 1510h
    int 2fh
    jc fail
%endmacro

start:
    mov ax, 1500h
    xor bx, bx
    int 2fh
    cmp bx, 2
    jne fail
    cmp cx, 4
    jne fail

    mov bx, 4
    mov ax, 150bh
    int 2fh
    cmp ax, 0adadh
    jne fail
    mov bx, 5
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
    cmp byte [drive_list + 1], 5
    jne fail

    mov bx, device_list
    mov ax, 1501h
    int 2fh
    cmp byte [device_list], 0
    jne fail
    mov ax, [device_list + 1]
    or ax, [device_list + 3]
    jz fail
    cmp byte [device_list + 5], 1
    jne fail
    mov ax, [device_list + 1]
    cmp ax, [device_list + 6]
    jne fail
    mov ax, [device_list + 3]
    cmp ax, [device_list + 8]
    jne fail
    push es
    mov bx, [device_list + 1]
    mov ax, [device_list + 3]
    mov es, ax
    cmp byte [es:bx + 20], 5
    pop es
    jne fail

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
    mov cx, 5
    mov ax, 1510h
    int 2fh
    jc fail
    cmp byte [request_header + 1], 1
    jne fail
    mov byte [request_header + 2], 84h
    mov word [request_header + 3], 0
    mov bx, request_header
    mov cx, 5
    mov ax, 1510h
    int 2fh
    jc fail
    cmp byte [request_header + 1], 1
    jne fail
    mov byte [request_header + 2], 85h
    mov word [request_header + 3], 0
    mov bx, request_header
    mov ax, 1510h
    int 2fh
    jc fail
    mov byte [request_header + 2], 88h
    mov word [request_header + 3], 0
    mov bx, request_header
    mov ax, 1510h
    int 2fh
    jc fail
    ; The same play request must be rejected on subunit zero, proving that
    ; media commands route to the selected drive rather than merely succeed.
    mov byte [request_header + 2], 84h
    mov word [request_header + 3], 0
    mov bx, request_header
    mov cx, 4
    mov ax, 1510h
    int 2fh
    jnc fail
    ; Exercise media-control IOCTL output and input on subunit one.
    mov byte [media_buffer], 0
    mov byte [request_header + 2], 12
    mov word [request_header + 3], 0
    mov word [request_header + 14], media_buffer
    mov word [request_header + 16], ds
    mov bx, request_header
    mov cx, 5
    mov ax, 1510h
    int 2fh
    jc fail
    mov byte [media_buffer], 6
    mov byte [request_header + 2], 3
    mov word [request_header + 3], 0
    mov bx, request_header
    mov ax, 1510h
    int 2fh
    jc fail
    test byte [media_buffer + 2], 8
    jz fail
    mov byte [media_buffer], 5
    mov byte [request_header + 2], 12
    mov word [request_header + 3], 0
    mov bx, request_header
    mov ax, 1510h
    int 2fh
    jc fail
    mov byte [media_buffer], 6
    mov byte [request_header + 2], 3
    mov word [request_header + 3], 0
    mov bx, request_header
    mov ax, 1510h
    int 2fh
    jc fail
    test byte [media_buffer + 2], 8
    jnz fail
    test byte [media_buffer + 1], 10h
    jz fail
    ; Exercise every standard query/control family through the same selected
    ; subunit.  Sentinels prove buffers are returned by the backing driver,
    ; rather than synthesized by MSCDEX.
    check_ioctl_input 1, 11h
    check_ioctl_input 4, 44h
    check_ioctl_input 8, 88h
    check_ioctl_input 9, 99h
    check_ioctl_input 10, 0aah
    check_ioctl_input 11, 0bbh
    check_ioctl_input 12, 0cch
    check_ioctl_input 15, 0ffh
    send_ioctl_output 1, 1
    send_ioctl_output 2, 0
    send_ioctl_output 3, 5ah
    check_ioctl_input 6, 10h
    cmp byte [media_buffer + 3], 1
    jne fail
    cmp byte [media_buffer + 4], 1
    jne fail
    cmp byte [media_buffer + 5], 5ah
    jne fail
    send_ioctl_output 1, 0
    mov word [request_header + 3], 0
    mov byte [request_header + 2], 3
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
    push ds
    pop si
    mov bx, root_file_path
    mov di, directory_record
    mov cx, 4
    mov ax, 150fh
    int 2fh
    jc fail
    cmp ax, 1
    jne fail
    cmp word [directory_record + 2], 30
    jne fail
    cmp byte [directory_record + 32], 12
    jne fail
    mov bx, versioned_file_path
    mov di, directory_record
    mov ax, 150fh
    int 2fh
    jc fail
    cmp word [directory_record + 2], 30
    jne fail
    mov bx, nested_file_path
    mov di, directory_record
    mov ax, 150fh
    int 2fh
    jc fail
    cmp word [directory_record + 2], 31
    jne fail
    mov bx, missing_path
    mov ax, 150fh
    int 2fh
    jnc fail
    cmp ax, 2
    jne fail
    mov bx, root_path
    mov ax, 150fh
    int 2fh
    jc fail
    cmp word [directory_record + 2], 20
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
    or ax, ax
    jne fail
    mov dx, 2
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
    mov cx,4
    mov ax, 1503h
    int 2fh
    jc fail
    mov si, name_buffer
    mov di, abstract_name
    mov cx, abstract_end - abstract_name
    repe cmpsb
    jne fail
    mov bx, name_buffer
    mov cx,4
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
    push ds
    pop es
    push ds
    pop si
    mov bx, supplementary_path
    mov di, directory_record
    mov cx, 4
    mov ax, 150fh
    int 2fh
    jc fail
    cmp word [directory_record + 2], 32
    jne fail
    mov bx, 1
    mov dx, 0100h
    mov ax, 150eh
    int 2fh
    jc fail
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

    ; Disable READ LONG in the backing driver.  Repeating a warmed lookup
    ; must still succeed from MSCDEX's /M resident sector buffers.
    mov byte [request_header + 2], 0feh
    mov word [request_header + 3], 0
    push ds
    pop es
    mov bx, request_header
    mov cx, 4
    mov ax, 1510h
    int 2fh
    jc fail
    push ds
    pop es
    push ds
    pop si
    mov bx, root_file_path
    mov di, directory_record
    mov cx, 4
    mov ax, 150fh
    int 2fh
    jc fail
    cmp word [directory_record + 2], 30
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
request_header db 32,0,13
               dw 0
               times 8 db 0
               db 0
               times 18 db 0
sector_buffer times 2048 db 0
media_buffer times 8 db 0
name_buffer times 38 db 0
copyright_name db 'COPY.TXT;1',0
copyright_end:
abstract_name db 'ABSTRACT.TXT;1',0
abstract_end:
biblio_name db 'BIBLIO.TXT;1',0
biblio_end:
root_file_path db '\README.TXT',0
versioned_file_path db '\readme.txt;1',0
nested_file_path db '\DOCS\INNER.TXT',0
supplementary_path db '\JPN.TXT',0
missing_path db '\MISSING.TXT',0
root_path db '\',0
directory_record times 255 db 0
pass_message db 'MSCDEX_API_PASS',13,10,'$'
fail_message db 'MSCDEX_API_FAIL',13,10,'$'
