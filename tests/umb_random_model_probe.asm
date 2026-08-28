bits 16
org 100h

%define SLOT_COUNT 32
%define ITERATIONS 1000
%define ERROR_NOT_ENOUGH_MEMORY 8

start:
    cli
    mov sp, stack_top
    sti
    push cs
    pop ds
    push cs
    pop es

    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h
    jc fail
    mov ah, 51h
    int 21h
    mov [psp], bx
    mov bx, 1
    mov ax, 5803h
    int 21h
    jc fail
    mov bx, 0040h
    mov ax, 5801h
    int 21h
    jc fail

    mov cx, ITERATIONS
.iteration:
    push cx
    call random_word
    mov bx, ax
    and bx, SLOT_COUNT - 1
    shl bx, 1
    mov si, bx
    cmp word [slot_segment + si], 0
    je .allocate
    test ah, 3
    jz .free
    call resize_slot
    jc fail_pop
    jmp short .validate
.free:
    call free_slot
    jc fail_pop
    jmp short .validate
.allocate:
    call allocate_slot
    jc fail_pop
.validate:
    call validate_model
    jc fail_pop
    pop cx
    loop .iteration

    xor si, si
.free_all:
    cmp word [slot_segment + si], 0
    je .next_slot
    call free_slot
.next_slot:
    add si, 2
    cmp si, SLOT_COUNT * 2
    jb .free_all
    call validate_model
    jc fail

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

fail_pop:
    pop cx
fail:
    mov dx, fail_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 12h
    out dx, ax
    mov ax, 4c01h
    int 21h

allocate_slot:
    call random_word
    and bx, 001fh
    inc bx
    push bx
    call random_word
    xor dx, dx
    mov bx, 3
    div bx
    mov bx, dx
    add bx, 0040h
    mov ax, 5801h
    int 21h
    pop bx
    jc .bad
    mov ah, 48h
    int 21h
    jc .allocation_failed
    cmp ax, 09000h
    jbe .bad
    cmp ax, 09500h
    jae .bad
    mov [slot_segment + si], ax
    mov [slot_size + si], bx
    call write_pattern
    ret
.allocation_failed:
    cmp ax, ERROR_NOT_ENOUGH_MEMORY
    jne .bad
    ret
.bad:
    stc
    ret

free_slot:
    call verify_pattern
    jc .bad
    mov ax, [slot_segment + si]
    mov es, ax
    mov ah, 49h
    int 21h
    jc .bad
    mov word [slot_segment + si], 0
    mov word [slot_size + si], 0
    clc
    ret
.bad:
    stc
    ret

resize_slot:
    call verify_pattern
    jc .bad
    call random_word
    and bx, 003fh
    inc bx
    mov ax, [slot_segment + si]
    mov es, ax
    mov ah, 4ah
    int 21h
    jnc .resized
    cmp ax, ERROR_NOT_ENOUGH_MEMORY
    jne .bad
    mov ax, es
    dec ax
    mov es, ax
    mov bx, [es:3]
.resized:
    mov [slot_size + si], bx
    call write_pattern
    clc
    ret
.bad:
    stc
    ret

write_pattern:
    mov ax, [slot_segment + si]
    mov es, ax
    mov ax, si
    or ax, 0a500h
    mov [es:0], ax
    mov bx, [slot_size + si]
    shl bx, 1
    shl bx, 1
    shl bx, 1
    shl bx, 1
    mov [es:bx - 2], ax
    ret

verify_pattern:
    mov ax, [slot_segment + si]
    mov es, ax
    mov dx, si
    or dx, 0a500h
    cmp [es:0], dx
    jne .bad
    mov bx, [slot_size + si]
    shl bx, 1
    shl bx, 1
    shl bx, 1
    shl bx, 1
    cmp [es:bx - 2], dx
    jne .bad
    clc
    ret
.bad:
    stc
    ret

validate_model:
    push si
    xor si, si
.slot:
    mov ax, [slot_segment + si]
    or ax, ax
    jz .next
    call verify_pattern
    jc .bad
    mov es, ax
    dec ax
    mov es, ax
    mov bx, [psp]
    cmp [es:1], bx
    jne .bad
    mov bx, [slot_size + si]
    cmp [es:3], bx
    jne .bad

    xor di, di
.other:
    cmp di, si
    je .other_next
    mov dx, [slot_segment + di]
    or dx, dx
    jz .other_next
    mov ax, [slot_segment + si]
    mov bx, ax
    add bx, [slot_size + si]
    mov cx, dx
    add cx, [slot_size + di]
    cmp ax, cx
    jae .other_next
    cmp dx, bx
    jb .bad
.other_next:
    add di, 2
    cmp di, SLOT_COUNT * 2
    jb .other
.next:
    add si, 2
    cmp si, SLOT_COUNT * 2
    jb .slot
    pop si
    clc
    ret
.bad:
    pop si
    stc
    ret

random_word:
    mov ax, [seed]
    mov bx, 25173
    mul bx
    add ax, 13849
    mov [seed], ax
    ret

seed dw 0c0deh
psp dw 0
slot_segment times SLOT_COUNT dw 0
slot_size times SLOT_COUNT dw 0
pass_message db 'UMB_RANDOM_MODEL_PASS', 13, 10, '$'
fail_message db 'UMB_RANDOM_MODEL_FAIL', 13, 10, '$'
stack_space times 256 db 0
stack_top:
program_end:
