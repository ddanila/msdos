; Only report public entry segments, then let the host inspect our own guest.
bits 16
org 100h
    mov dx, emm_label
    mov ah, 09h
    int 21h
    mov ax, 3567h
    int 21h
    mov ax, es
    call hexword
    mov dx, xms_label
    mov ah, 09h
    int 21h
    mov ax, 4310h
    int 2fh
    mov ax, es
    call hexword
    mov dx, ready
    mov ah, 09h
    int 21h
    cli
.halt:
    hlt
    jmp .halt
hexword:
    mov bx, ax
    mov cx, 4
.next:
    rol bx, 4
    mov dl, bl
    and dl, 15
    add dl, '0'
    cmp dl, '9'
    jbe .emit
    add dl, 7
.emit:
    mov ah, 02h
    int 21h
    loop .next
    ret
emm_label db 'EMM_SEG=','$'
xms_label db 13,10,'XMS_SEG=','$'
ready db 13,10,'EMM_LIVE_OWNER_READY',13,10,'$'
