; Same UMB service/peer bodies as HIMEM, with separate protected CS/DS/SS.
; DS publication here is a test transaction, not an installed-provider handoff.
.model tiny
.386p
.code
org 0
image_start label byte
include allocator_equates.inc
include XMSUMBPEER.INC
    jmp umb_test
include XMSUMB.INC
umb_services_end label near
umb_register proc near
    HIMEM_UMB_REGISTER
private_done:
    ret
umb_register endp
umb_unregister proc near
    HIMEM_UMB_UNREGISTER
private_unregister_done:
    ret
umb_unregister endp
umb_peer_end label near
xms_success:
    mov ax,1
    clc
    ret
xms_failure:
    xor ax,ax
    stc
    ret
umb_test:
    mov ax,30h
    mov es,ax                 ; read-only packet in the high code image
    mov si,offset invalid_packet
    call umb_register
    or ax,ax
    jnz failed
    cmp [umb_count],0
    jne failed
    mov si,offset valid_packet
    call umb_register
    cmp ax,1
    jne failed
    mov dx,4
    call xms_umb_request
    cmp ax,1
    jne failed
    cmp bx,0a000h
    jne failed
    mov dx,4
    call xms_umb_request
    cmp ax,1
    jne failed
    cmp bx,0a004h
    jne failed
    call umb_unregister
    or ax,ax
    jnz failed
    cmp bl,2
    jne failed
    ; Transfer the full table, including two already allocated entries.
    mov ax,20h
    mov es,ax
    mov si,offset umb_count
    mov di,si
    mov cx,umb_blocks_end-umb_count
    cld
    rep movsb
    mov si,offset umb_count
    mov cx,umb_blocks_end-umb_count
compare_owner:
    mov al,[si]
    cmp es:[si],al
    jne failed
    inc si
    loop compare_owner
    push ds
    push es
    pop ds
    pop es
    mov di,offset umb_count
    mov cx,umb_guard_end-umb_count
    mov al,0a5h
    rep stosb                 ; old low state must never be consulted again
    push ds
    pop es
    mov di,offset umb_blocks_end
    mov cx,umb_guard_end-umb_blocks_end
    mov al,05ah
seed_guard:
    stosb
    inc al
    loop seed_guard
    call umb_unregister       ; imported allocations still prevent rollback
    or ax,ax
    jnz failed
    cmp bl,2
    jne failed
    mov dx,0a000h
    call xms_umb_release
    cmp ax,1
    jne failed
    mov dx,0a004h
    call xms_umb_release
    cmp ax,1
    jne failed
    mov dx,0a004h
    call xms_umb_release
    or ax,ax
    jnz failed
    cmp bl,ERR_BAD_UMB
    jne failed
    mov dx,0ffffh
    call xms_umb_request
    or ax,ax
    jnz failed
    cmp dx,20h
    jne failed
    cmp [umb_count],2
    jne failed
    cmp word ptr [umb_blocks],0a000h
    jne failed
    cmp word ptr [umb_blocks+2],20h
    jne failed
    cmp word ptr [umb_blocks+4],0b000h
    jne failed
    cmp word ptr [umb_blocks+6],10h
    jne failed
    ; Host inspects the live high state and both retired/guard regions here.
    mov al,'P'
    out 0e9h,al
wait_key:
    in al,64h
    test al,1
    jz wait_key
    in al,60h
    call umb_unregister
    cmp ax,1
    jne failed
    cmp [umb_count],0
    jne failed
    mov dx,0f4h
    mov ax,10h
    out dx,ax
    jmp short stopped
failed:
    mov al,'!'
    out 0e9h,al
    mov dx,0f4h
    mov ax,11h
    out dx,ax
stopped:
    cli
    hlt
    jmp stopped
valid_packet dw 1,2,0a000h,20h,0b000h,10h
invalid_packet dw 1,2,0a000h,20h,0a010h,10h
    db 1000h-($-image_start) dup (0)
umb_count dw 0
umb_blocks db MAX_UMB_BLOCKS*UMB_BLOCK_SIZE dup (0)
umb_blocks_end label byte
    db 32 dup (0)
umb_guard_end label byte
handles label byte             ; only used by the deliberately wrong bound
end
