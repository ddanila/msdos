bits 16
org 100h

; Clean-room probe for the documented DOS allocation calls used by memory-aware
; loaders: link UMBs, ask for an impossibly large block, then allocate the
; reported maximum.  The same binary is run on reference DOS and this tree.

start:
    push cs
    pop ds
    push cs
    pop es
    cli
    mov sp, stack_top
    sti

    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h

    mov dx, begin_msg
    call puts

    mov ax, 5800h
    int 21h
    mov [saved_strategy], al
    mov dx, get_strategy_msg
    call report

    mov ax, 5802h
    int 21h
    mov [saved_link], al
    mov dx, get_link_msg
    call report

    mov ax, 5801h
    mov bx, 0040h
    int 21h
    mov dx, set_upper_msg
    call report

    mov ax, 5803h
    mov bx, 0001h
    int 21h
    mov dx, link_msg
    call report

    mov ah, 48h
    mov bx, 7fffh
    int 21h
    mov dx, oversize_7fff_msg
    call report

    mov ah, 48h
    mov bx, 0ffffh
    int 21h
    mov [reported_max], bx
    mov dx, oversize_ffff_msg
    call report

    mov ah, 48h
    mov bx, [reported_max]
    int 21h
    mov [allocated_segment], ax
    mov dx, allocate_max_msg
    call report
    test byte [result_flags], 1
    jnz restore
    mov es, [allocated_segment]
    mov ah, 49h
    int 21h
    mov dx, free_msg
    call report

restore:
    xor bx, bx
    mov bl, [saved_strategy]
    mov ax, 5801h
    int 21h
    xor bx, bx
    mov bl, [saved_link]
    mov ax, 5803h
    int 21h

    mov dx, end_msg
    call puts
    mov ax, 4c00h
    int 21h

; DX=label, flags/registers are captured at entry.
report:
    pushf
    pop word [result_flags]
    mov [result_ax], ax
    mov [result_bx], bx
    push cx
    push dx
    push si
    mov si, dx
    call puts_si
    mov dx, cf_msg
    call puts
    mov ax, [result_flags]
    and al, 1
    xor ah, ah
    call puthex4
    mov dx, ax_msg
    call puts
    mov ax, [result_ax]
    call puthex4
    mov dx, bx_msg
    call puts
    mov ax, [result_bx]
    call puthex4
    call newline
    pop si
    pop dx
    pop cx
    ret

puts_si:
    mov dx, si
puts:
    mov ah, 09h
    int 21h
    ret

puthex4:
    push ax
    push bx
    push cx
    mov bx, ax
    mov cx, 4
.digit:
    rol bx, 4
    mov al, bl
    and al, 0fh
    add al, '0'
    cmp al, '9'
    jbe .emit
    add al, 'A' - '9' - 1
.emit:
    mov dl, al
    mov ah, 02h
    int 21h
    loop .digit
    pop cx
    pop bx
    pop ax
    ret

newline:
    mov dx, crlf
    jmp puts

begin_msg          db 'UMB_LOADER_SEQUENCE_BEGIN',13,10,'$'
end_msg            db 'UMB_LOADER_SEQUENCE_END',13,10,'$'
get_strategy_msg   db 'GET_STRATEGY','$'
get_link_msg       db 'GET_LINK','$'
set_upper_msg      db 'SET_UPPER','$'
link_msg           db 'LINK','$'
oversize_7fff_msg  db 'ALLOC_7FFF','$'
oversize_ffff_msg  db 'ALLOC_FFFF','$'
allocate_max_msg   db 'ALLOC_MAX','$'
free_msg           db 'FREE_MAX','$'
cf_msg              db ' CF=','$'
ax_msg              db ' AX=','$'
bx_msg              db ' BX=','$'
crlf                db 13,10,'$'

saved_strategy      db 0
saved_link          db 0
reported_max        dw 0
allocated_segment   dw 0
result_flags        dw 0
result_ax           dw 0
result_bx           dw 0
                    times 128 db 0
stack_top:
program_end:
