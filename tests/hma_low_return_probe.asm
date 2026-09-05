; Architectural witness, not the installed HIMEM gateway. Copied nested HMA code
; calls a low simulated firmware service which really disables A20. Only the
; low gate may recover A20 before RETF resumes the leaf. DS remains low.
bits 16
org 100h

start:
    push cs
    pop ds
    mov [saved_sp],sp
    mov [gate_ptr+2],ds
    mov [dispatch_ptr+2],ds
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
    mov cx,1234h
    mov si,2345h
    mov di,3456h
    mov bp,4567h
    call far [dispatch_ptr]
    jnc failure
    cmp eax,11223344h
    jne failure
    cmp edx,55667788h
    jne failure
    cmp byte [returned_high],1
    jne failure
    cmp byte [observed_off],1
    jne failure
    call check_frame

    ; Suppress recovery after the actual A20-off transition. No instruction
    ; following the high call may run; the low dispatcher returns XMS error 82h.
    mov byte [force_failure],1
    mov byte [returned_high],0
    mov byte [observed_off],0
    call far [dispatch_ptr]
    jnc failure
    cmp ax,0
    jne failure
    cmp bl,82h
    jne failure
    cmp byte [returned_high],0
    jne failure
    cmp byte [observed_off],1
    jne failure
    call check_frame
    mov ax,0e705h             ; back in low caller; restore hardware for next call
    int 2fh
    cmp ax,0e7ffh
    jne failure
    mov byte [force_failure],0
    call far [dispatch_ptr]
    jnc failure
    cmp byte [returned_high],1
    jne failure
    call check_frame
    mov dx,pass_message
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h

check_frame:
    cmp cx,1234h
    jne failure
    cmp si,2345h
    jne failure
    cmp di,3456h
    jne failure
    cmp bp,4567h
    jne failure
    cmp word [active_frame],0beefh
    jne failure
    mov ax,sp
    add ax,2                 ; this check's own near return address
    cmp ax,[saved_sp]
    jne failure
    ret

low_dispatch:
    push bp
    mov bp,sp
    push word [cs:active_frame]
    push cx
    push si
    push di
    push ds
    push es
    mov [cs:active_frame],bp
    call far [high_ptr]
dispatch_return:
    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop word [cs:active_frame]
    pop bp
    retf

high_start:
    call high_nested
    mov byte [returned_high],1 ; MOV must preserve the firmware carry flag
    retf
high_nested:
    push si
    mov si,0aaaah
    call high_inner
    pop si
    ret
high_inner:
    push bp
    mov bp,sp
    sub sp,16                ; failure must discard workspaces and near returns
    mov di,0bbbbh
    call far [gate_ptr]       ; DS addresses low data, not the HMA code segment
    mov sp,bp
    pop bp
    ret
high_end:

low_gate:
    call simulated_firmware
    pushf
    pushad
    push ds
    push es
    cmp byte [cs:force_failure],0
    jne unwind_low
    mov ax,0e705h            ; repository low A20 recovery; no XMS count change
    int 2fh
    cmp ax,0e7ffh
    jne unwind_low
    pop es
    pop ds
    popad
    popf
    retf
low_gate_end:

unwind_low:
    ; One low anchor per dispatcher activation; never pop/execute high return
    ; addresses. Production must also prove interrupt/reentrant stack ownership.
    mov sp,[cs:active_frame]
    sub sp,12
    xor ax,ax
    mov bl,82h
    stc
    jmp dispatch_return

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
active_frame dw 0beefh
force_failure db 0
dispatch_ptr dw low_dispatch,0
gate_ptr dw low_gate,0
high_ptr dd 0
returned_high db 0
observed_off db 0
pass_message db 'HMA_LOW_RETURN_PASS',13,10,'$'
fail_message db 'HMA_LOW_RETURN_FAILURE',13,10,'$'
