bits 16
org 0

; Clean-room character driver used only to observe CONFIG.SYS loader behavior.
; The INIT request reports the driver's load segment and command tail directly
; to COM1, then keeps only the small resident header.

device_header:
    dd 0ffffffffh
    dw 8000h
    dw strategy
    dw interrupt
    db 'DHREF$  '

request_offset  dw 0
request_segment dw 0

strategy:
    mov [cs:request_offset], bx
    mov [cs:request_segment], es
    retf

interrupt:
    push ax
    push bx
    push dx
    push ds
    push es
    push si
    push di

    mov ax, [cs:request_segment]
    mov es, ax
    mov di, [cs:request_offset]
    cmp byte [es:di + 2], 0
    jne .unsupported

    mov si, begin_message
    call serial_print
    mov ax, cs
    call serial_hex_word
    mov si, tail_message
    call serial_print
    lds si, [es:di + 12h]
.tail_loop:
    lodsb
    cmp al, 0
    je .tail_done
    cmp al, 13
    je .tail_done
    call serial_char
    jmp .tail_loop
.tail_done:
    mov si, newline
    push cs
    pop ds
    call serial_print

    mov ax, 5800h
    int 21h
    push ax
    mov si, strategy_message
    call serial_print
    pop ax
    call serial_hex_word
    mov si, newline
    call serial_print
    mov ax, 5802h
    int 21h
    push ax
    mov si, link_message
    call serial_print
    pop ax
    call serial_hex_word
    mov si, newline
    call serial_print

    mov word [es:di + 0eh], resident_end
    mov word [es:di + 10h], cs
    mov word [es:di + 3], 0100h
    jmp short .done

.unsupported:
    mov word [es:di + 3], 8103h
.done:
    pop di
    pop si
    pop es
    pop ds
    pop dx
    pop bx
    pop ax
    retf

serial_hex_word:
    push ax
    mov al, ah
    call serial_hex_byte
    pop ax
serial_hex_byte:
    push ax
    shr al, 1
    shr al, 1
    shr al, 1
    shr al, 1
    call serial_hex_nibble
    pop ax
    and al, 0fh
serial_hex_nibble:
    add al, '0'
    cmp al, '9'
    jbe serial_char
    add al, 'A' - '9' - 1
serial_char:
    push ax
    push dx
    mov ah, al
.wait:
    mov dx, 03fdh
    in al, dx
    test al, 20h
    jz .wait
    mov dx, 03f8h
    mov al, ah
    out dx, al
    pop dx
    pop ax
    ret

serial_print:
    lodsb
    test al, al
    jz .done
    call serial_char
    jmp serial_print
.done:
    ret

begin_message db 'DEVICEHIGH_REF_SEG=', 0
tail_message  db ' TAIL=', 0
newline       db 13, 10, 0
strategy_message db 'DEVICEHIGH_REF_STRATEGY=', 0
link_message     db 'DEVICEHIGH_REF_LINK=', 0

resident_end:
