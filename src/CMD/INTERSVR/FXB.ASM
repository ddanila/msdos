bits 16
org 100h

; Temporary receiver installed by INTERSVR /RCOPY through a DEBUG script.

start:
    push cs
    pop ds
    push cs
    pop es
    mov al, [82h]                     ; FXB.COM n
    sub al, '1'
    cmp al, 3
    ja select_done
    xor ah, ah
    shl ax, 1
    mov bx, ax
    mov ax, [com_bases + bx]
    mov [com_port], ax
select_done:
    mov dx, header
    mov cx, 5
    call read_exact
    jc failed
    cmp word [header], 5249h           ; "IR"
    jne failed
    cmp word [header + 2], 5043h       ; "CP"
    jne failed
    mov al, [header + 4]
    mov [files_left], al

next_file:
    cmp byte [files_left], 0
    je complete
    mov dx, file_header
    mov cx, 16
    call read_exact
    jc failed
    mov si, file_header
    mov di, file_name
    mov cx, 12
    rep movsb
    mov byte [di], 0
    mov dx, file_name
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc failed
    mov [file_handle], ax
    mov ax, [file_header + 12]
    mov [bytes_low], ax
    mov ax, [file_header + 14]
    mov [bytes_high], ax
    mov word [checksum], 0
    mov al, 06h
    call write_control

receive_block:
    mov ax, [bytes_low]
    or ax, [bytes_high]
    jz file_received
    mov cx, 16
    cmp word [bytes_high], 0
    jne have_block
    cmp ax, cx
    jae have_block
    mov cx, ax
have_block:
    push cx
    mov dx, buffer
    call read_exact
    pop cx
    jc close_failed
    push cx
    mov si, buffer
sum_block:
    lodsb
    xor ah, ah
    add [checksum], ax
    loop sum_block
    pop cx
    push cx
    mov bx, [file_handle]
    mov dx, buffer
    mov ah, 40h
    int 21h
    pop cx
    jc close_failed
    cmp ax, cx
    jne close_failed
    sub [bytes_low], cx
    sbb word [bytes_high], 0
    mov al, 06h
    call write_control
    jmp receive_block

file_received:
    mov bx, [file_handle]
    mov ah, 3eh
    int 21h
    mov dx, expected_checksum
    mov cx, 2
    call read_exact
    jc failed
    mov ax, [expected_checksum]
    cmp ax, [checksum]
    jne failed
    mov al, 06h
    call write_control
    dec byte [files_left]
    jmp next_file

close_failed:
    mov bx, [file_handle]
    mov ah, 3eh
    int 21h
failed:
    mov al, 15h
    call write_control
    mov ax, 4c01h
    int 21h

complete:
    mov al, 04h
    call write_control
    mov dx, self_name
    mov ah, 41h
    int 21h
    mov ax, 4c00h
    int 21h

; Read directly from the selected UART. DOS console handles are cooked even
; after CTTY and therefore cannot carry an arbitrary executable byte stream.
read_exact:
    push ax
    push bx
    push si
    mov si, dx
read_more:
    mov dx, [com_port]
    add dx, 5
read_ready:
    in al, dx
    test al, 1
    jz read_ready
    mov dx, [com_port]
    in al, dx
    mov [si], al
    inc si
    loop read_more
    clc
read_return:
    pop si
    pop bx
    pop ax
    ret

write_control:
    push dx
    push ax
    mov ah, al
    mov dx, [com_port]
    add dx, 5
write_ready:
    in al, dx
    test al, 20h
    jz write_ready
    mov dx, [com_port]
    mov al, ah
    out dx, al
    pop ax
    pop dx
    ret

ack db 06h
nak db 15h
done db 04h
com_port dw 03f8h
com_bases dw 03f8h, 02f8h, 03e8h, 02e8h
self_name db 'FXB.COM', 0
files_left db 0
file_handle dw 0
bytes_low dw 0
bytes_high dw 0
checksum dw 0
expected_checksum dw 0
header times 5 db 0
file_header times 16 db 0
file_name times 13 db 0
buffer times 512 db 0
