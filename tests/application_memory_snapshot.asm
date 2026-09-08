; Fixed-size, non-allocating snapshot after shrinking our own conventional block.
; stdout: strategy/link, low free/largest, upper free/largest, EMS free/total.
bits 16
org 100h
    mov sp,stack_top
    mov bx,(program_end-$$+100h+15)/16
    mov ah,4ah
    int 21h
    jc fail
    mov ax,5800h
    int 21h
    jc fail
    mov [values],ax
    mov ax,5802h
    int 21h
    jc fail
    xor ah,ah
    mov [values+2],ax
    mov ax,5803h
    mov bx,1
    int 21h
    jc fail
    mov ah,52h
    int 21h
    mov ax,[es:bx-2]
.walk:
    mov es,ax
    mov dl,[es:0]
    cmp dl,'M'
    je .valid
    cmp dl,'Z'
    jne fail
.valid:
    cmp word [es:1],0
    jne .next
    mov si,values+4
    cmp ax,0a000h
    jb .low
    add si,4
.low:
    mov cx,[es:3]
    add [si],cx
    cmp cx,[si+2]
    jbe .next
    mov [si+2],cx
.next:
    cmp dl,'Z'
    je .done
    add ax,[es:3]
    inc ax
    jmp .walk
.done:
    mov ax,5803h
    mov bx,[values+2]
    int 21h
    jc fail
    mov ah,42h
    int 67h
    or ah,ah
    jnz fail
    mov [values+12],bx
    mov [values+14],dx
    mov bx,1
    mov dx,values
    mov cx,16
    mov ah,40h
    int 21h
    jc fail
    cmp ax,16
    jne fail
    mov ax,4c00h
    int 21h
fail:
    mov ax,4c01h
    int 21h
values times 8 dw 0
    times 128 db 0
stack_top:
program_end:
