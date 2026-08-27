bits 16
org 100h

; Assert geometry, raw I/O, isolation, and removable-media behavior of the two
; configured 64 KiB memory-backed block drivers.

start:
    push cs
    pop ds
    push ds
    pop es
    cld

    mov bl, 3                    ; C: RAMDRIVE
    call non_removable
    jc failed
    mov bl, 4                    ; D: VDISK
    call non_removable
    jc failed

    mov al, 2                    ; Resolve C:'s live DPB and RAMDRIVE header.
    call load_block_driver
    jc failed
    mov si, ram_success_commands
    mov di, ram_error_commands
    call verify_request_commands
    jc failed

    mov al, 3                    ; Resolve D:'s live DPB and VDISK header.
    call load_block_driver
    jc failed
    mov si, vdisk_success_commands
    mov di, vdisk_error_commands
    call verify_request_commands
    jc failed

    mov al, 2                    ; Read C: RAMDRIVE boot sector.
    xor dx, dx
    mov bx, sector_buffer
    call absolute_read
    jc failed
    cmp word [sector_buffer + 11], 512
    jne failed
    cmp word [sector_buffer + 17], 64
    jne failed
    cmp word [sector_buffer + 19], 128
    jne failed
    mov si, ram_oem
    mov di, sector_buffer + 3
    mov cx, 8
    repe cmpsb
    jne failed

    mov al, 3                    ; Read D: VDISK boot sector.
    xor dx, dx
    mov bx, sector_buffer
    call absolute_read
    jc failed
    cmp word [sector_buffer + 11], 128
    jne failed
    cmp word [sector_buffer + 17], 64
    jne failed
    cmp word [sector_buffer + 19], 512
    jne failed
    mov si, vdisk_oem
    mov di, sector_buffer + 3
    mov cx, 8
    repe cmpsb
    jne failed

    mov di, write_buffer
    mov cx, 512
    mov al, 0a5h
    rep stosb
    mov al, 2                    ; C: final 512-byte sector.
    mov dx, 127
    mov bx, write_buffer
    call absolute_write
    jc failed
    mov al, 2
    mov dx, 127
    mov bx, sector_buffer
    call absolute_read
    jc failed
    mov si, write_buffer
    mov di, sector_buffer
    mov cx, 512
    repe cmpsb
    jne failed

    mov di, write_buffer
    mov cx, 128
    mov al, 05ah
    rep stosb
    mov al, 3                    ; D: final 128-byte sector.
    mov dx, 511
    mov bx, write_buffer
    call absolute_write
    jc failed
    mov al, 3
    mov dx, 511
    mov bx, sector_buffer
    call absolute_read
    jc failed
    mov si, write_buffer
    mov di, sector_buffer
    mov cx, 128
    repe cmpsb
    jne failed

    mov al, 2                    ; D: write must not alter C:.
    mov dx, 127
    mov bx, sector_buffer
    call absolute_read
    jc failed
    mov di, sector_buffer
    mov cx, 512
    mov al, 0a5h
    repe scasb
    jne failed

    mov si, pass_message
    call serial_print
    mov ax, 4c00h
    int 21h

non_removable:
    mov ax, 4408h                ; IOCTL: is block device removable?
    int 21h
    jc .bad
    cmp ax, 1                    ; 1 = non-removable
    jne .bad
    clc
    ret
.bad:
    stc
    ret

; Locate the DPB for zero-based drive AL and retain its unit number and live
; device entry points.  This avoids relying on device-chain order to distinguish
; the two unnamed block drivers.
load_block_driver:
    push ax
    mov ah, 52h
    int 21h
    les si, [es:bx]              ; SYSI_DPB chain head.
    mov cx, 32
.next_dpb:
    pop ax
    push ax
    cmp [es:si], al
    je .found
    les si, [es:si + 25]         ; dpb_next_dpb.
    cmp si, 0ffffh
    je .missing
    loop .next_dpb
.missing:
    pop ax
    stc
    ret
.found:
    mov al, [es:si + 1]          ; dpb_unit.
    mov [request_packet + 1], al
    les bx, [es:si + 19]         ; dpb_driver_addr.
    mov [driver_header], bx
    mov ax, es
    mov [driver_header + 2], ax
    mov ax, [es:bx + 6]
    mov [driver_strategy], ax
    mov ax, [es:bx + 8]
    mov [driver_interrupt], ax
    mov ax, es
    mov [driver_strategy + 2], ax
    mov [driver_interrupt + 2], ax
    pop ax
    clc
    ret

; Success-command list at DS:SI and invalid-command list at DS:DI are both
; FF-terminated.  Direct requests prove the live handlers' status contracts;
; command 16 additionally checks the dispatch-table upper boundary.
verify_request_commands:
.success:
    lodsb
    cmp al, 0ffh
    je .errors
    call issue_request
    mov ax, [request_packet + 3]
    and ax, 0ff00h
    cmp ax, 0100h                ; Done, with no error or busy bits.
    jne .failed
    jmp .success
.errors:
    mov al, [di]
    inc di
    cmp al, 0ffh
    je .passed
    call issue_request
    cmp word [request_packet + 3], 8103h
    jne .failed                  ; Done + error + unknown command.
    jmp .errors
.passed:
    clc
    ret
.failed:
    stc
    ret

issue_request:
    mov [request_packet + 2], al
    mov word [request_packet + 3], 0deadH
    push cs
    pop es
    mov bx, request_packet
    push ds
    push si
    lds si, [driver_header]
    call far [cs:driver_strategy]
    call far [cs:driver_interrupt]
    pop si
    pop ds
    ret

absolute_read:
    mov cx, 1
    int 25h
    pop si                       ; Discard INT 25h's retained FLAGS word.
    ret

absolute_write:
    mov cx, 1
    int 26h
    pop si                       ; Discard INT 26h's retained FLAGS word.
    ret

failed:
    mov si, fail_message
    call serial_print
    mov ax, 4c01h
    int 21h

serial_print:
    lodsb
    test al, al
    jz .done
    mov ah, al
.wait:
    mov dx, 03fdh
    in al, dx
    test al, 20h
    jz .wait
    mov dx, 03f8h
    mov al, ah
    out dx, al
    jmp serial_print
.done:
    ret

ram_oem db 'RDV 1.20'
vdisk_oem db 'VDISKx.x'
ram_success_commands db 5, 6, 7, 10, 11, 12, 13, 14, 0ffh
ram_error_commands db 3, 16, 0ffh
vdisk_success_commands db 13, 14, 0ffh
vdisk_error_commands db 3, 5, 6, 7, 10, 11, 12, 16, 0ffh
pass_message db 'BLOCK_DRIVER_REQUEST_PASS', 13, 10, 0
fail_message db 'BLOCK_DRIVER_REQUEST_FAIL', 13, 10, 0
driver_strategy dd 0
driver_interrupt dd 0
driver_header dd 0
request_packet:
    db 22, 0, 0
    dw 0
    times 8 db 0
    db 0
    dw 0, 0
    dw 0
    dw 0
sector_buffer times 512 db 0
write_buffer times 512 db 0
