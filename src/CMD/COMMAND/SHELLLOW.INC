; Retained entries for whole-shell HMA execution. Only active high instances
; use the repository HIMEM hardware restore call; fallback keeps its old ABI.
PUBLIC shell_high_active,shell_restore_a20,shell_int21_low,shell_int2f_low
shell_high_active DB 0
shell_restore_a20 PROC NEAR
    pushf
    cmp byte ptr cs:[shell_high_active],0
    je shell_a20_done
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov ax,0e705h
    int 2fh
    cmp ax,0e7ffh
    jne shell_a20_failed
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
shell_a20_done:
    popf
    ret
shell_a20_failed:
    cli
    hlt
    jmp shell_a20_failed
shell_restore_a20 ENDP
shell_int21_low PROC FAR
    int 21h
    call shell_restore_a20
    retf
shell_int21_low ENDP
shell_int2f_low PROC FAR
    int 2fh
    call shell_restore_a20
    retf
shell_int2f_low ENDP
