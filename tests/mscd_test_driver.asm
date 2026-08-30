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
    dw 0
    db 0
    db 2

request_offset  dw 0
request_segment dw 0
fail_reads      db 0

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
    cmp byte [es:di + 2], 0feh
    jne .check_read
    mov byte [cs:fail_reads], 1
    jmp .complete
.check_read:
    cmp byte [es:di + 2], 80h
    jne .complete
    cmp byte [cs:fail_reads], 0
    jne .request_error
    cmp word [es:di + 18], 1
    jne .request_error
    mov bx, [es:di + 14]
    mov ax, [es:di + 16]
    mov ds, ax
    push es
    push di
    mov es, ax
    mov di, bx
    xor ax, ax
    mov cx, 1024
    rep stosw
    pop di
    pop es
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
    je .supplementary_vtoc
    cmp word [es:di + 20], 18
    je .terminating_vtoc
    cmp word [es:di + 20], 20
    je .root_directory
    cmp word [es:di + 20], 21
    je .nested_directory
    cmp word [es:di + 20], 22
    je .supplementary_directory
    jne .request_error
.terminating_vtoc:
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
    mov byte [bx + 156], 34
    mov word [bx + 158], 20
    mov word [bx + 160], 0
    mov word [bx + 166], 2048
    mov word [bx + 168], 0
    mov byte [bx + 181], 2
    mov byte [bx + 188], 1
    mov byte [bx + 189], 0
    jmp .complete
.supplementary_vtoc:
    mov byte [bx], 2
    mov word [bx + 1], 'CD'
    mov word [bx + 3], '00'
    mov byte [bx + 5], '1'
    mov word [bx + 88], '%/'
    mov byte [bx + 90], '@'
    mov word [bx + 158], 22
    mov word [bx + 160], 0
    mov word [bx + 166], 2048
    mov word [bx + 168], 0
    mov byte [bx + 181], 2
    mov byte [bx + 188], 1
    mov byte [bx + 189], 0
    jmp .complete
.root_directory:
    mov byte [bx], 46
    mov word [bx + 2], 30
    mov word [bx + 4], 0
    mov word [bx + 10], 12
    mov word [bx + 12], 0
    mov byte [bx + 25], 0
    mov byte [bx + 32], 12
    mov word [bx + 33], 'RE'
    mov word [bx + 35], 'AD'
    mov word [bx + 37], 'ME'
    mov word [bx + 39], '.T'
    mov word [bx + 41], 'XT'
    mov word [bx + 43], ';1'
    mov byte [bx + 46], 38
    mov word [bx + 48], 21
    mov word [bx + 50], 0
    mov word [bx + 56], 2048
    mov word [bx + 58], 0
    mov byte [bx + 71], 2
    mov byte [bx + 78], 4
    mov word [bx + 79], 'DO'
    mov word [bx + 81], 'CS'
    jmp .complete
.nested_directory:
    mov byte [bx], 46
    mov word [bx + 2], 31
    mov word [bx + 4], 0
    mov word [bx + 10], 14
    mov word [bx + 12], 0
    mov byte [bx + 25], 0
    mov byte [bx + 32], 11
    mov word [bx + 33], 'IN'
    mov word [bx + 35], 'NE'
    mov word [bx + 37], 'R.'
    mov word [bx + 39], 'TX'
    mov word [bx + 41], 'T;'
    mov byte [bx + 43], '1'
    jmp .complete
.supplementary_directory:
    mov byte [bx], 44
    mov word [bx + 2], 32
    mov word [bx + 4], 0
    mov word [bx + 10], 9
    mov word [bx + 12], 0
    mov byte [bx + 25], 0
    mov byte [bx + 32], 9
    mov word [bx + 33], 'JP'
    mov word [bx + 35], 'N.'
    mov word [bx + 37], 'TX'
    mov word [bx + 39], 'T;'
    mov byte [bx + 41], '1'
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
