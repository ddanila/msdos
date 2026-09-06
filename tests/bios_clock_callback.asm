; Test-only caller in the BIOS segment. Save/restore the loader entry while
; interrupts are masked; no resident test gateway or alternate clock body.
bits 16
org 100h
%include "clock-defs.inc"
start:
    mov al,'B'
    out 0e9h,al
    cli
    cld
    mov ax,70h
    mov es,ax
    cmp byte [es:ACTIVE],EXPECT_ACTIVE
    jne fail
%if EXPECT_POISON
    mov di,OLD_START
    mov cx,OLD_SIZE/2
    mov ax,0f4fah
    repe scasw
    jne fail
%endif
    xor si,si
    mov di,saved
    mov cx,8
.save:
    mov ax,[es:si]
    mov [di],ax
    add si,2
    add di,2
    loop .save
    ; CALL NEAR CS:[TimeToTicks]; RETF to this COM caller.
    mov byte [es:0],02eh
    mov word [es:1],016ffh
    mov word [es:3],CALLBACK
    mov byte [es:5],0cbh
%if OMIT_RESTORE
    mov byte [es:RESTORE_CALL],090h
    mov word [es:RESTORE_CALL+1],09090h
%endif
    mov word [cs:index],0
.sample:
    mov si,[cs:index]
    mov cx,[cs:samples+si]
    mov dx,[cs:samples+si+2]
%if EXPECT_ACTIVE
    ; Distinct saved words prove actual A20 aliasing, not port-latch state.
    push cx
    push dx
    xor ax,ax
    mov ds,ax
    mov ax,[0ffe0h]
    mov [cs:alias_save],ax
    mov word [0ffe0h],01234h
    mov ax,0ffffh
    mov ds,ax
    mov ax,[0fff0h]
    mov [cs:high_save],ax
    mov word [0fff0h],05678h
    in al,92h
    and al,0fch
    out 92h,al
    cmp word [0fff0h],01234h
    jne fail
    mov al,'O'
    out 0e9h,al
    pop dx
    pop cx
%endif
    mov ax,70h
    mov ds,ax
    mov ax,1234h
    mov es,ax
    mov si,5678h
    mov di,9abch
    mov bp,0def0h
    mov [cs:stack_save],sp
    call 70h:0
    cmp sp,[cs:stack_save]
    jne fail
    cmp si,5678h
    jne fail
    cmp di,9abch
    jne fail
    cmp bp,0def0h
    jne fail
    mov ax,ds
    cmp ax,70h
    jne fail
    mov ax,es
    cmp ax,1234h
    jne fail
    push cx
    push dx
%if EXPECT_ACTIVE
    mov ax,0ffffh
    mov ds,ax
    cmp word [0fff0h],05678h
    jne fail
    mov ax,[cs:high_save]
    mov [0fff0h],ax
    xor ax,ax
    mov ds,ax
    mov ax,[cs:alias_save]
    mov [0ffe0h],ax
%endif
    pop ax
    out 0e9h,al
    mov al,ah
    out 0e9h,al
    pop ax
    out 0e9h,al
    mov al,ah
    out 0e9h,al
    add word [cs:index],4
    cmp word [cs:index],samples_end-samples
    jb .sample
    push cs
    pop ds
    mov ax,70h
    mov es,ax
    mov si,saved
    xor di,di
    mov cx,8
    rep movsw
    mov al,'P'
    out 0e9h,al
    mov ax,10h
    mov dx,0f4h
    out dx,ax
    hlt
fail:
    mov ax,11h
    mov dx,0f4h
    out dx,ax
    hlt
    jmp fail
samples: dw 0,0, 0100h,0, 0c22h,384eh, 173bh,3b63h
samples_end:
saved: times 16 db 0
index dw 0
stack_save dw 0
alias_save dw 0
high_save dw 0
