bits 16
org 100h

; Focused get/set media-ID contract on disposable drive B:.

start:
    push cs
    pop ds

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
    mov ah, 0dh                    ; Persist the updated boot-sector metadata.
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
media_info times 26 db 0
returned_info times 26 db 0
pass_message db 'INT21_MEDIA_PASS', 13, 10, '$'
fail_message db 'INT21_69_FAIL', 13, 10, '$'
