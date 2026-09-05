; Explicit ownership for segment values passed to data/buffer consumers.
; The installed low layout expands to exactly PUSH CS. A separately linked
; service body must provide its relocated BIOS_SERVICE_LOW_SEGMENT word.
; These operations separate data ownership; none activates HMA relocation.
BIOS_PUSH_DATA_SEG MACRO
        IFDEF BIOS_SERVICE_SEPARATE_DATA
        PUSH WORD PTR CS:[BIOS_SERVICE_LOW_SEGMENT]
        ELSE
        PUSH CS
        ENDIF
ENDM

; Store the original SP in a fixed low word, not the wrapper's deeper SP.
; Address must not depend on BP: BP is temporarily used to recover input SP.
BIOS_LOW_SAVE_SP MACRO address
        IFDEF BIOS_SERVICE_SEPARATE_DATA
        PUSH AX
        PUSH DS
        PUSH BP
        MOV BP,SP
        BIOS_PUSH_DATA_SEG
        POP DS
        LEA AX,[BP+6]
        MOV DS:address,AX
        POP BP
        POP DS
        POP AX
        ELSE
        MOV CS:address,SP
        ENDIF
ENDM

; Unwind this same conventional stack to a previously saved SP. The discarded
; stack receives our scratch words; no word at/above the target SP is changed.
; Not a general SS switch or a way to restore another stack below current SP.
BIOS_LOW_RESTORE_SP MACRO address
        IFDEF BIOS_SERVICE_SEPARATE_DATA
        PUSH AX
        PUSH DS
        BIOS_PUSH_DATA_SEG
        POP DS
        MOV AX,DS:address
        POP DS
        PUSH BP
        MOV BP,SP
        XCHG AX,SS:[BP+2]
        POP BP
        POP SP
        ELSE
        MOV SP,CS:address
        ENDIF
ENDM

; INC/DEC preserve carry and update the arithmetic flags. Do not use this
; wrapper for PUSH/POP or other operations which change the stack shape.
BIOS_LOW_UNARY MACRO operation, address
        IFDIFI <operation>,<INC>
        IFDIFI <operation>,<DEC>
        .ERR ; only non-stack INC/DEC are supported here
        ENDIF
        ENDIF
        IFDEF BIOS_SERVICE_SEPARATE_DATA
        PUSH DS
        BIOS_PUSH_DATA_SEG
        POP DS
        operation DS:address
        POP DS
        ELSE
        operation CS:address
        ENDIF
ENDM

; Track descriptors belong to low data, unlike the high IOCTL dispatch table.
; Preserve caller DS and FLAGS/DF; LODSB supplies AL and advances SI normally.
BIOS_LOW_LODSB MACRO
        IFDEF BIOS_SERVICE_SEPARATE_DATA
        PUSH DS
        BIOS_PUSH_DATA_SEG
        POP DS
        LODSB
        POP DS
        ELSE
        LODS BYTE PTR CS:[SI]
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
