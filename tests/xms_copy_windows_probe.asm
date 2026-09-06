bits 16
org 100h
    push cs
    pop ds
    ; Repository-signed query: CONFIG text alone does not prove high residency.
    mov ax,580eh
    mov cx,4d55h
    mov si,2142h
    mov di,0a55ah
    int 21h
    jc residency_failed
    cmp ax,EXPECT_HMA
    jne residency_failed
    mov ax,3567h
    int 21h
    mov ax,[es:18]
    mov [control],ax
    mov [control+2],es
    call check_mode
    mov ax,4310h
    int 2fh
    mov [xms],bx
    mov [xms+2],es
    mov dx,16384
    mov ah,09h
    call far [xms]
    cmp ax,1
    jne failed
    mov [reserve],dx
    mov dx,32
    mov ah,09h
    call far [xms]
    cmp ax,1
    jne failed
    mov [block],dx
    mov ah,0ch
    call far [xms]
    cmp ax,1
    jne failed
    cmp dx,0100h
    jb failed ; the witness must actually reach physical memory above 16 MiB
    xor eax,eax
    mov ax,dx
    shl eax,16
    mov ax,bx
    mov [physical],eax
    xor bx,bx
.fill:
    mov al,bl
    xor al,bh
    xor al,5ah
    mov [source+bx],al
    inc bx
    cmp bx,8192
    jb .fill
    mov al,'A'
    call checkpoint
%ifdef HMA_ENDPOINT
    call hma_endpoint_test
%endif
%ifndef PUBLIC_COPY
    ; Rejected requests must not poison a later valid transaction.
    mov eax,[physical]
    mov [packet_source],eax
    inc eax
    mov [packet_dest],eax
    call reject ; non-identical overlap
    mov dword [packet_source],0fffffff0h
    call reject ; source range overflow, before dereferencing it
    mov dword [packet_length],0
    call copy
    jc failed
    test ah,ah
    jnz failed
    mov dword [packet_length],8192
%endif
    xor eax,eax
    mov ax,cs
    shl eax,4
    add eax,source
    cmp eax,40000h-8192 ; native conventional storage, outside bankable windows
    jae failed
    mov [packet_source],eax
    mov eax,[physical]
    add eax,4093
    mov [packet_dest],eax
    call copy
%ifdef EXPECT_MAP_FAILURE
    jnc failed
    cmp ah,2
    jne failed
%else
    jc failed
    test ah,ah
    jnz failed
    mov eax,[packet_dest]
    mov [packet_source],eax
    mov eax,[physical]
    add eax,16391
    mov [packet_dest],eax
    call copy
    jc failed
    test ah,ah
    jnz failed
    mov eax,[packet_dest]
    mov [packet_source],eax
    xor eax,eax
    mov ax,cs
    shl eax,4
    add eax,target
    cmp eax,40000h-8192
    jae failed
    mov [packet_dest],eax
    call copy
    jc failed
    test ah,ah
    jnz failed
    mov si,source
    mov di,target
%ifdef WRONG_DATA
    xor byte [target+4096],1
%endif
    mov cx,8192
    cld
    repe cmpsb
    jne failed
%ifdef MAPPED_ENDPOINT
%ifndef EXPECT_PAGE_FAILURE
    ; Native conventional addresses provide mixed physical/client identity
    ; and overlap controls without assuming the EMS backing's physical base.
    mov eax,[packet_dest] ; target buffer, just verified against source
    mov [packet_source],eax
    mov dword [packet_flags],1
    call copy
    jc failed
    test ah,ah
    jnz failed
    mov dword [packet_flags],2
    call copy
    jc failed
    test ah,ah
    jnz failed
    mov dword [packet_length],64
    inc dword [packet_dest]
    call reject
    mov dword [packet_flags],1
    call reject
    mov si,source
    mov di,target
    mov cx,8192
    cld
    repe cmpsb
    jne failed
    mov dword [packet_length],8192
