; Raw INT 21h/4B03h boundaries, destination bytes, and untouched EOF tail.
check_raw_overlays:
    mov bx,1000h
    mov ah,48h
    int 21h
    jc .bad
    mov [ov_block],ax
    mov [ov_segment],ax
    mov word [ov_case],0
.case:
    mov si,[ov_case]
    mov ax,[ov_sizes+si]
    mov [ov_size],ax
    mov [ov_remaining],ax
    mov es,[ov_block]
    xor di,di
    mov ax,0cccch
    mov cx,8000h
    rep stosw
    xor cx,cx
    mov dx,ov_name
    mov ah,3ch
    int 21h
    jc .bad
    mov [ov_handle],ax
.write:
    mov cx,[ov_remaining]
    jcxz .close
    cmp cx,512
    jbe .chunk
    mov cx,512
.chunk:
    mov bx,[ov_handle]
    mov dx,ov_data
    mov ah,40h
    int 21h
    jc .bad
    cmp ax,cx
    jne .bad
    sub [ov_remaining],ax
    jmp .write
.close:
    mov bx,[ov_handle]
    mov ah,3eh
    int 21h
    jc .bad
    push cs
    pop es
    mov bx,ov_segment
    mov dx,ov_name
    mov ax,4b03h
    int 21h
    pushf
    pop bx
    cmp word [ov_size],0
    jne .nonempty
    test bx,1
    jz .bad
    cmp ax,11
    jne .bad
    jmp .verify
.nonempty:
    cmp word [ov_size],0ffffh
    jne .success
    test bx,1
    jz .bad
    cmp ax,8
    jne .bad
    jmp .verify
.success:
    test bx,1
    jnz .bad
.verify:
    mov es,[ov_block]
    xor di,di
    mov cx,[ov_size]
    mov al,5ah
    jcxz .tail_setup
    repe scasb
    jne .bad
.tail_setup:
    ; Even a 65535-byte failed overlay must not write byte FFFFh.
    xor cx,cx
    sub cx,[ov_size]
    mov al,0cch
.tail:
    scasb
    jne .bad
    loop .tail
    mov dx,ov_name
    mov ah,41h
    int 21h
    jc .bad
    add word [ov_case],2
    cmp word [ov_case],ov_sizes_end-ov_sizes
    jb .case
    mov es,[ov_block]
    mov ah,49h
    int 21h
    jc .bad
    push cs
    pop es
    ret
.bad:
    push cs
    pop ds
    mov dx,ov_failed
    jmp fail
ov_sizes dw 0,1,511,512,513,9109,65534,65535
ov_sizes_end:
ov_case dw 0
ov_size dw 0
ov_remaining dw 0
ov_block dw 0
ov_handle dw 0
ov_segment dw 0
           dw 0
ov_name db 'RAWOVL.BIN',0
ov_data times 512 db 5ah
ov_failed db 'INT21_RAW_OVERLAY_FAIL',13,10,'$'
