; Vendor builds collect API registers only. LOCAL_SDA_LIVE additionally checks
; repository SDA fields; no vendor-private memory is dereferenced.
bits 16
org 100h

start:
    push cs
    pop ds
    mov dx, dpl
    xor cx, cx
    xor si, si
    mov ax, 5d06h
    clc
    int 21h
    call snapshot
    mov dx, label_06
    call record
%ifdef LOCAL_SDA_LIVE
    ; Repository SDA offsets only. Do not impose this layout on vendor DOS.
    cmp word [values], 0
    jne .bad_live
    mov es, [values+4]
    mov di, [values+6]
    mov ax, es
    mov [sda_segment], ax
    mov [sda_offset], di
    mov ax, [values+8]
    mov [sda_length], ax
    mov ax, [values+10]
    mov [sda_always], ax
    mov ax, cs
    cmp [es:di+10h], ax
    jne .bad_live
    cmp [es:di+0eh], ax
    jne .bad_live
    cmp word [es:di+0ch], 80h
    jne .bad_live
    ; A cached pointer must follow subsequent changes, not just a boot copy.
    mov dx, dpl
    mov ah, 1ah
    int 21h
    cmp word [es:di+0ch], dpl
    jne .bad_live
    mov dx, live_pass
    jmp .print_live
.bad_live:
    mov dx, live_fail
.print_live:
    mov ah, 09h
    int 21h
%endif

    mov dx, dpl
    xor cx, cx
    xor si, si
    mov ax, 5d0bh
    clc
    int 21h
    call snapshot
    mov dx, label_0b
    call record
%ifdef LOCAL_SDA_LIVE
    cmp word [values], 0
    jne .bad_table
    mov es, [values+4]
    mov di, [values+6]
    cmp word [es:di], 2
    jne .bad_table
    mov ax, [sda_offset]
    cmp [es:di+8], ax
    jne .bad_table
    add ax, [sda_always]
    cmp [es:di+2], ax
    jne .bad_table
    mov ax, [sda_segment]
    cmp [es:di+4], ax
    jne .bad_table
    cmp [es:di+10], ax
    jne .bad_table
    mov ax, [sda_always]
    or ax, 8000h
    cmp [es:di+12], ax
    jne .bad_table
    mov ax, [sda_length]
    sub ax, [sda_always]
    cmp [es:di+6], ax
    jne .bad_table
    mov dx, table_pass
    jmp .print_table
.bad_table:
    mov dx, table_fail
.print_table:
    mov ah, 09h
    int 21h
%endif
    mov dx, done
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

snapshot:
    mov [cs:values+2], ax
    mov [cs:values+4], ds
    mov [cs:values+6], si
    mov [cs:values+8], cx
    mov [cs:values+10], dx
    pushf
    pop ax
    and ax, 1
    mov [cs:values], ax
    push cs
    pop ds
    ret

record:
    mov ah, 09h
    int 21h
    mov si, values
    mov bp, 6
.word:
    lodsw
    mov bx, ax
    mov cx, 4
.digit:
    rol bx, 4
    mov dl, bl
    and dl, 15
    add dl, '0'
    cmp dl, '9'
    jbe .emit
    add dl, 7
.emit:
    mov ah, 02h
    int 21h
    loop .digit
    mov dl, ' '
    mov ah, 02h
    int 21h
    dec bp
    jnz .word
    mov dx, newline
    mov ah, 09h
    int 21h
    ret

values times 6 dw 0
dpl times 64 db 0
label_06 db 'SDA_5D06 CF AX DS SI CX DX: $'
label_0b db 'SDA_5D0B CF AX DS SI CX DX: $'
newline db 13,10,'$'
done db 'DRDOS_PUBLIC_MEMORY_END',13,10,'$'
%ifdef LOCAL_SDA_LIVE
live_pass db 'SDA_LIVE_PASS',13,10,'$'
live_fail db 'SDA_LIVE_FAIL',13,10,'$'
table_pass db 'SDA_TABLE_PASS',13,10,'$'
table_fail db 'SDA_TABLE_FAIL',13,10,'$'
sda_segment dw 0
sda_offset dw 0
sda_length dw 0
sda_always dw 0
%endif
