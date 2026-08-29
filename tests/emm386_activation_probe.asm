bits 16
org 100h

%ifndef EXPECT_EMS
%error EXPECT_EMS must be defined as 0 or 1
%endif
%ifndef EXPECT_UMB
%error EXPECT_UMB must be defined as 0 or 1
%endif

start:
    mov ah, 41h
    int 67h
%if EXPECT_EMS
    test ah, ah
    jnz fail
    test bx, bx
    jz fail
%else
    test ah, ah
    jz fail
%endif

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
%if EXPECT_UMB
    jc fail_restore
    mov bx, 1
    mov cx, 4d55h
    mov si, 2142h
    mov di, 0a55ah
    mov ax, 5809h
    int 21h
    jc fail_restore
    or ax, ax
    jz fail_restore
%ifdef EXPECT_ONE_REGION
    mov bx, 2
    mov cx, 4d55h
    mov si, 2142h
    mov di, 0a55ah
    mov ax, 5809h
    int 21h
    jnc fail_restore
%endif
    mov bx, 0040h
    mov ax, 5801h
    int 21h
    jc fail_restore
    mov bx, 1
    mov ah, 48h
    int 21h
    jc fail_restore
    mov es, ax
    mov ah, 49h
    int 21h
    jc fail_restore
%else
    jnc fail_restore
    cmp ax, 1
    jne fail_restore
%endif

    call restore_state
    mov dx, pass_message
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

saved_strategy dw 0
saved_link db 0
pass_message db 'EMM386_ACTIVATION_PASS', 13, 10, '$'
fail_message db 'EMM386_ACTIVATION_FAIL', 13, 10, '$'
