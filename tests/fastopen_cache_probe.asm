bits 16
org 100h

start:
    push cs
    pop ds
    push cs
    pop es

    cmp byte [80h], 2
    jb failed
    mov al, [82h]
    and al, 0dfh
    cmp al, 'B'
    je check_before
    cmp al, 'P'
    jne failed

    call query_installed
    jnc failed_post_query

    mov dx, original_file
    call verify_file
    jc failed_initial_read

    mov dx, original_dir
    mov di, renamed_dir
    mov ah, 56h
    int 21h
    jc failed_rename

    mov dx, original_file
    mov ax, 3d00h
    int 21h
    jnc failed_stale_open
    cmp ax, 3
    jne failed_stale_error

    mov dx, renamed_file
    call verify_file
    jc failed_renamed_read

    mov dx, renamed_dir
    mov di, original_dir
    mov ah, 56h
    int 21h
    jc failed_rename_back

    mov dx, original_file
    call verify_file
    jc failed_final_read
    jmp passed

check_before:
    call query_installed
    jc failed
    mov dx, level1_dir
    mov ah, 39h
    int 21h
    jc failed
    mov dx, original_dir
    mov ah, 39h
    int 21h
    jc failed
    mov dx, original_file
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc failed
    mov bx, ax
    mov cx, payload_size
    mov dx, payload
    mov ah, 40h
    int 21h
    jc failed_close
    cmp ax, payload_size
    jne failed_close
    mov ah, 3eh
    int 21h
    jc failed
    mov dx, original_file
    call verify_file
    jc failed

passed:
    mov ax, 4c00h
    int 21h

query_installed:
    push ds
    push es
    mov ax, 122ah
    mov bx, 1
    mov si, -1
    int 2fh
    pushf
    pop bp
    pop es
    pop ds
    push bp
    popf
    ret

verify_file:
    mov ax, 3d00h
    int 21h
    jc verify_done
    mov bx, ax
    mov cx, payload_size
    mov dx, buffer
    mov ah, 3fh
    int 21h
    jc verify_close_error
    cmp ax, payload_size
    jne verify_close_error
    mov si, payload
    mov di, buffer
    mov cx, payload_size
    repe cmpsb
    jne verify_close_error
    mov ah, 3eh
    int 21h
    ret

verify_close_error:
    mov ah, 3eh
    int 21h
    stc
verify_done:
    ret

failed_close:
    mov bx, ax
    mov ah, 3eh
    int 21h
failed:
    mov ax, 4c01h
    int 21h

failed_post_query:
    mov ax, 4c02h
    int 21h
failed_initial_read:
    mov ax, 4c03h
    int 21h
failed_rename:
    mov ax, 4c04h
    int 21h
failed_stale_open:
    mov bx, ax
    mov ah, 3eh
    int 21h
    mov ax, 4c05h
    int 21h
failed_stale_error:
    mov ax, 4c06h
    int 21h
failed_renamed_read:
    mov ax, 4c07h
    int 21h
failed_rename_back:
    mov ax, 4c08h
    int 21h
failed_final_read:
    mov ax, 4c09h
    int 21h

original_dir  db 'C:\LEVEL1\LEVEL2', 0
level1_dir    db 'C:\LEVEL1', 0
renamed_dir   db 'C:\LEVEL1\RENAMED', 0
original_file db 'C:\LEVEL1\LEVEL2\PAYLOAD.TXT', 0
renamed_file  db 'C:\LEVEL1\RENAMED\PAYLOAD.TXT', 0
payload       db 'FASTOPEN_CACHE_PAYLOAD'
payload_size  equ $ - payload
buffer        times payload_size db 0
