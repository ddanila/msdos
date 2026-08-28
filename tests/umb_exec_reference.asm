bits 16
org 100h

start:
    cli
    mov sp, stack_top
    sti
    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h
    jc fail
    push cs
    pop ds
    mov [exec_params+4], ds
    mov [exec_params+8], ds
    mov [exec_params+12], ds

    mov ax, 5800h
    int 21h
    jc fail
    mov [saved_strategy], ax
    mov ax, 5802h
    int 21h
    jc fail
    mov [saved_link], al

    mov bx, 1
    mov ax, 5803h
    int 21h
    jc fail_restore
    mov bx, 0040h
    mov ax, 5801h
    int 21h
    jc fail_restore

    push ds
    pop es
    mov bx, exec_params
    mov dx, child_name
    mov ax, 4b00h
    int 21h
    jc fail_restore
    mov ah, 4dh
    int 21h
    cmp ax, 002ah
    jne fail_restore

    mov ax, 5800h
    int 21h
    jc fail_restore
    cmp ax, 0040h
    jne fail_restore
    mov ax, 5802h
    int 21h
    jc fail_restore
    cmp al, 1
    jne fail_restore

    ; The child allocated this size under inherited upper-only policy. The
    ; same allocation succeeding again proves termination reclaimed its UMB.
    mov bx, 40h
    mov ah, 48h
    int 21h
    jc fail_restore
    mov [recovered_segment], ax
    mov es, ax
    mov ah, 49h
    int 21h
    jc fail_restore

    call restore_state
    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov ax, [recovered_segment]
    call print_hex_word
    mov dx, newline
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

fail_restore:
    call restore_state
fail:
    mov dx, fail_message
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

restore_state:
    push ax
    push bx
    mov bx, [saved_strategy]
    mov ax, 5801h
    int 21h
    xor bx, bx
    mov bl, [saved_link]
    mov ax, 5803h
    int 21h
    pop bx
    pop ax
    ret

print_hex_word:
    push ax
    xchg al, ah
    call print_hex_byte
    pop ax
print_hex_byte:
    push ax
    shr al, 1
    shr al, 1
    shr al, 1
    shr al, 1
    call print_hex_nibble
    pop ax
    and al, 0fh
print_hex_nibble:
    cmp al, 9
    jbe .digit
    add al, 'A' - 10
    jmp short .write
.digit:
    add al, '0'
.write:
    mov [character], al
    push bx
    push cx
    push dx
    mov bx, 1
    mov cx, 1
    mov dx, character
    mov ah, 40h
    int 21h
    pop dx
    pop cx
    pop bx
    ret

saved_strategy dw 0
saved_link db 0
recovered_segment dw 0
character db 0
child_name db 'UMBCHILD.COM', 0
command_tail db 0, 13
fcb1 times 16 db 0
fcb2 times 16 db 0
exec_params:
    dw 0
    dw command_tail, 0
    dw fcb1, 0
    dw fcb2, 0
pass_message db 'UMB_EXEC_PASS SEG=', '$'
fail_message db 'UMB_EXEC_FAIL', 13, 10, '$'
newline db 13, 10, '$'

align 16
stack_space times 512 db 0
stack_top:
program_end:
