bits 16
org 100h

    mov ax, 5801h
    int 67h
    test ah, ah
    jnz fail
    cmp cx, 52
    ja fail
    push ds
    pop es
    mov di, pages
    mov ax, 5800h
    int 67h
    test ah, ah
    jnz fail
    mov si, pages
    xor dx, dx
.scan:
    jcxz .done
    cmp word [si], 1000h
    jne .next
    mov dl, 1
.next:
    add si, 4
    loop .scan
.done:
%ifdef EXPECT_LOW
    cmp dl, 1
    jne fail
%else
    test dl, dl
    jnz fail
%endif
    mov dx, pass_message
    jmp short print
fail:
    mov dx, fail_message
print:
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

pages times 52*4 db 0
pass_message db 'EMM386_BANKING_BASE_PASS', 13, 10, '$'
fail_message db 'EMM386_BANKING_BASE_FAIL', 13, 10, '$'
