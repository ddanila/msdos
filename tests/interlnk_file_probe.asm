bits 16
org 100h

start:
    push cs
    pop ds
    mov dx, remote_name
    mov ax, 3d00h
    int 21h
    jc failed
    mov bx, ax
    mov dx, buffer
    mov cx, payload_end - payload
    mov ah, 3fh
    int 21h
    jc failed_close
    cmp ax, payload_end - payload
    jne failed_close
    mov si, payload
    mov di, buffer
    mov cx, payload_end - payload
    repe cmpsb
    jne failed_close
    mov ah, 3eh
    int 21h

    mov dx, written_name
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc failed
    mov bx, ax
    mov dx, write_payload
    mov cx, write_end - write_payload
    mov ah, 40h
    int 21h
    jc failed_close
    cmp ax, write_end - write_payload
    jne failed_close
    mov ah, 3eh
    int 21h

    mov si, pass_message
    call debug_print
    mov ax, 4c00h
    int 21h

failed_close:
    mov ah, 3eh
    int 21h
failed:
    mov si, fail_message
    call debug_print
    mov ax, 4c01h
    int 21h

debug_print:
    lodsb
    test al, al
    jz .done
    out 0e9h, al
    jmp debug_print
.done:
    ret

remote_name db 'C:\REMOTE.TXT',0
written_name db 'C:\WRITTEN.BIN',0
payload db 'Byte-exact Interlnk transport',13,10
payload_end:
write_payload db 00h,11h,22h,33h,44h,55h,0aah,0ffh
write_end:
pass_message db 'INTERLNK_TRANSPORT_PASS',13,10,0
fail_message db 'INTERLNK_TRANSPORT_FAIL',13,10,0
buffer times 64 db 0
