; Poison all three legacy transport packets after import. Their state flags
; remain intact. No steady-state call may read, refresh or reconstruct them.
common_packets_begin:
    pusha
    push es
    mov es,[himem_segment]
    mov bx,cf_ranges
    mov di,cf_saved
.range:
    mov si,[bx]
    mov cx,[bx+2]
    jcxz .done
.byte:
    mov al,[es:si]
    mov [di],al
    mov byte [es:si],0a5h
    inc si
    inc di
    loop .byte
    add bx,4
    jmp .range
.done:
    pop es
    popa
    ret
common_packets_restore:
    pusha
    push es
    mov es,[himem_segment]
    mov bx,cf_ranges
    mov di,cf_saved
.range:
    mov si,[bx]
    mov cx,[bx+2]
    jcxz .done
.byte:
    cmp byte [es:si],0a5h
    jne umb_failed
    mov al,[di]
    mov [es:si],al
    inc si
    inc di
    loop .byte
    add bx,4
    jmp .range
.done:
    pop es
    popa
    ret
common_packets_finish:
    call common_packets_restore
    mov dx,0e9h
    mov al,'C'
    out dx,al
    mov al,'F'
    out dx,al
    ret
cf_ranges dw COMMON_OWNER_PACKET_OFFSET,20
    dw COMMON_UMB_PACKET_OFFSET,24
    dw COMMON_COPY_PACKET_OFFSET,20
    dw 0,0
cf_saved times 64 db 0
