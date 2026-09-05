bits 16
org 100h

start:
    push cs
    pop ds
    mov ax, 1236h
    mov cx, 16
    int 2fh
    or ax, ax
    jz unavailable
    mov ax, es
    cmp ax, 0ffffh
    jne failure
%ifdef EXPECTED_TAIL
    cmp di, EXPECTED_TAIL
    jne failure
%endif
    cmp di, 0fff0h - 16
    ja failure
    mov bx, di
    mov word [es:di], 05aa5h
    cmp word [es:di], 05aa5h
    jne failure

%ifdef TAIL_FLOOR
    ; Reproduce the unpublished allocator state without writing its result.
    ; Restore both words before diagnosing rejection, including on old DOS.
    push word [es:TAIL_FLOOR]
    push word [es:TAIL_NEXT]
    mov word [es:TAIL_FLOOR],0
    mov word [es:TAIL_NEXT],0
    mov ax,1236h
    mov cx,16
    int 2fh
    pop word [es:TAIL_NEXT]
    pop word [es:TAIL_FLOOR]
    or ax,ax
    jnz failure
%endif

    mov ax, 1235h
    int 2fh
    or ax, ax
    jnz failure
    mov ax, 1236h
    mov cx, 16
    int 2fh
    or ax, ax
    jz failure
    mov dx, bx
    add dx, 16
    cmp di, dx
    jne failure

    mov ax, 1236h
    mov cx, 0ffffh
    int 2fh
    or ax, ax
    jnz failure
    cmp word [es:bx], 05aa5h
    jne failure

    mov ax, 1236h
    xor cx, cx
    int 2fh
    or ax, ax
    jnz failure

    mov dx, available_message
    jmp short success

unavailable:
    mov dx, unavailable_message
success:
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

failure:
    mov dx, failure_message
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

available_message db 'HMA_TAIL_AVAILABLE', 13, 10, '$'
unavailable_message db 'HMA_TAIL_UNAVAILABLE', 13, 10, '$'
failure_message db 'HMA_TAIL_FAILURE', 13, 10, '$'
