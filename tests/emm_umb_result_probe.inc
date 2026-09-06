; Exercise one sequenced allocation, then query the final result without
; submitting the operation again. UMB_CALL records each public return value.
umb_result_fault_probe:
    call umb_largest
    mov [ur_before],dx
    mov dx,1
    mov ah,10h
    UMB_CALL
%ifdef UMB_REPLY_UNKNOWN
    call ur_assert_failure
    call umb_pending_probe
    ret
%endif
%ifdef UMB_REPLY_BEFORE
    or ax,ax
    jnz umb_failed
    cmp bl,8eh
    jne umb_failed
%else
    cmp ax,1
    jne umb_failed
    mov dx,bx
    mov ah,11h
    UMB_CALL
    cmp ax,1
    jne umb_failed
%endif
    call umb_largest
    cmp dx,[ur_before]
    jne umb_failed
    ret

umb_result_receipt_probe:
    mov es,[himem_segment]
    cmp byte [es:UMB_STATE_OFFSET],2
    jne umb_failed
    mov eax,[es:UMB_SEQUENCE_OFFSET]
    test eax,eax
    jz umb_failed
    mov [ur_sequence],eax
    mov [ur_packet+20],eax
    ; A service submission must be exactly next, never current/stale/skipped.
    mov word [ur_packet+6],10h
    mov word [ur_packet+12],1
    call ur_refused
    mov eax,[ur_sequence]
    dec eax
    mov [ur_packet+20],eax
    call ur_refused
    mov eax,[ur_sequence]
    add eax,2
    mov [ur_packet+20],eax
    call ur_refused
    ; Older unsequenced mutations cannot interleave with the v2 owner.
    mov word [ur_packet+4],1
    mov word [ur_packet+6],13h
    call ur_refused
    mov word [ur_packet+4],2
    mov word [ur_packet+6],2
    mov eax,[ur_sequence]
    inc eax
    jnz .next_ready
    inc eax
.next_ready:
    mov [ur_packet+20],eax
    call ur_transport         ; exactly next has not begun; does not consume it
    jc umb_failed
    cmp word [ur_packet+8],0
    jne umb_failed
    inc dword [ur_packet+20]
    call ur_refused           ; skipped sequence has no such receipt
    mov eax,[ur_sequence]
    mov [ur_packet+20],eax
    call ur_transport
    jc umb_failed
    cmp word [ur_packet+8],1
    jne umb_failed
    mov ax,[ur_packet+10]
    cmp ax,[ur_last_ax]
    jne umb_failed
    mov ax,[ur_packet+12]
    cmp ax,[ur_last_dx]
    jne umb_failed
    mov ax,[ur_packet+14]
    cmp ax,[ur_last_bx]
    jne umb_failed
    mov es,[himem_segment]
    mov eax,[ur_sequence]
    cmp eax,[es:UMB_SEQUENCE_OFFSET]
    jne umb_failed
%ifdef UMB_REPLY_AFTER
    cmp word [es:UMB_RECOVERED_OFFSET],1
%else
    cmp word [es:UMB_RECOVERED_OFFSET],0
%endif
    jne umb_failed
%ifdef UMB_REPLY_BEFORE
    cmp word [es:UMB_NOT_EXECUTED_OFFSET],1
%else
    cmp word [es:UMB_NOT_EXECUTED_OFFSET],0
%endif
    jne umb_failed
    mov dx,0e9h
    mov al,'U'
    out dx,al
    mov al,'R'
    out dx,al
    mov ax,[ur_sequence]
    call word_out
    mov ax,[ur_sequence+2]
    call word_out
    mov ax,[es:UMB_RECOVERED_OFFSET]
    call word_out
    mov ax,[es:UMB_NOT_EXECUTED_OFFSET]
    call word_out
    ret
ur_refused:
    call ur_transport
    jnc umb_failed
    ret
ur_transport:
    push cs
    pop es
    mov word [ur_packet+8],0
    mov si,ur_packet
    mov ah,87h
    int 15h
    ret
ur_packet db 'XUMB'
    dw 2,0,0,0,0,0,0ffffh,0ffffh
    dd 0
ur_sequence dd 0
ur_before dw 0
ur_last_ax dw 0
ur_last_dx dw 0
ur_last_bx dw 0
%ifdef UMB_REPLY_UNKNOWN
umb_pending_probe:
    mov es,[himem_segment]
    cmp byte [es:UMB_STATE_OFFSET],3
    jne umb_failed
    mov si,UMB_PACKET_OFFSET
    mov di,ur_pending_packet
    mov cx,24
.save:
    mov al,[es:si]
    mov [di],al
    inc si
    inc di
    loop .save
    mov eax,[es:UMB_SEQUENCE_OFFSET]
    mov [ur_sequence],eax
    mov dx,1
    mov ah,10h
    UMB_CALL
    call ur_assert_failure
    mov dx,0a000h
    mov ah,11h
    UMB_CALL
    call ur_assert_failure
    mov ax,0e702h
    int 2fh
    call ur_assert_failure
    mov es,[himem_segment]
    cmp byte [es:UMB_STATE_OFFSET],3
    jne umb_failed
    mov si,UMB_PACKET_OFFSET
    mov di,ur_pending_packet
    mov cx,24
.check:
    mov al,[es:si]
    cmp al,[di]
    jne umb_failed
    inc si
    inc di
    loop .check
    mov si,UMB_GUARD_OFFSET-130
    mov cx,130
.poison:
    cmp byte [es:si],0a5h
    jne umb_failed
    inc si
    loop .poison
    mov eax,[ur_sequence]
    cmp eax,[es:UMB_SEQUENCE_OFFSET]
    jne umb_failed
    mov dx,0e9h
    mov al,'U'
    out dx,al
    mov al,'X'
    out dx,al
    mov ax,3
    call word_out
    mov ax,[ur_sequence]
    call word_out
    mov ax,[ur_sequence+2]
    call word_out
    mov ax,3                  ; three subsequent operations were refused
    call word_out
    ret
ur_assert_failure:
    or ax,ax
    jnz umb_failed
    cmp bl,8eh
    jne umb_failed
    ret
ur_pending_packet times 24 db 0
%endif
