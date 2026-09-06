; Development-only, discardable snapshot after CONFIG pass zero.
; No reservation or resident-size change is made here.
        PUBLIC HmaPlanBuffers,HmaPlanSlotSize,HmaPlanCacheBytes,HmaPlanValid
        PUBLIC HmaPlanParseError
HmaPlanBuffers DW 0
HmaPlanSlotSize DW 0
HmaPlanCacheBytes DW 0
HmaPlanValid DB 0
HmaPlanParseError DB 0
FreezeHmaCachePlan PROC NEAR
        pushf
        push ax
        push bx
        push cx
        push dx
        mov cs:[HmaPlanValid],0
        mov cs:[HmaPlanCacheBytes],0
        mov ax,cs:[Buffers]
        mov cs:[HmaPlanBuffers],ax
        mov ax,cs:[SingleBufferSize]
        mov cs:[HmaPlanSlotSize],ax
        cmp cs:[Multi_Pass_Id],0
        jne HmaPlanDone
        mov al,cs:[BootBypass]
        or al,cs:[BootStep]
        or al,cs:[HmaPlanParseError]
        or al,cs:[Buffer_Slash_X]
        jnz HmaPlanDone
        mov ax,cs:[HmaPlanBuffers]
        cmp ax,1
        jb HmaPlanDone
        cmp ax,99
        ja HmaPlanDone
        mov cx,ax
        mov bx,1
        cmp ax,30
        jb HmaPlanBucketsReady
        xor dx,dx
        mov bx,15
        div bx
        mov bx,ax
HmaPlanBucketsReady:
        mov ax,cx
        mul cs:[HmaPlanSlotSize]
        or dx,dx
        jnz HmaPlanDone
        or ax,ax
        jz HmaPlanDone
        shl bx,1
        shl bx,1
        shl bx,1
        add ax,bx
        jc HmaPlanDone
        mov cs:[HmaPlanCacheBytes],ax
        mov cs:[HmaPlanValid],1
HmaPlanDone:
        pop dx
        pop cx
        pop bx
        pop ax
        popf
        ret
FreezeHmaCachePlan ENDP
