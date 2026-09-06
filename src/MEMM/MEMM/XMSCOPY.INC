; Development-only physical-copy backend for the coordinated XMS provider.
; Caller validates ownership, ranges and permissions before entry. No public
; XMS dispatch, handle-zero translation or mode transition is supplied here.
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
