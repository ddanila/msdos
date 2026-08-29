bits 16
org 100h

start:
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
    jc fail_alloc

    mov ah, 30h
    int 21h
    cmp al, 5
    jne fail_version
    cmp ah, 0
    jne fail_version

    mov ax, 5802h
    int 21h
    jc fail_link
    or al, al
    jnz fail_link
    mov bx, 1
    mov ax, 5803h
    int 21h
    jnc fail_link
    cmp ax, 1
    jne fail_link

    mov bx, 16
    mov ah, 48h
    int 21h
    jc fail_alloc
    cmp ax, 0a000h
    jae fail_alloc
    mov es, ax
    mov ah, 49h
    int 21h
    jc fail_alloc

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

fail_version:
    mov dx, fail_version_message
    jmp short fail
fail_link:
    mov dx, fail_link_message
    jmp short fail
fail_alloc:
    mov dx, fail_alloc_message
fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

pass_message db 'PRE386_FALLBACK_PASS', 13, 10, '$'
fail_version_message db 'PRE386_VERSION_FAIL', 13, 10, '$'
fail_link_message db 'PRE386_LINK_FAIL', 13, 10, '$'
fail_alloc_message db 'PRE386_ALLOC_FAIL', 13, 10, '$'
stack_space times 128 db 0
stack_top:
program_end:
