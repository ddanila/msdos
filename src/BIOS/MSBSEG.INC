; Explicit ownership for segment values passed to data/buffer consumers.
; The installed low layout expands to exactly PUSH CS. A separately linked
; service body must provide its relocated BIOS_SERVICE_LOW_SEGMENT word.
; This does not convert ordinary CS-relative memory operands or activate HMA.
BIOS_PUSH_DATA_SEG MACRO
        IFDEF BIOS_SERVICE_SEPARATE_DATA
        PUSH WORD PTR CS:[BIOS_SERVICE_LOW_SEGMENT]
        ELSE
        PUSH CS
        ENDIF
ENDM
