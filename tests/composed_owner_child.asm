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
    mov bx, 40h
    mov ah, 48h
    int 21h
    jc fail
    cmp ax, 0a000h
    jb fail
    mov es, ax
    mov word [es:0], 0cafeh
    cmp byte [81h], 'U'
    jne .exit
    xor bx, bx
    mov ax, 5803h
    int 21h
    jc fail
.exit:
%ifdef RETAIN_CHILD
    mov dx, (program_end - $$ + 100h + 15) / 16
    mov ax, 312ah                 ; negative control: deliberately remain resident
%else
    mov ax, 4c2ah                 ; leave allocation for process cleanup
%endif
    int 21h
fail:
    mov ax, 4c7fh
    int 21h
align 16
    times 256 db 0
stack_top:
program_end:
