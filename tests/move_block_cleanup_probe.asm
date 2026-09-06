bits 16
org 100h
    push cs
    pop ds
    push cs
    pop es
    mov bx,source
    mov di,source_desc
    call set_base
    mov bx,target
    mov di,target_desc
    call set_base
    mov al,'A'
    call checkpoint
    mov cx,8001h
    call reject
    mov al,'B'
    call checkpoint
    mov word [source_desc],1
    mov cx,8
    call reject
    mov al,'C'
    call checkpoint
    mov word [source_desc],0ffffh
    mov word [target_desc],1
    mov cx,8
    call reject
    mov al,'D'
    call checkpoint
    mov word [target_desc],0ffffh
    mov cx,8
    call copy
    jc failed
    test ah,ah
    jnz failed
    mov si,source
    mov di,target
    mov cx,16
    cld
    repe cmpsb
    jne failed
    mov al,'E'
    call checkpoint
    mov cx,8001h
    call reject
    mov al,'F'
    call checkpoint
    mov ax,10h
    jmp finish
reject:
    call copy
    jnc failed
    cmp ah,2
    jne failed
    ret
copy:
    mov si,descriptors
    mov ah,87h
    int 15h
    ret
checkpoint:
    out 0e9h,al
    xor ah,ah
    int 16h
    ret
set_base:
    xor eax,eax
    mov ax,cs
    shl eax,4
    movzx ebx,bx
    add eax,ebx
    mov [di+2],ax
    shr eax,16
    mov [di+4],al
    ret
failed:
    mov al,'!'
    out 0e9h,al
    mov ax,11h
finish:
    mov dx,0f4h
    out dx,ax
    cli
    hlt
align 8
descriptors:
    dq 0,0
source_desc:
    dw 0ffffh,0
    db 0,93h,0,0
target_desc:
    dw 0ffffh,0
    db 0,93h,0,0
    dq 0,0
source db 'COPY OWNER CHECK'
target times 16 db 0