%endif
    call mapped_test
%endif
%endif
    mov al,'B'
    call checkpoint
%ifdef PUBLIC_COPY
%ifndef EXPECT_MAP_FAILURE
%ifndef ALIAS_OVERLAP
    call public_reallocate_test
    mov al,'R'
    call checkpoint
%endif
%endif
%endif
    mov dx,[block]
    mov ah,0dh
    call far [xms]
    cmp ax,1
    jne failed
    mov dx,[block]
    mov ah,0ah
    call far [xms]
    cmp ax,1
    jne failed
    mov dx,[reserve]
    mov ah,0ah
    call far [xms]
    cmp ax,1
    jne failed
    mov ax,10h
    jmp finish
%ifdef MAPPED_ENDPOINT
mapped_test:
    mov ah,41h
    int 67h
    test ah,ah
    jnz failed
    mov [ems_frame],bx
    mov bx,2
    mov ah,43h
    int 67h
    test ah,ah
    jnz failed
    mov [ems_handle],dx
    xor bx,bx
    mov ax,4400h
    int 67h
    test ah,ah
    jnz failed
    mov dx,[ems_handle]
    mov bx,1
%ifdef ALIAS_OVERLAP
    xor bx,bx ; a second client window onto the same logical EMS page
%endif
    mov ax,4401h
    int 67h
    test ah,ah
    jnz failed
    xor bx,bx
.invert:
    xor byte [source+bx],0ffh
    inc bx
    cmp bx,8192
    jb .invert
    mov es,[ems_frame]
    mov si,source
    mov di,4093
    mov cx,8192
    cld
    rep movsb
    mov al,'M'
    call checkpoint
    mov dword [packet_flags],4
%ifndef PUBLIC_COPY
    call reject ; no implicit acceptance of unknown address classes
%endif
    movzx eax,word [ems_frame]
    shl eax,4
    add eax,4093
    mov [packet_source],eax
    mov eax,[physical]
    add eax,4093
    mov [packet_dest],eax
    mov dword [packet_flags],1
%ifdef ALIAS_OVERLAP
    movzx eax,word [ems_frame]
    shl eax,4
    add eax,4007h
    mov [packet_dest],eax
    mov dword [packet_flags],3
%ifdef ALIAS_REVERSE
    sub dword [packet_source],4086
    add dword [packet_dest],4086
%endif
%ifdef ALIAS_IDENTITY
    add dword [packet_dest],4086
%endif
%ifdef ALIAS_DISJOINT
    mov dword [packet_length],64
%endif
    ; In the default overlap case, source 4093..12284 and destination 7..8198 occupy
    ; overlapping physical storage, despite disjoint client-linear ranges.
    ; Snapshot before checking status so partial writes cannot hide behind CF.
    call copy
    pushf
    pop word [alias_status]
    mov [alias_error],ah
    jmp mapped_done
%endif
%ifdef BYPASS_MAPPING
    mov dword [packet_flags],0
%endif
%ifdef EXPECT_PAGE_FAILURE
%ifdef EXPECT_DEST_PAGE_FAILURE
    mov eax,[packet_dest]
    mov [packet_source],eax
    movzx eax,word [ems_frame]
    shl eax,4
    add eax,4007h
    mov [packet_dest],eax
    mov dword [packet_flags],2
%endif
    call reject
    jmp mapped_done
%endif
    call copy
    jc failed
    test ah,ah
    jnz failed
    mov eax,[packet_dest]
    mov [packet_source],eax
    movzx eax,word [ems_frame]
    shl eax,4
    add eax,4007h
    mov [packet_dest],eax
    mov dword [packet_flags],2
    call copy
    jc failed
    test ah,ah
    jnz failed
    call mapped_read
    ; Also exercise client-to-client copying between different EMS pages.
    mov ax,[ems_frame]
    add ax,400h
    mov es,ax
    mov di,7
    mov cx,8192
    xor ax,ax
    rep stosb
    movzx eax,word [ems_frame]
    shl eax,4
    add eax,4093
    mov [packet_source],eax
    mov dword [packet_flags],3
    call copy
    jc failed
    test ah,ah
    jnz failed
    call mapped_read
mapped_done:
    mov al,'N'
    call checkpoint
%ifdef ALIAS_OVERLAP
%ifdef ALIAS_SUCCESS
    test word [alias_status],1
    jnz failed
    cmp byte [alias_error],0
%else
    test word [alias_status],1
    jz failed
    cmp byte [alias_error],2
%endif
    jne failed
%endif
    mov dx,[ems_handle]
    mov ah,45h
    int 67h
    test ah,ah
    jnz failed
    mov word [ems_frame],0
    ret
mapped_read:
    mov ax,[ems_frame]
    add ax,400h
    push ds
    mov ds,ax
    mov si,7
    push cs
    pop es
    mov di,target
    mov cx,8192
    cld
    rep movsb
    pop ds
    mov si,source
    mov di,target
    mov cx,8192
    repe cmpsb
    jne failed
    ret
%endif
copy:
    pushad
    mov ah,7
    call far [cs:xms]
    mov [cs:a20_before],ax
    popad
    push cs
    pop es
%ifdef PUBLIC_COPY
    call public_copy
%else
    mov si,packet
    mov ah,87h
    int 15h
%endif
    call check_mode
    pushf
    pushad
    mov ah,7
    call far [cs:xms]
    cmp ax,[cs:a20_before]
    jne failed
    popad
    popf
    ret
%ifdef PUBLIC_COPY
%ifdef HMA_ENDPOINT
hma_endpoint_test:
    mov ax,1236h
    mov cx,64
    int 2fh
    test ax,ax
    jz failed
    mov ax,es
    cmp ax,0ffffh
    jne failed
    mov [hma_offset],di
    mov si,source
    mov cx,64
    cld
    rep movsb
    movzx eax,word [hma_offset]
    add eax,0ffff0h
    mov [packet_source],eax
    mov eax,[physical]
    mov [packet_dest],eax
    mov dword [packet_length],64
    call copy
    jc failed
    mov ax,0ffffh
    mov es,ax
    mov di,[hma_offset]
    xor ax,ax
    mov cx,64
    rep stosb
    mov eax,[packet_source]
    xchg eax,[packet_dest]
    mov [packet_source],eax
    call copy
    jc failed
    mov ax,0ffffh
    mov es,ax
    mov si,source
    mov di,[hma_offset]
    mov cx,64
    repe cmpsb
    jne failed
%ifdef BAD_HMA_DATA
    xor byte [es:di-1],1 ; host must detect this after the guest comparison passed
%endif
    push cs
    pop es
    mov dword [packet_length],8192
    ret
%endif
public_reallocate_test:
    mov dx,[block]
    mov ah,0dh
    call far [xms]
    cmp ax,1
    jne failed
    mov dx,32
    mov ah,9
    call far [xms]
    cmp ax,1
    jne failed
    mov [blocker],dx
    mov ah,0ch
    call far [xms]
    cmp ax,1
    jne failed
    movzx eax,dx
    shl eax,16
    mov ax,bx
    sub eax,[physical]
    cmp eax,32768 ; prove the following interval blocks in-place growth
    jne failed
    mov ah,7
    call far [xms]
    mov [a20_before],ax
    mov dx,[block]
    mov bx,64
    mov ah,0fh
    call far [xms]
    cmp ax,1
    jne failed
    call check_mode
    mov ah,7
    call far [xms]
    cmp ax,[a20_before]
    jne failed
    mov dx,[block]
    mov ah,0ch
    call far [xms]
    cmp ax,1
    jne failed
    movzx eax,dx
    shl eax,16
    mov ax,bx
    cmp eax,[physical]
    je failed ; the existing handle must now refer to a different physical block
    mov [physical],eax
    push eax
    mov dx,[block]
    mov ah,0eh
    call far [xms]
    cmp ax,1
    jne failed
    cmp dx,64
    jne failed
    cmp bh,1
    jne failed
    pop eax
    add eax,4093
    mov [packet_source],eax
    xor eax,eax
    mov ax,cs
    shl eax,4
    add eax,target
    mov [packet_dest],eax
    mov dword [packet_length],8192
    call copy
    jc failed
    mov si,source
    mov di,target
    mov cx,8192
    cld
    repe cmpsb
    jne failed
%ifdef MAPPED_ENDPOINT
    xor bx,bx
.restore_pattern:
    xor byte [source+bx],0ffh
    inc bx
    cmp bx,8192
    jb .restore_pattern
%endif
    mov eax,[physical]
    add eax,16391
    mov [packet_source],eax
    call copy
    jc failed
    mov si,source
    mov di,target
    mov cx,8192
    cld
    repe cmpsb
    jne failed
    mov dx,[blocker]
    mov ah,0dh
    call far [xms]
    cmp ax,1
    jne failed
    mov dx,[blocker]
    mov ah,0ah
    call far [xms]
    cmp ax,1
    jne failed
    ret
public_copy:
    mov eax,[packet_length]
    mov [public_packet],eax
    mov eax,[packet_source]
    call public_endpoint
    mov [public_packet+4],dx
    mov [public_packet+6],eax
    mov eax,[packet_dest]
    call public_endpoint
    mov [public_packet+10],dx
    mov [public_packet+12],eax
    mov si,public_packet
    mov ah,0bh
    call far [xms]
    cmp ax,1
    je .ok
    test ax,ax
    jnz failed
    cmp bl,8eh ; existing HIMEM backend-failure translation
    jne failed
    mov ah,2 ; normalize only after checking actual public AX/BL
    stc
    ret
.ok:
    xor ah,ah
    clc
    ret
public_endpoint:
    cmp eax,110000h
    jb .conventional
    sub eax,[physical]
    jc failed
    cmp eax,32768
    jae failed
    mov dx,[block]
    ret
.conventional:
    cmp eax,0ffff0h
    jb .low
    sub eax,0ffff0h
    or eax,0ffff0000h
    xor dx,dx
    ret
.low:
    mov edx,eax
    and edx,15
    shr eax,4
    shl eax,16
    or eax,edx
    xor dx,dx
    ret
%endif
check_mode:
    pushf
    pushad
    push ds
    push es
    xor ah,ah
    call far [cs:control]
    cmp ah,EXPECT_MODE
    jne mode_failed
    pop es
    pop ds
    popad
    popf
    ret
mode_failed:
    mov al,'m'
    out 0e9h,al
    jmp failed
residency_failed:
    mov al,'h'
    out 0e9h,al
    jmp failed
reject:
    call copy
    jnc failed
    cmp ah,2
    jne failed
    ret
checkpoint:
    out 0e9h,al
    xor ah,ah
    int 16h
    ret
failed:
    mov al,'!'
    out 0e9h,al
    mov ax,11h
finish:
    mov dx,0f4h
    out dx,ax
    cli
    hlt
xms dd 0
control dd 0
a20_before dw 0
reserve dw 0
block dw 0
witness_signature db 'XWPROBE!'
physical dd 0
ems_frame dw 0
ems_handle dw 0
%ifdef HMA_ENDPOINT
hma_offset dw 0
%endif
%ifdef ALIAS_OVERLAP
alias_status dw 0
alias_error db 0
%endif
packet db 'XCPY'
packet_length:
    dd 8192
packet_source dd 0
packet_dest dd 0
packet_flags dd 0
%ifdef PUBLIC_COPY
public_packet times 16 db 0
blocker dw 0
%endif
source times 8192 db 0
target times 8192 db 0
