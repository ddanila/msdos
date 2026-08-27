bits 16
org 100h

start:
    push cs
    pop ds

    mov ax, 1100h                 ; IFSFUNC installation check.
    int 2fh
    or al, al
    jz failed

    mov ax, 5200h                 ; DOS list of lists.
    int 21h
    les bx, [es:bx + 59]          ; SYSI_IFS header-chain head.

find_header:
    mov si, expected_name
    mov di, bx
    add di, 4
    mov cx, 8
    repe cmpsb
    je found
    les bx, [es:bx]
    cmp bx, -1
    jne find_header
    mov ax, es
    cmp ax, -1
    jne find_header
    jmp failed

found:
    cmp word [es:bx + 22], 0beefh
    jne failed
    cmp word [es:bx + 24], 1      ; one FILESYS attach
    jne failed
    cmp word [es:bx + 26], 1      ; one FILESYS status query
    jne failed
    cmp word [es:bx + 28], 1      ; one FILESYS detach
    jne failed

    mov ax, 4c00h
    int 21h

failed:
    mov ax, 4c01h
    int 21h

expected_name db 'TESTIFS '
