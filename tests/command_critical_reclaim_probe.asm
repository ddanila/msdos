; Fixed-size child: verify the parent's installed allocation, then measure
; the largest free block with identical child/environment overhead in pairs.
bits 16
org 100h

start:
    mov sp, 2048
    push cs
    pop ds
    push cs
    pop es
    mov bx, 128
    mov ah, 4ah
    int 21h
    jc failure
    mov dx, [16h]
    mov ax, dx
    dec ax
    mov es, ax
    cmp [es:1], dx
    jne failure
    mov ax, [es:3]
    mov [parent_paras], ax
    cmp ax, EXPECTED_LOW_PARAS
    jne failure
%ifdef EXPECT_HIGH
%if BODY_START < EXPECTED_LOW_PARAS*16
%error The old body still lies inside the permanent allocation
%endif
    mov es, dx
    mov bx, DISPATCH_OFFSET
    cmp byte [es:bx], 0eah
    jne failure
    cmp word [es:bx+3], 0ffffh
    jne failure
    mov si, [es:bx+1]
    mov ax, 0ffffh
    mov es, ax
    cmp byte [es:si], 52h      ; complete body starts with PUSH DX
    jne failure
    cmp byte [es:si+1], 0e8h   ; followed by its copy-local CRLF bridge call
    jne failure
%endif
%ifdef EXPECT_LOW
%if BODY_END > EXPECTED_LOW_PARAS*16
%error The fallback body is outside the retained allocation
%endif
    mov es, dx
    mov bx, DISPATCH_OFFSET
    cmp byte [es:bx], 0e9h
    jne failure
    cmp word [es:bx+1], BODY_START-DISPATCH_OFFSET-3
    jne failure
%endif
%ifdef EXPECT_HMA_SHORTAGE
    ; A small allocation proves the DOS-owned tail is active; the complete
    ; shell payload must not fit. This control deliberately consumes 16 bytes.
    mov cx, 16
    mov ax, 1236h
    int 2fh
    or ax, ax
    jz failure
    mov ax, es
    cmp ax, 0ffffh
    jne failure
    mov cx, HMA_PAYLOAD_BYTES
    mov ax, 1236h
    int 2fh
    or ax, ax
    jnz failure
%endif
    mov bx, 0ffffh
    mov ah, 48h
    int 21h
    jnc failure
    cmp ax, 8
    jne failure
    mov [largest_paras], bx
    mov dx, parent_message
    mov ah, 09h
    int 21h
    mov ax, [parent_paras]
    call print_hex
    mov dx, largest_message
    mov ah, 09h
    int 21h
    mov ax, [largest_paras]
    call print_hex
    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h
failure:
    mov dx, fail_message
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

print_hex:
    mov bx, ax
    mov cx, 4
.digit:
    rol bx, 1
    rol bx, 1
    rol bx, 1
    rol bx, 1
    mov dl, bl
    and dl, 0fh
    cmp dl, 10
    jb .number
    add dl, 7
.number:
    add dl, '0'
    mov ah, 02h
    int 21h
    loop .digit
    ret

parent_paras dw 0
largest_paras dw 0
parent_message db 'COMMAND_CRITICAL_PARENT=', '$'
largest_message db 13, 10, 'COMMAND_CRITICAL_LARGEST=', '$'
pass_message db 13, 10, 'COMMAND_CRITICAL_LAYOUT_PASS', 13, 10, '$'
fail_message db 'COMMAND_CRITICAL_LAYOUT_FAIL', 13, 10, '$'
