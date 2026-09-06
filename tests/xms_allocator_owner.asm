; CPU witness for the actual shared allocator with separate high CS/DS/SS.
; The fixture supplies return adapters and a flat protected copy backend;
; it is not the installed EMM allocator or a production ownership transfer.
.model tiny
.386p
.code
org 0
include allocator_equates.inc
    jmp allocator_test
include XMSALLOC.INC
allocator_services_end label near
include XMSHANDLE.INC
allocator_helpers_end label near
ifdef ACCEPT_INVALID_OWNER
xms_validate_owner proc near
    clc
    ret
xms_validate_owner endp
else
include XMSSTATE.INC
endif
allocator_validator_end label near
xms_success:
    mov ax,1
    clc
    ret
xms_failure:
    xor ax,ax
    stc
    ret
xms_bad_handle:
    mov bl,ERR_BAD_HANDLE
    jmp xms_failure
xms_no_memory:
    mov bl,ERR_NO_MEMORY
    jmp xms_failure
kb_to_physical proc near
    mov dx,ax
    mov cl,6
    shr dx,cl
    add dx,10h
    mov cl,10
    shl ax,cl
    ret
kb_to_physical endp
copy_move_blocks proc near
    cmp byte ptr [fail_copy],0
    jne short copy_failed
    pushad
    push ds
    push es
    mov esi,dword ptr [move_source]
    mov edi,dword ptr [move_dest]
    mov ecx,dword ptr [move_length]
    push gs
    pop ds
    push gs
    pop es
    cld
    rep movs byte ptr es:[edi],byte ptr ds:[esi]
    pop es
    pop ds
    popad
    clc
    ret
copy_failed:
    stc
    ret
copy_move_blocks endp
allocator_test:
    ; Begin with a nonempty owner, including two existing locked handles.
    mov cx,4
    call owner_valid
    mov dx,16
    call xms_allocate
    cmp ax,1
    jne failed
    cmp dx,3
    jne failed
    cmp word ptr [handles+2*HANDLE_SIZE+HANDLE_BASE],128
    jne failed
    call xms_free
    cmp ax,1
    jne failed
    mov dx,1
    call xms_handle_info
    cmp bh,2
    jne failed
    cmp dx,32
    jne failed
    mov dx,2
    call xms_handle_info
    cmp bh,1
    jne failed
    cmp dx,32
    jne failed
    mov dx,1
    call xms_free
    cmp bl,ERR_LOCKED
    jne failed
    mov dx,1
    call xms_unlock
    mov dx,1
    call xms_unlock
    mov dx,2
    call xms_unlock
    mov dx,1
    call xms_lock
    cmp ax,1
    jne failed
    cmp dx,11h
    jne failed
    test bx,bx
    jnz failed
    mov esi,110000h
    xor ecx,ecx
seed_payload:
    mov eax,ecx
    xor eax,13579bdfh
    mov gs:[esi],eax
    add esi,4
    add ecx,4
    cmp ecx,32768
    jb seed_payload
    mov dx,1
    call xms_unlock
    cmp ax,1
    jne failed
    mov byte ptr [fail_copy],1
    mov dx,1
    mov bx,64
    call xms_reallocate
    test ax,ax
    jnz failed
    cmp bl,ERR_NO_MEMORY
    jne failed
    cmp word ptr [handles+HANDLE_BASE],64
    jne failed
    cmp word ptr [handles+HANDLE_LENGTH],32
    jne failed
    call xms_query_free
    cmp ax,384
    jne failed
    cmp dx,384
    jne failed
    test bl,bl
    jnz failed
    mov byte ptr [fail_copy],0
    mov dx,1
    mov bx,64
    call xms_reallocate
    cmp ax,1
    jne failed
    mov dx,1
    call xms_lock
    cmp ax,1
    jne failed
    cmp dx,12h
    jne failed
    test bx,bx
    jnz failed
    cmp dword ptr gs:[120000h],13579bdfh
    jne failed
    mov dx,1
    call xms_free
    test ax,ax
    jnz failed
    cmp bl,ERR_LOCKED
    jne failed
    mov dx,1
    call xms_unlock
    cmp ax,1
    jne failed
    mov dx,1
    call xms_free
    cmp ax,1
    jne failed
    mov dx,2
    call xms_free
    cmp ax,1
    jne failed
    call xms_query_free
    cmp ax,448
    jne failed
    cmp dx,448
    jne failed
    test bl,bl
    jnz failed
    call owner_cases
    mov al,'P'
    out 0e9h,al
wait_host:
    in al,64h
    test al,1
    jz wait_host
    in al,60h
    mov ax,10h
    jmp finish
