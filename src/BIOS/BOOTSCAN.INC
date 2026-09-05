; Development-only pointer census at the high-BIOS activation boundary.
; Emit raw regions on QEMU debug port E9h, never through DOS or the ROM BIOS.
; No pointer is inferred or rewritten here. The host maps candidate words to
; source symbols; equal numeric values alone are not relocation authority.
        INCLUDE BIOSSCAN_DEFS.INC
BiosScan PROC NEAR
        pushf
        push ax
        push bx
        push cx
        push dx
        push si
        push ds
        cld
        mov ax,0ffffh
        mov ds,ax
        mov bx,ds:[SCAN_LOW_SEGMENT]
        mov al,'H'
        mov si,10h
        mov cx,SCAN_HIGH_END-10h
        call BiosScanRegion
        mov ds,bx
        mov al,'L'
        xor si,si
        mov cx,SCAN_LOW_END
        call BiosScanRegion
        mov ax,70h
        mov ds,ax
        mov cx,ds:[SCAN_PERMANENT_END]
        shl cx,1
        shl cx,1
        shl cx,1
        shl cx,1
        mov al,'B'
        xor si,si
        call BiosScanRegion
        mov ax,cs:[AREA]
        mov ds,ax
        mov cx,word ptr cs:[BREAK_ADDR+2]
        sub cx,ax
        shl cx,1
        shl cx,1
        shl cx,1
        shl cx,1
        add cx,word ptr cs:[BREAK_ADDR]
        mov al,'D'
        xor si,si
        call BiosScanRegion
        push cs
        pop ds
        mov al,'I'
        xor si,si
        mov cx,OFFSET SYSSIZE
        call BiosScanRegion
        mov ax,0ffffh
        mov ds,ax
        xor ax,ax
        mov al,ds:[SCAN_CDSCOUNT]
        mov cx,curdirLen
        mul cx
        mov cx,ax
        lds si,dword ptr ds:[SCAN_CDSADDR]
        mov al,'C'
        call BiosScanRegion
        pop ds
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        popf
        ret
BiosScan ENDP

; Record: tag byte, segment/offset/length little-endian words, then raw bytes.
; BX (old low DOS owner) survives each record; SI advances by CX bytes.
BiosScanRegion PROC NEAR
        out 0e9h,al
        mov ax,ds
        call BiosScanWord
        mov ax,si
        call BiosScanWord
        mov ax,cx
        call BiosScanWord
BiosScanBytes:
        jcxz BiosScanEnd
        lodsb
        out 0e9h,al
        loop BiosScanBytes
BiosScanEnd:
        ret
BiosScanRegion ENDP
BiosScanWord PROC NEAR
        out 0e9h,al
        mov al,ah
        out 0e9h,al
        ret
BiosScanWord ENDP
