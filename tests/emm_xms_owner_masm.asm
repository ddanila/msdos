; Execute the actual AllocMem/XMSAlloc procedures against a faulting provider.
; This is an isolated control-flow witness, not a replacement XMS allocator.
.model tiny
.386p
.code
org 100h
start:
        push cs
        pop ds
        mov ax,352fh
        int 21h
        mov word ptr [old2f],bx
        mov word ptr [old2f+2],es
        mov dx,offset multiplex
        mov ax,252fh
        int 21h
next_case:
        push cs
        pop es
        mov di,offset msg_flag
        mov cx,(record_end-msg_flag)/2
        xor ax,ax
        cld
        rep stosw
        mov [pool_size],64
        mov [min_xms],0
        cmp [case_id],6
        jne run_case
        mov [min_xms],0ffffh
run_case:
        call AllocMem
        mov dx,0e9h
        mov si,offset owner_record
        mov cx,record_end-owner_record
emit:
        lodsb
        out dx,al
        loop emit
        inc [case_id]
        cmp [case_id],7
        jb next_case
        lds dx,[old2f]
        mov ax,252fh
        int 21h
        mov ax,4c00h
        int 21h

multiplex:
        cmp ax,4300h
        jne entry_query
        xor al,al
        cmp cs:[case_id],0
        je query_done
        mov al,80h
query_done:
        iret
entry_query:
        cmp ax,4310h
        jne chain
        push cs
        pop es
        mov bx,offset provider
        iret
chain:
        jmp dword ptr cs:[old2f]

provider proc far
        cmp ah,8
        je query
        cmp ah,9
        je allocate
        cmp ah,0ch
        je lock_block
        cmp ah,0dh
        je unlock_block
        cmp ah,0ah
        je free_block
        int 3
query:
        mov ax,4096
        mov dx,ax
        cmp [case_id],5
        jne provider_return
        xor dx,dx
        ret
allocate:
        inc [alloc_calls]
        mov dx,1234h
        mov ax,1
        cmp [case_id],2
        jne provider_return
        xor ax,ax
        ret
lock_block:
        inc [lock_calls]
        mov ax,1
        mov dx,10h
        xor bx,bx
        cmp [case_id],3
        jne address_check
        xor ax,ax
address_check:
        cmp [case_id],4
        jne provider_return
        mov dx,100h
        ret
unlock_block:
        inc [unlock_calls]
        mov ax,1
        ret
free_block:
        inc [free_calls]
        mov ax,1
provider_return:
        ret
provider endp

memreq proc near
        mov cx,64
        ret
memreq endp
pool_initialise_abs proc near
        inc [pool_calls]
        ret
pool_initialise_abs endp
xbuf_chk proc near
        inc [fallback_calls]
        ret
xbuf_chk endp
ExtAlloc proc near
        ret
ExtAlloc endp
SysAlloc proc near
        ret
SysAlloc endp

include OWNER_CODE.INC

old2f dd 0
xms_entry dd 0
pool_size dw 64
min_xms dw 0
reloc_size dw 0
xbase_addr_l dw 0
xbase_addr_h db 0
ext_size dw 0
avail_mem dw 0
total_mem dw 0
owner_record db 'XA'
case_id dw 0
msg_flag dw 0
xms_handle dw 0
alloc_calls dw 0
lock_calls dw 0
unlock_calls dw 0
free_calls dw 0
pool_calls dw 0
fallback_calls dw 0
record_end label byte
end start
