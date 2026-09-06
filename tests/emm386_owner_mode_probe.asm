; Repository EMM386 only: validate its installed control-entry signature.
; Queries may enter protected mode temporarily; AUTO must be idle on return.
bits 16
org 100h

%ifndef EXPECT_IDLE_STATUS
%define EXPECT_IDLE_STATUS 3
%endif

start:
    push cs
    pop ds
    mov ax, 3567h
    int 21h
    mov di, 20
    mov si, signature
    mov cx, signature_end - signature
    cld
    repe cmpsb
    jne failed
    mov ax, [es:18]
    mov [control], ax
    mov [control+2], es
    xor ax, ax
    call far [control]
    mov [original], ah
    mov ax, 0102h
    call far [control]
    jc failed
    mov byte [expected], EXPECT_IDLE_STATUS
    call check_mode

    mov ah, 40h
    call query
    mov ah, 41h
    call query
    mov ah, 42h
    call query
    mov ah, 46h
    call query
    mov ah, 4bh
    call query
    xor dx, dx
    mov ah, 4ch
    call query
    push cs
    pop es
    mov di, rows
    mov ah, 4dh
    call query
    xor dx, dx
    mov ax, 5202h
    call query
    mov ax, 5402h
    call query
    mov ax, 5801h
    call query
    mov ax, 5901h
    call query

    ; A live application handle keeps AUTO active; freeing it releases mode.
    mov byte [expected], 2
    mov bx, 1
    mov ah, 43h
    call query
    mov [handle], dx
    mov ah, 42h
    call query
    mov dx, [handle]
    mov byte [expected], EXPECT_IDLE_STATUS
    mov ah, 45h
    call query
    mov word [handle], 0

    mov ax, 0101h
    call far [control]
    jc failed
    mov byte [expected], 1
    ; Explicit OFF rejects all supported slots without dereferencing tables.
    mov bl, 40h
.off:
    mov ah, bl
    int 67h
    cmp bl, 49h
    je .reserved
    cmp bl, 4ah
    je .reserved
    cmp ah, 81h
    jne failed
    jmp .checked
.reserved:
    cmp ah, 84h
    jne failed
.checked:
    call check_mode
    inc bl
    cmp bl, 5dh
    jbe .off
    call restore
    mov dx, passed
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

query:
    int 67h
    test ah, ah
    jnz failed
check_mode:
    pusha
    push ds
    push es
    xor ax, ax
    call far [cs:control]
    cmp ah, [cs:expected]
    jne failed
    pop es
    pop ds
    popa
    ret

restore:
    mov al, [original]
    cmp al, 2
    jb .set
    mov al, 2
.set:
    mov ah, 1
    call far [control]
    ret

failed:
    ; This is a disposable boot fixture; do not resume tests after failure.
    mov dx, failure
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 11h
    out dx, ax
    mov ax, 4c01h
    int 21h

control dd 0
handle dw 0
original db 0
expected db 3
rows times 256*4 db 0
signature db 'MICROSOFT EXPANDED MEMORY MANAGER 386'
signature_end:
passed db 'EMM386_OWNER_MODE_PASS',13,10,'$'
failure db 'EMM386_OWNER_MODE_FAIL',13,10,'$'
