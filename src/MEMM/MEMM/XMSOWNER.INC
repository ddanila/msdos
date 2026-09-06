; Installed development read-only allocator service. A caller supplies XOWN,
; version/count/pool words, two result words and count five-byte records.
; Copy only to private high snapshot storage; never allocate from this copy.
; DS uses the installed writable _TEXT alias. No new GDT slot is required.
; Complete allocation services are linked but MUST NOT be dispatched against
; this snapshot. Only a future authoritative ownership commit may enable them.
        include XMSRECORD.INC
        include XMSERROR.INC
        assume ds:_TEXT
public XmsQueryOwner, XmsQueryOwnerEnd, XmsOwnerSnapshot, XmsOwnerResults, XmsOwnerSnapshotEnd
public XmsOwnerStorageEnd, XmsOwnerCopyCalls, XmsOwnerCopyPacket
XmsQueryOwner proc near
        pushad
        push    ds
IFDEF EMM_AUTHORITATIVE_OWNER_TEST
        cmp cs:[XmsOwnerActive],0
        jne owner_service_bad
ENDIF
        cmp     si, 65536-14-MAX_HANDLES*HANDLE_SIZE
        ja      owner_service_bad
        cmp     word ptr es:[si+4],1
        jne     owner_service_bad
        mov     cx,es:[si+6]
        jcxz    owner_service_bad
        cmp     cx,MAX_HANDLES
        ja      owner_service_bad
        mov     ax,VDMCA_GSEL
        mov     ds,ax
        mov     [handle_limit],cx
        mov     ax,es:[si+8]
        mov     [extended_kb],ax
        mov     bx,si
        add     si,14
        mov     di,offset handles
        imul    cx,HANDLE_SIZE
owner_service_copy:
        mov     al,es:[si]
        mov     [di],al
        inc     si
        inc     di
        loop    owner_service_copy
        mov     cx,MAX_HANDLES
        call    xms_validate_owner
        jc      short owner_service_bad
        push    bx
        call    largest_gap
        call    total_free
        pop     bx
IFDEF EMM_XMS_OWNER_BAD_RESULT
        inc     ax
ENDIF
        mov     es:[bx+10],ax
        mov     es:[bx+12],dx
        mov     [XmsOwnerResults],ax
        mov     [XmsOwnerResults+2],dx
        inc     dword ptr [XmsOwnerSnapshot]
        pop     ds
        popad
        clc
        ret
owner_service_bad:
        pop     ds
        popad
        stc
        ret
XmsQueryOwner endp
IFDEF EMM_AUTHORITATIVE_OWNER_TEST
        include XMSAUTH.INC
ENDIF
        include XMSALLOC.INC
        include XMSHANDLE.INC
        include XMSSTATE.INC
xms_success:
        mov ax,1
        clc
        ret
xms_failure:
        xor ax,ax
        clc
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

; Shared allocator backend: DS owns all scratch, not SS or implicit CS.
; Preserve SI (live handle record), other registers and DS; return backend CF.
copy_move_blocks proc near
        pushad
        inc dword ptr [XmsOwnerCopyCalls]
        mov esi,dword ptr [move_source]
        mov edi,dword ptr [move_dest]
        mov ecx,dword ptr [move_length]
        call XmsCopyPhysical
        popad
        ret
copy_move_blocks endp

; Development physical-only packet adapter exercises the same high backend
; without mutating snapshot handles. Caller already decoded/validated classes
; and owns both physical ranges. Entry: ESI/EDI addresses, ECX length.
; Save/restore scratch so this bridge does not publish allocator state. Like
; the existing shared workspace, it requires serialized, non-reentrant entry.
XmsOwnerCopyPacket proc near
        pushad
        push ds
        mov ax,VDMCA_GSEL
        mov ds,ax
        push dword ptr [move_length]
        push dword ptr [move_source]
        push dword ptr [move_dest]
        mov dword ptr [move_length],ecx
        mov dword ptr [move_source],esi
        mov dword ptr [move_dest],edi
        call copy_move_blocks
        pop dword ptr [move_dest]
        pop dword ptr [move_source]
        pop dword ptr [move_length]
        pop ds
        popad
        ret
XmsOwnerCopyPacket endp
XmsQueryOwnerEnd label near
XmsOwnerSnapshot dd 0
handle_limit dw 0
extended_kb dw 0
handles db MAX_HANDLES*HANDLE_SIZE dup (0)
XmsOwnerResults dw 0,0
XmsOwnerSnapshotEnd label near
; Keep the existing 652-byte snapshot layout stable. Complete service scratch
; and the execution witness follow it and are charged separately in the map.
move_length dd 0
move_source dd 0
move_dest dd 0
XmsOwnerCopyCalls dd 0
IFDEF EMM_AUTHORITATIVE_OWNER_TEST
XmsOwnerActive db 0
XmsOwnerImports dw 0
ENDIF
XmsOwnerStorageEnd label near
        assume ds:DGROUP
