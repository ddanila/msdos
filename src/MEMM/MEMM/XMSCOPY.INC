; Development-only physical-copy backend for the coordinated XMS provider.
; Caller validates ownership, ranges and permissions before entry. No public
; XMS dispatch, far-pointer validation or mode transition is supplied here.
; The typed layer below accepts already-decoded client-linear addresses.
;
; Ring 0, installed provider CR3/GDT. ESI/EDI physical source/destination,
; ECX byte count. Preserve all registers; CF=0 success, CF=1 rejected.
; Reject overlapping non-identical ranges and any occupied scratch PTE.
; Ordinary interrupts are excluded; real fault/NMI unwinding remains a gate.
; Both scratch PTEs must start at zero; temporary mappings are supervisor-only.
XW_SOURCE_PTE equ 4040h
XW_DEST_PTE   equ 4044h
public XmsCopyPhysical

XmsCopyPhysical proc near
    pushf
    cli
    pushad
    push ds
    push es
    push fs
    push gs
    test ecx,ecx
    jz XW_Success
    cmp esi,edi
    je XW_Success
    mov eax,esi
    add eax,ecx
    jc XW_Reject
    mov ebx,edi
    add ebx,ecx
    jc XW_Reject
    cmp esi,ebx
    jae short XW_Ranges_OK
    cmp edi,eax
    jb XW_Reject
XW_Ranges_OK:
    mov ax,PAGET_GSEL
    mov fs,ax
    cmp dword ptr fs:[XW_SOURCE_PTE],0
    jne XW_Reject
    cmp dword ptr fs:[XW_DEST_PTE],0
    jne XW_Reject
    mov ax,GDTD_GSEL
    mov gs,ax
    push dword ptr gs:[MBSRC_GSEL]
    push dword ptr gs:[MBSRC_GSEL+4]
    push dword ptr gs:[MBTAR_GSEL]
    push dword ptr gs:[MBTAR_GSEL+4]
    ; 4-KiB DPL0 data segments at 01010000h and 01011000h.
    mov dword ptr gs:[MBSRC_GSEL],00000fffh
    mov dword ptr gs:[MBSRC_GSEL+4],01009201h
    mov dword ptr gs:[MBTAR_GSEL],10000fffh
    mov dword ptr gs:[MBTAR_GSEL+4],01009201h
    mov ebp,ecx
XW_Next:
    mov eax,esi
    and eax,0fffff000h
    or eax,3
    mov fs:[XW_SOURCE_PTE],eax
    mov eax,edi
    and eax,0fffff000h
    or eax,3
    mov fs:[XW_DEST_PTE],eax
    mov eax,cr3
    mov cr3,eax
IFDEF EMM_XMS_COPY_FAIL_AFTER_MAP
    jmp XW_Failed_Map
ENDIF
    mov ebx,esi
    and ebx,4095
    neg ebx
    add ebx,4096
    mov edx,edi
    and edx,4095
    neg edx
    add edx,4096
    cmp ebx,edx
    jbe short XW_Source_Limit
    mov ebx,edx
XW_Source_Limit:
    cmp ebx,ebp
    jbe short XW_Count_Ready
    mov ebx,ebp
XW_Count_Ready:
    push esi
    push edi
    and esi,4095
    and edi,4095
    mov ax,MBSRC_GSEL
    mov ds,ax
    mov ax,MBTAR_GSEL
    mov es,ax
    mov ecx,ebx
    cld
    rep movsb
    pop edi
    pop esi
    add esi,ebx
    add edi,ebx
    sub ebp,ebx
    jnz XW_Next
    xor edx,edx
    jmp short XW_Restore
XW_Failed_Map:
    mov edx,1
XW_Restore:
    mov dword ptr fs:[XW_SOURCE_PTE],0
    mov dword ptr fs:[XW_DEST_PTE],0
    mov eax,cr3
    mov cr3,eax
    pop dword ptr gs:[MBTAR_GSEL+4]
    pop dword ptr gs:[MBTAR_GSEL]
    pop dword ptr gs:[MBSRC_GSEL+4]
    pop dword ptr gs:[MBSRC_GSEL]
    test edx,edx
    jnz short XW_Reject
