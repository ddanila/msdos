bits 16
org 100h


start:
    push cs
    pop ds

    mov ax, 3523h
    int 21h
    mov [old_int23_off], bx
    mov [old_int23_seg], es
    mov ax, 3528h
    int 21h
    mov [old_int28_off], bx
    mov [old_int28_seg], es

    mov dx, break_handler
    mov ax, 2523h
    int 21h
    mov dx, idle_handler
    mov ax, 2528h
    int 21h

    mov dx, ready_message
    mov ah, 09h
    int 21h

    mov ah, 01h
    int 21h
    cmp al, 'X'
    jne input_failed
    cmp word [break_count], 1
    jne break_failed
    cmp word [idle_count], 0
    je idle_failed

    call restore_vectors
    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

input_failed:
    mov dx, fail_input
    jmp fail
break_failed:
    mov dx, fail_break
    jmp fail
idle_failed:
    mov dx, fail_idle
fail:
    push dx
    call restore_vectors
    pop dx
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

restore_vectors:
    push ds
    mov dx, [old_int23_off]
    mov ax, [old_int23_seg]
    mov ds, ax
    mov ax, 2523h
    int 21h
    mov dx, [cs:old_int28_off]
    mov ax, [cs:old_int28_seg]
    mov ds, ax
    mov ax, 2528h
    int 21h
    pop ds
    ret

break_handler:
    inc word [cs:break_count]
    iret

idle_handler:
    inc word [cs:idle_count]
    iret

old_int23_off dw 0
old_int23_seg dw 0
old_int28_off dw 0
old_int28_seg dw 0
break_count dw 0
idle_count dw 0
ready_message db 'DOS_ASYNC_READY', 13, 10, '$'
pass_message db 'DOS_ASYNC_INTERRUPT_PASS', 13, 10, '$'
fail_input db 'DOS_ASYNC_INPUT_FAIL', 13, 10, '$'
fail_break db 'INT23_BREAK_CALLBACK_FAIL', 13, 10, '$'
fail_idle db 'INT28_IDLE_CALLBACK_FAIL', 13, 10, '$'
