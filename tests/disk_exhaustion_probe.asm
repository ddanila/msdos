bits 16
org 100h

; Fill the remaining FAT12 data clusters through DOS writes. A full disk must
; return a short successful write, then accept a complete write after the host
; filler and partial output are deleted.

start:
    push cs
    pop ds

    xor cx, cx
    mov dx, full_name
    mov ah, 3ch
    int 21h
    jc failed
    mov [handle], ax

.fill:
    mov bx, [handle]
    mov cx, buffer_size
    mov dx, buffer
    mov ah, 40h
    int 21h
    jc failed
    cmp ax, buffer_size
    je .fill
    cmp ax, buffer_size             ; A disk-full write is short, never long.
    ja failed

    mov bx, [handle]
    mov ah, 3eh
    int 21h
    jc failed
    mov dx, full_name
    mov ah, 41h
    int 21h
    jc failed
    mov dx, filler_name
    mov ah, 41h
    int 21h
    jc failed

    xor cx, cx
    mov dx, recovery_name
    mov ah, 3ch
    int 21h
    jc failed
    mov bx, ax
    mov cx, buffer_size
    mov dx, buffer
    mov ah, 40h
    int 21h
    jc failed
    cmp ax, buffer_size
    jne failed
    mov ah, 3eh
    int 21h
    jc failed
    mov dx, recovery_name
    mov ah, 41h
    int 21h
    jc failed

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

failed:
    mov dx, fail_message
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

handle        dw 0
full_name     db 'DISKFULL.TST', 0
filler_name   db 'FILLER.BIN', 0
recovery_name db 'RECOVER.TST', 0
pass_message  db 'DISK_EXHAUSTION_PASS', 13, 10, '$'
fail_message  db 'DISK_EXHAUSTION_FAIL', 13, 10, '$'
buffer        times 4096 db 0
buffer_size   equ $ - buffer
