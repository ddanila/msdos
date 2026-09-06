; Exercise every requested alternate register set through the public EMS API.
bits 16
org 100h
%ifdef SWITCH_SETS
    ; This fixed B=4000 profile has bankable conventional RAM. Its initial
    ; identity mappings must be reserved in handle zero, not NULL_PAGE slots.
    xor dx,dx
    mov ah,4ch
    int 67h
    test ah,ah
    jnz failed
    test bx,bx
    jz failed
%endif
    xor si,si
allocate:
    cmp si,ALTREGS
    jae exhausted
    mov ax,5b03h
    int 67h
    test ah,ah
    jnz failed
    test bl,bl
    jz failed
    mov [register_ids+si],bl
%ifdef SWITCH_SETS
    ; Separate gate: selection remaps physical windows, unlike allocation.
    mov ax,5b01h
    int 67h
    test ah,ah
    jnz failed
%endif
    inc si
    jmp allocate
exhausted:
    mov ax,5b03h
    int 67h
    cmp ah,9bh
    jne failed
%ifdef SWITCH_SETS
    xor bx,bx
    mov es,bx
    xor di,di
    mov ax,5b01h
    int 67h
    test ah,ah
    jnz failed
%endif
release:
    test si,si
    jz reuse
    dec si
    mov bl,[register_ids+si]
    mov ax,5b04h
    int 67h
    test ah,ah
    jnz failed
    jmp release
reuse:
%if ALTREGS > 0
    mov ax,5b03h
    int 67h
    test ah,ah
    jnz failed
    mov ax,5b04h
    int 67h
    test ah,ah
    jnz failed
%endif
    mov ax,ALTREGS
    jmp emit
failed:
    mov ax,0ffffh
emit:
    mov bx,ax
    mov dx,0e9h
    mov al,'A'
    out dx,al
    mov al,'C'
    out dx,al
    mov ax,bx
    out dx,al
    mov al,ah
    out dx,al
    push ds
    pop es
    mov ax,4c00h
    int 21h
register_ids times 254 db 0
