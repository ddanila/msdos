bits 16
org 100h
start:
    push cs
    pop ds
    mov word [row],cases
next_case:
    mov bx,[row]
    mov al,[bx]
    mov [scenario],al
    mov byte [mapped],0
    mov byte [returned_vid],0
    mov bp,0b00bh
    mov [saved_sp],sp
    mov ah,6
    test al,64
    jz .function_set
    mov ah,1
.function_set:
    test al,32
    jnz .io
    call BIOS_CHECKLATCH_RESULT
    jmp short .returned
.io:
    call BIOS_CHECKIO_RESULT
.returned:
    pushf
    pop dx
    cmp sp,[saved_sp]
    jne fail
    mov bx,[row]
    and dl,1
    cmp dl,[bx+1]
    jne fail
    test dl,dl
    jz .normal
    cmp al,0fh
    jne fail
.normal:
    mov al,[mapped]
    cmp al,[bx+2]
    jne fail
    mov al,[returned_vid]
    cmp al,[bx+3]
    jne fail
    xor ax,ax
    mov al,[bx+4]
    add ax,0b00bh
    cmp bp,ax
    jne fail
    add word [row],5
    cmp word [row],cases_end
    jb next_case
    mov ax,4c00h
    int 21h
fail:
    mov ax,4c01h
    int 21h

%include "MSCHKRSL.INC"

; Controlled service outcomes exercise every decision in the shared helpers.
CHKOPCNT:
    test byte [scenario],1
    ret
CHECKROMCHANGE:
    test byte [scenario],2
    ret
GETBP:
    test byte [scenario],4
    jz good
    mov ax,060fh                 ; already mapped by GETBP
    stc
    ret
CHECK_VID:
CHECKFATVID:
    test byte [scenario],8
    jz .no_read_error
    mov ah,20h
    stc
    ret
.no_read_error:
    xor si,si
    test byte [scenario],16
    jz good
    dec si
good:
    clc
    ret
RETURNVID:
    inc byte [returned_vid]
    mov ah,6
    stc
    ret
MAPERROR:
    inc byte [mapped]
    mov al,0fh
    stc
    ret

row dw 0
saved_sp dw 0
scenario db 0
mapped db 0
returned_vid db 0
; scenario bits, expected CF, MAPERROR calls, RETURNVID calls, BP increment
cases:
    db 0,0,0,0,0                ; latch: no open files
    db 1,0,0,0,0                ; no latched change
    db 7,1,0,0,0                ; GETBP already mapped error
    db 11,1,1,0,0               ; read error needs mapping
    db 3,0,0,0,0                ; unchanged volume
    db 19,1,1,1,0               ; changed volume
    db 96,0,0,0,0               ; I/O: not BIOS error 06h
    db 32,0,0,0,0               ; no open files
    db 37,1,0,0,0               ; GETBP already mapped error
    db 41,1,1,0,0               ; read error needs mapping
    db 33,0,0,0,1               ; unchanged: permit another retry
    db 49,1,1,1,0               ; changed volume
cases_end:
