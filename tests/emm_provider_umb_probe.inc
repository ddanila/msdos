; Exercise allocator metadata. Only the live-import RAM control accesses
; actually allocated UMB backing; synthetic ranges are never dereferenced.
; Real registered ranges are used when available. Otherwise a temporary
; two-range registration tests the same peer/public owner in OFF/cancel modes.
%macro UMB_CALL 0
%ifdef UMB_HANDOFF_TEST
    push ax
    smsw ax
    and ax,1
    mov [umb_pe],al
    pop ax
%endif
    call far [umb_entry]
%ifdef UMB_HANDOFF_TEST
    pushf
    push ax
    smsw ax
    and ax,1
    cmp al,[umb_pe]
    jne umb_failed
    pop ax
    popf
%endif
%ifdef UMB_SERVICE_RECEIPTS
    mov [ur_last_ax],ax
    mov [ur_last_dx],dx
    mov [ur_last_bx],bx
%endif
%endmacro
%macro UMB_IMPORT_FAILURE_CHECK 0
%ifdef UMB_LOST_IMPORT_REPLY
%define UMB_IMPORT_FAILURE 1
%endif
%ifdef UMB_REFUSED_IMPORT
%define UMB_IMPORT_FAILURE 1
%endif
%ifdef UMB_IMPORT_FAILURE
    mov dx,0ffffh
    mov ah,10h
    UMB_CALL
    or ax,ax
    jnz umb_failed
    cmp bl,8eh
    jne umb_failed
    mov es,[himem_segment]
    cmp byte [es:UMB_STATE_OFFSET],1
    jne umb_failed
%endif
%ifdef UMB_REFUSED_IMPORT
    mov dx,0ffffh
    mov ah,10h
    UMB_CALL
    or ax,ax
    jnz umb_failed
    cmp bl,8eh
    jne umb_failed
    mov es,[himem_segment]
    cmp byte [es:UMB_STATE_OFFSET],0
    jne umb_failed             ; confirmed uncommitted; original owner unfreezes
%endif
%endmacro
%macro UMB_ALLOCATE_PAIR 0
    mov dx,1
    mov ah,10h
    UMB_CALL
    cmp ax,1
    jne umb_failed
    mov [umb_first],bx
    mov dx,1
    mov ah,10h
    UMB_CALL
    cmp ax,1
    jne umb_failed
    mov [umb_second],bx
%endmacro
check_umb_owner:
    mov ax,4310h
    int 2fh
    mov [umb_entry],bx
    mov [umb_entry+2],es
    mov es,[himem_segment]
    mov si,UMB_GUARD_OFFSET
    mov di,umb_guard
    mov cx,48
.save:
    mov al,[es:si]
    mov [di],al
    inc si
    inc di
    loop .save
%ifndef UMB_LIVE_IMPORT
    UMB_IMPORT_FAILURE_CHECK
%endif
    call umb_largest
    or dx,dx
    jnz .have_ranges
    mov ax,0e701h
    mov si,umb_registration
    int 2fh
    cmp ax,1
    jne umb_failed
    mov byte [umb_synthetic],1
    call umb_largest
.have_ranges:
    cmp dx,2
    jb umb_failed
    mov [umb_before],dx
%ifdef UMB_LIVE_IMPORT
    UMB_ALLOCATE_PAIR
    mov es,[himem_segment]
    cmp byte [es:UMB_STATE_OFFSET],0
    jne umb_failed
    cmp byte [es:UMB_DEFER_OFFSET],1
    jne umb_failed
    mov ax,[umb_first]
    call umb_check_low_allocated
    mov ax,[umb_second]
    call umb_check_low_allocated
    cmp byte [umb_synthetic],0
    jne .live_payload_ready
    push es
    mov es,[umb_first]
    xor di,di
    mov cx,16
    mov al,5ah
    cld
    rep stosb
    mov es,[umb_second]
    xor di,di
    mov cx,16
    mov al,0a5h
    rep stosb
    pop es
.live_payload_ready:
    mov byte [es:UMB_DEFER_OFFSET],0
    UMB_IMPORT_FAILURE_CHECK
    call umb_largest          ; import the existing allocations, not an empty pool
    mov es,[himem_segment]
    cmp byte [es:UMB_STATE_OFFSET],2
    jne umb_failed
    cmp byte [umb_synthetic],0
    jne .live_payload_checked
    push es
    mov es,[umb_first]
    xor di,di
    mov cx,16
    mov al,5ah
    cld
    repe scasb
    jne umb_failed
    mov es,[umb_second]
    xor di,di
    mov cx,16
    mov al,0a5h
    repe scasb
    jne umb_failed
    pop es
.live_payload_checked:
%endif
%ifdef COMMON_PUBLIC_MOVE
    call common_packets_begin
    mov ax,0e701h
    mov si,umb_registration
    int 2fh
    test ax,ax                  ; already registered: same authoritative owner
    jnz umb_failed
    cmp bl,1
    jne umb_failed
%endif
%ifdef UMB_HANDOFF_TEST
    ; Retired low count/records must no longer drive either public or peer
    ; operations. Never touch the UMB backing addresses themselves.
    mov es,[himem_segment]
    mov di,UMB_GUARD_OFFSET-130
    mov cx,130
    mov al,0a5h
    cld
    rep stosb
%endif
%ifdef UMB_SERVICE_RECEIPTS
    call umb_result_fault_probe
%ifdef UMB_REPLY_UNKNOWN
    ret                       ; pending owner is intentionally not cleaned up
%endif
%endif
%ifndef UMB_LIVE_IMPORT
    UMB_ALLOCATE_PAIR
%endif
    mov ax,0e702h              ; live allocations must prevent peer rollback
    int 2fh
    or ax,ax
    jnz umb_failed
    cmp bl,2
    jne umb_failed
    mov dx,[umb_first]
    mov ah,11h
    UMB_CALL
    cmp ax,1
    jne umb_failed
    mov dx,[umb_second]
    mov ah,11h
    UMB_CALL
    cmp ax,1
    jne umb_failed
    mov dx,[umb_second]        ; duplicate/interior release must be rejected
    mov ah,11h
    UMB_CALL
    or ax,ax
    jnz umb_failed
    cmp bl,0b2h
    jne umb_failed
    call umb_largest
    cmp dx,[umb_before]
    jne umb_failed
    mov es,[himem_segment]
    mov si,UMB_GUARD_OFFSET
    mov di,umb_guard
    mov cx,48
.check:
    mov al,[es:si]
    cmp al,[di]
    jne umb_overrun
    inc si
    inc di
    loop .check
    cmp byte [umb_synthetic],0
    je .done
    mov ax,0e702h
    int 2fh
    cmp ax,1
    jne umb_failed
    call umb_largest
    or dx,dx
    jnz umb_failed
%ifdef COMMON_PUBLIC_MOVE
    mov ax,0e701h
    mov si,umb_registration
    int 2fh
    cmp ax,1
    jne umb_failed
    mov ax,0e702h
    int 2fh
    cmp ax,1
    jne umb_failed
    call umb_largest
    or dx,dx
    jnz umb_failed
%endif
.done:
%ifdef UMB_LOW_FALLBACK_TEST
    mov es,[himem_segment]
    cmp byte [es:UMB_STATE_OFFSET],0
    jne umb_failed
%endif
    mov dx,0e9h
    mov al,'U'
    out dx,al
    mov al,'C'
    out dx,al
    mov al,[umb_synthetic]
    out dx,al
%ifdef UMB_HANDOFF_TEST
    call umb_handoff_receipt
%endif
%ifdef UMB_LIVE_IMPORT
    mov dx,0e9h
    mov al,'U'
    out dx,al
    mov al,'L'
    out dx,al
    mov ax,[umb_first]
    call word_out
    mov ax,[umb_second]
    call word_out
    mov ax,2
    call word_out
%endif
%ifdef UMB_SERVICE_RECEIPTS
    call umb_result_receipt_probe
%endif
%ifdef COMMON_PUBLIC_MOVE
    call check_common_public_move
    call check_common_binding
    call common_packets_finish
%endif
    ret
%ifdef UMB_LIVE_IMPORT
umb_check_low_allocated:
    mov si,UMB_GUARD_OFFSET-128
    mov cx,[es:si-2]
    or cx,cx
    jz umb_failed
    cmp cx,32
    ja umb_failed
.find:
    cmp [es:si],ax
    je .found
    add si,4
    loop .find
    jmp umb_failed
.found:
    cmp word [es:si+2],8001h
    jne umb_failed
    ret
%endif
%ifdef UMB_HANDOFF_TEST
umb_handoff_receipt:
    mov es,[himem_segment]
    mov si,UMB_GUARD_OFFSET-130
    mov cx,130
.poison:
    cmp byte [es:si],0a5h
    jne umb_failed
    inc si
    loop .poison
    cmp byte [es:UMB_STATE_OFFSET],2
    jne umb_failed
    push cs
    pop es
    mov si,umb_receipt_packet
    mov ah,87h
    int 15h
    jc umb_failed
    cmp word [umb_receipt_packet+10],1
    jne umb_failed
    cmp word [umb_receipt_packet+14],1
    jne umb_failed
    mov ax,[umb_receipt_packet+12]
    cmp ax,32
    ja umb_failed
    cmp byte [umb_synthetic],0
    je .real
    or ax,ax
    jnz umb_failed
    jmp .emit
.real:
    or ax,ax
    jz umb_failed
.emit:
    mov dx,0e9h
    mov al,'U'
    out dx,al
    mov al,'H'
    out dx,al
    mov ax,[umb_receipt_packet+10]
    call word_out
    mov ax,[umb_receipt_packet+14]
    call word_out
    mov ax,[umb_receipt_packet+12]
    call word_out
    ret
umb_receipt_packet db 'XUMB'
    dw 1,0,0,0,0,0,0ffffh,0ffffh
umb_pe db 0
%endif
umb_largest:
    mov dx,0ffffh
    mov ah,10h
    UMB_CALL
    or ax,ax
    jnz umb_failed
    cmp bl,0b0h
    je .done
    cmp bl,0b1h
    jne umb_failed
.done:
    ret
umb_overrun:
    mov al,'W'
    jmp short umb_error
umb_failed:
    mov al,'F'
umb_error:
    mov dx,0e9h
    out dx,al
    jmp failed
himem_segment dw 0
umb_entry dd 0
umb_first dw 0
umb_second dw 0
umb_before dw 0
umb_synthetic db 0
umb_registration dw 1,2,0a000h,10h,0b000h,20h
umb_guard times 48 db 0
%ifdef UMB_SERVICE_RECEIPTS
    %include "tests/emm_umb_result_probe.inc"
%endif
%ifdef COMMON_PUBLIC_MOVE
    %include "tests/emm_common_move_probe.inc"
    %include "tests/emm_common_binding_probe.inc"
    %include "tests/emm_common_frame_probe.inc"
%endif
