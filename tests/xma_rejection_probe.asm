bits 16
org 100h


start:
    push cs
    pop ds

    mov ah, 52h
    int 21h
    mov si, [es:bx + 34]
    mov ax, [es:bx + 36]
    mov es, ax
    mov cx, 256

.next_device:
    test word [es:si + 4], 8000h
    jz .advance

    mov di, xmaem_name
    call name_matches
    jc xmaem_resident

    mov di, xma2ems_name
    call name_matches
    jc xma2ems_resident

.advance:
    mov ax, [es:si + 2]
    mov si, [es:si]
    cmp si, 0ffffh
    je .chain_done
    mov es, ax
    loop .next_device
    mov dx, chain_fail
    jmp fail

.chain_done:
    mov ax, 3567h
    int 21h
    mov si, bx
    mov di, xma2ems_name
    call name_matches
    jc ems_resident

    mov ah, 30h
    int 21h
    cmp al, 4
    jne dos_failed

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

xmaem_resident:
    mov dx, xmaem_fail
    jmp fail
xma2ems_resident:
    mov dx, xma2ems_fail
    jmp fail
ems_resident:
    mov dx, ems_fail
    jmp fail
dos_failed:
    mov dx, dos_fail
fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

name_matches:
    push ax
    push cx
    push si
    push di
    add si, 10
    mov cx, 8
.compare:
    mov al, [es:si]
    cmp al, [di]
    jne .different
    inc si
    inc di
    loop .compare
    pop di
    pop si
    pop cx
    pop ax
    stc
    ret
.different:
    pop di
    pop si
    pop cx
    pop ax
    clc
    ret

xmaem_name   db '386XMAEM'
xma2ems_name db 'EMMXXXX0'
pass_message db 'XMA_REJECTION_PASS', 13, 10, '$'
xmaem_fail   db 'XMAEM_UNEXPECTEDLY_RESIDENT', 13, 10, '$'
xma2ems_fail db 'XMA2EMS_UNEXPECTEDLY_RESIDENT', 13, 10, '$'
ems_fail     db 'XMA_EMS_VECTOR_UNEXPECTEDLY_ACTIVE', 13, 10, '$'
dos_fail     db 'XMA_DOS_CONTINUITY_FAIL', 13, 10, '$'
chain_fail   db 'XMA_DEVICE_CHAIN_FAIL', 13, 10, '$'
