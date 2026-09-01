bits 16
org 0x7c00

start:
    cli
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7c00
    sti

    ; COM1, 9600 baud, 8N1. The 86Box VM routes this UART to stdout.
    mov dx, 0x3fb
    mov al, 0x80
    out dx, al
    mov dx, 0x3f8
    mov al, 12
    out dx, al
    inc dx
    xor al, al
    out dx, al
    mov dx, 0x3fb
    mov al, 3
    out dx, al
    mov dx, 0x3fc
    out dx, al

    mov si, message
.next:
    lodsb
    test al, al
    jz .wait
    mov bl, al
    mov dx, 0x3fd
.ready:
    in al, dx
    test al, 0x20
    jz .ready
    mov dx, 0x3f8
    mov al, bl
    out dx, al
    jmp .next

.wait:
    hlt
    jmp .wait

message db '86BOX_BOOT_PROBE_PASS', 13, 10, 0

times 510 - ($ - $$) db 0
dw 0xaa55
