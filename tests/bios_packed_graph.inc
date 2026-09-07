; Validate the packed BIOS graph while a DOS file is open. No probe may
; accept mere successful I/O while DSKDRVS still points at poisoned templates.
check_packed_graph:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es
    mov ax,70h
    mov es,ax
%ifdef STALE_BDS_CONTROL
    push es
    mov dx,packed_graph_control
    mov ah,9
    int 21h
    pop es
    mov word [es:PACKED_GRAPH_BPBS],PACKED_GRAPH_TEMPLATES+6
%endif
    cmp word [es:PACKED_GRAPH_ROOT+2],70h
    jne fail
    xor cx,cx
    mov cl,[es:PACKED_GRAPH_COUNT]
    cmp cx,2
    jb fail
    cmp cx,26
    ja fail
    mov bp,cx
    mov di,[es:PACKED_GRAPH_ROOT]
    mov bx,PACKED_GRAPH_BPBS
    xor dx,dx
.record:
    cmp [es:di+5],dl
    jne fail
    lea ax,[di+6]
    cmp [es:bx],ax
    jne fail
    add bx,2
    add di,100                 ; MSBDS.INC's complete BDS_TYPE
    inc dx
    dec cx
    jz .last
    cmp [es:di-100],di
    jne fail
    cmp word [es:di-98],70h
    jne fail
    jmp .record
.last:
    cmp word [es:di-100],-1
    jne fail
    cmp [es:PACKED_GRAPH_POOL],di
    jne fail
    mov ax,bp
    sub ax,2
    mov cx,33                  ; DPBSIZ; DOS retains its first two DPBs
    mul cx
    add ax,di
    jc fail
    add ax,15
    jc fail
    mov cl,4
    shr ax,cl
    cmp [es:PERMANENT_END_OFFSET],ax
    jne fail
    shl ax,cl
    cmp ax,PACKED_GRAPH_TEMPLATES
    ja fail
    pop es
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
%ifdef STALE_BDS_CONTROL
packed_graph_control db 'BIOS_PACKED_GRAPH_CONTROL_READY',13,10,'$'
%endif
