; Relocation-safe media checks. Ordinary near RET only: CF=0 means continue,
; CF=1 means AL already contains the mapped DOS error. The caller owns unwind.
; Unlike CHECKIO/CHECKLATCHIO these entries never discard frames or branch to
; HARDERR. Include in the low helper segment; existing service calls must be
; bound to their low/high entry gates before activation.
BIOS_CHECKLATCH_RESULT:
        call CHKOPCNT
        jz BIOS_CHECK_NORMAL
        call CHECKROMCHANGE
        jz BIOS_CHECK_NORMAL
        call GETBP
        jc BIOS_CHECK_ERROR
        call CHECK_VID
        jc BIOS_CHECK_MAP
        or si,si
        jns BIOS_CHECK_NORMAL
        call RETURNVID
BIOS_CHECK_MAP:
        call MAPERROR
BIOS_CHECK_ERROR:
        stc
        ret
BIOS_CHECK_NORMAL:
        clc
        ret

BIOS_CHECKIO_RESULT:
        cmp ah,6
        jne BIOS_CHECK_NORMAL
        call CHKOPCNT
        jz BIOS_CHECK_NORMAL
        call GETBP
        jc BIOS_CHECK_ERROR
        call CHECKFATVID
        jc BIOS_CHECK_MAP
        or si,si
        js BIOS_CHECK_CHANGED
        inc bp
        jmp BIOS_CHECK_NORMAL
BIOS_CHECK_CHANGED:
        call RETURNVID
        jmp BIOS_CHECK_MAP
