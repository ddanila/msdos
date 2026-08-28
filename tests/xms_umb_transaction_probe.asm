bits 16
org 100h

start:
    push cs
    pop ds
    mov ax, 4300h
    int 2fh
    cmp al, 80h
    jne fail
    mov ax, 4310h
    int 2fh
    mov [xms_entry], bx
    mov [xms_entry + 2], es
    mov ah, 0f0h
    call far [xms_entry]
    mov [mode], cx
    or cx, cx
    jnz rollback_case

    cmp bx, 2
    jne fail
    or ax, ax
    jnz fail
    mov ax, 5802h
    int 21h
    jc fail
    cmp al, 0
    jne fail
    mov bx, 1
    mov ax, 5803h
    int 21h
    jc fail
    mov bx, 0040h
    mov ax, 5801h
    int 21h
    jc fail
    mov bx, 10h
    mov ah, 48h
    int 21h
    jc fail
    cmp ax, 09001h
    jne fail
    mov es, ax
    mov word [es:0], 5aa5h
    cmp word [es:0], 5aa5h
    jne fail
    mov ah, 49h
    int 21h
    jc fail
    jmp short pass

rollback_case:
    mov dx, ax
    cmp cx, 1
    jne .not_partial
    cmp bx, 1
    jne fail
    cmp dx, 1
    jne fail
    jmp short .check_unavailable
.not_partial:
    cmp cx, 2
    jne .not_overlap
    cmp bx, 2
    jne fail
    cmp dx, 2
    jne fail
    jmp short .check_unavailable
.not_overlap:
    cmp cx, 3
    jne .location
    cmp bx, 1
    jne fail
    cmp dx, 1
    jne fail
    jmp short .check_unavailable
.location:
    cmp cx, 4
    jne fail
    cmp bx, 1
    jne fail
    cmp dx, 1
    jne fail
.check_unavailable:
    mov bx, 1
    mov ax, 5803h
    int 21h
    jnc fail
    cmp ax, 1
    jne fail

pass:
    mov dx, pass_message
    mov cx, pass_message_end - pass_message
    jmp short print_and_exit
fail:
    mov dx, fail_message
    mov cx, fail_message_end - fail_message
print_and_exit:
    mov bx, 1
    mov ah, 40h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

xms_entry dd 0
mode dw 0
pass_message db 'XMS_UMB_TRANSACTION_PASS', 13, 10
pass_message_end:
fail_message db 'XMS_UMB_TRANSACTION_FAIL', 13, 10
fail_message_end:
