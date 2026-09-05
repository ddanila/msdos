; Test-only whole-body HMA placement. All addresses come from the variant map.
; Low allocation is deliberately retained, but its old body is poisoned.
bits 16
org 100h

start:
    cmp byte [80h], 0
    jne check_old_body
    mov ax, [16h]
    mov [shell_segment], ax
    mov es, ax
    mov bx, DISPATCH_OFFSET
    cmp byte [es:bx], 0e9h
    jne failure
    cmp word [es:bx+1], BODY_START-DISPATCH_OFFSET-3
    jne failure
    cmp word [es:bx+3], 9090h
    jne failure
    mov cx, BODY_END-BODY_START
    mov ax, 1236h
    int 2fh
    or ax, ax
    jz failure
    mov ax, es
    cmp ax, 0ffffh
    jne failure
    mov [high_body], di
    push ds
    mov ds, [shell_segment]
    mov si, BODY_START
    mov cx, BODY_END-BODY_START
    cld
    rep movsb
    pop ds
    mov bx, [high_body]
    mov dx, [shell_segment]
%assign slot 0
%rep 12
    cmp [es:bx+SEGMENT_FIXUP_%+slot-BODY_START], dx
    jne failure
%assign slot slot+1
%endrep

    ; No handler may observe poisoned code before the dispatch switches.
    pushf
    cli
    mov es, dx
    mov di, BODY_START
    mov cx, BODY_END-BODY_START
    mov al, 0cch
    rep stosb
    mov bx, DISPATCH_OFFSET
    mov ax, [high_body]
    mov [es:bx+1], ax
    mov word [es:bx+3], 0ffffh
    mov byte [es:bx], 0eah
    popf
    mov dx, success_message
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h
check_old_body:
    ; The fixture invokes /CHECK after all errors and child-shell cleanup.
    ; Old-body writes are just as unsafe for reclamation as old-body execution.
    mov ax, [16h]
    mov es, ax
    mov di, BODY_START
    mov cx, BODY_END-BODY_START
    mov al, 0cch
    cld
    repe scasb
    jne failure
    mov dx, unchanged_message
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

shell_segment dw 0
high_body dw 0
success_message db 'COMMAND_CRITICAL_BODY_HIGH', 13, 10, '$'
unchanged_message db 'COMMAND_CRITICAL_OLD_BODY_UNTOUCHED', 13, 10, '$'
failure_message db 'COMMAND_CRITICAL_BODY_LOAD_FAIL', 13, 10, '$'
