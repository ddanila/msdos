; Development-only low-DOS ownership move, on SYSINIT's stack with IF clear.
; The old arena/HIMEM allocation remains reserved: this proves pointer rebasing
; independently of the subsequent boot-arena coalescing transaction.
        INCLUDE BIOSREBASE_DEFS.INC
BiosRebase PROC NEAR
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push ds
        push es
        mov ax,0ffffh
        mov ds,ax
        mov bx,ds:[RB_LOW_OWNER]
        mov ax,70h
        mov es,ax
        mov bp,es:[RB_PERMANENT_END]
        add bp,70h
        ; First proof requires disjoint source/destination, no active DOS frame,
        ; and the original first-HIMEM-only boot allocation.
        mov ax,bp
        add ax,RB_LOW_PARAS
        cmp ax,bx
        ja BiosRebaseDone
        mov ax,ss
        mov dx,cs
        cmp ax,dx
        jne BiosRebaseDone
        push ds
        mov ds,bx
        cmp byte ptr ds:[RB_INDOS],0
        pop ds
        jne BiosRebaseDone
        cmp word ptr es:[RB_FROM],0
        jne BiosRebaseDone
        IFDEF BIOS_BOOT_COMPACT
        mov ax,bx
        add ax,RB_LOW_PARAS+1
        cmp ax,cs:[AREA]
        jne BiosRebaseDone
        ENDIF
        mov es,bp
        mov ds,bx
        xor si,si
        xor di,di
        mov cx,RB_LOW_PARAS*8
        rep movsw
        ; Patch only declared segment fields pointing inside the moved prefix.
        ; HMA and low state are separate owners and must be inspected separately.
        push cs
        pop ds
        call BiosRebaseFields
        mov ax,0ffffh
        mov es,ax
        call BiosRebaseFields
        mov es:[RB_LOW_OWNER],bp
        mov es:[RB_DRIVER_ENTRY+2],bp

        ; The two built-in DOS DPBs move; BIOS overflow records do not.
        mov es,bp
        mov di,RB_LOW_DPBS+DPB_NEXT_DPB+2
        call BiosRebasePointer
        add di,DPBSIZ
        call BiosRebasePointer

        ; CDS lives in separately allocated initialization storage.
        mov ax,0ffffh
        mov ds,ax
        xor cx,cx
        mov cl,ds:[RB_CDSCOUNT]
        les di,ds:[RB_CDSADDR]
        add di,curdir_devptr+2
BiosRebaseCds:
        jcxz BiosRebaseCdsDone
        call BiosRebasePointer
        add di,curdirLen
        loop BiosRebaseCds
BiosRebaseCdsDone:
        ; CONFIG's parser cached DOS table addresses before relocation. Force
        ; fresh public NLS queries; patching kernel pointers cannot update these
        ; independently cached far addresses (notably the legacy DBCS vector).
        mov word ptr cs:[$P_DBCSEV_SEG],0
        mov byte ptr cs:[$P_Char_CAP_Ptr],0ffh
        IF CAPSW
        mov byte ptr cs:[$P_File_CAP_Ptr],0ffh
        ENDIF
        ; No request is live here, but leave the cached BIOS packet owner valid.
        mov ax,70h
        mov es,ax
        mov di,RB_PTRSAV+2
        call BiosRebasePointer
        mov es:[RB_FROM],bx
        mov es:[RB_TO],bp
        ; An unchanged arena deliberately continues to account for this range.
        ; Poisoning proves no exercised path still depends on the old prefix.
        mov es,bx
        xor di,di
        mov ax,0a5a5h
        mov cx,RB_LOW_PARAS*8
        rep stosw
        IFDEF BIOS_BOOT_COMPACT
        call BiosCompactBoot
        ENDIF
BiosRebaseDone:
        pop es
        pop ds
        pop bp
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret
BiosRebase ENDP
        IFDEF BIOS_BOOT_COMPACT
        INCLUDE BOOTCOMPACT.INC
        ENDIF

BiosRebaseFields PROC NEAR
        mov si,OFFSET BiosRebaseFieldsList
        mov cx,RB_FIELD_COUNT
BiosRebaseFieldsLoop:
        lodsw
        mov di,ax
        call BiosRebasePointer
        loop BiosRebaseFieldsLoop
        ret
BiosRebaseFields ENDP

; ES:DI is a declared far-pointer segment, BX old owner, BP new owner.
BiosRebasePointer PROC NEAR
        cmp es:[di],bx
        jne BiosRebasePointerDone
        cmp word ptr es:[di-2],RB_LOW_END
        jae BiosRebasePointerDone
        mov es:[di],bp
BiosRebasePointerDone:
        ret
BiosRebasePointer ENDP
BiosRebaseFieldsList LABEL WORD
        INCLUDE BIOSREBASE_FIELDS.INC
