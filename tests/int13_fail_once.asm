bits 16
org 100h

start:
    mov ax,3513h
    int 21h
    mov [old13],bx
    mov [old13+2],es
    push cs
    pop ds
    mov dx,handler
    mov ax,2513h
    int 21h
    mov dx,message
    mov ah,9
    int 21h
    mov dx,resident_paragraphs
    mov ax,3100h
    int 21h

handler:
    cmp byte [cs:armed],0
    je chain
    cmp ah,2
    jne chain
    cmp dl,1
    jne chain
    mov byte [cs:armed],0
    push bp
    mov bp,sp
    or word [ss:bp+6],1
    pop bp
    mov ah,80h
    iret
chain:
    jmp far [cs:old13]

old13 dd 0
armed db 1
message db 'INT13 transient-read fault armed',13,10,'$'
resident_end:
resident_paragraphs equ (resident_end - $$ + 100h + 15) / 16
