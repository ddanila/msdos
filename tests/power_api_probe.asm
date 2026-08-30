bits 16
org 100h

    mov ax,5400h
    xor bx,bx
    int 2fh
    mov si,install_label
    call print_result

    mov byte [setting],0
.setting_loop:
    mov bl,[setting]
    mov bh,1
    mov ax,5401h
    int 2fh
    mov si,set_label
    call print_result
    xor bx,bx
    mov ax,5401h
    int 2fh
    mov si,query_label
    call print_result
    inc byte [setting]
    cmp byte [setting],4
    jb .setting_loop

    xor bx,bx
    mov ax,5403h
    int 2fh
    mov si,level_query_label
    call print_result

    push ds
    pop es
    mov si,stats
    mov cx,28
    xor bx,bx
    mov ax,5481h
    int 2fh
    mov si,stats_label
    call print_result

    mov dx,done_label
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h

print_result:
    push ax
    push bx
    push dx
    mov dx,si
    mov ah,9
    int 21h
    pop dx
    pop bx
    pop ax
    call print_hex
    mov dl,' '
    mov ah,2
    int 21h
    mov ax,bx
    call print_hex
    mov dx,newline
    mov ah,9
    int 21h
    ret

print_hex:
    push ax
    mov al,ah
    call print_byte
    pop ax
print_byte:
    push ax
    shr al,1
    shr al,1
    shr al,1
    shr al,1
    call print_nibble
    pop ax
    and al,0fh
print_nibble:
    add al,'0'
    cmp al,'9'
    jbe .emit
    add al,'A'-'9'-1
.emit:
    mov dl,al
    mov ah,2
    int 21h
    ret

install_label db 'INSTALL AX/BX=','$'
set_label     db 'SET AX/BX=','$'
query_label   db 'QUERY AX/BX=','$'
level_query_label db 'LEVEL_QUERY AX/BX=','$'
stats_label   db 'STATS AX/BX=','$'
done_label    db 'POWER_API_DONE',13,10,'$'
newline       db 13,10,'$'
setting       db 0
stats         times 28 db 0
