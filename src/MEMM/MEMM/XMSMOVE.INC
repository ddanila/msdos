; Public XMS Move validation against the authoritative high handle owner.
; DS=VDMCA_GSEL; ES:SI names a readable 16-byte descriptor snapshot. The
; adapter bounds the snapshot and serializes the call. No handle lookup is
; exported to low scratch. Preserve the allocator's idle copy workspace.
public XmsPublicMove, XmsPublicMoveEnd
XmsPublicMove proc near
        push bp
        mov bp,si
        push dword ptr [move_length]
        push dword ptr [move_source]
        push dword ptr [move_dest]
        mov ecx,es:[bp]
        mov [move_length],ecx
        mov bl,ERR_BAD_LENGTH
        test ecx,1
        jnz public_move_bad
        test ecx,ecx
        jz public_move_good
        mov dx,es:[bp+4]
        mov eax,es:[bp+6]
        mov bl,ERR_BAD_SOURCE
        call public_move_endpoint
        jc public_move_bad
        mov [move_source],eax
        push edx                ; source address class, not an owner copy
        mov dx,es:[bp+10]
        mov eax,es:[bp+12]
        mov bl,ERR_BAD_DEST
        call public_move_endpoint
        pop ecx
        jc public_move_bad
        mov [move_dest],eax
        shl edx,1
        or edx,ecx
        mov eax,edx
        mov esi,[move_source]
        mov edi,[move_dest]
        mov ecx,[move_length]
        call XmsCopyClient
        mov bl,ERR_GENERAL
        jc public_move_bad
public_move_good:
        mov ax,1
        jmp short public_move_return
public_move_bad:
        xor ax,ax
public_move_return:
        pop dword ptr [move_dest]
        pop dword ptr [move_source]
        pop dword ptr [move_length]
        pop bp
        clc                     ; XMS outcome is AX/BL, not transport CF
        ret
XmsPublicMove endp

; DX handle, EAX public offset; return EAX address and EDX class (1 client,
; 0 physical). Invalid handle retains caller's source/destination error.
; Extent/overflow errors match the existing front's A7h contract.
public_move_endpoint proc near
        test dx,dx
        jnz public_move_handle
        movzx edx,ax
        shr eax,16
        shl eax,4
        add eax,edx
        mov edx,1
        clc
        ret
public_move_handle:
        call validate_handle
        jc public_move_endpoint_bad
        mov ecx,eax
        add ecx,[move_length]
        jc public_move_extent_bad
        movzx edi,word ptr [si+HANDLE_LENGTH]
        shl edi,10
        cmp ecx,edi
        ja public_move_extent_bad
        movzx edx,word ptr [si+HANDLE_BASE]
        shl edx,10
        add eax,edx
        add eax,100000h
        xor edx,edx
        ret
public_move_extent_bad:
        mov bl,ERR_BAD_LENGTH
public_move_endpoint_bad:
        stc
        ret
public_move_endpoint endp
XmsPublicMoveEnd label near
