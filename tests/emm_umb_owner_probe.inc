; Private metadata-only XUMB owner. Does not switch HIMEM or claim/map UMB RAM.
check_high_umb_owner:
    mov ax,0e7c0h
    int 15h
    cmp ax,0e7cfh
    jne failed
    test dx,64
    jz failed
    mov word [up_packet+4],2
    call up_refused
    mov word [up_packet+4],1
    mov word [up_packet+8],1
    call up_refused
    mov word [up_packet+8],0
    mov word [up_packet+6],0ffffh
    call up_refused
    call up_receipt
    cmp word [up_packet+10],0
    jne failed
    cmp word [up_packet+14],0
    jne failed
    mov word [up_packet+6],10h
    call up_refused           ; no service before explicit publication
    mov word [up_packet+6],1
    call up_refused           ; FFFF source offset cannot supply a count
    mov word [up_packet+16],up_source
    mov word [up_packet+18],1
    call up_refused           ; source capacity too short
    mov word [up_packet+18],2
    mov word [up_source+4],8000h
    call up_refused           ; allocated zero-length range
    mov word [up_source+4],8004h
    call up_receipt
    cmp word [up_packet+10],0
    jne failed
    mov word [up_packet+6],1
    call up_send
    cmp word [up_packet+10],1
    jne failed
    cmp word [up_packet+14],1
    jne failed
    cmp word [up_packet+12],2
    jne failed
    mov word [up_packet+16],0ffffh
    mov word [up_packet+18],0ffffh
    mov di,up_source
    mov cx,10
    push cs
    pop es
    mov al,0a5h
    cld
    rep stosb
    call up_refused           ; duplicate import never reads poisoned source
    call up_receipt
    cmp word [up_packet+12],2
    jne failed
    mov word [up_packet+6],13h
    call up_send              ; live imported allocation prevents unregister
    cmp word [up_packet+10],0
    jne failed
    cmp byte [up_packet+14],2
    jne failed
    mov word [up_packet+6],11h
    mov word [up_packet+12],0a000h
    call up_success
    call up_largest
    cmp word [up_packet+12],20h
    jne failed
    mov word [up_packet+6],10h
    mov word [up_packet+12],4
    call up_success
    cmp word [up_packet+14],0a000h
    jne failed
    mov word [up_packet+6],11h
    mov word [up_packet+12],0a000h
    call up_success
    mov word [up_packet+6],13h
    call up_success
    mov word [up_packet+6],12h
    mov word [up_packet+16],up_registration
    mov word [up_packet+18],2
    mov word [up_registration+6],8000h
    call up_refused           ; invalid registration cannot mutate empty owner
    mov word [up_registration+6],10h
    call up_success
    call up_send              ; cannot replace an existing registered owner
    cmp word [up_packet+10],0
    jne failed
    cmp byte [up_packet+14],1
    jne failed
    call up_largest
    cmp word [up_packet+12],20h
    jne failed
    mov word [up_packet+6],13h
    call up_success
    mov word [up_packet+16],0ffffh
    mov word [up_packet+18],0ffffh
    call up_receipt           ; empty table does not undo commitment
    cmp word [up_packet+10],1
    jne failed
    cmp word [up_packet+14],1
    jne failed
    cmp word [up_packet+12],0
    jne failed
    mov si,up_source
    mov cx,10
.source_unchanged:
    cmp byte [si],0a5h
    jne failed
    inc si
    loop .source_unchanged
    mov dx,0e9h
    mov al,'U'
    out dx,al
    mov al,'P'
    out dx,al
    mov ax,[up_packet+10]
    call word_out
    mov ax,[up_packet+14]
    call word_out
    mov ax,[up_packet+12]
    call word_out
    ret
up_largest:
    mov word [up_packet+6],10h
    mov word [up_packet+12],0ffffh
    call up_send
    cmp word [up_packet+10],0
    jne failed
    cmp byte [up_packet+14],0b0h
    jne failed
    ret
up_receipt:
    mov word [up_packet+6],0
    jmp up_send
up_success:
    call up_send
    cmp word [up_packet+10],1
    jne failed
    ret
up_refused:
    call up_transport
    jnc failed
    ret
up_send:
    call up_transport
    jc failed
    ret
up_transport:
    smsw ax
    and ax,1
    mov [up_pe],al
    push cs
    pop es
    mov si,up_packet
    mov ah,87h
    int 15h
    pushf
    push ax
    smsw ax
    and ax,1
    cmp al,[up_pe]
    jne failed               ; OFF/idle AUTO must return to their entry mode
    pop ax
    popf
    ret
up_pe db 0
up_packet db 'XUMB'
    dw 1,0,0,0,0,0,0ffffh,0ffffh
up_source dw 2,0a000h,8004h,0a004h,1ch
up_registration dw 1,2,0b000h,10h,0b020h,20h
