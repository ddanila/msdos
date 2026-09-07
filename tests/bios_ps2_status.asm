; Exercise the installed BIOS's PS/2 two-call contract with synthetic firmware.
; Restore every modified vector/model/code byte before reporting the result.
bits 16
org 100h
start:
    pushf
    pop ax
    mov [saved_flags],ax
    cli
    cld
    mov ax,70h
    mov es,ax
    cmp byte [es:ACTIVE],1
    jne not_active
    mov al,[es:MODEL]
    mov [saved_model],al
    mov ax,[es:ORIG13]
    mov [saved_vector],ax
    mov ax,[es:ORIG13+2]
    mov [saved_vector+2],ax
    mov byte [es:MODEL],0fah
    mov word [es:ORIG13],firmware
    mov [es:ORIG13+2],cs
%ifdef OMIT_RESTORE
    mov bx,[es:HIGH_ENTRY]
    sub bx,HIGH_BLOCK13
    add bx,RESTORE_OFFSET
    mov [patch_offset],bx
    mov ax,0ffffh
    mov es,ax
    ; MOV DX,CS:[Prev_DX]: retain the operand; skip only this instruction.
    cmp word [es:bx],08b2eh
    jne failed
    cmp byte [es:bx+2],16h
    jne failed
    mov si,bx
    mov di,saved_code
    mov cx,5
.save_code:
    mov al,[es:si]
    mov [di],al
    mov byte [es:si],90h
    inc si
    inc di
    loop .save_code
    mov byte [patched],1
%endif
next_case:
    mov byte [phase],0
    mov byte [hook_bad],0
    mov [caller_sp],sp
    mov ax,[request]
    mov bx,1111h
    mov cx,2222h
    mov dx,1880h
    mov si,4444h
    mov di,5555h
    mov bp,6666h
    pushf
    call 70h:LOW_ENTRY
    mov [cs:result_ax],ax
    pushf
    pop ax
    mov [cs:result_flags],ax
    mov [cs:result_ds],ds
    mov [cs:result_es],es
    mov ax,cs
    mov ds,ax
    mov es,ax
    cmp sp,[caller_sp]
    jne failed
    cmp byte [phase],2
    jne failed
    cmp byte [hook_bad],0
    jne failed
    cmp bx,1111h
    jne failed
    cmp cx,2222h
    jne failed
    cmp dx,0abcdh
    jne failed
    cmp si,4444h
    jne failed
    cmp di,5555h
    jne failed
    cmp bp,6666h
    jne failed
    cmp word [result_ds],7777h
    jne failed
    cmp word [result_es],8888h
    jne failed
    mov ax,0034h
    cmp byte [first_error],0
    je .expected_ax
    mov ax,2034h
.expected_ax:
    cmp [result_ax],ax
    jne failed
    mov ax,[result_flags]
    and ax,1
    cmp al,[first_error]
    jne failed
    cmp word [request],1500h
    jne .next_function
    cmp byte [first_error],1
    je succeeded
    mov byte [first_error],1
    mov word [request],0800h
    jmp next_case
.next_function:
    mov word [request],1500h
    jmp next_case
succeeded:
    mov byte [passed],1
failed:
    cli
    mov ax,cs
    mov ds,ax
%ifdef OMIT_RESTORE
    cmp byte [patched],1
    jne .unpatched
    mov ax,0ffffh
    mov es,ax
    mov si,saved_code
    mov di,[patch_offset]
    mov cx,5
    cld
    rep movsb
.unpatched:
%endif
    mov ax,70h
    mov es,ax
    mov al,[saved_model]
    mov [es:MODEL],al
    mov ax,[saved_vector]
    mov [es:ORIG13],ax
    mov ax,[saved_vector+2]
    mov [es:ORIG13+2],ax
not_active:
    push word [saved_flags]
    popf
    mov dx,fail_message
    cmp byte [passed],1
    jne .report
    mov dx,pass_message
.report:
    mov ah,9
    int 21h
    mov ax,11h
    cmp byte [passed],1
    jne .exit
    mov ax,10h
.exit:
    out 0f4h,ax
    cli
    hlt

firmware:
    cmp byte [cs:phase],0
    jne .status
    cmp ax,[cs:request]
    jne .bad
    cmp dx,1880h
    jne .bad
    inc byte [cs:phase]
    ; The first result changes DX and segment registers intentionally.
    mov dx,0abcdh
    mov ax,7777h
    mov ds,ax
    mov ax,8888h
    mov es,ax
    mov ax,0034h
    cmp byte [cs:first_error],0
    je .first_success
    mov ah,20h
    stc
    retf 2
.first_success:
    clc
    retf 2
.status:
    cmp byte [cs:phase],1
    jne .bad
    cmp ah,1
    jne .bad
    cmp dx,1880h
    jne .bad
    inc byte [cs:phase]
    ; Every first-call result must survive this destructive reset response.
    mov ax,9999h
    mov bx,ax
    mov cx,ax
    mov dx,ax
    mov si,ax
    mov di,ax
    mov bp,ax
    mov ds,ax
    mov es,ax
    cmp byte [cs:first_error],0
    jne .reset_success
    stc
    retf 2
.reset_success:
    clc
    retf 2
.bad:
    mov byte [cs:hook_bad],1
    mov ah,20h
    stc
    retf 2

saved_flags dw 0
saved_vector dd 0
saved_model db 0
caller_sp dw 0
request dw 0800h
result_ax dw 0
result_flags dw 0
result_ds dw 0
result_es dw 0
phase db 0
first_error db 0
hook_bad db 0
passed db 0
patched db 0
patch_offset dw 0
saved_code times 5 db 0
pass_message db 'BIOS_PS2_STATUS_PASS',13,10,'$'
fail_message db 'BIOS_PS2_STATUS_FAIL',13,10,'$'
