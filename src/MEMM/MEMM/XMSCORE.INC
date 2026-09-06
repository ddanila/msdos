; Common protected service entry for the paired provider candidate.
; This is NOT a public entry or an import protocol. The adapter establishes
; installed mappings, serialized execution, writable DS=VDMCA_GSEL and a safe
; stack. BP selects the service; service-specific registers are unchanged.
; 08..0A,0C..11 are XMS service numbers; 12/13 are UMB register/unregister;
; 14 is private handle lookup. 0B consumes ALREADY RESOLVED Move endpoints:
; ESI/EDI addresses, ECX length, EAX client-linear class flags. 15 validates a
; public 16-byte Move descriptor snapshot at ES:SI against the high owner.
; UMB registration additionally consumes validated ES:SI input. Never import
; or fall back here. Return AX/BX/DX service status; copy also retains CF.
public XmsServiceCore, XmsServiceCoreEnd
XmsServiceCore proc near
        cmp bp,0bh
        je core_copy
        cmp bp,10h
        jae core_umb_or_lookup
        cmp [XmsOwnerActive],1
        jne core_unavailable
IFDEF EMM_COMMON_XMS_REJECT_HANDLE
        jmp core_unavailable
ENDIF
        cmp bp,8
        je xms_query_free
        cmp bp,9
        je xms_allocate
        cmp bp,0ah
        je xms_free
        cmp bp,0ch
        je xms_lock
        cmp bp,0dh
        je xms_unlock
        cmp bp,0eh
        je xms_handle_info
        cmp bp,0fh
        je xms_reallocate
        jmp short core_unavailable
core_umb_or_lookup:
        cmp bp,15h
        jne core_lookup
IFDEF EMM_COMMON_XMS_REJECT_COPY
        jmp core_unavailable
ENDIF
        cmp [XmsOwnerActive],1
        jne core_unavailable
        jmp XmsPublicMove
core_lookup:
        cmp bp,14h
        jne core_umb
        cmp [XmsOwnerActive],1
        jne core_unavailable
        jmp auth_owner_record
core_umb:
IFDEF EMM_COMMON_XMS_REJECT_UMB
        jmp core_unavailable
ENDIF
        cmp [XmsUmbActive],1
        jne core_unavailable
        cmp bp,10h
        je xms_umb_request
        cmp bp,11h
        je xms_umb_release
        cmp bp,12h
        je umb_high_register
        cmp bp,13h
        je umb_high_unregister
core_unavailable:
        xor ax,ax
        mov bl,ERR_GENERAL
        stc
        ret
core_copy:
IFDEF EMM_COMMON_XMS_REJECT_COPY
        jmp core_unavailable
ENDIF
        ; Physical copy may be needed before handle publication. It does not
        ; gain authority to allocate from an uncommitted snapshot.
        test eax,eax
        jnz core_client_copy
        call XmsOwnerCopyPacket
        jmp short core_copy_result
core_client_copy:
        call XmsCopyClient
core_copy_result:
        jc core_unavailable
        mov ax,1
        ret
XmsServiceCore endp
XmsServiceCoreEnd label near
        include XMSMOVE.INC
        include XMSFRAME.INC
