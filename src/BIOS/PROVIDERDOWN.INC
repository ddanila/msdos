; Pinned paired-provider experiment. The only accepted hole is the adjacent
; HIMEM bootstrap tail; all planning checks precede freeze/copy/mark changes.
        .286
ProviderReclaimParas dw 0
ProviderOldBase dw 0
ProviderHimemMark dw 0
ProviderHimemSize dw 0
ProviderDownMoved db 0
ProviderSavedPrefix db 34 dup (0) ; EMM mark plus its 18-byte device header

ProviderPlanDown proc near
        mov cs:[ProviderDownMoved],0
        mov cs:[ProviderOldBase],bp
        cmp bp,cs:[MEMHI]
        jne ProviderPlanBad
        cmp bp,cs:[LDOFF]
        jne ProviderPlanBad
        mov ax,cs:[DevMark_Addr]
        inc ax
        cmp ax,bp
        jne ProviderPlanBad
        mov ax,XCP_LAYOUT_QUERY
        mov cx,XCP_LAYOUT_SIGNATURE
        mov si,XCP_LAYOUT_VERSION
        xor di,di
        int 2fh
        cmp ax,XCP_LAYOUT_REPLY
        jne ProviderPlanBad
        test bx,15
        jnz ProviderPlanBad
        or bx,bx
        jz ProviderPlanBad
        cmp bx,si
        jae ProviderPlanBad
        cmp di,1
        jb ProviderPlanBad
        cmp di,128
        ja ProviderPlanBad
        mov ax,di
        imul ax,5
        add ax,si
        jc ProviderPlanBad
        add ax,15
        jc ProviderPlanBad
        and ax,0fff0h
        cmp ax,cx
        jne ProviderPlanBad
        cmp dx,cs:[AREA]
        jb ProviderPlanBad
        shr ax,4
        mov cs:[ProviderHimemSize],ax
        add ax,dx
        jc ProviderPlanBad
        inc ax
        cmp ax,bp              ; exactly one mark between the two drivers
        jne ProviderPlanBad
        sub cx,bx
        shr cx,4
        jz ProviderPlanBad
        cmp cx,PROVIDER_IMAGE_PARAS
        jae ProviderPlanBad
        mov cs:[ProviderReclaimParas],cx
        dec dx
        mov cs:[ProviderHimemMark],dx
        mov es,dx
        cmp byte ptr es:[DEVMARK_ID],'D'
        jne ProviderPlanBad
        inc dx
        cmp es:[DEVMARK_SEG],dx
        jne ProviderPlanBad
        mov ax,cs:[ProviderHimemSize]
        cmp es:[DEVMARK_SIZE],ax
        jne ProviderPlanBad
        mov ax,bp
        dec ax
        mov ds,ax
        cmp byte ptr ds:[DEVMARK_ID],'D'
        jne ProviderPlanBad
        cmp ds:[DEVMARK_SEG],bp
        jne ProviderPlanBad
        push cs
        pop es
        xor si,si
        mov di,offset ProviderSavedPrefix
        mov cx,17
        cld
        rep movsw
        clc
        ret
ProviderPlanBad:
        stc
        ret
ProviderPlanDown endp

; Publish the smaller mark chain only after successful activation. SET_BREAK
; will size the moved EMM mark and advance later allocations from its new end.
ProviderCommitDown proc near
        pusha
        push ds
        push es
        cmp cs:[ProviderDownMoved],1
        jne ProviderCommitDone
        mov bx,word ptr cs:[ENTRY_POINT+2]
        mov ax,word ptr cs:[BREAK_ADDR]
        add ax,15
        jc ProviderDownFatal
        shr ax,4
        add ax,word ptr cs:[BREAK_ADDR+2]
        jc ProviderDownFatal
        cmp ax,bx
        jbe ProviderDownFatal
        cmp ax,cs:[ALLOCLIM]
        jae ProviderDownFatal
        mov ax,cs:[ProviderHimemMark]
        mov es,ax
        mov ax,cs:[ProviderHimemSize]
        sub ax,cs:[ProviderReclaimParas]
        mov es:[DEVMARK_SIZE],ax
        mov cs:[MEMHI],bx
        mov cs:[LDOFF],bx
        dec bx
        mov cs:[DevMark_Addr],bx
        mov es,bx
        push cs
        pop ds
        mov si,offset ProviderSavedPrefix
        xor di,di
        mov cx,8
        cld
        rep movsw
        inc bx
        mov es:[DEVMARK_SEG],bx
ProviderCommitDone:
        pop es
        pop ds
        popa
        ret
ProviderCommitDown endp

ProviderAbortDown proc near
        cmp cs:[ProviderDownMoved],0
        je ProviderAbortDone
IFNDEF BIOS_PROVIDER_CANCEL
        ; Partial activation/retarget failures are not a qualified rollback.
        ; Do not free storage or resume boot through uncertain owners.
        jmp ProviderDownFatal
ELSE
        pusha
        push ds
        push es
        ; The paired cancellation witness restored and checked HIMEM's live
        ; tail before returning from LAST. Restore the unlinked EMM header so
        ; ordinary SET_BREAK recognizes the zero-length aborted installation.
        mov ax,cs:[ProviderOldBase]
        mov word ptr cs:[ENTRY_POINT+2],ax
        mov cs:[MEMHI],ax
        mov cs:[LDOFF],ax
        dec ax
        mov cs:[DevMark_Addr],ax
        mov es,ax
        push cs
        pop ds
        mov si,offset ProviderSavedPrefix
        xor di,di
        mov cx,17
        cld
        rep movsw
        pop es
        pop ds
        popa
ENDIF
ProviderAbortDone:
        ret
ProviderAbortDown endp

ProviderDownFatal:
        mov al,'D'
        out 0e9h,al
        mov al,'F'
        out 0e9h,al
        mov dx,0f4h
        mov ax,11h
        out dx,ax
        cli
ProviderDownHalt:
        hlt
        jmp ProviderDownHalt
        .8086
