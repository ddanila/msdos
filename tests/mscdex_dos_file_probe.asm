bits 16
org 100h

start:
    push cs
    pop ds
    mov dx, filename
    mov ax, 3d00h
    int 21h
    jc fail_open
    mov [handle], ax
    mov bx, ax
    mov ax, 1220h
    int 2fh
    jc fail_sft
    xor bx, bx
    mov bl, [es:di]
    mov ax, 1216h
    int 2fh
    jc fail_sft
    test word [es:di + 5], 8000h
    jz fail_sft_flags
    cmp word [es:di + 17], 13
    jne fail_sft_size
    cmp word [es:di + 19], 0
    jne fail_sft
    mov bx, [handle]
    xor cx, cx
    xor dx, dx
    mov ax, 4202h
    int 21h
    jc fail_size
    or dx, dx
    jnz fail_size
    cmp ax, 13
    jne fail_size
    xor cx, cx
    xor dx, dx
    mov ax, 4200h
    int 21h
    jc fail_seek
    mov bx, [handle]
    mov dx, buffer
    mov cx, 13
    mov ah, 3fh
    int 21h
    jc fail_read_carry
    cmp ax, 13
    je read_count_ok
    or ax, ax
    jz fail_read_zero
    jmp fail_read_count
read_count_ok:
    push ds
    pop es
    mov si, buffer
    mov di, expected
    mov cx, 13
    repe cmpsb
    jne fail_data
    mov bx, [handle]
    xor cx, cx
    xor dx, dx
    mov ax, 4200h
    int 21h
    jc fail_seek
    mov bx, [handle]
    mov ah, 3eh
    int 21h
    jc fail_close
    mov dx, pass_message
    mov ah, 9
    int 21h
    mov ax, 4c00h
    int 21h

fail_open:
    mov dx, open_message
    jmp short failed
fail_read_carry:
    mov dx, read_carry_message
    jmp short failed
fail_read_count:
    mov dx, read_count_message
    jmp short failed
fail_read_zero:
    mov dx, read_zero_message
    jmp short failed
fail_data:
    mov dx, data_message
    jmp short failed
fail_seek:
    mov dx, seek_message
    jmp short failed
fail_size:
    mov dx, size_message
    jmp short failed
fail_sft:
    push cs
    pop ds
    mov dx, sft_message
    jmp short failed
fail_sft_flags:
    push cs
    pop ds
    mov dx, sft_flags_message
    jmp short failed
fail_sft_size:
    push cs
    pop ds
    mov dx, sft_size_message
    jmp short failed
fail_close:
    mov dx, close_message
failed:
    mov ah, 9
    int 21h
    mov ax, 4c01h
    int 21h

filename db 'E:\README.TXT',0
expected db 'DOS_FILE_OK',13,10
handle dw 0
buffer times 32 db 0
pass_message db 'MSCDEX_DOS_FILE_PASS',13,10,'$'
open_message db 'MSCDEX_DOS_OPEN_FAIL',13,10,'$'
read_carry_message db 'MSCDEX_DOS_READ_CARRY_FAIL',13,10,'$'
read_count_message db 'MSCDEX_DOS_READ_COUNT_FAIL',13,10,'$'
read_zero_message db 'MSCDEX_DOS_READ_ZERO_FAIL',13,10,'$'
data_message db 'MSCDEX_DOS_DATA_FAIL',13,10,'$'
seek_message db 'MSCDEX_DOS_SEEK_FAIL',13,10,'$'
size_message db 'MSCDEX_DOS_SIZE_FAIL',13,10,'$'
sft_message db 'MSCDEX_DOS_SFT_FAIL',13,10,'$'
sft_flags_message db 'MSCDEX_DOS_SFT_FLAGS_FAIL',13,10,'$'
sft_size_message db 'MSCDEX_DOS_SFT_SIZE_FAIL',13,10,'$'
close_message db 'MSCDEX_DOS_CLOSE_FAIL',13,10,'$'
