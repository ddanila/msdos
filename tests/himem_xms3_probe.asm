bits 16
cpu 386
org 100h

start:
    mov byte [step],'1'
    mov ax,4300h
    int 2fh
    cmp al,80h
    jne fail
    mov ax,4310h
    int 2fh
    mov [entry],bx
    mov [entry+2],es

    xor ah,ah
    call far [entry]
    cmp ax,0300h
    jne fail
    cmp bx,0310h
    jne fail

    mov byte [step],'2'
    mov ah,88h
    call far [entry]
    mov [highest],ecx
    mov byte [step],'a'
    test eax,eax
    jz fail
    mov byte [step],'b'
    test edx,edx
    jz fail
    mov byte [step],'c'
    cmp edx,eax
    jb fail
    mov byte [step],'d'
    cmp ecx,000000ffh
    jne fail
    mov [largest],eax
    mov [total],edx

    mov ah,08h
    call far [entry]
    mov byte [step],'q'
    or bl,bl
    jnz fail
    mov byte [step],'e'
    movzx ebx,ax
    cmp ebx,[largest]
    jne fail
    mov byte [step],'f'
    movzx ebx,dx
    cmp ebx,[total]
    jne fail

    mov byte [step],'3'
    mov ah,89h
    mov edx,64
    call far [entry]
    mov byte [step],'g'
    cmp ax,1
    jne fail
    mov [handle],dx

    ; Allocation moves the gap scanner's base to 0080h. That scratch value
    ; must not leak into BL as a false "function not implemented" status.
    mov byte [step],'Q'
    mov ah,08h
    call far [entry]
    or bl,bl
    jnz fail

    mov ah,8eh
    mov dx,[handle]
    mov cx,55aah
    call far [entry]
    mov byte [step],'h'
    cmp ax,1
    jne fail
    cmp edx,64
    jne fail
    mov byte [step],'i'
    or bh,bh
    jnz fail
    mov byte [step],'j'
    cmp cx,55aah
    jne fail

    mov byte [step],'4'
    mov ah,8fh
    mov dx,[handle]
    mov ebx,32
    call far [entry]
    cmp ax,1
    jne fail
    mov ah,8eh
    mov dx,[handle]
    mov cx,55aah
    call far [entry]
    cmp ax,1
    jne fail
    cmp edx,32
    jne fail

    mov byte [step],'5'
    mov ah,8fh
    mov dx,[handle]
    mov ebx,10000h
    call far [entry]
    or ax,ax
    jnz fail
    cmp bl,0a0h
    jne fail

    mov byte [step],'6'
    mov ah,89h
    mov edx,10000h
    call far [entry]
    or ax,ax
    jnz fail
    cmp bl,0a0h
    jne fail

    mov byte [step],'7'
    mov ah,0ah
    mov dx,[handle]
    call far [entry]
    cmp ax,1
    jne fail

    mov byte [step],'8'
    mov bx,005ah
    mov ah,8ah
    call far [entry]
    mov [unknown_bx],bx
    mov byte [step],'k'
    or ax,ax
    jnz fail
    mov byte [step],'l'
    cmp bl,0a2h
    jne fail

    ; Exhaust the pool and check the documented no-free-memory status.
    mov byte [step],'X'
    mov ah,08h
    call far [entry]
    mov ah,09h
    call far [entry]
    cmp ax,1
    jne fail
    mov [handle],dx
    mov ah,08h
    call far [entry]
    or ax,ax
    jnz fail
    or dx,dx
    jnz fail
    cmp bl,0a0h
    jne fail
    mov ah,0ah
    mov dx,[handle]
    call far [entry]
    cmp ax,1
    jne fail

    mov dx,pass_message
    jmp short finish
fail:
    mov dx,fail_message
    mov ah,9
    int 21h
    mov dl,[step]
    mov ah,2
    int 21h
    mov dx,newline
    mov ah,9
    int 21h
    mov eax,[highest]
    call print_hex32
    mov dx,newline
    mov ah,9
    int 21h
    movzx eax,word [unknown_bx]
    call print_hex32
    mov dx,newline
    mov ah,9
    int 21h
    jmp short exit_probe
finish:
    mov ah,9
    int 21h
exit_probe:
    mov dx,0f4h
    mov ax,10h
    out dx,ax
    mov ax,4c00h
    int 21h

print_hex32:
    push ax
    push bx
    push cx
    push dx
    mov ebx,eax
    mov cx,8
.digit:
    rol ebx,4
    mov dl,bl
    and dl,0fh
    add dl,'0'
    cmp dl,'9'
    jbe .emit
    add dl,'A'-'9'-1
.emit:
    mov ah,2
    int 21h
    loop .digit
    pop dx
    pop cx
    pop bx
    pop ax
    ret

entry        dd 0
largest      dd 0
total        dd 0
highest      dd 0
unknown_bx   dw 0
handle       dw 0
step         db '0'
pass_message db 'HIMEM_XMS3_PASS',13,10,'$'
fail_message db 'HIMEM_XMS3_FAIL phase ','$'
newline      db 13,10,'$'
