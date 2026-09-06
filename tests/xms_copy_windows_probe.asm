bits 16
org 100h
    push cs
    pop ds
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
    call reject ; no implicit acceptance of unknown address classes
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
    mov si,packet
    mov ah,87h
    int 15h
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
source times 8192 db 0
target times 8192 db 0
