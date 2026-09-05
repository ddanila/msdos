bits 16
org 100h
%include "low-defs.inc"
%ifdef ACTIVATE_HIGH
%include "activation-defs.inc"
%endif
start:
    mov ax,70h
    mov es,ax
    cmp byte [es:ACTIVE_OFFSET],0
    jne fail
    mov si,slots
    mov cx,SLOT_WORD_COUNT
.slot:
    lodsw
    mov bx,ax
    cmp word [es:bx],0
    jne fail
    loop .slot
    mov ax,1236h
    mov cx,16
    int 2fh
%if EXPECT_HIGH
    or ax,ax
    jz fail
    mov ax,es
    cmp ax,0ffffh
    jne fail
    mov word [es:di],0a55ah
    cmp word [es:di],0a55ah
    jne fail
%else
    or ax,ax
    jnz fail
%endif
%ifdef ACTIVATE_HIGH
    call activate_live_bios
%endif
    mov dx,filename
    xor cx,cx
    mov ah,3ch
    int 21h
    jc fail
    mov bx,ax
    mov dx,pattern
    mov cx,4
    mov ah,40h
    int 21h
    jc fail
    cmp ax,4
    jne fail
    xor cx,cx
    xor dx,dx
    mov ax,4200h
    int 21h
    jc fail
    mov dx,buffer
    mov cx,4
    mov ah,3fh
    int 21h
    jc fail
    cmp ax,4
    jne fail
    mov ah,3eh
    int 21h
    jc fail
    mov ax,[pattern]
    cmp [buffer],ax
    jne fail
    mov ax,[pattern+2]
    cmp [buffer+2],ax
    jne fail
    mov dx,filename
    mov ah,41h
    int 21h
    jc fail
%ifdef ACTIVATE_HIGH
    ; Force BIOS-backed writes, then a raw read through the live INT 13h entry.
    mov ah,0dh
    int 21h
    push cs
    pop es
    mov bx,sector
    mov ax,0201h
    mov cx,1
    xor dx,dx
    int 13h
    jc fail
    cmp word [sector+510],0aa55h
    jne fail
    cmp word [sector_before],1234h
    jne fail
    cmp word [sector_after],5678h
    jne fail
%endif
    mov dx,passed
    mov ah,9
    int 21h
    mov ax,10h
    jmp finish
fail:
    push cs
    pop ds
    mov dx,failed
    mov ah,9
    int 21h
    mov ax,11h
finish:
    mov dx,0f4h
    out dx,ax
    mov ax,4c00h
    int 21h
filename db 'LOWTEST.TMP',0
pattern db 'BIOS'
buffer times 4 db 0
passed db 'BIOS_LOW_BOOT_PASS',13,10,'$'
failed db 'BIOS_LOW_BOOT_FAIL',13,10,'$'
slots:
%include "low-slots.inc"
%ifdef ACTIVATE_HIGH
%include "bios_live_activate.inc"
sector_before dw 1234h
sector times 512 db 0
sector_after dw 5678h
%endif
