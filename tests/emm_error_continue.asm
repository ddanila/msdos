bits 16
org 100h
    push cs
    pop ds
%ifdef LIVE_EMS
    mov ah,43h
    mov bx,1
    int 67h
    test ah,ah
    jnz failed
%endif
    mov [saved_sp],sp
    mov eax,12345678h
    mov edx,87654321h
%ifdef FAULT_CR2
    mov cr2,eax                 ; CTRErr: a different saved-EAX unwind shape
%else
    lidt [real_idt]              ; real instruction: EMM's privileged-error path
%endif
    cmp eax,12345678h
    jne failed
    cmp edx,87654321h
    jne failed
    cmp sp,[cs:saved_sp]
    jne failed
    smsw ax
    test ax,1
    jnz failed
    mov si,passed
    call debug
    mov ax,10h
    out 0f4h,ax
failed:
    mov si,failure
    call debug
    mov ax,11h
    out 0f4h,ax
    cli
    hlt
debug:
    mov al,[cs:si]
    inc si
    test al,al
    jz .done
    out 0e9h,al
    jmp debug
.done:
    ret
saved_sp dw 0
real_idt dw 03ffh
    dd 0
passed db 'ERROR_CONTINUE_PASS',0
failure db 'ERROR_CONTINUE_FAIL',0
