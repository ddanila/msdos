bits 16
org 100h
    mov ah,42h
    int 67h
    or ah,ah
    jnz fail
    or bx,bx
    jz fail
    mov [counts],bx
    mov [counts+2],dx
    push dx
    mov al,'E'
    out 0e9h,al
    mov al,'C'
    out 0e9h,al
    mov ax,bx
    out 0e9h,al
    mov al,ah
    out 0e9h,al
    mov ax,dx
    out 0e9h,al
    mov al,ah
    out 0e9h,al
    pop dx
    mov byte [stage],'2'
    xor dx,dx
    mov ah,4ch                     ; handle zero owns conventional system pages
    int 67h
    or ah,ah
    jnz fail
    mov [counts+4],bx
%ifdef EXPECT_NO_UMB
    add bx,[counts]
    cmp bx,[counts+2]              ; all non-system pages must have been returned
    jne fail
%endif
    mov byte [stage],'3'
    mov bx,[counts]
    mov ah,43h                     ; allocate every free EMS page
    int 67h
    or ah,ah
    jnz fail
    mov [handle],dx
    mov byte [stage],'4'
    mov ah,42h
    int 67h
    or ah,ah
    jnz fail
    or bx,bx
    jnz fail
    mov bx,1
    mov byte [stage],'5'
    mov ah,43h
    int 67h
    cmp ah,88h                     ; exhaustion must refuse, not overlap owners
    jne fail
    mov dx,[handle]
    mov byte [stage],'6'
    mov ah,45h
    int 67h
    or ah,ah
    jnz fail
    mov ah,42h
    int 67h
    or ah,ah
    jnz fail
    cmp bx,[counts]
    jne fail
    cmp dx,[counts+2]
    jne fail
    mov dx,name
    xor cx,cx
    mov ah,3ch
    int 21h
    jc fail
    mov bx,ax
    mov dx,counts
    mov cx,6
    mov ah,40h
    int 21h
    jc fail
    cmp ax,6
    jne fail
    mov ah,3eh
    int 21h
    jc fail
    mov dx,passed
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
fail:
    mov dx,failed
    mov ah,9
    int 21h
    mov ax,4c01h
    int 21h
counts dw 0,0,0
handle dw 0
name db 'EMSCOUNT.BIN',0
passed db 'COMPOSED_EMS_ACCOUNTING_PASS',13,10,'$'
failed db 'COMPOSED_EMS_ACCOUNTING_FAIL stage='
stage db '1',13,10,'$'
