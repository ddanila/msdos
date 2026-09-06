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
    mov dx,32
    call xms_allocate
    cmp ax,1
    jne failed
    cmp dx,1
    jne failed
    mov dx,32
    call xms_allocate
    cmp ax,1
    jne failed
    cmp dx,2
    jne failed
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

org 1000h
handle_limit dw 4
extended_kb dw 512
move_length dd 0
move_source dd 0
move_dest dd 0
fail_copy db 0
handles db 4*HANDLE_SIZE dup (0)
end
