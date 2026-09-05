; Count actual primary buffers through the public list-of-lists graph.
; No assumption that the configured count implies successful high placement.
check_buffer_count:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov ah,52h
    int 21h
    les bx,[es:bx+PUB_SYSI_BUF]
    mov cx,[es:bx+PUB_HASH_COUNT]
    jcxz .bad
    cmp cx,EXPECT_BUFFERS
    ja .bad
    les bx,[es:bx+PUB_HASH_PTR]
    mov byte [cs:buffer_locations],0
    xor bp,bp
.bucket:
    push es
    push bx
    les di,[es:bx+PUB_BUFFER_BUCKET]
    mov ax,es
    cmp ax,0ffffh
    jne .low_bucket
    or byte [cs:buffer_locations],1
    jmp short .located
.low_bucket:
    or byte [cs:buffer_locations],2
.located:
    mov si,di
.buffer:
    inc bp
    cmp bp,EXPECT_BUFFERS
    ja .bad
    mov di,[es:di+PUB_BUF_NEXT]
    cmp di,si
    jne .buffer
    pop bx
    pop es
    add bx,PUB_HASH_ENTRY_SIZE
    loop .bucket
    cmp bp,EXPECT_BUFFERS
    jne .bad
    push cs
    pop ds
    mov dx,buffers_low
    cmp byte [buffer_locations],2
    je .print
    mov dx,buffers_mixed
    cmp byte [buffer_locations],1
    jne .print
    mov dx,buffers_high
.print:
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
    ret
.bad:
    push cs
    pop ds
    mov dx,buffers_bad
    mov ah,9
    int 21h
    jmp fail
buffer_locations db 0
buffers_high db 'BIOS_BUFFERS_COUNT_OK HIGH',13,10,'$'
buffers_low db 'BIOS_BUFFERS_COUNT_OK LOW',13,10,'$'
buffers_mixed db 'BIOS_BUFFERS_COUNT_OK MIXED',13,10,'$'
buffers_bad db 'BIOS_BUFFERS_COUNT_FAIL',13,10,'$'
