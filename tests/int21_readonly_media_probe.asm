bits 16
org 100h


%macro require_error 2
    jc %%carried
    mov dx, %2
    jmp fail
%%carried:
    cmp ax, %1
    je %%ok
    mov dx, %2
    jmp fail
%%ok:
%endmacro

start:
    push cs
    pop ds
    push ds
    pop es

    mov dx, critical_error_handler
    mov ax, 2524h
    int 21h

    mov bl, 2
    mov dx, media_info
    mov ax, 6900h
    int 21h
    jc setup_failed
    mov byte [media_info + 6], 'R'

    mov bl, 2
    mov cx, 0846h
    mov dx, media_info
    mov ax, 440dh
    int 21h
    require_error 5, fail_ioctl_access

    mov bl, 2
    mov dx, media_info
    mov ax, 6901h
    int 21h
    require_error 5, fail_media_access

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

setup_failed:
    mov dx, fail_setup
fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

critical_error_handler:
    mov al, 3
    iret

media_info times 26 db 0
pass_message db 'INT21_READONLY_MEDIA_PASS', 13, 10, '$'
fail_setup db 'INT21_READONLY_MEDIA_SETUP_FAIL', 13, 10, '$'
fail_ioctl_access db 'INT21_READONLY_IOCTL_ACCESS_FAIL', 13, 10, '$'
fail_media_access db 'INT21_READONLY_MEDIA_ACCESS_FAIL', 13, 10, '$'
