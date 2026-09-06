; One guarded entry remains usable without repeating discovery. Revocation
; keeps this low guard resident; it does NOT free backing or model an OS reset.
check_common_binding:
    mov es,[himem_segment]
    mov eax,[es:COMMON_BINDING_OFFSET]
    mov [cb_entry],eax
    shr eax,16
    test ax,ax
    jz umb_failed
    mov es,ax
    cmp byte [es:COMMON_GUARD_OFFSET],1
    jne umb_failed
    pushf
    cli
    xor ax,ax
    mov es,ax
    mov eax,[es:15h*4]
    mov [cb_old_i15],eax
    mov word [es:15h*4],cb_i15
    mov [es:15h*4+2],cs
    mov ah,8
    UMB_CALL
    test ax,ax
    jz umb_failed
    call pm_move                ; prior probe leaves a zero-length descriptor
    cmp ax,1
    jne umb_failed
    call umb_largest
    cmp bl,8eh
    je umb_failed
    mov es,[cb_entry+2]
    mov byte [es:COMMON_GUARD_OFFSET],0
    mov ax,0e7c0h
    clc
    pushf
    call far [cb_entry]
    jnc umb_failed
    mov ah,8
    UMB_CALL
    test ax,ax
    jnz umb_failed
    cmp bl,8eh
    jne umb_failed
    mov es,[cb_entry+2]
    mov byte [es:COMMON_GUARD_OFFSET],1
    mov ah,8
    UMB_CALL
    test ax,ax
    jz umb_failed
    cmp word [cb_discoveries],0
    jne umb_failed
    xor ax,ax
    mov es,ax
    mov eax,[cb_old_i15]
    mov [es:15h*4],eax
    popf
    mov dx,0e9h
    mov al,'C'
    out dx,al
    mov al,'B'
    out dx,al
    mov ax,[cb_entry]
    call word_out
    mov ax,[cb_entry+2]
    call word_out
    mov ax,1
    call word_out
    ret
cb_i15:
    cmp ax,0e7c0h
    je .refuse
    cmp ax,0e7d0h
    je .refuse
    jmp far [cs:cb_old_i15]
.refuse:
    inc word [cs:cb_discoveries]
    xor ax,ax
    iret
cb_entry dd 0
cb_old_i15 dd 0
cb_discoveries dw 0
