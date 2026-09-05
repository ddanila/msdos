; After the low-owner move: BX old DOS segment, BP new DOS segment, IF clear.
; This is the same first-HIMEM-only allocation contract as CompactFirstHimem.
BiosCompactBoot PROC NEAR
        mov dx,bx
        sub dx,bp
        mov ax,cs:[AREA]
        dec ax
        mov ds,ax
        sub ax,dx
        mov es,ax
        xor si,si
        xor di,di
        mov cx,8
        rep movsw
        add es:[3],dx
        mov ax,cs:[AREA]
        mov ds,ax
        sub ax,dx
        mov es,ax
        mov ax,word ptr cs:[BREAK_ADDR]
        add ax,15
        mov cl,4
        shr ax,cl
        mov cx,word ptr cs:[BREAK_ADDR+2]
        sub cx,cs:[AREA]
        add cx,ax
        shl cx,1
        shl cx,1
        shl cx,1
        xor si,si
        xor di,di
        rep movsw
        sub word ptr es:[DEVMARK_SEG],dx
        sub cs:[AREA],dx
        sub cs:[MEMHI],dx
        sub word ptr cs:[ENTRY_POINT+2],dx
        sub word ptr cs:[BREAK_ADDR+2],dx
        sub cs:[DevMark_Addr],dx
        sub cs:[LDOFF],dx
        ; Publish the coalesced arena in both kernel data owners.
        mov ax,cs:[AREA]
        dec ax
        mov es,bp
        mov es:[RB_ARENA_HEAD],ax
        mov cx,0ffffh
        mov es,cx
        mov es:[RB_ARENA_HEAD],ax
        ; No interrupt may traverse the old HIMEM entry after this publication.
        xor ax,ax
        mov ds,ax
        mov dx,word ptr cs:[ENTRY_POINT+2]
        mov word ptr ds:[2fh*4+2],dx
        mov word ptr ds:[15h*4+2],dx
        mov ax,1234h
        int 2fh
        ret
BiosCompactBoot ENDP
