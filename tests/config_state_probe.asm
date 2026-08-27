bits 16
org 100h

; Focused contracts for CONFIG.SYS settings exposed through DOS state.
; CONFIG.SYS for this probe selects BREAK=ON, BUFFERS=20, FILES=32,
; FCBS=8,3, and LASTDRIVE=Z. COMMENT and REM lines attempt to override BREAK;
; observing it still enabled also proves those lines were ignored.

start:
    push cs
    pop ds

    mov ax, 3300h                 ; BREAK=ON is observable through AH=33h.
    int 21h
    cmp dl, 1
    jne break_failed

    mov ah, 19h                   ; Preserve the current drive.
    int 21h
    mov [current_drive], al
    mov dl, al
    mov ah, 0eh                   ; AL is the number of CDS entries.
    int 21h
    cmp al, 26                    ; LASTDRIVE=Z => A through Z.
    jne lastdrive_failed

    mov ah, 52h                   ; ES:BX -> DOS SYSINITVAR/list of lists.
    int 21h

    cmp word [es:bx + 63], 20     ; BUFFERS first configured parameter.
    jne buffers_failed
    cmp word [es:bx + 65], 0      ; No secondary /X or look-ahead value.
    jne buffers_failed

    mov si, [es:bx + 4]           ; SYSI_SFT far pointer.
    mov ax, [es:bx + 6]
    push es
    mov es, ax
    xor cx, cx
.sum_sfts:
    add cx, [es:si + 4]           ; SFCount.
    mov ax, [es:si + 2]           ; SFLink segment.
    mov si, [es:si]
    cmp si, 0ffffh
    je .sfts_done
    mov es, ax
    jmp .sum_sfts
.sfts_done:
    pop es
    cmp cx, 32
    jne files_failed

    cmp word [es:bx + 30], 3      ; SYSI_Keep from FCBS=8,3.
    jne fcbs_failed
    mov si, [es:bx + 26]          ; SYSI_FCB far pointer.
    mov ax, [es:bx + 28]
    push es
    mov es, ax
    cmp word [es:si + 4], 8       ; FCB SFT entry count.
    pop es
    jne fcbs_failed

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
current_drive  db 0
