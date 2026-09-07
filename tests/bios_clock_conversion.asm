; Exercise DOS clock writes and check the conversion at the INT 1Ah boundary.
bits 16
org 100h
    cld
%ifdef BIOS_ACTIVE
    mov ax,70h
    mov es,ax
    cmp byte [es:BIOS_ACTIVE],EXPECT_ACTIVE
    jne fail
%ifdef LEGACY_BCD
    cmp word [es:LEGACY_BCD],0ffffh
    jne fail
    cmp word [es:LEGACY_DAY],0ffffh
    jne fail
%endif
%endif
    mov ax,351ah
    int 21h
    mov [old1a],bx
    mov [old1a+2],es
    mov dx,observe
    mov ax,251ah
    int 21h
    mov si,dates
.date:
    mov word [date_cx],0
    mov cx,[si]
    mov dx,[si+2]
    mov ah,2bh
    push si
    int 21h
    pop si
    or al,al
    jnz fail
    mov cx,[date_cx]
    mov dx,[date_dx]
    cmp cx,[si+4]
    jne fail
    cmp dx,[si+6]
    jne fail
    add si,8
    cmp si,dates_end
    jb .date
    mov word [time_cx],0
    mov cx,0c22h            ; 12:34:00.00
    xor dx,dx
    mov ah,2dh
    int 21h
    or al,al
    jnz fail
    mov cx,[time_cx]
    mov dx,[time_dx]
    cmp cx,1234h
    jne fail
    or dh,dh
    jnz fail
    push ds
    lds dx,[old1a]
    mov ax,251ah
    int 21h
    pop ds
    mov si,passed
.print:
    lodsb
    or al,al
    jz .done
    out 0e9h,al
    jmp .print
.done:
    mov ax,10h
    out 0f4h,ax
    jmp $
fail:
    mov ax,[cs:date_cx]
    out 0e9h,al
    mov al,ah
    out 0e9h,al
    mov ax,[cs:date_dx]
    out 0e9h,al
    mov al,ah
    out 0e9h,al
    mov al,'F'
    out 0e9h,al
    mov ax,11h
    out 0f4h,ax
    jmp $
observe:
    pushf
    cmp ah,05h
    jne .time
    mov [cs:date_cx],cx
    mov [cs:date_dx],dx
.time:
    cmp ah,03h
    jne .chain
    mov [cs:time_cx],cx
    mov [cs:time_dx],dx
.chain:
    popf
    jmp far [cs:old1a]
old1a dd 0
date_cx dw 0
date_dx dw 0
time_cx dw 0
time_dx dw 0
dates:
    dw 1980,0101h,1980h,0101h
    dw 1980,021dh,1980h,0229h
    dw 1999,0c1fh,1999h,1231h
    dw 2000,021dh,2000h,0229h
    dw 2000,0301h,2000h,0301h
    dw 2099,0c1fh,2099h,1231h
dates_end:
passed db 'BIOS_CLOCK_CONVERSION_PASS',13,10,0
