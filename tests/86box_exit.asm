; Flush guest writes and exit through the 86Box Unit Tester device.
; Enable unittester_enabled in the private VM configuration.
; Completion markers remain the responsibility of the invoking guest test.
bits 16
cpu 8086
org 100h
    mov ah,0dh
    int 21h
    cld
    cli
    mov si,enable
    mov cx,7
    mov dx,80h
.next:
    lodsb
    out dx,al
    loop .next
    sti
    mov dx,0f4h
    in al,dx
    cmp al,4
    jne failed
    mov al,4
    out dx,al
    inc dx
    xor al,al
    cmp byte [80h],0
    je .exit
    mov al,1                  ; Any argument requests a failing exit.
.exit:
    out dx,al
failed:
    mov dx,message
    mov ah,9
    int 21h
    mov ax,4c01h
    int 21h
enable db '86Box',0f4h,0
message db 'RU_86BOX_EXIT_FAIL',13,10,'$'