XW_Success:
    pop gs
    pop fs
    pop es
    pop ds
    popad
    popf
    clc
    ret
XW_Reject:
    pop gs
    pop fs
    pop es
    pop ds
    popad
    popf
    stc
    ret
XmsCopyPhysical endp
public XmsCopyPhysicalEnd
XmsCopyPhysicalEnd label near

; Typed-address layer. EAX bits 0/1 mark ESI/EDI as client-linear addresses;
; other endpoints are physical. Caller establishes A20 policy and validates
; whole-range ownership/non-overlap, including aliases. Client addresses are
; limited to the conventional/HMA window; each page needs user read/write
; permission. A later rejected page can follow earlier completed chunks: this
; is not an atomic public XMS Move implementation or a full-range preflight.
public XmsCopyClient
XmsCopyClient proc near
    pushf
    cli
    pushad
    push fs
    test eax,0fffffffch
    jnz XM_Reject
    test eax,eax
    jnz short XM_Mapped
    call XmsCopyPhysical
    jc XM_Reject
    jmp XM_Success
XM_Mapped:
    mov ebp,eax
    test ecx,ecx
    jz XM_Success
    mov eax,esi
    add eax,ecx
    jc XM_Reject
    test ebp,1
    jz short XM_Source_Range
    cmp eax,110000h
    ja XM_Reject
XM_Source_Range:
    mov eax,edi
    add eax,ecx
    jc XM_Reject
    test ebp,2
    jz short XM_Dest_Range
    cmp eax,110000h
    ja XM_Reject
XM_Dest_Range:
    mov ax,PAGET_GSEL
    mov fs,ax
XM_Next:
    mov ebx,esi
    and ebx,4095
    neg ebx
    add ebx,4096
    mov edx,edi
    and edx,4095
    neg edx
    add edx,4096
    cmp ebx,edx
    jbe short XM_Source_Limit
    mov ebx,edx
XM_Source_Limit:
    cmp ebx,ecx
    jbe short XM_Chunk
    mov ebx,ecx
XM_Chunk:
    push esi
    push edi
    push ecx
    mov ecx,ebx
    test ebp,1
    jz short XM_Source_Ready
    mov eax,esi
    mov edx,5 ; present, user-readable
    call XmsResolveClientPage
    jc short XM_Chunk_Failed
    mov esi,eax
XM_Source_Ready:
    test ebp,2
    jz short XM_Dest_Ready
    mov eax,edi
    mov edx,7 ; present, user-writable
    call XmsResolveClientPage
    jc short XM_Chunk_Failed
    mov edi,eax
XM_Dest_Ready:
    call XmsCopyPhysical
    jc short XM_Chunk_Failed
    pop ecx
    pop edi
    pop esi
    add esi,ebx
    add edi,ebx
    sub ecx,ebx
    jnz XM_Next
XM_Success:
    pop fs
    popad
    popf
    clc
    ret
XM_Chunk_Failed:
    pop ecx
    pop edi
    pop esi
XM_Reject:
    pop fs
    popad
    popf
    stc
    ret
XmsCopyClient endp

; FS is the installed first-page-table alias. The caller has bounded EAX to
; 00000000h..0010ffffh and retains the provider's present/user PDE zero.
; EDX is required PTE permission bits; return EAX physical, or CF on rejection.
XmsResolveClientPage proc near
    push ebx
    push ecx
    mov ebx,eax
    shr ebx,12
    shl bx,2
    mov ebx,fs:[bx]
    mov ecx,ebx
    and ecx,edx
    cmp ecx,edx
    jne short XM_Page_Failed
    and ebx,0fffff000h
    and eax,4095
    or eax,ebx
    pop ecx
    pop ebx
    clc
    ret
XM_Page_Failed:
    pop ecx
    pop ebx
    stc
    ret
XmsResolveClientPage endp
public XmsCopyClientEnd
XmsCopyClientEnd label near
