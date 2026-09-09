; Save a rendered 86Box monitor snapshot: little-endian width/height, then BGR24.
; DOS writes are checked; the caller handles carry as a failed test.
box_snapshot:
    push es
    push ds
    pop es
    mov ax,40h
    push ds
    mov ds,ax
    mov bx,[6ch]
.wait:
    mov ax,[6ch]
    sub ax,bx
    cmp ax,2
    jb .wait
    pop ds
    cli
    mov si,box_enable
    mov cx,7
    mov dx,80h
.enable:
    lodsb
    out dx,al
    loop .enable
    sti
    mov dx,0f4h
    in al,dx
    cmp al,4
    jne .fail
    mov al,1
    out dx,al
    inc dx
    out dx,al                 ; Capture monitor 1.
    mov di,box_geometry
    mov cx,12
.geometry:
    in al,dx
    stosb
    loop .geometry
    mov ax,[box_geometry]
    test ax,ax
    jz .fail
    cmp ax,2048
    ja .fail
    mov [box_rect],ax
    mov ax,[box_geometry+2]
    test ax,ax
    jz .fail
    cmp ax,2048
    ja .fail
    mov [box_rect+2],ax
    mov bp,ax
    xor cx,cx
    mov dx,box_filename
    mov ah,3ch
    int 21h
    jc .fail
    mov bx,ax
    mov cx,4
    mov dx,box_geometry
    mov ah,40h
    int 21h
    jc .close_fail
    cmp ax,4
    jne .close_fail
    mov dx,0f4h
    mov al,2
    out dx,al
    inc dx
    mov si,box_rect
    mov cx,8
.rectangle:
    lodsb
    out dx,al
    loop .rectangle
.row:
    mov dx,0f5h
    mov di,box_row
    mov cx,[box_geometry]
.pixel:
    in al,dx
    stosb
    in al,dx
    stosb
    in al,dx
    stosb
    in al,dx                 ; Discard the fourth byte.
    loop .pixel
    mov cx,di
    sub cx,box_row
    mov dx,box_row
    mov ah,40h
    int 21h
    jc .close_fail
    cmp ax,cx
    jne .close_fail
    dec bp
    jnz .row
    mov ah,3eh
    int 21h
    pop es
    ret
.close_fail:
    mov ah,3eh
    int 21h
.fail:
    pop es
    stc
    ret
box_enable db '86Box',0f4h,0
box_filename db 'SCREEN.BIN',0
box_geometry times 12 db 0
box_rect times 8 db 0
box_row times 2048*3 db 0
