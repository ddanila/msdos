bits 16
org 100h

    mov ah, 40h
    int 67h
%ifdef EXPECT_INSTALLED
    test ah, ah
    jnz fail
%else
    test ah, ah
    jz fail
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

pass_message db 'EMM386_INSTALL_EXPECTATION_PASS', 13, 10, '$'
fail_message db 'EMM386_INSTALL_EXPECTATION_FAIL', 13, 10, '$'
