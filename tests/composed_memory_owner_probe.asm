bits 16
org 100h
    cli
    mov sp, stack_top
    sti
    push cs
    pop ds
    push cs
    pop es
    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h
    jc fail
    mov [params+4], ds
    mov [params+8], ds
    mov [params+12], ds
    mov ax, 5800h
    int 21h
    jc fail
    mov [strategy], ax
    mov ax, 5802h
    int 21h
    jc fail
    mov [link], al
    mov ax, 5803h
    mov bx, 1
    int 21h
    jc fail
    mov ax, 5801h
    mov bx, 40h
    int 21h
    jc fail
    mov bx, 10h
    mov ah, 48h
    int 21h
    jc fail
    cmp ax, 0a000h
    jb fail
    mov [parent_block], ax
    mov es, ax
    xor di, di
    mov cx, 80h
    mov ax, 5aa5h
    cld
    rep stosw
    call largest
    mov [before], bx
    call upper_free
    mov [free_before], ax
    mov ah, 42h
    int 67h
    or ah, ah
    jnz fail
    mov [ems_free], bx
    mov byte [iterations], 16
.child:
    push cs
    pop es
    mov bx, params
    mov dx, child
    mov ax, 4b00h
    int 21h
    jc fail
    mov ah, 4dh
    int 21h
    cmp al, 2ah
    jne fail
    mov [exit_type], ah
    ; A child may unlink the public arena before exit. Its allocations must
    ; still be reclaimed, and the parent's upper allocation must survive.
    mov bx, 1
    mov ax, 5803h
    int 21h
    jc fail
    mov ax, 5800h
    int 21h
    jc fail
    cmp ax, 40h
    jne fail
    call largest
    cmp bx, [before]
    jne accounting_fail
    call upper_free
    cmp ax, [free_before]
    jne accounting_fail
    cmp byte [exit_type], 0
    jne fail
    mov es, [parent_block]
    xor di, di
    mov cx, 80h
    mov ax, 5aa5h
    cld
    repe scasw
    jne fail
    mov ah, 42h
    int 67h
    or ah, ah
    jnz fail
    cmp bx, [ems_free]
    jne fail
    xor byte [tail+1], 'L' ^ 'U'
    dec byte [iterations]
    jnz .child
    mov es, [parent_block]
    mov ah, 49h
    int 21h
    jc fail
    mov ax, 5801h
    mov bx, [strategy]
    int 21h
    jc fail
    mov ax, 5803h
    xor bx, bx
    mov bl, [link]
    int 21h
    jc fail
    mov dx, passed
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
largest:
    mov bx, 0ffffh
    mov ah, 48h
    int 21h
    jnc fail
    cmp ax, 8
    jne fail
    or bx, bx
    jz fail
    ret
upper_free:
    ; Count every free upper extent, not just the largest hole: leaking a
    ; child in a smaller extent must also fail the ownership check.
    mov ah, 52h
    int 21h
    mov si, [es:bx-2]
    xor dx, dx
    mov cx, 512
.walk:
    mov es, si
    cmp byte [es:0], 'M'
    je .valid
    cmp byte [es:0], 'Z'
    jne fail
.valid:
    cmp si, 0a000h
    jb .next
    cmp word [es:1], 0
    jne .next
    add dx, [es:3]
    jc fail
.next:
    cmp byte [es:0], 'Z'
    je .done
    add si, [es:3]
    jc fail
    inc si
    jz fail
    loop .walk
    jmp fail
.done:
    mov ax, dx
    ret
accounting_fail:
    mov dx, accounting_failed
    jmp print_fail
fail:
    mov dx, failed
print_fail:
    mov ah, 9
    int 21h
    mov ax, 11h                  ; stop before returning to a deliberately damaged arena
    out 0f4h, ax
    cli
.halt:
    hlt
    jmp .halt
strategy dw 0
link db 0
parent_block dw 0
before dw 0
free_before dw 0
exit_type db 0
ems_free dw 0
iterations db 0
child db 'OWNCHILD.COM', 0
tail db 1, 'L', 13
fcb1 times 16 db 0
fcb2 times 16 db 0
params dw 0, tail, 0, fcb1, 0, fcb2, 0
passed db 'COMPOSED_OWNER_PASS',13,10,'$'
failed db 'COMPOSED_OWNER_FAIL',13,10,'$'
accounting_failed db 'COMPOSED_OWNER_ACCOUNTING_FAIL',13,10,'$'
align 16
    times 512 db 0
stack_top:
program_end:
