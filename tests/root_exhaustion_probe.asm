bits 16
org 100h

; The host fills every FAT12 root-directory slot after installing this probe.
; Creating one more file must fail with access denied even though data clusters
; remain free. Removing one controlled entry must make creation work again.

start:
    push cs
    pop ds

    xor cx, cx
    mov dx, overflow_name
    mov ah, 3ch
    int 21h
    jnc failed
    cmp ax, 5                      ; Root directory full -> access denied.
    jne failed

    mov dx, filler_name
    mov ah, 41h
    int 21h
    jc failed

    xor cx, cx
    mov dx, overflow_name
    mov ah, 3ch
    int 21h
    jc failed
    mov bx, ax
    mov ah, 3eh
    int 21h
    jc failed
    mov dx, overflow_name
    mov ah, 41h
    int 21h
    jc failed

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

failed:
    mov dx, fail_message
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

filler_name   db 'RF00000.TMP', 0
overflow_name db 'ROOTFULL.TST', 0
pass_message  db 'ROOT_EXHAUSTION_PASS', 13, 10, '$'
fail_message  db 'ROOT_EXHAUSTION_FAIL', 13, 10, '$'
