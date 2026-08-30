bits 16
org 100h

start:
    push cs
    pop ds
    mov ax, 0e900h
    int 2fh
    cmp ax, 0ff00h
    jne failed
    cmp bx, 1
    jne failed
    cmp cx, 2
    jne failed
    cmp dx, 2
    jne failed
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

    ; Force a complete discovery/BPB renegotiation over the live transport.
    ; Subsequent access proves the resident client remains synchronized.
    mov ax, 0e901h
    int 2fh
    cmp ax, 0ff00h
    jne failed
    mov ax, 0e900h
    int 2fh
    cmp ax, 0ff00h
    jne failed
    cmp bx, 1
    jne failed
    mov ax, 0e902h
    int 2fh
    cmp ax, 0ff00h
    jne failed
    mov ax, 0e900h
    int 2fh
    cmp ax, 0ff00h
    jne failed
    cmp bx, 0
    jne failed

    mov dx, remote_name_two
    mov ax, 3d00h
    int 21h
    jc failed
    mov bx, ax
    mov dx, buffer
    mov cx, payload_two_end - payload_two
    mov ah, 3fh
    int 21h
    jc failed_close
    cmp ax, payload_two_end - payload_two
    jne failed_close
    mov si, payload_two
    mov di, buffer
    mov cx, payload_two_end - payload_two
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

    mov dx, written_name_two
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc failed
    mov bx, ax
    mov dx, write_payload_two
    mov cx, write_two_end - write_payload_two
    mov ah, 40h
    int 21h
    jc failed_close
    cmp ax, write_two_end - write_payload_two
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
remote_name_two db 'D:\REMOTE2.TXT',0
written_name db 'C:\WRITTEN.BIN',0
written_name_two db 'D:\WRITTN2.BIN',0
payload db 'Byte-exact Interlnk transport',13,10
payload_end:
payload_two db 'Second Interlnk volume',13,10
payload_two_end:
write_payload db 00h,11h,22h,33h,44h,55h,0aah,0ffh
write_end:
write_payload_two db 0feh,0dch,0bah,098h,076h,054h,032h,010h
write_two_end:
pass_message db 'INTERLNK_TRANSPORT_PASS',13,10,0
fail_message db 'INTERLNK_TRANSPORT_FAIL',13,10,0
buffer times 64 db 0
