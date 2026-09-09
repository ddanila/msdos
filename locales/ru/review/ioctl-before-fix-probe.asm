bits 16
org 100h
mov ax,ds
call hex
mov [packetseg],ds
mov ax,3d02h
mov dx,con
int 21h
mov bx,ax
push bx
mov dx,packet
mov cx,034ch
mov ax,440ch
int 21h
pushf
push ax
push ds
push es
push si
push di
push cx
mov ax,0355h
mov ds,ax
lds si,[04e2h]
push cs
pop es
mov di,snapshot
mov cx,23
rep movsb
pop cx
pop di
pop si
pop es
pop ds
pop ax
popf
pushf
call hex
pop ax
call hex
pop bx
mov ax,1220h
int 2fh
mov bl,[es:di]
xor bh,bh
mov ax,1216h
int 2fh
les di,[es:di+7]
mov ax,[es:di+6]
mov [strategy],ax
mov ax,[es:di+8]
mov [intr],ax
mov ax,es
mov [strategy+2],ax
mov [intr+2],ax
push ds
push es
pop ds
push cs
pop es
mov bx,request
call far [cs:strategy]
mov bx,request
call far [cs:intr]
pop ds
mov ax,[status]
call hex
mov dx,filename
xor cx,cx
mov ah,3ch
int 21h
mov bx,ax
mov dx,snapshot
mov cx,23
mov ah,40h
int 21h
mov ah,3eh
int 21h
mov ax,4c00h
int 21h
filename db 'REQ.BIN',0
snapshot times 23 db 0
con db 'CON',0
strategy dd 0
intr dd 0
request db 23,0,13h
status dw 0
times 8 db 0
db 3,4ch
dw 0,0
dw packet
packetseg dw 0
packet dw 0,4,1,866
hex:
    push bx
    push cx
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
    jbe .print
    add dl,7
.print:
    mov ah,2
    int 21h
    loop .digit
    pop cx
    pop bx
    ret
