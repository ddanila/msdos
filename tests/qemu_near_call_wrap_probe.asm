; A 16-bit CALL must wrap IP before adding a non-page-aligned CS base.
; The unwrapped target lies in the same physical page as the CALL. QEMU's
; affected CF_PCREL chaining path incorrectly treats that as proof of no wrap.
bits 16
org 100h
start:
    mov sp, 1000h              ; keep the stack inside our shrunken block
    mov bx, 100h
    mov ah, 4ah
    int 21h
    jc setup_failed
    mov bx, 1200h
    mov ah, 48h
    int 21h
    jc setup_failed
    ; Reserve enough prefix and suffix for both target addresses.
    add ax, 0ffh
    and ax, 0ff00h
    add ax, 0f4h
    mov [entry+2], ax
    mov es, ax
    mov ax, cs
    mov [good_jump+3], ax
    mov [bad_jump+3], ax
    mov word [es:39h], 0bce8h    ; CALL rel16 -2884
    mov byte [es:3bh], 0f4h     ; 003Ch + F4BCh wraps to F4F8h
    mov si, good_jump
    mov di, 3ch
    mov cx, 5
    cld
    rep movsb
    mov byte [es:0f4f8h], 0c3h  ; correctly wrapped target: RET
    mov ax, es
    sub ax, 100h
    mov es, ax
    mov si, bad_jump
    mov di, 4f8h                ; unwrapped target: CS base - 0B08h
    mov cx, 5
    rep movsb
    jmp far [entry]
passed:
    mov dx, pass_message
    mov ah, 9
    int 21h
    mov al, 10h
    jmp quit
failed:
    mov dx, fail_message
    mov ah, 9
    int 21h
    mov al, 11h
    jmp quit
setup_failed:
    mov dx, setup_message
    mov ah, 9
    int 21h
    mov al, 12h
quit:
    out 0f4h, al
    mov ax, 4c01h
    int 21h
entry: dw 39h, 0
good_jump: db 0eah
    dw passed, 0
bad_jump: db 0eah
    dw failed, 0
pass_message: db 'NEAR_CALL_WRAP_PASS', 13, 10, '$'
fail_message: db 'NEAR_CALL_WRAP_UNMASKED_TARGET', 13, 10, '$'
setup_message: db 'NEAR_CALL_WRAP_SETUP_FAILED', 13, 10, '$'
