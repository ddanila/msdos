bits 16
org 100h

%ifndef HEIGHT
%define HEIGHT 16
%endif
%ifndef PAGE
%define PAGE 866
%endif

%ifdef SETUP_ONLY
    ; Ask BIOS for the desired cell geometry before MODE selects the CP.
%if HEIGHT = 8
    mov ax, 1112h
%elif HEIGHT = 14
    mov ax, 1111h
%else
    mov ax, 1114h
%endif
    xor bx, bx
    int 10h
    mov ax, 4c00h
    int 21h
%else
    cld
    mov ax, 0ad02h
    int 2fh
    jc fail
    cmp bx, PAGE
    jne fail
    mov ax, 40h
    mov es, ax
    cmp word [es:85h], HEIGHT
    jne fail

    ; Read the actual loaded VGA font plane, including 32-byte glyph strides.
    ; Preserve the indexed registers; no video memory is written here.
    cli
    mov dx, 3c4h
    mov al, 4
    out dx, al
    inc dx
    in al, dx
    mov [seq4], al
    mov al, 6
    out dx, al
    mov dx, 3ceh
    mov al, 4
    out dx, al
    inc dx
    in al, dx
    mov [gc4], al
    mov al, 2
    out dx, al
    dec dx
    mov al, 5
    out dx, al
    inc dx
    in al, dx
    mov [gc5], al
    xor al, al
    out dx, al
    dec dx
    mov al, 6
    out dx, al
    inc dx
    in al, dx
    mov [gc6], al
    mov al, 4
    out dx, al
    push ds
    push cs
    pop es
    mov ax, 0a000h
    mov ds, ax
    xor si, si
    mov di, font_buffer
    mov cx, 4096
    rep movsw
    pop ds
    mov al, [gc6]
    out dx, al
    dec dx
    mov al, 5
    out dx, al
    inc dx
    mov al, [gc5]
    out dx, al
    dec dx
    mov al, 4
    out dx, al
    inc dx
    mov al, [gc4]
    out dx, al
    mov dx, 3c4h
    mov al, 4
    out dx, al
    inc dx
    mov al, [seq4]
    out dx, al
    sti

    mov dx, filename
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc fail
    mov bx, ax
    mov dx, font_buffer
    mov cx, 8192
    mov ah, 40h
    int 21h
    jc fail
    cmp ax, 8192
    jne fail
    mov ah, 3eh
    int 21h
    jc fail

    mov ax, 0b800h
    mov es, ax
    xor di, di
    mov ax, 0720h
    mov cx, 80 * (400 / HEIGHT)
    rep stosw
    mov si, title
    mov di, 2 * 80
    call text_line
    mov si, sample
    mov di, 2 * 80 * 2
    call text_line
    ; Grid in byte order, 16 rows by 16 glyphs; each cell spans 3 columns.
    xor bx, bx
    mov di, 2 * 80 * 4
.row:
    push di
    mov cx, 16
.glyph:
    mov al, bl
    mov ah, 7
    stosw
    add di, 4
    inc bx
    loop .glyph
    pop di
    add di, 160
    cmp bx, 256
    jb .row
    mov di, 2 * 80 * 21
    mov si, border_top
    call text_line
    mov di, 2 * 80 * 22
    mov si, border_mid
    call text_line
    mov di, 2 * 80 * 23
    mov si, border_bottom
    call text_line
    mov dx, ready
    mov ah, 9
    int 21h
    ; The host captures the screen, then sends a real keyboard Enter.
    xor ah, ah
    int 16h
    cmp al, 13
    jne fail
    mov dx, passed
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h

text_line:
    lodsb
    test al, al
    jz .done
    mov ah, 7
    stosw
    jmp text_line
.done:
    ret

fail:
    mov dx, failed
    mov ah, 9
    int 21h
    mov dx, 0f4h
    mov ax, 11h
    out dx, ax
    jmp $

seq4 db 0
gc4 db 0
gc5 db 0
gc6 db 0
filename db 'FONT.BIN',0
title db 'CP866: DOS font slots 00-FF, left to right / top to bottom',0
sample db 'Russian / Latin: ',8fh,0e0h,0a8h,0a2h,0a5h,0e2h,'! ',0f0h,0f1h,' ',0f2h,0f3h,' ',0f4h,0f5h,' ',0f6h,0f7h,0
border_top db 0dah,0c4h,0c4h,0c2h,0c4h,0c4h,0bfh,' ',0c9h,0cdh,0cdh,0cbh,0cdh,0cdh,0bbh,0
border_mid db 0b3h,'ab',0b3h,0f0h,0f1h,0b3h,' ',0bah,80h,0a0h,0bah,0b0h,0b2h,0bah,0
border_bottom db 0c0h,0c4h,0c4h,0c1h,0c4h,0c4h,0d9h,' ',0c8h,0cdh,0cdh,0cah,0cdh,0cdh,0bch,0
ready db 'RU_FONT_READY',13,10,'$'
passed db 'RU_FONT_PASS',13,10,'$'
failed db 'RU_FONT_FAIL',13,10,'$'
font_buffer times 8192 db 0
%endif
