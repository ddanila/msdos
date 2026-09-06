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
IFDEF EMM_XMS_COPY_FAIL_REALLOC_ONCE
    ; The fixture's relocating copy is exactly 32 KiB. Fail it once after
    ; installing both windows, then allow retry through the identical backend.
    cmp ebp,32768
    jne short XW_ReallocFaultDone
    push ds
    mov ax,VDMD_GSEL
    mov ds,ax
    cmp byte ptr [XmsReallocFaultUsed],0
    jne short XW_ReallocFaultUsed
    inc byte ptr [XmsReallocFaultUsed]
    pop ds
    jmp XW_Failed_Map
XW_ReallocFaultUsed:
    pop ds
XW_ReallocFaultDone:
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
; whole-range ownership. Client addresses are
; limited to the conventional/HMA window; each page needs user read/write
; permission, checked across both complete ranges before any copy. This does
; also checks physical aliases, but does not establish ownership or make
; hardware faults atomic.
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
ifndef EMM_XMS_COPY_SKIP_PREFLIGHT
    test ebp,1
    jz short XM_Check_Dest
    mov eax,esi
    mov edx,5
    call XmsCheckClientRange
    jc XM_Reject
XM_Check_Dest:
    test ebp,2
    jz short XM_Check_Aliases
    mov eax,edi
    mov edx,7
    call XmsCheckClientRange
    jc XM_Reject
endif
XM_Check_Aliases:
ifndef EMM_XMS_COPY_SKIP_ALIASES
    call XmsCheckClientAliases
    jc XM_Reject
    test eax,eax
    jz XM_Success ; complete physical identity, including aliased windows
endif
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

; EAX client-linear start, ECX nonzero length, EDX required permissions.
; Caller checked the exclusive end and holds interrupts disabled. Preserve
; all inputs; walk each touched page using the same resolver as the copy.
XmsCheckClientRange proc near
    pushad
    mov esi,eax
    mov edi,eax
    add edi,ecx
XM_Check_Page:
    mov eax,esi
    call XmsResolveClientPage
    jc short XM_Check_Failed
    and esi,0fffff000h
    add esi,4096
    cmp esi,edi
    jb short XM_Check_Page
    popad
    clc
    ret
XM_Check_Failed:
    popad
    stc
    ret
XmsCheckClientRange endp

; Complete translated-range check. EBP address classes, ESI/EDI endpoints,
; ECX nonzero length, FS first-page-table alias; ranges/permissions validated.
; Return EAX=0 for complete physical identity, EAX=1 for disjoint ranges,
; or CF=1 for any other overlap. All other registers are preserved.
; Fixed 40-byte frame, no resident scratch owner. The nested disjointness
; walk is bounded by 272*272 page pairs; latency qualification remains open.
XA_FLAGS equ -4
XA_SOURCE equ -8
XA_DEST equ -12
XA_LENGTH equ -16
XA_SCURSOR equ -20
XA_SLEFT equ -24
XA_SPHYS equ -28
XA_SSIZE equ -32
XA_DCURSOR equ -36
XA_DLEFT equ -40
XmsCheckClientAliases proc near
    pushad
    mov eax,ebp
    mov bp,sp
    sub sp,40
    mov ss:[bp+XA_FLAGS],eax
    mov ss:[bp+XA_SOURCE],esi
    mov ss:[bp+XA_DEST],edi
    mov ss:[bp+XA_LENGTH],ecx
    mov ss:[bp+XA_SCURSOR],esi
    mov ss:[bp+XA_DCURSOR],edi
    mov ss:[bp+XA_SLEFT],ecx
    mov ss:[bp+XA_DLEFT],ecx
XA_Identity:
    call XA_SourceSpan
    jc XA_Failed
    mov ss:[bp+XA_SPHYS],eax
    mov ss:[bp+XA_SSIZE],ebx
    call XA_DestSpan
    jc XA_Failed
    cmp eax,ss:[bp+XA_SPHYS]
    jne short XA_Reset
    cmp ebx,ss:[bp+XA_SSIZE]
    jbe short XA_IdentityStep
    mov ebx,ss:[bp+XA_SSIZE]
