; Read-only ownership witness: run the same binary as REFVER.COM and ASSIGN.COM.
bits 16
org 100h
start:
    push cs
    pop ds
    mov ax,1231h
    int 2fh
    push es
    push di
    push cx
    mov dx,table_message
    mov ah,9
    int 21h
    pop cx
    pop di
    pop es
    mov ax,es
    call hex
    mov ax,di
    call hex
    mov ax,cx
    call hex
    cmp cx,640
    jne bad_table
    mov ax,di
    add ax,cx
    jc bad_table
    mov si,defaults
    cld
    repe cmpsb
    jne different_table
    mov dx,table_pass
    jmp short table_done
different_table:
    mov dx,difference_message
    mov ah,9
    int 21h
    mov ax,si
    sub ax,defaults+1
    call hex
bad_table:
    mov dx,table_fail
table_done:
    mov ah,9
    int 21h
    mov dx,version_message
    mov ah,9
    int 21h
    mov ax,3000h
    int 21h
    call hex
    mov dx,end_message
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
hex:
    push ax
    push bx
    push cx
    push dx
    mov bx,ax
    mov cx,4
.digit:
    rol bx,1
    rol bx,1
    rol bx,1
    rol bx,1
    mov dl,bl
    and dl,15
    add dl,'0'
    cmp dl,'9'
    jbe .emit
    add dl,7
.emit:
    mov ah,2
    int 21h
    loop .digit
    mov dl,13
    mov ah,2
    int 21h
    mov dl,10
    int 21h
    pop dx
    pop cx
    pop bx
    pop ax
    ret
table_message db 'SETVER_TABLE_SEG_OFF_CAP',13,10,'$'
difference_message db 'SETVER_FIRST_DIFFERENCE',13,10,'$'
table_pass db 'SETVER_DEFAULT_TABLE_PASS',13,10,'$'
table_fail db 'SETVER_DEFAULT_TABLE_FAIL',13,10,'$'
version_message db 'SETVER_REPORTED_AX',13,10,'$'
end_message db 'SETVER_TABLE_PROBE_END',13,10,'$'
defaults:
%include 'SETVER62.INC'
times 640-($-defaults) db 0
