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

; Binary operation with a low memory source. Borrow only DS or ES, chosen
; explicitly so LDS/LES and segment-register results survive restoration.
; PUSH/POP/MOV do not disturb either incoming carry or the operation's flags.
BIOS_LOW_READ MACRO operation, result, address, workseg
        IFDIFI <workseg>,<DS>
        IFDIFI <workseg>,<ES>
        .ERR ; only data segments may be borrowed
        ENDIF
        ENDIF
        IFIDNI <result>,<workseg>
        .ERR ; cannot restore over the instruction result
        ENDIF
        IFIDNI <result>,<SP>
        .ERR ; stack replacement needs its own gateway
        ENDIF
        IFIDNI <operation>,<LDS>
        IFIDNI <workseg>,<DS>
        .ERR ; LDS intentionally changes DS
        ENDIF
        ENDIF
        IFIDNI <operation>,<LES>
        IFIDNI <workseg>,<ES>
        .ERR ; LES intentionally changes ES
        ENDIF
        ENDIF
        IFDEF BIOS_SERVICE_SEPARATE_DATA
        PUSH workseg
        BIOS_PUSH_DATA_SEG
        POP workseg
        operation result,workseg:address
        POP workseg
        ELSE
        operation result,CS:address
        ENDIF
ENDM

; Binary operation with low memory first (MOV, CMP, TEST, XCHG, etc.).
; Values taken from SP cannot be sampled after pushing the borrowed segment.
BIOS_LOW_MEM MACRO operation, address, value, workseg
        IFDIFI <workseg>,<DS>
        IFDIFI <workseg>,<ES>
        .ERR ; only data segments may be borrowed
        ENDIF
        ENDIF
        IFIDNI <value>,<workseg>
        .ERR ; borrowed segment would replace the input value
        ENDIF
        IFIDNI <value>,<SP>
        .ERR ; original SP needs an explicit stack-preserving operation
        ENDIF
        IFDEF BIOS_SERVICE_SEPARATE_DATA
        PUSH workseg
        BIOS_PUSH_DATA_SEG
        POP workseg
        operation workseg:address,value
        POP workseg
        ELSE
        operation CS:address,value
        ENDIF
ENDM
