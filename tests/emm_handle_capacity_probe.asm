; Exercise the complete handle table without making EMS page capacity the limit.
bits 16
org 100h
    mov ah,4bh
    int 67h
    test ah,ah
    jnz failed
    cmp bx,1                       ; reserved system handle zero
    jne failed
    xor si,si
allocate:
    cmp si,(HANDLES-1)*2
    jae exhausted
    xor bx,bx
    mov ax,5a00h                   ; unlike AH=43h, zero-page handles are legal
    int 67h
    test ah,ah
    jnz failed
    test dx,dx
    jz failed
    cmp dx,HANDLES
    jae failed
    mov bx,dx
    cmp byte [seen+bx],0
    jne failed
    mov byte [seen+bx],1
    mov [handle_ids+si],dx
    mov ah,4ch
    int 67h
    test ah,ah
    jnz failed
    test bx,bx
    jnz failed
    add si,2
    jmp allocate
exhausted:
    mov ah,4bh
    int 67h
    test ah,ah
    jnz failed
    cmp bx,HANDLES
    jne failed
    xor bx,bx
    mov ax,5a00h
    int 67h
    cmp ah,85h
    jne failed
release:
    test si,si
    jz reuse
    sub si,2
    mov dx,[handle_ids+si]
    mov ah,45h
    int 67h
    test ah,ah
    jnz failed
    jmp release
reuse:
    xor bx,bx
    mov ax,5a00h
    int 67h
    test ah,ah
    jnz failed
    mov ah,45h
    int 67h
    test ah,ah
    jnz failed
    mov ah,4bh
    int 67h
    test ah,ah
    jnz failed
    cmp bx,1
    jne failed
    mov bx,HANDLES
    jmp emit
failed:
    mov bx,0ffffh
emit:
    mov dx,0e9h
    mov al,'H'
    out dx,al
    mov al,'C'
    out dx,al
    mov ax,bx
    out dx,al
    mov al,ah
    out dx,al
    mov ax,4c00h
    int 21h
handle_ids times 254 dw 0
seen times 255 db 0
