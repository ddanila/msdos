bits 16
org 100h

; Exercise the DOS 4.x-6.x data layouts that applications, redirectors and
; resident utilities obtain through documented and de-facto public calls.

start:
    push cs
    pop ds

    ; Current PSP and the stable PSP fields used by DOS applications.
    mov ah, 62h
    int 21h
    mov [cs:psp_seg], bx
    mov es, bx
    cmp word [es:0], 20cdh
    jne fail_psp
    cmp word [es:50h], 21cdh
    jne fail_psp
    cmp byte [es:52h], 0cbh
    jne fail_psp
    cmp word [es:32h], 20
    jb fail_psp
    cmp word [es:36h], 0
    je fail_psp
    mov ax, [es:2]
    cmp ax, bx
    jbe fail_psp

    ; The process-owning MCB immediately precedes the PSP.
    dec bx
    mov es, bx
    cmp byte [es:0], 'M'
    je .mcb_type_ok
    cmp byte [es:0], 'Z'
    jne fail_mcb
.mcb_type_ok:
    mov ax, [cs:psp_seg]
    cmp [es:1], ax
    jne fail_mcb
    mov ax, [es:3]
    add ax, bx
    inc ax
    cmp ax, [cs:psp_seg]
    jbe fail_mcb

    ; AH=52h returns SYSINITVAR (the List of Lists base in DOS 4+).
    mov ah, 52h
    int 21h
    mov [cs:lol_off], bx
    mov [cs:lol_seg], es
    cmp word [es:bx+16], 128
    jb fail_lol_maxsec
    cmp byte [es:bx+33], 1
    jb fail_lol_cds
    cmp word [es:bx+38], 8004h       ; character device + NUL bit
    jne fail_lol_attr
    cmp byte [es:bx+44], 'N'
    jne fail_lol_name
    cmp byte [es:bx+45], 'U'
    jne fail_lol_name
    cmp byte [es:bx+46], 'L'
    jne fail_lol_name

%ifdef DPB_SPLIT_ONLY
    ; The two floppy letters occupy DOS's reserved low DPBs. The test's two
    ; partitioned hard disks exercise the cross-segment link and two records in
    ; the BIOS overflow store without depending on private absolute addresses.
    les di, [es:bx]
    xor si, si
.split_dpb_loop:
    mov byte [cs:split_step], 1
    mov ax, si
    cmp byte [es:di], al
    jne fail_dpb_split
    mov ax, es
    cmp si, 0
    jne .split_second
    mov [cs:low_dpb_seg], ax
    mov [cs:low_dpb_off], di
    jmp .split_next
.split_second:
    cmp si, 1
    jne .split_overflow
    mov byte [cs:split_step], 2
    cmp ax, [cs:low_dpb_seg]
    jne fail_dpb_split
    mov ax, [cs:low_dpb_off]
    add ax, 33
    cmp di, ax
    jne fail_dpb_split
    jmp .split_next
.split_overflow:
    cmp si, 2
    jne .split_fourth
    mov byte [cs:split_step], 3
    mov [cs:overflow_dpb_seg], ax
    mov [cs:overflow_dpb_off], di
    cmp ax, [cs:low_dpb_seg]
    jne .split_next
    mov ax, [cs:low_dpb_off]
    add ax, 66
    cmp di, ax
    je fail_dpb_split
    jmp .split_next
.split_fourth:
    mov byte [cs:split_step], 4
    cmp ax, [cs:overflow_dpb_seg]
    jne fail_dpb_split
    mov ax, [cs:overflow_dpb_off]
    add ax, 33
    cmp di, ax
    jne fail_dpb_split
.split_next:
    inc si
    cmp si, 4
    je .split_dpb_done
    mov byte [cs:split_step], 5
    cmp word [es:di+25], 0ffffh
    je fail_dpb_split
    les di, [es:di+25]
    jmp .split_dpb_loop
.split_dpb_done:
    jmp pass
%endif

    ; Current-drive DPB returned by AH=32h and the same pointer in the LoL.
    mov dl, 0
    mov ah, 32h
    int 21h
    cmp al, 0ffh
    je fail_dpb_call
    mov [cs:dpb_off], bx
    mov [cs:dpb_seg], ds
    mov ah, 19h
    int 21h
    cmp [ds:bx], al
    jne fail_dpb_drive
    cmp word [ds:bx+2], 512
    jne fail_dpb_sector
    cmp byte [ds:bx+8], 1
    jb fail_dpb_fat
    cmp word [ds:bx+18], 0
    je fail_dpb_driver
    cmp word [ds:bx+20], 0
    je fail_dpb_driver
    mov es, [cs:lol_seg]
    mov di, [cs:lol_off]
    les di, [es:di]
    mov cx, 26
