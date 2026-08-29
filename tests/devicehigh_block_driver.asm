bits 16
org 0

header:
    dd 0ffffffffh
    dw 0000h                       ; block device
    dw strategy
    dw interrupt
    times 8 db 0

strategy:
    mov [cs:request_offset], bx
    mov [cs:request_segment], es
    retf

interrupt:
    push ax
    push bx
    push ds
    lds bx, [cs:request_offset]
    mov al, [bx + 2]
    cmp al, 0
    je .init
    cmp al, 13
    je .done
    cmp al, 14
    je .done
    mov word [bx + 3], 8103h       ; unknown command
    jmp short .return
.init:
    mov byte [bx + 13], 1
    mov word [bx + 14], resident_end
    mov word [bx + 16], cs
    mov word [bx + 18], bpb_array
    mov word [bx + 20], cs
.done:
    mov word [bx + 3], 0100h
.return:
    pop ds
    pop bx
    pop ax
    retf

request_offset  dw 0
request_segment dw 0
bpb_array       dw bpb
bpb:
    dw 128                         ; bytes per sector
    db 1                           ; sectors per cluster
    dw 1                           ; reserved sectors
    db 1                           ; FATs
    dw 16                          ; root entries
    dw 16                          ; total sectors
    db 0feh                        ; media descriptor
    dw 1                           ; sectors per FAT

resident_end:
