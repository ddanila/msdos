; Shared conventional return support for the complete high character owner.
; Use actual INT instructions: preserve hardware interrupt entry semantics,
; then restore A20 without changing result registers/flags before the FAR return.
; Requires the same qualified provider and conventional stack as HIGHROM.INC.
BIOS_HMA_INT14:
        int     14h
        call    BIOS_HMA_ROM_RESTORE
        retf
BIOS_HMA_INT15:
        int     15h
        call    BIOS_HMA_ROM_RESTORE
        retf
BIOS_HMA_INT16:
        int     16h
        call    BIOS_HMA_ROM_RESTORE
        retf
BIOS_HMA_INT17:
        int     17h
        call    BIOS_HMA_ROM_RESTORE
        retf
BIOS_HMA_INT29:
        int     29h
        call    BIOS_HMA_ROM_RESTORE
        retf