.dpb_chain:
    mov ax, [cs:dpb_off]
    cmp di, ax
    jne .dpb_next
    mov ax, [cs:dpb_seg]
    mov dx, es
    cmp dx, ax
    je .dpb_link_ok
.dpb_next:
    cmp word [es:di+25], 0ffffh
    je fail_dpb_lol
    les di, [es:di+25]
    loop .dpb_chain
    jmp fail_dpb_lol
.dpb_link_ok:

    ; Current CDS: X:\ prefix, in-use/local flags, and matching DPB pointer.
    mov ah, 19h
    int 21h
    xor ah, ah
    mov cx, 88
    mul cx
    mov es, [cs:lol_seg]
    mov di, [cs:lol_off]
    les di, [es:di+22]
    add di, ax
    mov al, [es:di]
    and al, 0dfh
    mov ah, 19h
    int 21h
    add al, 'A'
    cmp [es:di], al
    jne fail_cds
    cmp byte [es:di+1], ':'
    jne fail_cds
    cmp byte [es:di+2], 5ch
    jne fail_cds
    test word [es:di+67], 4000h
    jz fail_cds
    mov ax, [cs:dpb_off]
    cmp [es:di+69], ax
    jne fail_cds
    mov ax, [cs:dpb_seg]
    cmp [es:di+71], ax
    jne fail_cds

    ; Create an open file and map its JFT byte through the SFT chain.
    push cs
    pop ds
    mov dx, probe_name
    xor cx, cx
    mov ah, 3ch
    int 21h
    jc fail_sft
    mov [cs:handle], ax
    mov bx, ax
    mov dx, payload
    mov cx, 4
    mov ah, 40h
    int 21h
    jc fail_sft_close
    cmp ax, 4
    jne fail_sft_close

    mov es, [cs:psp_seg]
    mov bx, [cs:handle]
    cmp bx, [es:32h]
    jae fail_sft_close
    les di, [es:34h]
    add di, bx
    xor ax, ax
    mov al, [es:di]
    cmp al, 0ffh
    je fail_sft_close
    mov [cs:sft_index], ax
    les di, [cs:lol_ptr]
    les di, [es:di+4]
.sft_table:
    mov cx, [es:di+4]
    cmp [cs:sft_index], cx
    jb .sft_found_table
    sub [cs:sft_index], cx
    cmp word [es:di], 0ffffh
    je fail_sft_close
    les di, [es:di]
    jmp .sft_table
.sft_found_table:
    add di, 6
    mov ax, [cs:sft_index]
    mov cx, 59
    mul cx
    add di, ax
    cmp word [es:di], 1
    jb fail_sft_close
    test word [es:di+5], 0080h
    jnz fail_sft_close
    cmp word [es:di+17], 4
    jne fail_sft_close
    cmp word [es:di+19], 0
    jne fail_sft_close
    mov si, sft_name
    mov cx, 11
.name_loop:
    mov al, [cs:si]
    cmp [es:di+32], al
    jne fail_sft_close
    inc si
    inc di
    loop .name_loop

    ; AL=6 exposes the swappable DOS data area. It must contain the PSP,
    ; current DTA and current drive at the DOS 4+ offsets.
    mov bx, [cs:handle]
    mov ah, 3eh
    int 21h
    push cs
    pop ds
    mov ax, 5d06h
    int 21h
    cmp cx, 16
    jb fail_sda
    cmp dx, 1
    jb fail_sda
    mov ax, [cs:psp_seg]
    cmp [ds:si+16], ax
    jne fail_sda
    mov ah, 2fh
    int 21h
    cmp [ds:si+12], bx
    jne fail_sda
    mov ax, es
    cmp [ds:si+14], ax
    jne fail_sda

    ; The NUL header anchors a finite device chain ending in FFFF:FFFF.
    les di, [cs:lol_ptr]
    add di, 34
    mov cx, 32
.device_loop:
    mov ax, [es:di]
    mov dx, [es:di+2]
    cmp ax, 0ffffh
    jne .device_next
    jmp pass
.device_next:
    or dx, dx
    jz fail_device
    mov di, ax
    mov es, dx
    loop .device_loop
    jmp fail_device

pass:
    push cs
    pop ds
    mov dx, pass_message
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

fail_sft_close:
    push cs
    pop ds
    mov bx, [cs:handle]
    mov ah, 3eh
    int 21h
fail_sft:       mov dx, fail_sft_msg
                jmp fail
fail_psp:       mov dx, fail_psp_msg
                jmp fail
fail_mcb:       mov dx, fail_mcb_msg
                jmp fail
fail_lol:       mov dx, fail_lol_msg
                jmp fail
fail_lol_maxsec: mov dx, fail_lol_maxsec_msg
                jmp fail
fail_lol_cds:   mov dx, fail_lol_cds_msg
                jmp fail
