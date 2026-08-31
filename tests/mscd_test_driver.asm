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
audio_state     db 0
media_open      db 0
door_locked     db 0
reset_count     db 0
channel_value   db 0

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
    cmp byte [es:di + 2], 84h
    je .audio_play
    cmp byte [es:di + 2], 85h
    je .audio_stop
    cmp byte [es:di + 2], 88h
    je .audio_resume
    cmp byte [es:di + 2], 3
    je .ioctl_input
    cmp byte [es:di + 2], 12
    je .ioctl_output
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
.audio_play:
    cmp byte [es:di + 1], 1
    jne .request_error
    mov byte [cs:audio_state], 1
    jmp .complete
.audio_stop:
    cmp byte [es:di + 1], 1
    jne .request_error
    cmp byte [cs:audio_state], 1
    jne .request_error
    mov byte [cs:audio_state], 2
    jmp .complete
.audio_resume:
    cmp byte [es:di + 1], 1
    jne .request_error
    cmp byte [cs:audio_state], 2
    jne .request_error
    mov byte [cs:audio_state], 1
    jmp .complete
.ioctl_input:
    cmp byte [es:di + 1], 1
    jne .request_error
    mov bx, [es:di + 14]
    mov ax, [es:di + 16]
    mov ds, ax
    cmp byte [bx], 1
    je .head_location
    cmp byte [bx], 4
    je .audio_channels
    cmp byte [bx], 6
    je .device_status
    cmp byte [bx], 8
    je .volume_size
    cmp byte [bx], 9
    je .media_change
    cmp byte [bx], 10
    je .disc_info
    cmp byte [bx], 11
    je .track_info
    cmp byte [bx], 12
    je .q_channel
    cmp byte [bx], 15
    je .audio_status
    jmp .request_error
.head_location:
    mov byte [bx + 1], 11h
    jmp .complete
.audio_channels:
    mov byte [bx + 1], 44h
    jmp .complete
.volume_size:
    mov byte [bx + 1], 88h
    jmp .complete
.media_change:
    mov byte [bx + 1], 99h
    jmp .complete
.disc_info:
    mov byte [bx + 1], 0aah
    jmp .complete
.track_info:
    mov byte [bx + 1], 0bbh
    jmp .complete
.q_channel:
    mov byte [bx + 1], 0cch
    jmp .complete
.audio_status:
    mov byte [bx + 1], 0ffh
    jmp .complete
.device_status:
    mov byte [bx + 1], 10h       ; audio and door-control capabilities
    mov byte [bx + 2], 0
    mov al, [cs:door_locked]
    mov [bx + 3], al
    mov al, [cs:reset_count]
    mov [bx + 4], al
    mov al, [cs:channel_value]
    mov [bx + 5], al
    cmp byte [cs:media_open], 0
    je .complete
    or byte [bx + 2], 8          ; door open
    jmp .complete
.ioctl_output:
    cmp byte [es:di + 1], 1
    jne .request_error
    mov bx, [es:di + 14]
    mov ax, [es:di + 16]
    mov ds, ax
    cmp byte [bx], 0
    je .media_eject
    cmp byte [bx], 1
    je .door_lock
    cmp byte [bx], 2
    je .drive_reset
    cmp byte [bx], 3
    je .channel_control
    cmp byte [bx], 5
    jne .request_error
    mov byte [cs:media_open], 0
    jmp .complete
.media_eject:
    mov byte [cs:media_open], 1
    jmp .complete
.door_lock:
    mov al, [bx + 1]
    and al, 1
    mov [cs:door_locked], al
    jmp .complete
.drive_reset:
    inc byte [cs:reset_count]
    jmp .complete
.channel_control:
    mov al, [bx + 1]
    mov [cs:channel_value], al
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
    cmp word [es:di + 20], 30
    je .root_file
    jne .request_error
.root_file:
    mov word [bx], 'DO'
    mov word [bx + 2], 'S_'
    mov word [bx + 4], 'FI'
    mov word [bx + 6], 'LE'
    mov word [bx + 8], '_O'
    mov byte [bx + 10], 'K'
    mov byte [bx + 11], 13
    mov byte [bx + 12], 10
    jmp .complete
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
    mov word [bx + 10], 13
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
