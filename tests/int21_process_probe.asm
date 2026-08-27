bits 16
org 100h

; Focused contracts for EXEC/wait, IOCTL device classification, and NLS case.

start:
    push cs
    pop ds
    push ds
    pop es

    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h
    jnc memory_ready
    mov dx, fail_4b
    jmp fail
memory_ready:

    mov ax, ds
    mov [exec_command_segment], ax
    mov [exec_fcb1_segment], ax
    mov [exec_fcb2_segment], ax
    mov dx, child_name
    mov bx, exec_block
    mov ax, 4b00h                  ; Load and execute child returning 2Ah.
    int 21h
    jnc exec_ok
    mov dx, fail_4b
    jmp fail
exec_ok:

    mov ah, 4dh                    ; Consume child termination status.
    int 21h
    cmp ah, 0                      ; Normal termination.
    jne wait_failed
    cmp al, 2ah
    je wait_ok
wait_failed:
    mov dx, fail_4d
    jmp fail
wait_ok:

    mov bx, 1                     ; stdout remains the AUX character device.
    mov ax, 4400h
    int 21h
    jc ioctl_failed
    test dx, 80h
    jnz ioctl_ok
ioctl_failed:
    mov dx, fail_44
    jmp fail
ioctl_ok:

    mov dl, 'a'                   ; Active NLS table uppercases ASCII a.
    mov ax, 6520h
    int 21h
    jc nls_failed
    cmp dl, 'A'
    je nls_ok
nls_failed:
    mov dx, fail_65
    jmp fail
nls_ok:

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

child_name db 'I21CHILD.COM', 0
command_tail db 0, 13
exec_block:
    dw 0
    dw command_tail
exec_command_segment dw 0
    dw 5ch
exec_fcb1_segment dw 0
    dw 6ch
exec_fcb2_segment dw 0
pass_message db 'INT21_PROCESS_PASS', 13, 10, '$'
fail_44 db 'INT21_44_FAIL', 13, 10, '$'
fail_4b db 'INT21_4B_FAIL', 13, 10, '$'
fail_4d db 'INT21_4D_FAIL', 13, 10, '$'
fail_65 db 'INT21_65_FAIL', 13, 10, '$'
program_end:
