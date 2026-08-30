bits 16
org 100h

%ifndef EXPECT_FRAME
%error EXPECT_FRAME is required
%endif

    mov ah, 41h
    int 67h
    test ah, ah
    jnz fail
    cmp bx, EXPECT_FRAME
    jne fail
    mov dx, pass_message
    jmp short print
fail:
    mov ax, bx
    call print_hex
    mov dl, 13
    mov ah, 02h
    int 21h
    mov dl, 10
    int 21h
    mov dx, fail_message
print:
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

print_hex:
    mov cx, 4
.next:
    rol ax, 4
    mov dl, al
    and dl, 0fh
    add dl, '0'
    cmp dl, '9'
    jbe .emit
    add dl, 7
.emit:
    push ax
    mov ah, 02h
    int 21h
    pop ax
    loop .next
    ret

pass_message db 'EMM386_FRAME_PASS', 13, 10, '$'
fail_message db 'EMM386_FRAME_FAIL', 13, 10, '$'
