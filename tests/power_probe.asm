bits 16
org 100h

    mov ax, 0xe800
    int 0x2f
    cmp ax, 0xe8ff
    jne fail
    cmp di, 0x5057
    jne fail
    cmp bl, 4
    jne fail
    mov [apm_present], bh
    mov [apm_before], si
    mov bl, 1
    mov ax, 0xe801
    int 0x2f
    cmp ax, 0xe8ff
    jne fail
    int 0x28
    mov ax, 0xe800
    int 0x2f
    cmp byte [apm_present], 0
    je .set_max
    cmp si, [apm_before]
    jbe fail
.set_max:
    mov bl, 4
    mov ax, 0xe801
    int 0x2f
    cmp ax, 0xe8ff
    jne fail
    mov ax, 0xe800
    int 0x2f
    mov bp, dx
    mov cx, 16
.idle:
    int 0x28
    loop .idle
    mov ax, 0xe800
    int 0x2f
    cmp dx, bp
    jbe fail
    mov ax, 0xe803
    int 0x2f
    cmp ax, 0xe8ff
    jne fail
    mov [poll_before], bx
    mov [busy_before], cx
    mov [halt_before], si
    mov cx, 16
.poll:
    mov ah, 1
    int 0x16
    loop .poll
    mov ah, 0x0f
    int 0x10
    mov ah, 0x30
    int 0x21
    mov ax, 0xe803
    int 0x2f
    sub bx, [poll_before]
    cmp bx, 16
    jb fail
    cmp cx, [busy_before]
    jbe fail
    cmp si, [halt_before]
    jbe fail
    mov bl, 5
    mov ax, 0xe801
    int 0x2f
    cmp ax, 0
    jne fail
    cmp bh, 1
    jne fail
    mov ax, 0xe800
    int 0x2f
    cmp bl, 4
    jne fail
    mov dx, pass_message
    jmp short print
fail:
    mov dx, fail_message
print:
    mov ah, 9
    int 0x21
    mov ax, 0x4c00
    int 0x21

pass_message db 'POWER_IDLE_PASS', 13, 10, '$'
fail_message db 'POWER_IDLE_FAIL', 13, 10, '$'
apm_present db 0
apm_before dw 0
poll_before dw 0
busy_before dw 0
halt_before dw 0
