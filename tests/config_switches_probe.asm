bits 16
org 100h

; Observe which BIOS keyboard-read function the DOS CON driver selects.
; EXPECTED_KEY_FN is 10h for the QEMU extended keyboard default and 00h when
; CONFIG.SYS contains SWITCHES=/K.

%ifndef EXPECTED_KEY_FN
%error EXPECTED_KEY_FN must be defined
%endif

start:
    push cs
    pop ds

    mov si, start_message
    call serial_print

    mov ax, 3516h
    int 21h
    mov [old_int16_off], bx
    mov [old_int16_seg], es

    mov dx, int16_hook
    mov ax, 2516h
    int 21h

    mov byte [observed_fn], 0ffh
    mov ah, 07h                   ; Direct console input, no echo.
    int 21h
    cmp al, 'K'
    jne failed
    cmp byte [observed_fn], EXPECTED_KEY_FN
    jne failed

    call restore_vector
    mov si, pass_message
    call serial_print
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

failed:
    call restore_vector
    mov si, fail_message
    call serial_print
    mov ax, 4c01h
    int 21h

restore_vector:
    push ds
    mov dx, [old_int16_off]
    mov ax, [old_int16_seg]
    mov ds, ax
    mov ax, 2516h
    int 21h
    pop ds
    ret

serial_print:
    lodsb
    test al, al
    jz .done
    mov ah, al
.wait:
    mov dx, 03fdh
    in al, dx
    test al, 20h
    jz .wait
    mov dx, 03f8h
    mov al, ah
    out dx, al
    jmp serial_print
.done:
    ret

int16_hook:
    cmp ah, 00h
    je .read
    cmp ah, 10h
    je .read
    cmp ah, 01h
    je .status
    cmp ah, 11h
    je .status
    jmp far [cs:old_int16_off]
.read:
    mov [cs:observed_fn], ah
    mov ax, 254bh                 ; Scan code 25h, ASCII K.
    iret
.status:
    mov [cs:observed_fn], ah
    mov ax, 254bh
    push bp
    mov bp, sp
    and word [ss:bp + 6], 0ffbfh  ; Clear ZF in the caller's saved FLAGS.
    pop bp
    iret

start_message db 'CONFIG_SWITCHES_START', 13, 10, 0
pass_message db 'CONFIG_SWITCHES_PASS', 13, 10, 0
fail_message db 'CONFIG_SWITCHES_FAIL', 13, 10, 0
observed_fn  db 0ffh
old_int16_off dw 0
old_int16_seg dw 0
