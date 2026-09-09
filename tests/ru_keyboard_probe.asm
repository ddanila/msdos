bits 16
org 100h
    cld
%ifdef DOS_INPUT
    ; Replace only this process's stdin with CON; stdout remains serial AUX.
    mov ax,3d00h
    mov dx,console
    int 21h
    jc fail
    mov bx,ax
    xor cx,cx
    mov ah,46h
    int 21h
    jc fail
    mov ah,3eh
    int 21h
%endif
    mov si, expected
%ifndef START_INDEX
%define START_INDEX 0
%endif
    mov bp, START_INDEX
.next:
    mov dx, ready
    mov ah,9
    int 21h
    mov ax,bp
    call hex
    mov dx,newline
    mov ah,9
    int 21h
%ifdef DOS_INPUT
    mov ah,07h
    int 21h
    cmp al,[si]
    jne fail
    test al,al
    jnz .dos_read
    mov ah,07h
    int 21h
    cmp al,[si+1]
    jne fail
.dos_read:
    mov ax,[si]
%else
    xor ah,ah
    int 16h
%endif
    cmp ax,[si]
    jne fail
    ; Let queued break events reach the IRQ handler before checking held bits.
    push ds
    mov ax,40h
    mov ds,ax
    mov bx,[6ch]
.wait:
    mov ax,[6ch]
    sub ax,bx
    cmp ax,2
    jb .wait
    mov al,[17h]
    and al,0fh
    mov ah,[18h]
    and ah,03h
    or al,ah
    mov ah,[96h]
    and ah,0ch
    or al,ah
    pop ds
    test al,al
    jnz fail
    mov ah,01h
    int 16h
    jnz fail
    add si,2
    inc bp
    cmp si,expected_end
    jb .next
    mov dx,passed
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
fail:
    push ax
    mov dx,failed
    mov ah,9
    int 21h
    pop ax
    call hex
    mov dx,newline
    mov ah,9
    int 21h
    mov ax,4c01h
    int 21h
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
console db 'CON',0
ready db 'RU_KEY_READY ', '$'
passed db 'RU_KEY_PASS',13,10,'$'
failed db 'RU_KEY_FAIL actual=', '$'
newline db 13,10,'$'
expected: incbin 'expected.bin'
expected_end:
