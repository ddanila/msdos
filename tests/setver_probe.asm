bits 16
org 100h

start:
%ifdef EXPECT_HIGH
    ; This fixture has no INT 21h-hooking TSR: the public vector must point
    ; at the high kernel on every boot, including the persistence phases.
    mov ax,3521h
    int 21h
    mov ax,es
    cmp ax,0ffffh
    jne ownership_fail
    mov ax,1231h
    int 2fh
    cmp cx,640
    jne ownership_fail
    mov ax,es
    cmp ax,70h
    jb ownership_fail
    cmp ax,0a000h
    jae ownership_fail
    mov bx,di
    add bx,cx
    jc ownership_fail
    mov dx,bx
    mov cl,4
    shr bx,cl
    and dx,15
    jz .end_rounded
    inc bx
.end_rounded:
    add bx,ax
    jc ownership_fail
    cmp bx,0a000h
    ja ownership_fail
    push ax
    mov dx,owner_prefix
    mov ah,9
    int 21h
    pop ax
    call print_hex
    mov dl,':'
    mov ah,2
    int 21h
    mov ax,di
    call print_hex
    mov dx,crlf
    mov ah,9
    int 21h
%endif
    mov ax, 3000h
    int 21h
    push ax
    mov dx, prefix
    mov ah, 09h
    int 21h
    pop ax
    push ax
    call print_u8
    mov dl, '.'
    mov ah, 02h
    int 21h
    pop ax
    mov al, ah
    aam
    push ax
    mov dl, ah
    add dl, '0'
    mov ah, 02h
    int 21h
    pop ax
    mov dl, al
    add dl, '0'
    mov ah, 02h
    int 21h
    mov dx, crlf
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

%ifdef EXPECT_HIGH
ownership_fail:
    mov dx,owner_fail
    mov ah,9
    int 21h
    mov ax,4c01h
    int 21h

print_hex:
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
    pop dx
    pop cx
    pop bx
    pop ax
    ret
owner_prefix db 'SETVER_HIGH_LOW_OWNER=','$'
owner_fail db 'SETVER_OWNERSHIP_FAIL',13,10,'$'
%endif

print_u8:
    aam
    push ax
    test ah, ah
    jz .ones
    mov dl, ah
    add dl, '0'
    mov ah, 02h
    int 21h
.ones:
    pop ax
    mov dl, al
    add dl, '0'
    mov ah, 02h
    int 21h
    ret

prefix db 'SETVER_PROBE_VERSION=', '$'
crlf  db 13, 10, '$'
