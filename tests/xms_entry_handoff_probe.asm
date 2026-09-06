; Exercise DOS's cached entry protocol, not a provider ownership transfer.
bits 16
org 100h
    push cs
    pop ds
    xor di,di
    call exchange
%ifdef DOS_LOW
    test ax,ax
    jnz failed
    mov bx,bridge
    mov dx,cs
    mov di,1
    call exchange
    test ax,ax
    jnz failed
    jmp passed
%else
    cmp ax,1
    jne failed
    mov [original],bx
    mov [original+2],dx
    mov ax,4310h
    int 2fh
    cmp bx,[original]
    jne failed
    mov ax,es
    cmp ax,[original+2]
    jne failed
    mov bx,bridge
    cmp bx,[original]
    jne .offset_different
    mov bx,bridge_alternate
.offset_different:
    mov [expected],bx
    mov dx,cs
    mov [expected+2],dx
    cmp dx,[original+2]
    je failed
    mov di,1
    call exchange
    cmp ax,1
    jne failed
    call check_expected
    ; A real call through the cache's returned full pointer reaches the bridge.
    mov [cached],bx
    mov [cached+2],dx
    mov ah,7
    call far [cached]
    cmp ax,1
    jne failed
    cmp word [calls],1
    jne failed
    ; Bad version, operation and wrapped/HMA/null addresses must not mutate it.
    mov ax,1234h
    mov cx,584dh
    mov si,2
    mov di,1
    xor dx,dx
    int 2fh
    test ax,ax
    jnz failed
    call check_expected
    mov di,2
    call exchange
    test ax,ax
    jnz failed
    call check_expected
    xor dx,dx
    mov di,1
    call exchange
    test ax,ax
    jnz failed
    call check_expected
    mov dx,0ffffh
    xor bx,bx
    mov di,1
    call exchange
    test ax,ax
    jnz failed
    call check_expected
    mov dx,0fff0h
    mov bx,100h
    mov di,1
    call exchange
    test ax,ax
    jnz failed
    call check_expected
    ; Legacy form changes only the segment, retaining the new offset.
    mov ax,1234h
    xor cx,cx
    mov dx,[original+2]
    int 2fh
    mov [expected+2],dx
    call check_expected
    ; Roll back the complete pointer before terminating the probe.
    mov bx,[original]
    mov dx,[original+2]
    mov [expected],bx
    mov di,1
    call exchange
    cmp ax,1
    jne failed
    call check_expected
%endif
passed:
    mov al,'P'
    out 0e9h,al
    mov ax,10h
    jmp finish
failed:
    mov al,'!'
    out 0e9h,al
    mov ax,11h
finish:
    mov dx,0f4h
    out dx,ax
    cli
    hlt
exchange:
    mov ax,1234h
    mov cx,584dh
    mov si,1
    int 2fh
    ret
check_expected:
    xor di,di
    call exchange
    cmp ax,1
    jne failed
    cmp bx,[expected]
    jne failed
    cmp dx,[expected+2]
    jne failed
    ret
bridge_alternate:
    nop
bridge:
    pushf
    inc word [cs:calls]
    popf
    jmp far [cs:original]
original dd 0
expected dd 0
cached dd 0
calls dw 0
