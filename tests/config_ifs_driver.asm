bits 16
org 0

; Minimal installable-file-system fixture. It accepts boot-time INIT plus the
; runtime attach lifecycle and records each request in its resident header.

ifs_header:
    dd 0ffffffffh                  ; IFS_NEXT, rewritten by SYSINIT.
    db 'TESTIFS '                  ; IFS_NAME.
    dw 0                           ; No disk/device/UNC services.
    dw 0                           ; Interface version.
    dd 0                           ; IFS_DOSCALL@, supplied by SYSINIT.
    dw ifs_entry                   ; IFS_CALL@.

    dw 0beefh                      ; Fixture signature for runtime probes.
attach_count dw 0
status_count dw 0
detach_count dw 0

ifs_entry:
    mov al, [es:bx + 2]
    cmp al, 1                      ; IFSINIT.
    je .init
    cmp al, 2                      ; IFSATTSTART.
    je .attach
    cmp al, 3                      ; IFSATTSTAT.
    je .status
    cmp al, 4                      ; IFSATTEND.
    je .detach
    jmp .unsupported

.init:
    mov word [es:bx + 3], 0        ; IFSR_RETCODE = success.
    mov word [es:bx + 26], (driver_end - $$ + 15) / 16
    retf
.attach:
    inc word [cs:attach_count]
    jmp .success
.status:
    inc word [cs:status_count]
    push ds
    push si
    lds si, [es:bx + 24]           ; ATTSTAT IFSR_PARMS@.
    mov word [si], 0               ; No driver-specific parameters.
    pop si
    pop ds
    jmp .success
.detach:
    inc word [cs:detach_count]
.success:
    mov word [es:bx + 3], 0
    retf
.unsupported:
    mov word [es:bx + 3], 1
    retf

driver_end:
