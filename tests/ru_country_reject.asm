bits 16
cpu 8086
org 100h

    ; NLSFUNC is resident. Reject absent country/page pairs without changing
    ; state; the host runs the full current-country probe after this program.
    mov ax, 6602h
    mov bx, 855
    int 21h
    jnc fail
    cmp ax, 2
    jne fail
    mov ax, 6501h
    mov bx, 855
    mov dx, 7
    mov cx, 41
    mov di, buffer
    int 21h
    jnc fail
    cmp ax, 2
    jne fail
    mov ax, 38ffh
    mov bx, 9999
    mov dx, buffer
    int 21h
    jnc fail
    cmp ax, 2
    jne fail
    mov dx, passed
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
fail:
    mov dx, failed
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
buffer times 64 db 0
passed db 'RU_REJECTION_PASS',13,10,'$'
failed db 'RU_REJECTION_FAIL',13,10,'$'
