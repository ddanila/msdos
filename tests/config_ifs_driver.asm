bits 16
org 0

; Minimal installable-file-system fixture. It accepts only the boot-time INIT
; request; the runtime probe verifies that SYSINIT linked this exact header.

ifs_header:
    dd 0ffffffffh                  ; IFS_NEXT, rewritten by SYSINIT.
    db 'TESTIFS '                  ; IFS_NAME.
    dw 0                           ; No disk/device/UNC services.
    dw 0                           ; Interface version.
    dd 0                           ; IFS_DOSCALL@, supplied by SYSINIT.
    dw ifs_entry                   ; IFS_CALL@.

ifs_entry:
    cmp byte [es:bx + 2], 1        ; IFSINIT.
    jne .unsupported
    mov word [es:bx + 3], 0        ; IFSR_RETCODE = success.
    mov word [es:bx + 26], (driver_end - $$ + 15) / 16
    retf
.unsupported:
    mov word [es:bx + 3], 1
    retf

driver_end:
