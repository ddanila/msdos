bits 16
org 100h


start:
    push cs
    pop ds

    mov ax, 3300h
    int 21h
    cmp dl, 1
    jne break_failed

    mov ah, 19h
    int 21h
    mov [current_drive], al
    mov dl, al
    mov ah, 0eh
    int 21h
    cmp al, 26
    jne lastdrive_failed

    mov ah, 52h
    int 21h

    cmp word [es:bx + 63], 20
    jne buffers_failed
    cmp word [es:bx + 65], 0
    jne buffers_failed

    mov si, [es:bx + 4]
    mov ax, [es:bx + 6]
    push es
    mov es, ax
    xor cx, cx
.sum_sfts:
    add cx, [es:si + 4]
    mov ax, [es:si + 2]
    mov si, [es:si]
    cmp si, 0ffffh
    je .sfts_done
    mov es, ax
    jmp .sum_sfts
.sfts_done:
    pop es
    cmp cx, 32
    jne files_failed

    cmp word [es:bx + 30], 3
    jne fcbs_failed
    mov si, [es:bx + 26]
    mov ax, [es:bx + 28]
    push es
    mov es, ax
    cmp word [es:si + 4], 8
    pop es
    jne fcbs_failed

    mov dx, 5aa5h
    mov ax, 3303h
    int 21h
    cmp dx, 5aa5h
    jne cpsw_failed
    mov dx, 0a55ah
    mov ax, 3304h
    int 21h
    cmp dx, 0a55ah
    jne cpsw_failed

    mov bx, 2
    mov cx, 0860h
    mov dx, device_parameters
    mov ax, 440dh
    int 21h
    jc drivparm_failed
    cmp byte [device_parameters + 1], 2
    jne drivparm_failed
    cmp word [device_parameters + 4], 77
    jne drivparm_failed
    cmp word [device_parameters + 20], 17
    jne drivparm_failed
    cmp word [device_parameters + 22], 1
    jne drivparm_failed

    mov dl, [current_drive]
    mov ah, 0eh
    int 21h

    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

break_failed:
    mov dx, fail_break
    jmp fail
lastdrive_failed:
    mov dx, fail_lastdrive
    jmp fail
buffers_failed:
    mov dx, fail_buffers
    jmp fail
files_failed:
    mov dx, fail_files
    jmp fail
fcbs_failed:
    mov dx, fail_fcbs
    jmp fail
cpsw_failed:
    mov dx, fail_cpsw
    jmp fail
drivparm_failed:
    mov dx, fail_drivparm
fail:
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

pass_message   db 'CONFIG_STATE_PASS', 13, 10, '$'
fail_break     db 'CONFIG_BREAK_COMMENT_REM_FAIL', 13, 10, '$'
fail_lastdrive db 'CONFIG_LASTDRIVE_FAIL', 13, 10, '$'
fail_buffers   db 'CONFIG_BUFFERS_FAIL', 13, 10, '$'
fail_files     db 'CONFIG_FILES_FAIL', 13, 10, '$'
fail_fcbs      db 'CONFIG_FCBS_FAIL', 13, 10, '$'
fail_cpsw      db 'CONFIG_CPSW_COMPAT_FAIL', 13, 10, '$'
fail_drivparm  db 'CONFIG_DRIVPARM_FAIL', 13, 10, '$'
current_drive  db 0
device_parameters times 300 db 0
