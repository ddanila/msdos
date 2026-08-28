bits 16
org 100h

%ifndef EXPECT_HIGH
%define EXPECT_HIGH 1
%endif

start:
    mov ax, 5802h
    int 21h
    jc fail
%if EXPECT_HIGH
    cmp al, 1
%else
    cmp al, 0
%endif
    jne fail

    mov ah, 52h
    int 21h
    les bx, [es:bx + 22h]
.next_device:
    mov ax, es
    push bx
    add bx, 0ah
    mov si, device_name
    mov cx, 8
.compare:
    mov al, [es:bx]
    cmp al, [cs:si]
    jne .not_this
    inc bx
    inc si
    loop .compare
    pop bx
    mov ax, es
%if EXPECT_HIGH
    cmp ax, 8000h
    jb fail
    mov [cs:device_segment], ax
    call validate_resident_mcb
    jc fail
%else
    cmp ax, 8000h
    jae fail
%endif
    mov dx, pass_message
    jmp short print_and_exit
.not_this:
    pop bx
.advance:
    mov dx, [es:bx]
    mov ax, [es:bx + 2]
    cmp ax, 0ffffh
    je fail
    mov bx, dx
    mov es, ax
    jmp .next_device

%if EXPECT_HIGH
validate_resident_mcb:
    push ds
    mov ah, 52h
    int 21h
    mov ax, [es:bx - 2]
.mcb_loop:
    mov ds, ax
    cmp byte [0], 'M'
    je .signature_ok
    cmp byte [0], 'Z'
    jne .bad
.signature_ok:
    mov dx, ax
    inc dx
    cmp [cs:device_segment], dx
    jb .next_mcb
    add dx, [3]
    cmp [cs:device_segment], dx
    jae .next_mcb
    cmp word [1], 8
    jne .bad
    ; The tiny test driver plus DEVMARK must not retain the whole UMB region.
    cmp word [3], 0100h
    jae .bad
    clc
    pop ds
    ret
.next_mcb:
    cmp byte [0], 'Z'
    je .bad
    add ax, [3]
    inc ax
    jmp .mcb_loop
.bad:
    stc
    pop ds
    ret
%endif

fail:
    mov dx, fail_message
print_and_exit:
    push cs
    pop ds
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

device_name  db 'DHREF$  '
device_segment dw 0
%if EXPECT_HIGH
pass_message db 'DEVICEHIGH_STATE_PASS', 13, 10, '$'
%else
pass_message db 'DEVICEHIGH_FALLBACK_PASS', 13, 10, '$'
%endif
fail_message db 'DEVICEHIGH_STATE_FAIL', 13, 10, '$'
