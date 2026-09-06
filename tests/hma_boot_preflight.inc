; Scan-build-only calls into the actual SYSINIT preflight. Results are captured
; in the existing raw SYSINIT region; no cursor or HMA bytes are changed.
        PUBLIC HmaServiceProbeResults,HmaServiceProbe
HmaServiceProbeResults DB 15 DUP (0)
HmaServiceProbe PROC NEAR
        pushf
        push ax
        push bx
        push cx
        push dx
        push di
        xor di,di
        mov bx,cs:[HmaBiosEnd]
        mov ax,1672
        mov cx,2447+2451
        call HmaServiceProbeOne
        xor ax,ax
        call HmaServiceProbeOne
        mov bx,0fff0h
        mov ax,20h
        xor cx,cx
        call HmaServiceProbeOne
        mov bx,10h
        mov ax,1
        mov cx,0ffdfh
        sub cx,cs:[HmaPlanCacheBytes]
        call HmaServiceProbeOne
        inc cx
        call HmaServiceProbeOne
        pop di
        pop dx
        pop cx
        pop bx
        pop ax
        popf
        ret
HmaServiceProbe ENDP
HmaServiceProbeOne PROC NEAR
        mov dx,0deadh
        call PreflightHmaService
        mov word ptr cs:[HmaServiceProbeResults+di+1],dx
        mov dl,0
        adc dl,0
        mov cs:[HmaServiceProbeResults+di],dl
        add di,3
        ret
HmaServiceProbeOne ENDP
