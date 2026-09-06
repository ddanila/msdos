; Paired experimental handle-owner publication. First XAUT request imports a
; validated stable owner; later requests never import the client's low view.
; HMA/A20/UMB state is not transferred by this handle-only protocol.
public XmsAuthoritativeOwner, XmsOwnerActive
XmsAuthoritativeOwner proc near
        pushad
        push ds
        cmp si,65536-20
        ja auth_owner_bad
        cmp word ptr es:[si+4],3
        jne auth_owner_bad
        mov bx,si
        mov ax,VDMCA_GSEL
        mov ds,ax
        mov ax,es:[bx+16]
        ; Read-only receipt: never import, execute an operation, or dereference
        ; bootstrap storage. Capability discovery alone cannot prove commit.
        or ax,ax
        jz auth_owner_receipt
        cmp ax,8
        jb auth_owner_bad
        cmp ax,15
        ja auth_owner_bad
IFDEF EMM_AUTHORITATIVE_REIMPORT
        mov [XmsOwnerActive],0
ENDIF
        cmp [XmsOwnerActive],0
        jne auth_owner_existing
        mov cx,es:[bx+6]
        or cx,cx
        jz auth_owner_bad
        cmp cx,MAX_HANDLES
        ja auth_owner_bad
        mov [handle_limit],cx
        mov ax,es:[bx+8]
        mov [extended_kb],ax
        ; Import directly from a checked offset in the same client segment.
        ; Later requests neither read nor require this bootstrap storage.
        movzx esi,word ptr es:[bx+18]
        movzx ecx,cx
        imul ecx,HANDLE_SIZE
        add ecx,esi
        cmp ecx,10000h
        ja auth_owner_bad
        mov cx,[handle_limit]
        mov di,offset handles
        imul cx,HANDLE_SIZE
auth_owner_import:
        mov al,es:[si]
        mov [di],al
        inc si
        inc di
        loop auth_owner_import
        mov cx,MAX_HANDLES
        call xms_validate_owner
        jc auth_owner_bad
        mov [XmsOwnerActive],1
        inc [XmsOwnerImports]
IFDEF EMM_XMS_OWNER_TRACE
        ; Loader integration witness: emitted only at the actual high commit,
        ; never by capability discovery or the low front-end's attempted call.
        mov al,'X'
        out 0e9h,al
        mov al,'A'
        out 0e9h,al
        push ds
        mov ax,GDTD_GSEL
        mov ds,ax
        mov ax,word ptr ds:[VDMC_GSEL+2]
        out 0e9h,al
        mov al,ah
        out 0e9h,al
        mov al,byte ptr ds:[VDMC_GSEL+4]
        out 0e9h,al
        mov al,byte ptr ds:[VDMC_GSEL+7]
        out 0e9h,al
        pop ds
ENDIF
auth_owner_existing:
        mov ax,es:[bx+6]
        cmp ax,[handle_limit]
        jne auth_owner_bad
        mov ax,es:[bx+8]
        cmp ax,[extended_kb]
        jne auth_owner_bad
        push bx
        mov si,es:[bx+16]
        sub si,8
        shl si,1
        mov dx,es:[bx+12]
        mov bx,es:[bx+14]
        push dword ptr [move_length]
        push dword ptr [move_source]
        push dword ptr [move_dest]
        call word ptr cs:[auth_owner_dispatch+si]
        pop dword ptr [move_dest]
        pop dword ptr [move_source]
        pop dword ptr [move_length]
        pop di
        mov es:[di+10],ax
        mov es:[di+12],dx
        mov es:[di+14],bx
        push di
        call largest_gap
        call total_free
        pop di
        mov [XmsOwnerResults],ax
        mov [XmsOwnerResults+2],dx
        inc dword ptr [XmsOwnerSnapshot]
auth_owner_done:
        pop ds
        popad
        clc
        ret
auth_owner_receipt:
        xor ax,ax
        mov al,[XmsOwnerActive]
IFDEF EMM_XMS_OWNER_BAD_RECEIPT
        xor ax,1
ENDIF
IFDEF EMM_XMS_OWNER_BAD_RECEIPT_ACTIVE
        xor ax,ax
ENDIF
        mov es:[bx+10],ax
        mov ax,[XmsOwnerImports]
        mov es:[bx+14],ax
        xor ax,ax
        cmp [XmsOwnerActive],0
        je short auth_receipt_limit
        mov ax,[handle_limit]
auth_receipt_limit:
        mov es:[bx+12],ax
        jmp short auth_owner_done
auth_owner_bad:
        pop ds
        popad
        stc
        ret
XmsAuthoritativeOwner endp
; Private operation 0Bh is record lookup, not public XMS Move. It neither
; locks nor mutates the handle and returns AX=status, BX=base KiB, DX=size KiB.
auth_owner_record proc near
        call validate_handle
        jc xms_bad_handle
        mov bx,word ptr [si+HANDLE_BASE]
        mov dx,word ptr [si+HANDLE_LENGTH]
        jmp xms_success
auth_owner_record endp
auth_owner_dispatch dw xms_query_free,xms_allocate,xms_free,auth_owner_record
        dw xms_lock,xms_unlock,xms_handle_info,xms_reallocate
