; Validate the complete live table allocation without entering DOS while A20
; is off, then while distinct EMS pages replace the first page-frame window.
check_upper_table_access:
    pushf
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov byte [cs:upper_access_bad],0
    mov byte [cs:upper_restored],0
%ifdef UPPER_ACCESS_CONTROL
    mov dx,upper_control_ready
    mov ah,9
    int 21h
%endif
    push cs
    pop es
    mov ds,[cs:public_table_owner]
    xor si,si
    mov di,upper_snapshot
    mov cx,EXPECT_TABLE_PARAS*8
    cld
    rep movsw
%ifdef UPPER_ACCESS_CONTROL
    xor byte [es:upper_snapshot],1
%endif
    push cs
    pop ds
    ; Reuse this probe's existing HMA sentinel, with a freshly read low alias.
    mov di,[ctrl_alias_offset]
    xor ax,ax
    mov es,ax
    mov ax,[es:di-16]
    mov [upper_alias],ax
    not ax
    mov bx,0ffffh
    mov es,bx
    mov [es:di],ax
    pushf
    cli
    in al,92h
    and al,0fch
    out 92h,al
    mov ax,[es:di]
    cmp ax,[upper_alias]
    je .alias_off
    mov byte [upper_access_bad],1
.alias_off:
    call upper_compare
    je .tables_off
    mov byte [upper_access_bad],1
.tables_off:
    in al,92h
    and al,0feh
    or al,2
    out 92h,al
    mov ax,[upper_alias]
    not ax
    cmp ax,[es:di]
    je .a20_restored
    ; Do not attempt a high DOS diagnostic if the gate could not be restored.
    mov dx,0f4h
    mov ax,1
    out dx,ax
    cli
    hlt
.a20_restored:
    popf
    mov ah,41h
    int 67h
    or ah,ah
    jnz fail
    mov [upper_frame],bx
    mov ah,42h
    int 67h
    or ah,ah
    jnz fail
    mov [upper_free_pages],bx
    mov bx,2
    mov ah,43h
    int 67h
    or ah,ah
    jnz fail
    mov [upper_handle],dx
    mov ah,47h
    int 67h
    or ah,ah
    jnz .release_bad
    xor bp,bp
.write_page:
    call upper_map
    jnz .restore_bad
    mov es,[upper_frame]
    mov ax,bp
    xor ax,0a55ah
    mov [es:0],ax
    call upper_compare
    jne .restore_bad
    inc bp
    cmp bp,2
    jb .write_page
    xor bp,bp
.read_page:
    call upper_map
    jnz .restore_bad
    mov es,[upper_frame]
    mov ax,bp
    xor ax,0a55ah
    cmp [es:0],ax
    jne .restore_bad
    call upper_compare
    jne .restore_bad
    inc bp
    cmp bp,2
    jb .read_page
    jmp short .restore
.restore_bad:
    mov byte [upper_access_bad],1
.restore:
    mov dx,[upper_handle]
    mov ah,48h
    int 67h
    or ah,ah
    jnz .release_bad
    mov byte [upper_restored],1
    jmp short .release
.release_bad:
    mov byte [upper_access_bad],1
.release:
    mov dx,[upper_handle]
    mov ah,45h
    int 67h
    or ah,ah
    jnz fail
    cmp byte [upper_restored],1
    jne fail
    mov ah,42h
    int 67h
    or ah,ah
    jnz fail
    cmp bx,[upper_free_pages]
    jne fail
%ifdef UPPER_ACCESS_CONTROL
    mov dx,upper_control_clean
    mov ah,9
    int 21h
%endif
    call upper_compare
    jne fail
    cmp byte [upper_access_bad],0
    jne fail
    mov dx,upper_access_pass
    mov ah,9
    int 21h
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    ret

upper_map:
    mov dx,[upper_handle]
    mov bx,bp
    mov ax,4400h
    int 67h
    or ah,ah
    ret

; Preserve registers and return ZF for a complete byte-for-byte comparison.
upper_compare:
    push ds
    push es
    push si
    push di
    push cx
    mov ds,[cs:public_table_owner]
    push cs
    pop es
    xor si,si
    mov di,upper_snapshot
    mov cx,EXPECT_TABLE_PARAS*8
    cld
    repe cmpsw
    pop cx
    pop di
    pop si
    pop es
    pop ds
    ret
upper_handle dw 0
upper_frame dw 0
upper_alias dw 0
upper_access_bad db 0
upper_restored db 0
upper_free_pages dw 0
upper_access_pass db 'BIOS_UPPER_ACCESS_PASS',13,10,'$'
%ifdef UPPER_ACCESS_CONTROL
upper_control_ready db 'BIOS_UPPER_CONTROL_READY',13,10,'$'
upper_control_clean db 'BIOS_UPPER_CONTROL_CLEAN',13,10,'$'
%endif
upper_snapshot times EXPECT_TABLE_PARAS*16 db 0
