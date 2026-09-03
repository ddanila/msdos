bits 16
org 0

device_header:
    dd 0ffffffffh
    dw 8000h
    dw strategy
    dw interrupt
    db 'A20OFF$ '

request_offset dw 0
request_segment dw 0
old_int21 dd 0
%ifdef A20_DEBUG
debug_saved_ax dw 0
%endif

strategy:
%ifdef A20_DEBUG
    mov [cs:debug_saved_ax], ax
    mov al, 'S'
    out 0e9h, al
    in al, 92h
    and al, 2
    shr al, 1
    add al, '0'
    out 0e9h, al
    mov ax, ss
    cmp ax, 0ffffh
    mov al, 'L'
    jne short strategy_debug_stack
    mov al, 'H'
strategy_debug_stack:
    out 0e9h, al
    mov ax, [cs:debug_saved_ax]
%endif
    mov [cs:request_offset], bx
    mov [cs:request_segment], es
%ifndef A20_NO_STRATEGY_DISABLE
    call disable_a20
%endif
    retf

interrupt:
%ifdef A20_DEBUG
    mov [cs:debug_saved_ax], ax
    mov al, 'I'
    out 0e9h, al
    in al, 92h
    and al, 2
    shr al, 1
    add al, '0'
    out 0e9h, al
    mov ax, ss
    cmp ax, 0ffffh
    mov al, 'L'
    jne short interrupt_debug_stack
    mov al, 'H'
interrupt_debug_stack:
    out 0e9h, al
    mov ax, [cs:debug_saved_ax]
%endif
    push ax
    push ds
    push es
    push di
%ifndef A20_NO_INTERRUPT_DISABLE
    call disable_a20
%endif
    mov ax, [cs:request_segment]
    mov es, ax
    mov di, [cs:request_offset]
    cmp byte [es:di + 2], 0
    jne .complete
%ifndef A20_NO_INT21_HOOK
    xor ax, ax
    mov ds, ax
    mov ax, [ds:21h * 4]
    mov [cs:old_int21], ax
    mov ax, [ds:21h * 4 + 2]
    mov [cs:old_int21 + 2], ax
    cli
    mov word [ds:21h * 4], int21_hook
    mov word [ds:21h * 4 + 2], cs
    sti
%endif
    mov word [es:di + 0eh], resident_end
    mov word [es:di + 10h], cs
.complete:
    mov word [es:di + 3], 0100h
    pop di
    pop es
    pop ds
    pop ax
    retf

int21_hook:
    jmp far [cs:old_int21]

disable_a20:
    in al, 92h
    and al, 0fdh
    out 92h, al
    ret

resident_end:
