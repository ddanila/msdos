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

    ; Core status, page-frame, page-count, version, and handle-count queries
    ; execute through the protected copy even while AUTO is initially idle.
    mov ah, 40h
    int 67h
    test ah, ah
    jnz fail
    mov ah, 42h
    int 67h
    test ah, ah
    jnz fail
    test dx, dx
    jz fail
    cmp bx, dx
    ja fail

    ; Function 59h is serviced through the protected/XMS copy.  In AUTO mode
    ; this must enter virtual mode for the request and return cleanly.
    mov ax, 5901h
    int 67h
    test ah, ah
    jnz fail
    test dx, dx
    jz fail
    cmp bx, dx
    ja fail
    mov ah, 46h
    int 67h
    test ah, ah
    jnz fail
    cmp al, 40h
    jne fail
    mov ah, 4bh
    int 67h
    test ah, ah
    jnz fail
    cmp bx, 1
    jb fail

    ; Internal handle zero is always present.  Keep the far-buffer 4C/4D pair
    ; covered here as retained-low neighbors while AUTO remains idle.
    xor dx, dx
    mov ah, 4ch
    int 67h
    test ah, ah
    jnz fail
    push cs
    pop es
    mov di, handle_rows
    mov ah, 4dh
    int 67h
    test ah, ah
    jnz fail
    cmp bx, 1
    jb fail

    ; Directory capacity is also protected and must make the same temporary
    ; AUTO transition without requiring an application handle.
    mov ax, 5402h
    int 67h
    test ah, ah
    jnz fail
    cmp bx, 2
    jb fail

    ; Attribute query runs protected from inactive AUTO.  Following it with a
    ; retained-low mappable-address query proves the temporary return is clean.
    xor dx, dx
    mov ax, 5202h
    int 67h
    test ah, ah
    jnz fail
    mov ax, 5801h
    int 67h
    test ah, ah
    jnz fail
    test cx, cx
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
handle_rows times 4 db 0
pass_message db 'EMM386_ACTIVATION_PASS', 13, 10, '$'
fail_message db 'EMM386_ACTIVATION_FAIL', 13, 10, '$'
