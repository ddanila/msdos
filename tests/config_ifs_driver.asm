bits 16
org 0


ifs_header:
    dd 0ffffffffh
    db 'TESTIFS '
    dw 0
    dw 0
    dd 0
    dw ifs_entry

    dw 0beefh
attach_count dw 0
status_count dw 0
detach_count dw 0

ifs_entry:
    mov al, [es:bx + 2]
    cmp al, 1
    je .init
    cmp al, 2
    je .attach
    cmp al, 3
    je .status
    cmp al, 4
    je .detach
    jmp .unsupported

.init:
    mov word [es:bx + 3], 0
    mov word [es:bx + 26], (driver_end - $$ + 15) / 16
    retf
.attach:
    inc word [cs:attach_count]
    jmp .success
.status:
    inc word [cs:status_count]
    push ds
    push si
    lds si, [es:bx + 24]
    mov word [si], 0
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
