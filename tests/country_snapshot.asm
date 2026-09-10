bits 16
cpu 8086
org 100h
    cld
    push cs
    pop ds
    push cs
    pop es
    mov ax, 3800h
    mov dx, country_buffer
    int 21h
    jc fail
    mov [dump], ax
    mov [dump+2], bx
    mov ax, 6601h
    int 21h
    jc fail
    mov [dump+4], bx
    mov [dump+6], dx
    mov ax, 6501h
    mov bx, -1
    mov dx, -1
    mov cx, 41
    mov di, dump+8
    int 21h
    jc fail
    cmp cx, 41
    jne fail
    ; Ignore the runtime far-uppercase address, retaining all table bytes.
    mov word [dump+8+25], 0
    mov word [dump+8+27], 0
    mov word [cursor], dump+49
    mov bp, kinds
next_table:
    mov al, [bp]
    mov ah, 65h
    mov bx, -1
    mov dx, -1
    mov cx, 5
    mov di, pointer
    int 21h
    jc fail
    cmp cx, 5
    jne fail
    mov al, [bp]
    cmp [pointer], al
    jne fail
    push ds
    lds si, [pointer+1]
    mov cx, [si]
    cmp cx, 256
    ja restore_fail
    add cx, 2
    mov di, [es:cursor]
    mov ax, di
    add ax, cx
    cmp ax, dump_end
    ja restore_fail
    rep movsb
    mov [es:cursor], di
    pop ds
    inc bp
    cmp bp, kinds_end
    jb next_table
    mov dx, filename
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc fail
    mov bx, ax
    mov dx, dump
    mov cx, [cursor]
    sub cx, dx
    mov bp, cx
    mov ah, 40h
    int 21h
    jc fail
    cmp ax, bp
    jne fail
    mov ah, 3eh
    int 21h
    jc fail
    mov dx, passed
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h
restore_fail:
    pop ds
fail:
    mov dx, failed
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h
kinds db 2,4,5,6,7
kinds_end:
filename db 'SNAP.BIN',0
passed db 'COUNTRY_SNAPSHOT_PASS',13,10,'$'
failed db 'COUNTRY_SNAPSHOT_FAIL',13,10,'$'
cursor dw 0
pointer times 5 db 0
country_buffer times 34 db 0
dump times 1024 db 0
dump_end:
