; Shared timing MBR for bootable FAT16 benchmark images.
bits 16
org 600h
    cli
    xor ax,ax
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov sp,7c00h
    sti
    cld
    mov si,7c00h
    mov di,600h
    mov cx,256
    rep movsw
    jmp 0:relocated
relocated:
    mov si,marker
.mark:
    lodsb
    test al,al
    jz .marked
    out 0e9h,al
    jmp .mark
.marked:
    mov [drive],dl
    mov ax,[600h+446+8]
    mov [dap+8],ax
    mov ax,[600h+446+10]
    mov [dap+10],ax
    mov si,dap
    mov ah,42h
    int 13h
    jc failed
    mov dl,[drive]
    mov si,600h+446
    jmp 0:7c00h
failed:
    mov al,'F'
    out 0e9h,al
    cli
    hlt
    jmp failed
drive: db 0
marker: db '~BOOTBENCH_START~',10,0
align 4
dap: db 10h,0
     dw 1,7c00h,0
     dq 63
times 446-($-$$) db 0
times 64 db 0
dw 0aa55h
