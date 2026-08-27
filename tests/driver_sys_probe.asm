bits 16
org 100h

; Read known data through the logical drive installed by DRIVER.SYS.

start:
    push cs
    pop ds

    mov dx, filename
    mov ax, 3d00h
    int 21h
    jc failed
    mov bx, ax
    mov cx, payload_size
    mov dx, buffer
    mov ah, 3fh
    int 21h
    jc failed_close
    cmp ax, payload_size
    jne failed_close
    mov si, payload
    mov di, buffer
    mov cx, payload_size
    repe cmpsb
    jne failed_close
    mov ah, 3eh
    int 21h

    mov si, pass_message
    call serial_print
    mov ax, 4c00h
    int 21h

failed_close:
    mov ah, 3eh
    int 21h
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

filename     db 'C:\DRVTEST.TXT', 0
payload      db 'DRIVER_OK'
payload_size equ $ - payload
buffer       times payload_size db 0
pass_message db 'DRIVER_SYS_PASS', 13, 10, 0
fail_message db 'DRIVER_SYS_FAIL', 13, 10, 0