fail_lol_attr:  mov dx, fail_lol_attr_msg
                jmp fail
fail_lol_name:  mov dx, fail_lol_name_msg
                jmp fail
fail_dpb:       mov dx, fail_dpb_msg
                jmp fail
fail_dpb_call:  mov dx, fail_dpb_call_msg
                jmp fail
fail_dpb_drive: mov dx, fail_dpb_drive_msg
                jmp fail
fail_dpb_sector: mov dx, fail_dpb_sector_msg
                jmp fail
fail_dpb_fat:   mov dx, fail_dpb_fat_msg
                jmp fail
fail_dpb_driver: mov dx, fail_dpb_driver_msg
                jmp fail
fail_dpb_split: push cs
                pop ds
                mov dx, fail_dpb_split_msg
                mov ah, 09h
                int 21h
                mov dl, [split_step]
                add dl, '0'
                mov ah, 02h
                int 21h
                mov dl, ' '
                int 21h
                mov ax, [low_dpb_seg]
                call print_hex
                mov dl, ' '
                mov ah, 02h
                int 21h
                mov ax, es
                call print_hex
                mov dx, newline
                jmp fail
fail_dpb_lol:   mov dx, fail_dpb_lol_msg
                push es
                push di
                push cs
                pop ds
                mov ah, 09h
                int 21h
                mov ax, [cs:dpb_seg]
                call print_hex
                mov dl, ':'
                mov ah, 02h
                int 21h
                mov ax, [cs:dpb_off]
                call print_hex
                mov dl, ' '
                mov ah, 02h
                int 21h
                pop ax
                call print_hex
                mov dl, ':'
                mov ah, 02h
                int 21h
                pop ax
                call print_hex
                mov dx, newline
                jmp fail
fail_cds:       mov dx, fail_cds_msg
                jmp fail
fail_sda:       mov dx, fail_sda_msg
                jmp fail
fail_device:    mov dx, fail_device_msg
fail:
    push cs
    pop ds
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

print_hex:
    push ax
    push bx
    push cx
    push dx
    mov bx, ax
    mov cx, 4
.digit:
    rol bx, 4
    mov dl, bl
    and dl, 0fh
    add dl, '0'
    cmp dl, '9'
    jbe .emit
    add dl, 7
.emit:
    mov ah, 02h
    int 21h
    loop .digit
    pop dx
    pop cx
    pop bx
    pop ax
    ret

psp_seg dw 0
lol_ptr:
lol_off dw 0
lol_seg dw 0
dpb_off dw 0
dpb_seg dw 0
low_dpb_seg dw 0
low_dpb_off dw 0
overflow_dpb_seg dw 0
overflow_dpb_off dw 0
split_step db 0
handle dw 0ffffh
sft_index dw 0
probe_name db 'SFTPROBE.DAT',0
sft_name db 'SFTPROBE', 'DAT'
payload db 'SFT!'
pass_message db 'INTERNAL_STRUCTURES_PASS',13,10,'$'
fail_psp_msg db 'PSP_LAYOUT_FAIL',13,10,'$'
fail_mcb_msg db 'MCB_LAYOUT_FAIL',13,10,'$'
fail_lol_msg db 'LOL_LAYOUT_FAIL',13,10,'$'
fail_lol_maxsec_msg db 'LOL_MAXSEC_FAIL',13,10,'$'
fail_lol_cds_msg db 'LOL_CDS_COUNT_FAIL',13,10,'$'
fail_lol_attr_msg db 'LOL_NUL_ATTR_FAIL',13,10,'$'
fail_lol_name_msg db 'LOL_NUL_NAME_FAIL',13,10,'$'
fail_dpb_msg db 'DPB_LAYOUT_FAIL',13,10,'$'
fail_dpb_call_msg db 'DPB_CALL_FAIL',13,10,'$'
fail_dpb_drive_msg db 'DPB_DRIVE_FAIL',13,10,'$'
fail_dpb_sector_msg db 'DPB_SECTOR_FAIL',13,10,'$'
fail_dpb_fat_msg db 'DPB_FAT_FAIL',13,10,'$'
fail_dpb_driver_msg db 'DPB_DRIVER_FAIL',13,10,'$'
fail_dpb_split_msg db 'DPB_SPLIT_LAYOUT_FAIL',13,10,'$'
fail_dpb_lol_msg db 'DPB_LOL_LINK_FAIL',13,10,'$'
fail_cds_msg db 'CDS_LAYOUT_FAIL',13,10,'$'
fail_sft_msg db 'SFT_LAYOUT_FAIL',13,10,'$'
fail_sda_msg db 'SDA_LAYOUT_FAIL',13,10,'$'
fail_device_msg db 'DEVICE_CHAIN_FAIL',13,10,'$'
newline db 13,10,'$'
