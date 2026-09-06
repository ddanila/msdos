; Read-only conventional MCB and DOS DEVMARK census. No DR-DOS internals.
bits 16
org 100h
start:
    push cs
    pop ds
    mov ah,52h
    int 21h
    mov bp,[es:bx-2]
    mov cx,512
.arena:
    cmp bp,70h
    jb fail
    cmp bp,0a000h
    jae done
    mov es,bp
    mov al,[es:0]
    cmp al,'M'
    je .valid
    cmp al,'Z'
    jne fail
.valid:
    mov di,bp
    add di,[es:3]
    jc fail
    inc di
    jz fail
    mov dx,mcb
    call print
    mov ax,bp
    call hex
    mov ax,[es:1]
    call hex
    mov ax,[es:3]
    call hex
    call newline
    cmp word [es:1],8
    jne .next
    push bp
    inc bp
.sub:
    cmp bp,di
    jae .sub_done
    mov es,bp
    mov ax,bp
    inc ax
    cmp ax,[es:1]             ; DEVMARK_SEG points just past its header
    jne .gap
    add ax,[es:3]
    jc .gap
    cmp ax,di
    ja .gap
    mov si,ax
    mov dx,submark
    call print
    mov ax,bp
    call hex
    xor ax,ax
    mov al,[es:0]
    call hex
    mov ax,[es:1]
    call hex
    mov ax,[es:3]
    call hex
    call newline
    mov bp,si
    jmp .sub
.gap:
    mov dx,gap
    call print
    mov ax,bp
    call hex
    mov ax,di
    call hex
    call newline
.sub_done:
    pop bp
    mov es,bp
.next:
    cmp byte [es:0],'Z'
    je done
    mov bp,di
    loop .arena_bridge
    jmp fail
.arena_bridge:
    jmp .arena
done:
    mov dx,ending
    call print
    mov ax,4c00h
    int 21h
fail:
    mov dx,error
    call print
    mov ax,4c01h
    int 21h
print:
    push ax
    mov ah,9
    int 21h
    pop ax
    ret
newline:
    push dx
    mov dx,eol
    call print
    pop dx
    ret
hex:
    push ax
    push bx
    push cx
    push dx
    mov bx,ax
    mov cx,4
.digit:
    rol bx,1
    rol bx,1
    rol bx,1
    rol bx,1
    mov dl,bl
    and dl,15
    add dl,'0'
    cmp dl,'9'
    jbe .emit
    add dl,7
.emit:
    mov ah,2
    int 21h
    loop .digit
    mov dl,' '
    mov ah,2
    int 21h
    pop dx
    pop cx
    pop bx
    pop ax
    ret
mcb db 'MCB ', '$'
submark db 'SUB ', '$'
gap db 'UNCLASSIFIED ', '$'
eol db 13,10,'$'
ending db 'SYSTEM_OWNER_END',13,10,'$'
error db 'SYSTEM_OWNER_FAIL',13,10,'$'
