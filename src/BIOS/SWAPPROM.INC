; Complete disk-swap prompt owner, shared by the cold and high BIOS bodies.
PUBLIC SWPDSK,WRMSG
SWPDSK PROC NEAR
        mov al,byte ptr ds:[di].DRIVELET
        add al,'A'
        mov cs:DRVLET,al
        push ds
        push cs
        pop ds
        mov si,offset SNGMSG
        push bx
        call WRMSG
IFDEF BIOS_SWAP_HIGH
        ; FLUSH owns low ALTAH even though the prompt text belongs to high CS.
        push word ptr cs:[BIOS_SERVICE_LOW_SEGMENT]
        pop ds
ENDIF
        call FLUSH
        xor ah,ah
IFDEF BIOS_SWAP_HIGH
        call dword ptr cs:[BIOS_CHAR_INT16]
ELSE
        int 16h
ENDIF
        pop bx
        pop ds
WRMRET:
        ret
SWPDSK ENDP
WRMSG PROC NEAR
        lodsb
        or al,al
        jz WRMRET
IFDEF BIOS_SWAP_HIGH
        ; Preserve the original direct OUTCHR contract, not a hooked INT 29h.
        ; The conventional vector gate restores A20 after OUTCHR's IRET.
        push word ptr cs:[BIOS_SERVICE_LOW_SEGMENT]
        push word ptr cs:[BIOS_SWAP_OUTCHR_OFFSET]
        call dword ptr cs:[BIOS_SERVICE_VECTOR_GATE]
ELSE
        pushf
        push cs
        call OUTCHR
ENDIF
        jmp short WRMSG
WRMSG ENDP
        INCLUDE MSBIO.CL2
