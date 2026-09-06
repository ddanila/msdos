; Shared device-request decoder, after MSBIO1's nine saved register words.
; SI identifies a LOW command table; AL is the selected AUX/PRN index.
; The normal expansion retains the original instruction stream.
; BIOS_DISPATCH_SEPARATE binds a distinct code owner through the CS-relative
; BIOS_DISPATCH_LOW_SEGMENT word and BIOS_DISPATCH_ERROR_ENTRY far pointer.
; Tables, patches and completion entries stay
; low for this binding stage. Caller must establish A20 and a conventional
; stack before tail-entering; this include neither publishes nor activates it.
IFDEF BIOS_DISPATCH_SEPARATE
        push word ptr cs:[BIOS_DISPATCH_LOW_SEGMENT]
        pop es
        mov es:[AUXNUM],al
        lds bx,es:[PTRSAV]
ELSE
        mov cs:[AUXNUM],al
        lds bx,cs:[PTRSAV]
ENDIF
        assume ds:nothing
        mov al,byte ptr ds:[bx].UNIT
        mov ah,byte ptr ds:[bx].MEDIA
        mov cx,word ptr ds:[bx].COUNT
        mov dx,word ptr ds:[bx].START

        ; Only disk requests own START_SEC_H. FFFFh selects the packet's
        ; extended starting sector; ordinary requests clear its high word.
        cmp si,offset DSKTBL
        jnz DSK_REQ_CONT
        cmp dx,-1
        jnz DSK_REQ_16
        mov dx,ds:[bx].START_H
IFDEF BIOS_DISPATCH_SEPARATE
        mov es:START_SEC_H,dx
ELSE
        mov cs:START_SEC_H,dx
ENDIF
        mov dx,ds:[bx].START_L
        jmp short DSK_REQ_CONT
DSK_REQ_16:
IFDEF BIOS_DISPATCH_SEPARATE
        mov es:START_SEC_H,0
ELSE
        mov cs:START_SEC_H,0
ENDIF
DSK_REQ_CONT:
        xchg di,ax
        mov al,byte ptr ds:[bx].CMD
IFDEF BIOS_DISPATCH_SEPARATE
        cmp al,es:[si]
        jbe short DISPATCH_VALID_COMMAND
        ; No extra return address survives: CMDERR consumes the original
        ; device frame, including the caller's saved ES and DS.
        jmp dword ptr cs:[BIOS_DISPATCH_ERROR_ENTRY]
DISPATCH_VALID_COMMAND:
ELSE
        cmp al,cs:[si]
        ja CMDERR
ENDIF
        cbw
        shl ax,1
        add si,ax
        xchg ax,di
        les di,dword ptr ds:[bx].TRANS
IFDEF BIOS_DISPATCH_SEPARATE
        push word ptr cs:[BIOS_DISPATCH_LOW_SEGMENT]
ELSE
        push cs
ENDIF
        pop ds
        assume ds:CODE
        cld
IFDEF BIOS_DISPATCH_SEPARATE
        ; The table's current target may already be a low high-service gate.
        ; Read it at dispatch time so boot purge/publication policy is retained.
        push ds
        push word ptr [si+1]
        retf
ELSE
        jmp word ptr [si+1]
ENDIF
