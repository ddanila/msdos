; Architectural witness, not the installed HIMEM gateway. A copied HMA leaf
; calls a low simulated firmware service which really disables A20. Only the
; low gate may recover A20 before RETF resumes the leaf. DS remains low.
bits 16
org 100h

start:
    push cs
    pop ds
    mov [saved_sp],sp
    mov [gate_ptr+2],ds
    mov ax,1236h
    mov cx,high_end-high_start
    int 2fh
    or ax,ax
    jz failure
    mov ax,es
    cmp ax,0ffffh
    jne failure
    mov [high_ptr],di
    mov [high_ptr+2],es
    mov si,high_start
    mov cx,high_end-high_start
    cld
    rep movsb
    mov eax,12345678h
    mov edx,87654321h
    call far [high_ptr]
    jnc failure
    cmp eax,11223344h
    jne failure
    cmp edx,55667788h
    jne failure
    cmp byte [returned_high],1
    jne failure
    cmp byte [observed_off],1
    jne failure
    mov dx,pass_message
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h

high_start:
    call far [gate_ptr]       ; DS addresses low data, not the HMA code segment
    mov byte [returned_high],1 ; MOV must preserve the firmware carry flag
    retf
high_end:

low_gate:
    call simulated_firmware
    pushf
    pushad
    push ds
    push es
    mov ax,0e705h            ; repository low A20 recovery; no XMS count change
    int 2fh
    cmp ax,0e7ffh
    jne failure             ; test abort stays low; no unsafe HMA return
    pop es
    pop ds
    popad
    popf
    retf
low_gate_end:

simulated_firmware:
    ; As in an XMS alias test, preserve one low word under CLI and make it
    ; differ from its high counterpart. Restore it on both outcomes.
    pushf
    cli
    push ds
    push es
    push bx
    xor ax,ax
    mov ds,ax
    dec ax
    mov es,ax
    mov bx,[500h]
    mov ax,[es:510h]
    not ax
    mov [500h],ax
    cmp ax,[es:510h]
    je .restore_failure
    in al,92h
    and al,0fch
    out 92h,al
    mov ax,[500h]
    cmp ax,[es:510h]
    jne .restore_failure
    mov [500h],bx
    pop bx
    pop es
    pop ds
    popf
    mov byte [observed_off],1
    mov eax,11223344h
    mov edx,55667788h
    stc                     ; firmware error status must survive A20 recovery
    ret
.restore_failure:
    mov [500h],bx
    pop bx
    pop es
    pop ds
    popf
    jmp failure

failure:
    ; Diagnostic abort only: no claim of a production nested-frame unwind.
    push cs
    pop ds
    mov sp,[saved_sp]
    in al,92h
    and al,0feh
    or al,2
    out 92h,al
    mov dx,fail_message
    mov ah,9
    int 21h
    mov ax,4c01h
    int 21h

saved_sp dw 0
gate_ptr dw low_gate,0
high_ptr dd 0
returned_high db 0
observed_off db 0
pass_message db 'HMA_LOW_RETURN_PASS',13,10,'$'
fail_message db 'HMA_LOW_RETURN_FAILURE',13,10,'$'
