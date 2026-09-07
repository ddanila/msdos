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
%ifdef FAULT_LOADALL
    mov ax,2506h
    mov dx,real_invalid_opcode
    int 21h
    push cs
    pop es
    mov edi,loadall_buffer
    mov ecx,76543210h
%endif
    mov [saved_sp],sp
    mov eax,12345678h
    mov edx,87654321h
%ifdef FAULT_CR2
    mov cr2,eax                 ; CTRErr: a different saved-EAX unwind shape
%elifdef FAULT_LOADALL
fault_opcode:
    db 0fh,07h                 ; EMM's 386 LOADALL emulator rejects requested VM=1
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
%ifdef FAULT_LOADALL
    cmp ecx,76543210h
    jne failed
    cmp edi,loadall_buffer
    jne failed
    cmp byte [cs:real_ud],1
    jne failed
%endif
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
%ifdef FAULT_LOADALL
; The selected 486 does not execute LOADALL in real mode. The application
; owns INT 6 and handles that second, real-mode fault, not EMM's first one.
real_invalid_opcode:
    push bp
    mov bp,sp
    push eax
    smsw ax
    test ax,1
    jnz failed
    mov ax,cs
    cmp [ss:bp+4],ax
    jne failed
    cmp word [ss:bp+2],fault_opcode
    jne failed
    inc byte [cs:real_ud]
    add word [ss:bp+2],2
    pop eax
    pop bp
    iret
real_ud db 0
align 4
%ifdef FAULT_EXCEPTION
; Let the emulator reach its own 0F07 in protected mode. On the selected 486
; this faults inside EMM, exercising the exception-only entry and reboot.
loadall_buffer dd 0,0
    times 248 db 0
%else
loadall_buffer dd 0,20000h
%endif
%endif
