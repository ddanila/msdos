bits 16
org 100h

    push ds
    pop es
    mov di, info
    mov ax, 5900h
    int 67h
    test ah, ah
    jnz fail
    cmp word [info+2], 2
    jne fail

    mov ah, 41h
    int 67h
    test ah, ah
    jnz fail
    mov [frame], bx
    mov bx, 2
    mov ah, 43h
    int 67h
    test ah, ah
    jnz fail
    mov [handle], dx
    xor bx, bx
    mov ax, 4400h
    int 67h
    test ah, ah
    jnz fail
    mov es, [frame]
    mov ax, 0a55ah
    mov cx, 8192
    xor di, di
    cld
    rep stosw

    ; Both new sets must clone the currently mapped page, not an empty map.
    mov ax, 5b03h
    int 67h
    test ah, ah
    jnz fail
    mov [set1], bl
    mov ax, 5b03h
    int 67h
    test ah, ah
    jnz fail
    mov [set2], bl
    mov ax, 5b03h
    int 67h
    test ah, ah
    jz fail

    ; Descending and repeated selections must not inherit comparison carry.
    mov bl, [set2]
    mov ax, 5b01h
    int 67h
    test ah, ah
    jnz fail
    call check_page_zero
    ; Change only set 2: set 1 and set zero must retain page zero.
    mov dx, [handle]
    mov bx, 1
    mov ax, 4400h
    int 67h
    test ah, ah
    jnz fail
    mov es, [frame]
    mov ax, 0b66bh
    mov cx, 8192
    xor di, di
    cld
    rep stosw
    mov bl, [set1]
    mov ax, 5b01h
    int 67h
    test ah, ah
    jnz fail
    call check_page_zero
    mov ax, 5b01h
    int 67h
    test ah, ah
    jnz fail
    mov ax, 5b00h
    int 67h
    test ah, ah
    jnz fail
    cmp bl, [set1]
    jne fail
    mov ax, 5b04h
    int 67h
    cmp ah, 9dh
    jne fail
    ; Switching back must restore set 2's independent modified mapping.
    mov bl, [set2]
    mov ax, 5b01h
    int 67h
    test ah, ah
    jnz fail
    mov ax, 0b66bh
    call check_page
    ; Return to internal set zero, with no external restore buffer.
    xor bx, bx
    mov es, bx
    xor di, di
    mov ax, 5b01h
    int 67h
    test ah, ah
    jnz fail
    call check_page_zero

    mov bl, [set1]
    mov ax, 5b04h
    int 67h
    test ah, ah
    jnz fail
    mov bl, [set2]
    mov ax, 5b04h
    int 67h
    test ah, ah
    jnz fail
    mov bl, [set2]
    mov ax, 5b04h
    int 67h
    cmp ah, 9dh
    jne fail
    ; A reused record must clone current set zero, not its old page-one map.
    mov ax, 5b03h
    int 67h
    test ah, ah
    jnz fail
    mov [set1], bl
    mov ax, 5b03h
    int 67h
    test ah, ah
    jnz fail
    mov [set2], bl
    mov ax, 5b01h
    int 67h
    test ah, ah
    jnz fail
    call check_page_zero
    xor bx, bx
    mov es, bx
    xor di, di
    mov ax, 5b01h
    int 67h
    test ah, ah
    jnz fail
    mov bl, [set1]
    mov ax, 5b04h
    int 67h
    test ah, ah
    jnz fail
    mov bl, [set2]
    mov ax, 5b04h
    int 67h
    test ah, ah
    jnz fail
    mov bx, 0ffffh
    mov dx, [handle]
    mov ax, 4400h
    int 67h
    test ah, ah
    jnz fail
    mov dx, [handle]
    mov ah, 45h
    int 67h
    test ah, ah
    jnz fail
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

check_page_zero:
    push ax
    mov ax, 0a55ah
    call check_page
    pop ax
    ret

check_page:
    push cx
    push di
    mov es, [frame]
    mov cx, 8192
    xor di, di
    cld
    repe scasw
    jne fail
    pop di
    pop cx
    ret

frame dw 0
handle dw 0
set1 db 0
set2 db 0
info times 10 db 0
pass_message db 'EMM386_ALTREG_LIMIT_PASS', 13, 10, '$'
fail_message db 'EMM386_ALTREG_LIMIT_FAIL', 13, 10, '$'