failed:
    mov al,'!'
    out 0e9h,al
    mov ax,11h
finish:
    mov dx,0f4h
    out dx,ax
    cli
    hlt

; Each validation must preserve the entire owner, including stale lengths,
; on success and failure. Snapshot through an independent physical selector.
owner_prepare:
    push cx
    xor esi,esi
owner_snapshot:
    mov al,byte ptr [handle_limit+si]
    mov gs:[230000h+esi],al
    inc si
    cmp si,37
    jb owner_snapshot
    pop cx
    mov ax,1234h
    mov bx,2345h
    mov dx,3456h
    mov si,4567h
    mov di,5678h
    mov bp,6789h
    ret
owner_valid:
    call owner_prepare
    push cx
    call xms_validate_owner
    jc failed
    jmp short owner_unchanged
owner_invalid_expected:
    call owner_prepare
    push cx
    call xms_validate_owner
    jnc failed
owner_unchanged:
    cmp ax,1234h
    jne failed
    cmp bx,2345h
    jne failed
    cmp dx,3456h
    jne failed
    cmp si,4567h
    jne failed
    cmp di,5678h
    jne failed
    cmp bp,6789h
    jne failed
    pop ax
    cmp cx,ax
    jne failed
    mov ax,ds
    cmp ax,20h
    jne failed
    mov ax,es
    cmp ax,20h
    jne failed
    xor esi,esi
owner_compare:
    mov al,byte ptr [handle_limit+si]
    cmp al,gs:[230000h+esi]
    jne failed
    inc si
    cmp si,37
    jb owner_compare
    ret
owner_cases:
    mov cx,4
    call owner_valid                 ; freed records retain their lengths
    xor cx,cx
    call owner_invalid_expected
    mov cx,MAX_HANDLES+1
    call owner_invalid_expected
    mov cx,3                        ; owner limit exceeds backed capacity
    call owner_invalid_expected
    mov cx,4
    mov word ptr [handle_limit],0
    call owner_invalid_expected
    mov word ptr [handle_limit],4
    mov byte ptr [handles+HANDLE_LOCK],1
    call owner_invalid_expected     ; locked free record
    mov word ptr [handles+HANDLE_BASE],63
    call owner_invalid_expected     ; HMA overlap
    mov word ptr [handles+HANDLE_BASE],0fff0h
    call owner_invalid_expected     ; base + stale length wraps
    mov word ptr [handles+HANDLE_BASE],500
    call owner_invalid_expected     ; pool overflow
    mov word ptr [handles+HANDLE_BASE],64
    mov word ptr [handles+HANDLE_LENGTH],32
    mov word ptr [handles+HANDLE_SIZE+HANDLE_BASE],80
    mov word ptr [handles+HANDLE_SIZE+HANDLE_LENGTH],32
    call owner_invalid_expected     ; partial overlap
    mov word ptr [handles+HANDLE_SIZE+HANDLE_BASE],64
    call owner_invalid_expected     ; identical nonempty ranges
    mov word ptr [handles+HANDLE_SIZE+HANDLE_BASE],96
    call owner_valid                 ; adjacent ranges
    mov word ptr [handles+HANDLE_SIZE+HANDLE_BASE],64
    mov word ptr [handles+HANDLE_BASE],80
    call owner_invalid_expected     ; reversed record ordering
    mov word ptr [handles+HANDLE_BASE],64
    mov word ptr [handles+HANDLE_SIZE+HANDLE_BASE],70
    mov word ptr [handles+HANDLE_SIZE+HANDLE_LENGTH],0
    call owner_valid                 ; zero-size handle inside live range
    mov word ptr [handles+HANDLE_SIZE+HANDLE_BASE],512
    mov byte ptr [handles+HANDLE_SIZE+HANDLE_LOCK],255
    call owner_valid                 ; zero-size handle at pool end
    mov word ptr [handles+HANDLE_SIZE+HANDLE_BASE],513
    call owner_invalid_expected
    mov word ptr [handles+HANDLE_SIZE+HANDLE_BASE],0
    mov byte ptr [handles+HANDLE_SIZE+HANDLE_LOCK],0
    mov word ptr [handles+HANDLE_BASE],0
    mov byte ptr [handles+HANDLE_LOCK],0
    mov word ptr [extended_kb],0
    call owner_valid                 ; no ordinary XMS, all records free
    mov word ptr [extended_kb],512
    ret

org 1000h
handle_limit dw 4
extended_kb dw 512
move_length dd 0
move_source dd 0
move_dest dd 0
fail_copy db 0
handles db 2
    dw 64,32
    db 1
    dw 96,32
    db 2*HANDLE_SIZE dup (0)
end
