; Public API registers only: no dereference of vendor-private memory.
bits 16
org 100h

start:
    push cs
    pop ds
    mov dx, dpl
    xor cx, cx
    xor si, si
    mov ax, 5d06h
    clc
    int 21h
    call snapshot
    mov dx, label_06
    call record
%ifdef LOCAL_SDA_LIVE
    ; Repository SDA offsets only. Do not impose this layout on vendor DOS.
    cmp word [values], 0
    jne .bad_live
    mov es, [values+4]
    mov di, [values+6]
    mov ax, cs
    cmp [es:di+10h], ax
    jne .bad_live
    cmp [es:di+0eh], ax
    jne .bad_live
    cmp word [es:di+0ch], 80h
    jne .bad_live
    mov dx, live_pass
    jmp .print_live
.bad_live:
    mov dx, live_fail
.print_live:
    mov ah, 09h
    int 21h
%endif

    mov dx, dpl
    xor cx, cx
    xor si, si
    mov ax, 5d0bh
    clc
    int 21h
    call snapshot
    mov dx, label_0b
    call record
    mov dx, done
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

snapshot:
    mov [cs:values+2], ax
    mov [cs:values+4], ds
    mov [cs:values+6], si
    mov [cs:values+8], cx
    mov [cs:values+10], dx
    pushf
    pop ax
    and ax, 1
    mov [cs:values], ax
    push cs
    pop ds
    ret

record:
    mov ah, 09h
    int 21h
    mov si, values
    mov bp, 6
.word:
    lodsw
    mov bx, ax
    mov cx, 4
.digit:
    rol bx, 4
    mov dl, bl
    and dl, 15
    add dl, '0'
    cmp dl, '9'
    jbe .emit
    add dl, 7
.emit:
    mov ah, 02h
    int 21h
    loop .digit
    mov dl, ' '
    mov ah, 02h
    int 21h
    dec bp
    jnz .word
    mov dx, newline
    mov ah, 09h
    int 21h
    ret

values times 6 dw 0
dpl times 64 db 0
label_06 db 'SDA_5D06 CF AX DS SI CX DX: $'
label_0b db 'SDA_5D0B CF AX DS SI CX DX: $'
newline db 13,10,'$'
done db 'DRDOS_PUBLIC_MEMORY_END',13,10,'$'
%ifdef LOCAL_SDA_LIVE
live_pass db 'SDA_LIVE_PASS',13,10,'$'
live_fail db 'SDA_LIVE_FAIL',13,10,'$'
%endif
