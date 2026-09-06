; Paired experimental handle-owner publication. First XAUT request imports a
; validated stable owner; later requests never import the client's low view.
; HMA/A20/UMB state is not transferred by this handle-only protocol.
public XmsAuthoritativeOwner, XmsOwnerActive
XmsAuthoritativeOwner proc near
        pushad
        push ds
        cmp si,65536-18-MAX_HANDLES*HANDLE_SIZE
        ja auth_owner_bad
        cmp word ptr es:[si+4],2
        jne auth_owner_bad
        mov bx,si
        mov ax,VDMCA_GSEL
        mov ds,ax
        mov ax,es:[bx+16]
        cmp ax,8
        jb auth_owner_bad
        cmp ax,15
        ja auth_owner_bad
IFDEF EMM_AUTHORITATIVE_REIMPORT
        mov [XmsOwnerActive],0
ENDIF
        cmp [XmsOwnerActive],0
        jne short auth_owner_existing
        mov cx,es:[bx+6]
        or cx,cx
        jz auth_owner_bad
        cmp cx,MAX_HANDLES
        ja auth_owner_bad
        mov [handle_limit],cx
        mov ax,es:[bx+8]
        mov [extended_kb],ax
        add si,18
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
        pop ds
        popad
        clc
        ret
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
