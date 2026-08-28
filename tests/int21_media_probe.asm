bits 16
org 100h


%macro require_error 2
    jc %%carried
    mov dx, %2
    jmp finish
%%carried:
    cmp ax, %1
    je %%ok
    mov dx, %2
    jmp finish
%%ok:
%endmacro

start:
    push cs
    pop ds
    push ds
    pop es

    xor cx, cx
    mov dx, cross_source
    mov ah, 3ch
    int 21h
    jc media_failed
    mov bx, ax
    mov ah, 3eh
    int 21h
    jc media_failed
    mov dx, cross_source
    mov di, cross_target
    mov ah, 56h
    int 21h
    require_error 17, rename_failed
    mov dx, cross_source
    mov ah, 41h
    int 21h
    jc media_failed

    mov bl, 26
    mov dx, media_info
    mov ax, 6900h
    int 21h
    require_error 15, media_drive_failed

    mov bl, 2
    mov dx, media_info
    mov ax, 6900h
    int 21h
    jc media_failed
    cmp word [media_info], 0
    jne media_failed

    mov si, test_label
    mov di, media_info + 6
    mov cx, 11
    rep movsb
    mov bl, 2
    mov dx, media_info
    mov ax, 6901h
    int 21h
    jc media_failed
    mov ah, 0dh
    int 21h

    mov di, returned_info
    mov cx, 13
    xor ax, ax
    rep stosw
    mov bl, 2
    mov dx, returned_info
    mov ax, 6900h
    int 21h
    jc media_failed
    mov si, test_label
    mov di, returned_info + 6
    mov cx, 11
    repe cmpsb
    je media_ok
media_failed:
    mov dx, fail_message
    jmp finish
media_ok:
    mov dx, pass_message
finish:
    mov ah, 09h
    int 21h
    cmp dx, pass_message
    jne failed_exit
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h
failed_exit:
    mov ax, 4c01h
    int 21h

test_label db 'I21MEDIA   '
cross_source db 'A:\CROSS.TST', 0
cross_target db 'B:\CROSS.TST', 0
media_info times 26 db 0
returned_info times 26 db 0
pass_message db 'INT21_MEDIA_PASS', 13, 10, '$'
fail_message db 'INT21_69_FAIL', 13, 10, '$'
rename_failed db 'INT21_RENAME_DRIVE_FAIL', 13, 10, '$'
media_drive_failed db 'INT21_MEDIA_DRIVE_FAIL', 13, 10, '$'
