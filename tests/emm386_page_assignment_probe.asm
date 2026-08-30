bits 16
org 100h

    mov ah, 41h
    int 67h
    test ah, ah
    jnz fail
    cmp bx, 0d000h
    jne fail
    mov byte [stage], '2'

    mov ax, 5801h
    int 67h
    test ah, ah
    jnz fail
    mov byte [stage], '3'
    push ds
    pop es
    mov di, pages
    mov ax, 5800h
    int 67h
    test ah, ah
    jnz fail
    mov si, pages
.scan:
    jcxz .scan_done
    cmp word [si+2], 4
    jne .check_sparse
    cmp word [si], 09000h
    jne fail
    inc byte [id4_count]
.check_sparse:
    cmp word [si], 0e000h
    jne .next
    cmp word [si+2], 200
    jne .next
    mov byte [found_sparse], 1
.next:
    add si, 4
    loop .scan
.scan_done:
    cmp byte [found_sparse], 1
    jne fail
    cmp byte [id4_count], 1
    jne fail
    mov byte [stage], '4'
    mov bx, 1
    mov ah, 43h
    int 67h
    test ah, ah
    jnz fail
    mov [handle], dx
    mov byte [stage], '5'
    mov al, 200
    xor bx, bx
    mov ah, 44h
    int 67h
    test ah, ah
    jnz release_fail
    mov byte [stage], '6'
    mov ax, 0e000h
    mov es, ax
    mov word [es:0], 0a55ah
    cmp word [es:0], 0a55ah
    jne release_fail
    mov byte [stage], '7'
    mov al, 200
    mov bx, 0ffffh
    mov dx, [handle]
    mov ah, 44h
    int 67h
    test ah, ah
    jnz release_fail
    mov dx, [handle]
    mov ah, 45h
    int 67h
    test ah, ah
    jnz fail
    mov dx, pass_message
    jmp short print
release_fail:
    mov dx, [handle]
    mov ah, 45h
    int 67h
fail:
    mov dl, [stage]
    mov ah, 02h
    int 21h
    mov dl, 13
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

handle dw 0
stage db '1'
found_sparse db 0
id4_count db 0
pages times 52*4 db 0
pass_message db 'EMM386_PAGE_ASSIGNMENT_PASS', 13, 10, '$'
fail_message db 'EMM386_PAGE_ASSIGNMENT_FAIL', 13, 10, '$'
