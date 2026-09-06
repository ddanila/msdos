; One source for normal character services and the proposed complete high owner.
; High compilation supplies explicit low-state/firmware/completion bindings.
IFDEF BIOS_CHAR_HIGH
CODE TEXTEQU <BIOSHIGH>
BIOSHIGH SEGMENT BYTE PUBLIC 'BIOSHIGH'
ASSUME CS:BIOSHIGH
EXIT TEXTEQU <BIOS_CHAR_EXIT>
BUS$EXIT TEXTEQU <BIOS_CHAR_BUSY>
ERR$CNT TEXTEQU <BIOS_CHAR_ERRCNT>
ERR$EXIT TEXTEQU <BIOS_CHAR_ERREXIT>
CMDERR TEXTEQU <BIOS_CHAR_CMDERR>
GETDX TEXTEQU <BIOS_CHAR_GETDX>
EXTRN BIOS_CHAR_LOW_SEGMENT:WORD
EXTRN BIOS_CHAR_INT14:DWORD, BIOS_CHAR_INT15:DWORD, BIOS_CHAR_INT16:DWORD
EXTRN BIOS_CHAR_INT17:DWORD, BIOS_CHAR_INT1A:DWORD, BIOS_CHAR_INT29:DWORD
ELSE
INCLUDE MSGROUP.INC
ENDIF

CHAR_INTERRUPT MACRO number
IFDEF BIOS_CHAR_HIGH
IF number EQ 14h
        call dword ptr cs:[BIOS_CHAR_INT14]
ELSEIF number EQ 15h
        call dword ptr cs:[BIOS_CHAR_INT15]
ELSEIF number EQ 16h
        call dword ptr cs:[BIOS_CHAR_INT16]
ELSEIF number EQ 17h
        call dword ptr cs:[BIOS_CHAR_INT17]
ELSEIF number EQ 1ah
        call dword ptr cs:[BIOS_CHAR_INT1A]
ELSEIF number EQ 29h
        call dword ptr cs:[BIOS_CHAR_INT29]
ELSE
        .ERR <unbound character interrupt>
ENDIF
ELSE
        int number
ENDIF
ENDM

; Printer output temporarily uses DS for the caller's transfer buffer.
; Do not replace its explicit CS accesses with an assumed low DS.
CHAR_LOW_LOAD MACRO destination,source
IFDEF BIOS_CHAR_HIGH
        push ds
        push word ptr cs:[BIOS_CHAR_LOW_SEGMENT]
        pop ds
        mov destination,source
        pop ds
ELSE
        mov destination,cs:source
ENDIF
ENDM

CHAR_REQUEST MACRO
IFDEF BIOS_CHAR_HIGH
        push es
        push word ptr cs:[BIOS_CHAR_LOW_SEGMENT]
        pop es
        lds bx,es:[PTRSAV]
        pop es
ELSE
        lds bx,cs:[PTRSAV]
ENDIF
ENDM
