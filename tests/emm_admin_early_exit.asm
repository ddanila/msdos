; SYSINIT recognizes this provider name and installs its administrative image,
; but this witness returns before preparing/binding any allocator stage.
bits 16
org 0
    dd 0ffffffffh
    dw 8000h
    dw strategy, interrupt
    db 'EMMXXXX0'
request dd 0
strategy:
    mov [cs:request],bx
    mov [cs:request+2],es
    retf
interrupt:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
%ifdef STAGED_ABORT
    mov ax,0e706h
    mov cx,584dh
    mov si,1
    xor di,di
    int 2fh
    cmp ax,0e7ffh
    jne failed
    mov ds,dx
    mov dx,stage_image
    shr dx,4
    mov ax,cs
    add dx,ax
    mov es,dx
    xor si,si
    xor di,di
    cld
    rep movsb
    mov ax,0e707h
    mov cx,584dh
    mov si,1
    xor di,di
    int 2fh
    cmp ax,0e7ffh
    jne failed
    mov al,'S'
    out 0e9h,al
    mov al,'B'
    out 0e9h,al
%endif
    les bx,[cs:request]
    mov word [es:bx+14],0
    mov ax,cs
    mov [es:bx+16],ax
%ifdef NO_CALLBACK
    mov word [es:bx+3],0100h
%else
    mov word [es:bx+3],8103h
%endif
    mov al,'E'
    out 0e9h,al
    mov al,'A'
    out 0e9h,al
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    retf
%ifdef STAGED_ABORT
failed:
    mov al,18
    out 0f4h,al
    cli
    hlt
    jmp failed
align 16, db 0
stage_image times 8192 db 0
%endif
