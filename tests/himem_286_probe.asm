bits 16
cpu 286
org 100h

    mov ax, 4300h
    int 2fh
    cmp al, 80h
    jne .early_fail
    mov ax, 4310h
    int 2fh
    mov [entry], bx
    mov [entry+2], es

    xor ah, ah
    call far [entry]
    cmp ax, 0300h
    jne .early_fail
    cmp bx, 0310h
    jne .early_fail

    mov ah, 09h
    mov dx, 16
    call far [entry]
    cmp ax, 1
    jne .early_fail
    mov [handle], dx
    jmp short .moves_begin
.early_fail:
    jmp fail

    ; Repeated conventional-to-XMS-to-conventional moves exercise the 286
    ; protected-mode transition path under cycle-counted CPU emulation.
.moves_begin:
    mov byte [cycle], 0
.move_cycle:
    xor bx, bx
.fill:
    mov al, [cycle]
    xor al, bl
    mov [buffer + bx], al
    inc bx
    cmp bx, 256
    jb .fill

    mov word [move_source_handle], 0
    mov word [move_source_offset], buffer
    mov word [move_source_offset + 2], ds
    mov ax, [handle]
    mov [move_target_handle], ax
    xor ax, ax
    mov al, [cycle]
    and ax, 31
    mov cl, 8
    shl ax, cl
    mov word [move_target_offset], ax
    mov word [move_target_offset + 2], 0
    mov si, move_descriptor
    mov ah, 0bh
    call far [entry]
    cmp ax, 1
    je .move_out_ok
    jmp release_fail
.move_out_ok:

    push ds
    pop es
    mov di, buffer
    mov cx, 128
    rep stosw

    mov ax, [handle]
    mov [move_source_handle], ax
    mov ax, [move_target_offset]
    mov [move_source_offset], ax
    mov word [move_source_offset + 2], 0
    mov word [move_target_handle], 0
    mov word [move_target_offset], buffer
    mov word [move_target_offset + 2], ds
    mov si, move_descriptor
    mov ah, 0bh
    call far [entry]
    cmp ax, 1
    je .move_back_ok
    jmp release_fail
.move_back_ok:

    xor bx, bx
.verify:
    mov al, [cycle]
    xor al, bl
    cmp [buffer + bx], al
    jne release_fail
    inc bx
    cmp bx, 256
    jb .verify
    inc byte [cycle]
    cmp byte [cycle], 64
    jae .moves_done
    jmp .move_cycle
.moves_done:

    mov ah, 0ch
    mov dx, [handle]
    call far [entry]
    cmp ax, 1
    jne release_fail
    mov ah, 0dh
    mov dx, [handle]
    call far [entry]
    cmp ax, 1
    jne release_fail

    mov ah, 0ah
    mov dx, [handle]
    call far [entry]
    cmp ax, 1
    jne fail

    ; XMS 3.0 identifies itself on a 286, but its four 32-bit entry points
    ; must reject without executing a 386 instruction.
    mov ah, 088h
    call far [entry]
    or ax, ax
    jnz fail
    cmp bl, 080h
    jne fail
    mov ah, 089h
    mov dx, 16
    call far [entry]
    or ax, ax
    jnz fail
    cmp bl, 080h
    jne fail
    mov ah, 08eh
    mov dx, 1
    call far [entry]
    or ax, ax
    jnz fail
    cmp bl, 080h
    jne fail
    mov ah, 08fh
    mov bx, 16
    mov dx, 1
    call far [entry]
    or ax, ax
    jnz fail
    cmp bl, 080h
    jne fail
    mov dx, pass_message
    jmp short print

release_fail:
    mov ah, 0ah
    mov dx, [handle]
    call far [entry]
fail:
    mov dx, fail_message
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

print:
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

entry dd 0
handle dw 0
cycle db 0
move_descriptor:
    dd 256
move_source_handle dw 0
move_source_offset dd 0
move_target_handle dw 0
move_target_offset dd 0
pass_message db 'HIMEM_286_PASS', 13, 10, '$'
fail_message db 'HIMEM_286_FAIL', 13, 10, '$'
buffer times 256 db 0
