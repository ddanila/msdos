; Restrict maximum-allocation queries by two paragraphs while a child shell runs.
; Its preloaded transient then has to move even if the additive checksum matches.
bits 16
cpu 8086
org 100h
    mov sp, 0ff0h
    mov bx, 100h
    mov ah, 4ah
    int 21h
    jc fail
    mov ax, 3521h
    int 21h
    mov [old21], bx
    mov [old21+2], es
    mov dx, hook
    mov ax, 2521h
    int 21h
    push cs
    pop es
    mov [params+4], es
    mov [params+8], es
    mov [params+12], es
    mov dx, shell
    mov bx, params
    mov ax, 4b00h
    int 21h
    pushf
    pop word [cs:exec_flags]
    mov ax, cs
    mov ds, ax
    mov ss, ax
    mov sp, 0ff0h
    mov dx, [old21]
    mov ax, [old21+2]
    mov ds, ax
    mov ax, 2521h
    int 21h
    push cs
    pop ds
    test word [exec_flags], 1
    jnz fail
    cmp word [queries], 0
    je fail
    mov dx, exercised
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
fail:
    mov ax, 4c01h
    int 21h
hook:
    cmp ah, 48h
    jne chain
    cmp bx, 0ffffh
    jne chain
    pushf
    call far [cs:old21]
    jnc returned
    cmp ax, 8
    jne returned
    cmp bx, 2
    jbe returned
    sub bx, 2
    inc word [cs:queries]
returned:
    ; These oversized queries must return failure; preserve caller IF and TF.
    push bp
    mov bp, sp
    or word [ss:bp+6], 1
    pop bp
    iret
chain:
    jmp far [cs:old21]
old21 dd 0
queries dw 0
exec_flags dw 0
shell db 'A:\COMMAND.COM',0
params dw 0, tail, 0, 5ch, 0, 6ch, 0
tail db tail_end-tail-1
    db ' /C ECHO SHIFT_RECOVERED'
tail_end db 13
exercised db 'SHIFT_QUERY_EXERCISED',13,10,'$'
