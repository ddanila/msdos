bits 16
org 100h
    push cs
    pop ds
    mov ax,4310h
    int 2fh
    mov [xms],bx
    mov [xms+2],es
    mov dx,16384
    mov ah,09h
    call far [xms]
    cmp ax,1
    jne failed
    mov [reserve],dx
    mov dx,32
    mov ah,09h
    call far [xms]
    cmp ax,1
    jne failed
    mov [block],dx
    mov ah,0ch
    call far [xms]
    cmp ax,1
    jne failed
    cmp dx,0100h
    jb failed ; the witness must actually reach physical memory above 16 MiB
    xor eax,eax
    mov ax,dx
    shl eax,16
    mov ax,bx
    mov [physical],eax
    xor bx,bx
.fill:
    mov al,bl
    xor al,bh
    xor al,5ah
    mov [source+bx],al
    inc bx
    cmp bx,8192
    jb .fill
    mov al,'A'
    call checkpoint
    ; Rejected requests must not poison a later valid transaction.
    mov eax,[physical]
    mov [packet_source],eax
    inc eax
    mov [packet_dest],eax
    call reject ; non-identical overlap
    mov dword [packet_source],0fffffff0h
    call reject ; source range overflow, before dereferencing it
    mov dword [packet_length],0
    call copy
    jc failed
    test ah,ah
    jnz failed
    mov dword [packet_length],8192
    xor eax,eax
    mov ax,cs
    shl eax,4
    add eax,source
    cmp eax,40000h-8192 ; native conventional storage, outside bankable windows
    jae failed
    mov [packet_source],eax
    mov eax,[physical]
    add eax,4093
    mov [packet_dest],eax
    call copy
%ifdef EXPECT_MAP_FAILURE
    jnc failed
    cmp ah,2
    jne failed
%else
    jc failed
    test ah,ah
    jnz failed
    mov eax,[packet_dest]
    mov [packet_source],eax
    mov eax,[physical]
    add eax,16391
    mov [packet_dest],eax
    call copy
    jc failed
    test ah,ah
    jnz failed
    mov eax,[packet_dest]
    mov [packet_source],eax
    xor eax,eax
    mov ax,cs
    shl eax,4
    add eax,target
    cmp eax,40000h-8192
    jae failed
    mov [packet_dest],eax
    call copy
    jc failed
    test ah,ah
    jnz failed
    mov si,source
    mov di,target
%ifdef WRONG_DATA
    xor byte [target+4096],1
%endif
    mov cx,8192
    cld
    repe cmpsb
    jne failed
%endif
    mov al,'B'
    call checkpoint
    mov dx,[block]
    mov ah,0dh
    call far [xms]
    cmp ax,1
    jne failed
    mov dx,[block]
    mov ah,0ah
    call far [xms]
    cmp ax,1
    jne failed
    mov dx,[reserve]
    mov ah,0ah
    call far [xms]
    cmp ax,1
    jne failed
    mov ax,10h
    jmp finish
copy:
    push cs
    pop es
    mov si,packet
    mov ah,87h
    int 15h
    ret
reject:
    call copy
    jnc failed
    cmp ah,2
    jne failed
    ret
checkpoint:
    out 0e9h,al
    xor ah,ah
    int 16h
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
xms dd 0
reserve dw 0
block dw 0
witness_signature db 'XWPROBE!'
physical dd 0
packet db 'XCPY'
packet_length:
    dd 8192
packet_source dd 0
packet_dest dd 0
source times 8192 db 0
target times 8192 db 0
