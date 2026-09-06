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
include XMSUMBSTATE.INC
umb_state_end label near
xms_success:
    mov ax,1
    clc
    ret
xms_failure:
    xor ax,ax
    stc
    ret
umb_test:
    call umb_validator_matrix
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
    ; Checked staging, including two already allocated entries. Every refused
    ; attempt must leave the complete zero-filled destination unchanged.
    mov ax,20h
    mov es,ax
    mov si,offset umb_count
    mov di,si
    mov cx,MAX_UMB_BLOCKS
    mov bx,3                   ; source has four records after both splits
    call xms_stage_umb
    jnc failed
    mov bx,MAX_UMB_BLOCKS
    mov word ptr [umb_blocks+2],UMB_ALLOCATED ; zero-length live block
    call xms_stage_umb
    jnc failed
    mov word ptr [umb_blocks+2],UMB_ALLOCATED+4
    mov [umb_count],MAX_UMB_BLOCKS+1
    call xms_stage_umb
    jnc failed
    mov [umb_count],4
    push si
    mov si,0ffffh
    call xms_stage_umb          ; reject before even reading count
    pop si
    jnc failed
    push di
    mov di,0fff0h              ; selected records cross destination limit
    call xms_stage_umb
    pop di
    jnc failed
    push cx
    mov cx,umb_guard_end-umb_count
    push si
stage_rejected_check:
    cmp byte ptr es:[si],0
    jne failed
    inc si
    loop stage_rejected_check
    pop si
    pop cx
    std                       ; stager must preserve caller DF
    call xms_stage_umb
    jc failed
    pushf
    pop ax
    test ax,0400h
    jz failed
    cld
ifdef CORRUPT_UMB_STAGE
    and word ptr es:[umb_blocks+2],NOT UMB_ALLOCATED
endif
    ; Public import must validate the copied live state before publication.
    push ds
    push es
    pop ds
    call xms_validate_umb
    pop ds
    jc failed
    mov si,offset umb_count
    mov cx,2+4*UMB_BLOCK_SIZE
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
umb_validator_matrix proc near
    mov si,offset umb_count
    mov cx,MAX_UMB_BLOCKS
    call xms_validate_umb       ; empty owner is legal before RAM registration
    jc failed
    mov [umb_count],MAX_UMB_BLOCKS+1
    call xms_validate_umb
    jnc failed
    mov [umb_count],1
    mov word ptr [umb_blocks],0a000h
    mov word ptr [umb_blocks+2],0
    call xms_validate_umb
    jnc failed
    mov word ptr [umb_blocks+2],UMB_ALLOCATED
    call xms_validate_umb
    jnc failed
    mov word ptr [umb_blocks+2],UMB_ALLOCATED+1
    call xms_validate_umb
    jc failed
    mov word ptr [umb_blocks],09fffh
    call xms_validate_umb
    jnc failed
    mov word ptr [umb_blocks],0efffh
    call xms_validate_umb
    jc failed
    mov word ptr [umb_blocks+2],2
    call xms_validate_umb
    jnc failed
    mov word ptr [umb_blocks],0ffffh
    call xms_validate_umb
    jnc failed
    mov [umb_count],2
    mov word ptr [umb_blocks],0a000h
    mov word ptr [umb_blocks+2],20h
    mov word ptr [umb_blocks+4],0a010h
    mov word ptr [umb_blocks+6],10h
    call xms_validate_umb
    jnc failed
    mov word ptr [umb_blocks+4],0a020h
    call xms_validate_umb       ; adjacency does not require eager coalescing
    jc failed
    mov word ptr [umb_blocks+4],0a040h
    call xms_validate_umb
    jc failed
    mov [umb_count],MAX_UMB_BLOCKS
    mov di,offset umb_blocks
    mov ax,0a000h
    mov bx,MAX_UMB_BLOCKS
seed_full_owner:
    mov [di],ax
    mov word ptr [di+2],10h
    add ax,20h
    add di,4
    dec bx
    jnz seed_full_owner
    call xms_validate_umb
    jc failed
    dec cx
    call xms_validate_umb
    jnc failed
    inc cx
    mov bx,MAX_UMB_BLOCKS
    mov di,3000h              ; destination layout need not share source offset
    call xms_stage_umb
    jc failed
    push ds
    push si
    push es
    pop ds
    mov si,di
    call xms_validate_umb
    pop si
    pop ds
    jc failed
    cmp word ptr es:[3000h],MAX_UMB_BLOCKS
    jne failed
    cmp word ptr es:[3002h+(MAX_UMB_BLOCKS-1)*4],0a3e0h
    jne failed
    ; Full 64-KiB source selector is backed. An exclusive end at 10000h
    ; is legal, but count/record reads may not wrap to offset zero.
    mov si,0fffeh
    mov word ptr [si],0
    xor cx,cx
    call xms_validate_umb
    jc failed
    xor bx,bx
    mov di,0fffeh
    call xms_stage_umb          ; empty count ends exactly at destination 10000h
    jc failed
    mov word ptr [si],1
    mov cx,1
    call xms_validate_umb
    jnc failed
    mov si,0fffah
    mov word ptr [si],1
    mov word ptr [si+2],0a000h
    mov word ptr [si+4],1
    call xms_validate_umb
    jc failed
    mov si,offset umb_count
    mov cx,(umb_blocks_end-umb_count)/2
clear_owner:
    mov word ptr [si],0
    add si,2
    loop clear_owner
    ret
umb_validator_matrix endp
    db 1000h-($-image_start) dup (0)
umb_count dw 0
umb_blocks db MAX_UMB_BLOCKS*UMB_BLOCK_SIZE dup (0)
umb_blocks_end label byte
    db 32 dup (0)
umb_guard_end label byte
handles label byte             ; only used by the deliberately wrong bound
end
