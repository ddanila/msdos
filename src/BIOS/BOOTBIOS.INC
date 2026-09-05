; Development-only early BIOS activation, called after CompactFirstHimem has
; moved DOS high and refreshed HIMEM's entry. Generated operands must match
; this image. SYSINIT owns the reservation until it publishes the buffer tail.
        INCLUDE BIOSBOOT_DEFS.INC
        PUBLIC HmaBiosEnd
HmaBiosEnd DW 0
BiosBootActivate PROC NEAR
        pushf
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push ds
        push es
        push cs
        pop ds
        cld
        cmp cs:[HmaBiosEnd],0
        jne BiosBootDone
        cmp word ptr cs:[DEVICE_LIST+2],70h
        jne BiosBootDone
        mov ax,0e700h
        int 2fh
        cmp ax,0e7ffh
        jne BiosBootDone
        cmp bx,4d55h
        jne BiosBootDone
        xor ax,ax
        mov es,ax
        cmp word ptr es:[13h*4],ORIGINAL_BLOCK13
        jne BiosBootDone
        cmp word ptr es:[13h*4+2],70h
        jne BiosBootDone
        mov ax,70h
        mov es,ax
        cmp byte ptr es:[ACTIVE_OFFSET],0
        jne BiosBootDone
        INCLUDE BIOSBOOT_PREFLIGHT.INC
        ; DOS already owns and occupies HMA below SYSBUF. Nothing has yet
        ; constructed buffers there or published a tail allocator.
        mov ax,1232h
        int 2fh
        or ax,ax
        jz BiosBootDone
        mov ax,bx
        add ax,BOOT_PAYLOAD_BYTES
        jc BiosBootDone
        cmp ax,BOOT_RESERVATION_LIMIT
        ja BiosBootDone
        mov bp,ax
        mov ax,0ffffh
        mov es,ax
        mov di,bx
        mov si,OFFSET BiosBootPayload
        mov cx,BOOT_PAYLOAD_BYTES
        rep movsb
        mov si,OFFSET activation_fixups
        mov cx,ACTIVATION_FIXUP_COUNT
BiosBootFixup:
        lodsw
        mov di,ax
        add di,bx
        add es:[di],bx
        loop BiosBootFixup
        INCLUDE BIOSBOOT_BIND_HIGH.INC
        cli
        mov ax,70h
        mov es,ax
        INCLUDE BIOSBOOT_BIND_LOW.INC
        push ds
        xor ax,ax
        mov ds,ax
        mov word ptr ds:[13h*4],NEW_BLOCK13
        mov word ptr ds:[13h*4+2],70h
        pop ds
        mov byte ptr es:[ACTIVE_OFFSET],1
        mov cs:[HmaBiosEnd],bp
        IFDEF BIOS_BOOT_POISON
        mov di,OLD_SERVICE_START
        mov cx,OLD_SERVICE_SIZE/2
        mov ax,0f4fah
        rep stosw
        ENDIF
BiosBootFail:
BiosBootDone:
        pop es
        pop ds
        pop bp
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        popf
        ret
BiosBootActivate ENDP
        INCLUDE BIOSBOOT_DATA.INC
BiosBootPayload LABEL BYTE
        INCLUDE BIOSBOOT_PAYLOAD.INC