XA_IdentityStep:
    add ss:[bp+XA_SCURSOR],ebx
    add ss:[bp+XA_DCURSOR],ebx
    sub ss:[bp+XA_DLEFT],ebx
    sub ss:[bp+XA_SLEFT],ebx
    jnz XA_Identity
    mov dword ptr ss:[bp+28],0 ; saved EAX in PUSHAD frame
    jmp XA_Passed
XA_Reset:
    mov eax,ss:[bp+XA_SOURCE]
    mov ss:[bp+XA_SCURSOR],eax
    mov eax,ss:[bp+XA_LENGTH]
    mov ss:[bp+XA_SLEFT],eax
XA_SourceNext:
    call XA_SourceSpan
    jc XA_Failed
    mov ss:[bp+XA_SPHYS],eax
    mov ss:[bp+XA_SSIZE],ebx
    mov eax,ss:[bp+XA_DEST]
    mov ss:[bp+XA_DCURSOR],eax
    mov eax,ss:[bp+XA_LENGTH]
    mov ss:[bp+XA_DLEFT],eax
XA_DestNext:
    call XA_DestSpan
    jc short XA_Failed
    mov edx,eax
    add edx,ebx
    jc short XA_Failed
    cmp ss:[bp+XA_SPHYS],edx
    jae short XA_Disjoint
    mov edx,ss:[bp+XA_SPHYS]
    add edx,ss:[bp+XA_SSIZE]
    jc short XA_Failed
    cmp eax,edx
    jb short XA_Failed
XA_Disjoint:
    add ss:[bp+XA_DCURSOR],ebx
    sub ss:[bp+XA_DLEFT],ebx
    jnz XA_DestNext
    mov ebx,ss:[bp+XA_SSIZE]
    add ss:[bp+XA_SCURSOR],ebx
    sub ss:[bp+XA_SLEFT],ebx
    jnz XA_SourceNext
    mov dword ptr ss:[bp+28],1
XA_Passed:
    mov sp,bp
    popad
    clc
    ret
XA_Failed:
    mov sp,bp
    popad
    stc
    ret
XA_SourceSpan:
    mov eax,ss:[bp+XA_SCURSOR]
    mov ecx,ss:[bp+XA_SLEFT]
    xor edx,edx
    test dword ptr ss:[bp+XA_FLAGS],1
    jz short XA_SourcePhysical
    mov edx,5
XA_SourcePhysical:
    jmp short XmsClientSpan
XA_DestSpan:
    mov eax,ss:[bp+XA_DCURSOR]
    mov ecx,ss:[bp+XA_DLEFT]
    xor edx,edx
    test dword ptr ss:[bp+XA_FLAGS],2
    jz short XA_DestPhysical
    mov edx,7
XA_DestPhysical:
    jmp short XmsClientSpan
XmsCheckClientAliases endp

; EAX start, ECX remaining, EDX=0 physical or required client permission.
; Return EAX physical start, EBX contiguous length, CF on invalid mapping.
XmsClientSpan proc near
    mov ebx,ecx
    test edx,edx
    jz short XA_SpanPhysical
    mov ebx,eax
    and ebx,4095
    neg ebx
    add ebx,4096
    cmp ebx,ecx
    jbe short XA_SpanMapped
    mov ebx,ecx
XA_SpanMapped:
    call XmsResolveClientPage
    jc short XA_SpanReturn
XA_SpanPhysical:
    mov edx,eax
    add edx,ebx ; also reject a translated exclusive end wrapping at 4 GiB
XA_SpanReturn:
    ret
XmsClientSpan endp

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
ifdef EMM_XMS_COPY_DENY_ALIGNED_PAGE
    ; Test-only: the mapped probe starts at offset 4093. Deny its next
    ; page through the ordinary permission check, without changing a PTE.
ifdef EMM_XMS_COPY_DENY_DESTINATION
    cmp edx,7
    jne short XM_Test_Page_Allowed
endif
    test eax,4095
    jnz short XM_Test_Page_Allowed
    and ebx,0fffffffbh
XM_Test_Page_Allowed:
endif
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
