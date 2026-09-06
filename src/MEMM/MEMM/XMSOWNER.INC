; Installed development read-only allocator service. A caller supplies XOWN,
; version/count/pool words, two result words and count five-byte records.
; Copy only to private high snapshot storage; never allocate from this copy.
; DS uses the installed writable _TEXT alias. No new GDT slot is required.
        include XMSRECORD.INC
        assume ds:_TEXT
public XmsQueryOwner, XmsQueryOwnerEnd, XmsOwnerSnapshot, XmsOwnerResults, XmsOwnerSnapshotEnd
XmsQueryOwner proc near
        pushad
        push    ds
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
        include XMSHANDLE.INC
        include XMSSTATE.INC
XmsQueryOwnerEnd label near
XmsOwnerSnapshot dd 0
handle_limit dw 0
extended_kb dw 0
handles db MAX_HANDLES*HANDLE_SIZE dup (0)
XmsOwnerResults dw 0,0
XmsOwnerSnapshotEnd label near
        assume ds:DGROUP
