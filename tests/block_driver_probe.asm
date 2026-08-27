bits 16
org 100h

; Assert the removable-media request path of the two configured block drivers.

start:
    mov bl, 3                    ; C: RAMDRIVE
    call non_removable
    jc failed
    mov bl, 4                    ; D: VDISK
    call non_removable
    jc failed

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

pass_message db 'BLOCK_DRIVER_REQUEST_PASS', 13, 10, 0
fail_message db 'BLOCK_DRIVER_REQUEST_FAIL', 13, 10, 0
