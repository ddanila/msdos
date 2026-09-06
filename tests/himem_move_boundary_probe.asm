bits 16
org 100h

start:
    mov ax,4310h
    int 2fh
    mov [entry],bx
    mov [entry+2],es
    mov ah,9
    mov dx,192
    call far [entry]
    cmp ax,1
    jne fail
    mov [handle],dx
    mov [to_xms+10],dx
    mov [from_xms+4],dx
    mov ax,ds
    mov [to_xms+8],ax
    mov [from_xms+14],ax

    ; Seed the first eight bytes using a move that does not cross 64 KiB.
    mov word [to_xms],8
    mov word [to_xms+6],zeros
    mov si,to_xms
    call move
    jc fail

    ; A 32-byte write at FFF0h crosses a 64 KiB offset boundary. The
    ; calculated end must not replace the high word of its start address.
    mov word [to_xms],32
    mov word [to_xms+6],pattern
    mov si,to_xms
    call move
    jc fail
    mov word [from_xms],8
    mov si,from_xms
    call move
    jc fail
    mov cx,8
    call compare
    jne fail

    ; Independently seed all four subranges, then test a crossing read.
    mov word [to_xms],8
    mov word [to_xms+6],pattern
    mov word [to_xms+12],0fff0h
    mov word [to_xms+14],0
    mov bx,4
.seed:
    push bx
    mov si,to_xms
    call move
    pop bx
    jc fail
    add word [to_xms+6],8
    add word [to_xms+12],8
    adc word [to_xms+14],0
    dec bx
    jnz .seed
    mov word [from_xms],32
    mov si,from_xms
    call move
    jc fail
    mov cx,32
    call compare
    jne fail
    mov ah,0ah
    mov dx,[handle]
    call far [entry]
    cmp ax,1
    jne fail
    mov dx,pass_message
    jmp finish
fail:
    mov dx,fail_message
finish:
    mov ah,9
    int 21h
    mov dx,0f4h
    mov ax,10h
    out dx,ax
    mov ax,4c00h
    int 21h
move:
    mov ah,0bh
    call far [entry]
    cmp ax,1
    je .ok
    stc
    ret
.ok:
    clc
    ret
compare:
    push ds
    pop es
    mov si,pattern
    mov di,result
    cld
    repe cmpsb
    ret
entry dd 0
handle dw 0
to_xms:
    dd 32
    dw 0
    dw pattern,0
    dw 0
    dd 0fff0h
from_xms:
    dd 32
    dw 0
    dd 0fff0h
    dw 0
    dw result,0
pattern db '0123456789ABCDEFabcdefghijklmnop'
zeros times 32 db 0
result times 32 db 0
pass_message db 'HIMEM_MOVE_BOUNDARY_PASS',13,10,'$'
fail_message db 'HIMEM_MOVE_BOUNDARY_FAIL',13,10,'$'
