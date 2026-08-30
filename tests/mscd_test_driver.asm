bits 16
org 0

; Test-only CD-ROM character driver header.  MSCDEX uses it to prove /D
; discovery and publishes its address through INT 2Fh/1501h.
device_header:
    dd 0ffffffffh
    dw 0c800h
    dw strategy
    dw interrupt
    db 'MSCD001 '

request_offset  dw 0
request_segment dw 0

strategy:
    mov [cs:request_offset], bx
    mov [cs:request_segment], es
    retf

interrupt:
    push ax
    push bx
    push cx
    push ds
    push es
    push di
    mov ax, [cs:request_segment]
    mov es, ax
    mov di, [cs:request_offset]
    cmp byte [es:di + 2], 0
    jne .forwarded
    mov word [es:di + 0eh], resident_end
    mov word [es:di + 10h], cs
    jmp .complete
.forwarded:
    mov byte [es:di + 0dh], 0a5h
    cmp byte [es:di + 2], 80h
    jne .complete
    cmp word [es:di + 18], 1
    jne .request_error
    mov bx, [es:di + 14]
    mov ax, [es:di + 16]
    mov ds, ax
    cmp word [es:di + 22], 1234h
    jne .vtoc_read
    cmp word [es:di + 20], 5678h
    jne .request_error
    mov word [bx], 'CD'
    mov word [bx + 2], '22'
    jmp .complete
.vtoc_read:
    cmp word [es:di + 22], 0
    jne .request_error
    cmp word [es:di + 20], 16
    je .primary_vtoc
    cmp word [es:di + 20], 17
    jne .request_error
    mov byte [bx], 0ffh
    jmp .complete
.primary_vtoc:
    mov byte [bx], 1
    mov word [bx + 1], 'CD'
    mov word [bx + 3], '00'
    mov byte [bx + 5], '1'
    mov word [bx + 702], 'CO'
    mov word [bx + 704], 'PY'
    mov word [bx + 706], '.T'
    mov word [bx + 708], 'XT'
    mov word [bx + 710], ';1'
    mov word [bx + 739], 'AB'
    mov word [bx + 741], 'ST'
    mov word [bx + 743], 'RA'
    mov word [bx + 745], 'CT'
    mov word [bx + 747], '.T'
    mov word [bx + 749], 'XT'
    mov word [bx + 751], ';1'
    mov word [bx + 776], 'BI'
    mov word [bx + 778], 'BL'
    mov word [bx + 780], 'IO'
    mov word [bx + 782], '.T'
    mov word [bx + 784], 'XT'
    mov word [bx + 786], ';1'
    jmp .complete
.request_error:
    mov word [es:di + 3], 810bh
    jmp .return
.complete:
    mov word [es:di + 3], 0100h
.return:
    pop di
    pop es
    pop ds
    pop cx
    pop bx
    pop ax
    retf

resident_end:
