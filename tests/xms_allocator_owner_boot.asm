bits 16
org 7c00h
    cli
    xor ax,ax
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov sp,7c00h
    sti
    mov bx,8000h
    mov ax,0200h+STAGE_SECTORS
    mov cx,2
    xor dh,dh
    int 13h
    jc failed
    cli
flush_keys:
    in al,64h
    test al,1
    jz keys_empty
    in al,60h
    jmp flush_keys
keys_empty:
    in al,92h
    and al,0feh
    or al,2
    out 92h,al
    lgdt [gdt_ptr]
    mov eax,cr0
    or eax,1
    mov cr0,eax
    jmp dword 8:protected
failed:
    mov al,'!'
    out 0e9h,al
    cli
    hlt
bits 32
protected:
    mov ax,10h
    mov ds,ax
    mov es,ax
    mov esi,8000h
    mov edi,200000h
    mov ecx,STAGE_BYTES
    cld
    rep movsb
    mov edi,210000h
    mov ecx,STAGE_BYTES
    xor eax,eax
    rep stosb                     ; no pre-seeded high allocator
    ; Valid state exists only at the data owner. A code-relative data access
    ; or selecting the code owner's data alias must fail, not read a mirror.
    mov edi,201000h
    mov ecx,STAGE_BYTES-1000h
    xor eax,eax
    rep stosb
    mov ax,10h
    mov gs,ax
    mov ax,38h                    ; bootstrap allocator stays below 1 MiB
%ifdef WRONG_OWNER
    mov ax,30h
%endif
    mov ds,ax
    mov ax,20h
    mov es,ax
    mov ax,28h
    mov ss,ax
    mov esp,0fff0h
    jmp word 18h:0
align 8
gdt:
    dq 0
    dq 00cf9a000000ffffh ; flat 32-bit bootstrap code
    dq 00cf92000000ffffh ; flat physical data
    dq 00009a200000ffffh ; 16-bit code at 2 MiB
    dq 000092210000ffffh ; data owner at 2 MiB + 64 KiB
    dq 000092220000ffffh ; independent stack
    dq 000092200000ffffh ; negative-control data alias of code owner
    dq 000092008000ffffh ; bootstrap data owner at physical 8000h
gdt_ptr:
    dw $-gdt-1
    dd gdt
times 510-($-$$) db 0
dw 0aa55h
