; Exercise the real local BIOS INT 19h restoration routine, then chain to ROM.
bits 16
org 100h
%include "int19-defs.inc"
start:
    push cs
    pop ds
    cld
    mov dx,tag
    mov ax,3d00h
    int 21h
    jc .first
    mov bx,ax
    mov dx,receipt
    mov cx,8
    mov ah,3fh
    int 21h
    jc fail
    cmp ax,8
    jne fail
    mov ah,3eh
    int 21h
    jc fail
    push cs
    pop es
    mov si,receipt
    mov di,magic
    mov cx,8
    repe cmpsb
    jne fail
    mov dx,tag
    mov ah,41h
    int 21h
    jc fail
    mov si,boot_pass
    call debug
    mov ax,4c00h
    int 21h
.first:
    cmp ax,2
    jne fail
    xor cx,cx
    mov ah,3ch
    int 21h
    jc fail
    mov bx,ax
    mov cx,8
    mov dx,magic
    mov ah,40h
    int 21h
    jc fail
    cmp ax,8
    jne fail
    mov ah,3eh
    int 21h
    jc fail
    mov ah,0dh
    int 21h
    cli
    mov ax,70h
    mov ds,ax
    push cs
    pop es
    mov ax,[ORIG19]
    mov [cs:original19],ax
    mov ax,[ORIG19+2]
    mov [cs:original19+2],ax
    mov ax,[OLD13]
    mov [cs:original13],ax
    mov ax,[OLD13+2]
    mov [cs:original13+2],ax
    mov si,OLD_VECTORS
    mov di,vectors
    mov cx,70
    rep movsb
    ; Sentinel entries must remain unchanged, rather than becoming FFFF:FFFF.
    xor ax,ax
    mov es,ax
    cmp word [es:19h*4],ENTRY19
    jne fail
    cmp word [es:19h*4+2],70h
    jne fail
    mov si,vectors
    mov cx,14
.snapshot:
    xor bx,bx
    mov bl,[cs:si+4]
    shl bx,1
    shl bx,1
    cmp word [cs:si+2],0ffffh
    jne .next
    mov ax,[es:bx]
    mov [cs:si],ax
    mov ax,[es:bx+2]
    mov [cs:si+2],ax
.next:
    add si,5
    loop .snapshot
    mov word [ORIG19],restored
    mov [ORIG19+2],cs
    mov si,ready
    call debug
    mov ax,9876h
    mov ds,ax
    mov ax,5432h
    mov es,ax
    int 19h
    jmp fail
restored:
    xor ax,ax
    mov ds,ax
    mov ax,[cs:original13]
    cmp [13h*4],ax
    jne fail
    mov ax,[cs:original13+2]
    cmp [13h*4+2],ax
    jne fail
    cmp word [19h*4],restored
    jne fail
    mov ax,cs
    cmp [19h*4+2],ax
    jne fail
    mov si,vectors
    mov cx,14
.check:
    xor bx,bx
    mov bl,[cs:si+4]
    shl bx,1
    shl bx,1
    mov ax,[cs:si]
    cmp [bx],ax
    jne fail
    mov ax,[cs:si+2]
    cmp [bx+2],ax
    jne fail
    add si,5
    loop .check
    mov si,vector_pass
    call debug
    ; Restore the real bootstrap pointer, including the IVT slot temporarily
    ; selecting this checker, then continue exactly that ROM bootstrap chain.
    mov ax,70h
    mov es,ax
    mov ax,[cs:original19]
    mov [es:ORIG19],ax
    mov [19h*4],ax
    mov ax,[cs:original19+2]
    mov [es:ORIG19+2],ax
    mov [19h*4+2],ax
    jmp far [cs:original19]
fail:
    mov si,failed
    call debug
    mov ax,11h
    out 0f4h,ax
    cli
    hlt
    jmp fail
debug:
    mov al,[cs:si]
    inc si
    or al,al
    jz .done
    out 0e9h,al
    jmp debug
.done:
    ret
original19 dd 0
original13 dd 0
vectors times 70 db 0
receipt times 8 db 0
tag db 'SWBOOT.TAG',0
magic db 'SWRBOOT!'
ready db 'BIOS_INT19_READY',13,10,0
vector_pass db 'BIOS_INT19_VECTORS_PASS',13,10,0
boot_pass db 'BIOS_INT19_SECOND_BOOT_PASS',13,10,0
failed db 'BIOS_INT19_FAIL',13,10,0
