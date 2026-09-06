; Local DOS device-chain check after deferred provider installation/cancellation.
bits 16
org 100h
    mov ah,52h
    int 21h
    les si,[es:bx+34]            ; SYSI_DEV, same contract as ANSI driver probe
    mov cx,256
    xor bx,bx
.next:
    cmp si,0ffffh
    je .done
    test word [es:si+4],8000h
    jz .advance
    cmp word [es:si+10],4d45h
    jne .advance
    cmp word [es:si+12],584dh
    jne .advance
    cmp word [es:si+14],5858h
    jne .advance
    cmp word [es:si+16],3058h
    jne .advance
    inc bx
.advance:
    les si,[es:si]
    loop .next
    mov bx,0ffffh               ; malformed/cyclic chain is never an absent owner
.done:
    mov dx,0e9h
    mov al,'D'
    out dx,al
    mov al,'O'
    out dx,al
    mov ax,bx
    out dx,al
    mov al,ah
    out dx,al
    mov ax,4c00h
    int 21h
