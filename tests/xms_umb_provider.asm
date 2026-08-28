bits 16
org 0

%ifndef TEST_MODE
%define TEST_MODE 0
%endif

device_header:
    dd 0ffffffffh
    dw 8000h
    dw strategy
    dw interrupt
    db 'XMSUMB$ '

request_offset dw 0
request_segment dw 0
old_int2f dd 0
extent_index db 0
allocation_count dw 0
release_count dw 0
first_mcb dw 0
saved_tail dw 0
saved_tail_size dw 0
ram_prepared db 0

strategy:
    mov [cs:request_offset], bx
    mov [cs:request_segment], es
    retf

interrupt:
    push ax
    push bx
    push dx
    push ds
    push es
    push di
    mov ax, [cs:request_segment]
    mov es, ax
    mov di, [cs:request_offset]
    cmp byte [es:di + 2], 0
    jne .unsupported

    mov ah, 52h
    int 21h
    mov ax, [es:bx - 2]
    mov [cs:first_mcb], ax
    mov ax, 352fh
    int 21h
    mov [cs:old_int2f], bx
    mov [cs:old_int2f + 2], es
    push cs
    pop ds
    mov dx, int2f_handler
    mov ax, 252fh
    int 21h
    mov ax, [cs:request_segment]
    mov es, ax
    mov di, [cs:request_offset]
    mov word [es:di + 0eh], resident_end
    mov word [es:di + 10h], cs
    mov word [es:di + 3], 0100h
    jmp short .done

.unsupported:
    mov word [es:di + 3], 8103h
.done:
    pop di
    pop es
    pop ds
    pop dx
    pop bx
    pop ax
    retf

int2f_handler:
    cmp ax, 4300h
    je .installed
    cmp ax, 4310h
    je .control
    jmp far [cs:old_int2f]
.installed:
    call prepare_test_ram
    mov al, 80h
    iret
.control:
    push cs
    pop es
    mov bx, xms_entry
    iret

xms_entry:
    cmp ah, 10h
    je xms_request_umb
    cmp ah, 11h
    je xms_release_umb
    cmp ah, 0f0h
    je xms_test_status
    xor ax, ax
    mov bl, 80h
    retf

xms_request_umb:
%if TEST_MODE = 1
    cmp byte [cs:extent_index], 1
    je .forced_failure
%elif TEST_MODE = 6
    xor ax, ax
    xor dx, dx
    mov bl, 80h
    retf
%endif
    xor ax, ax
    mov al, [cs:extent_index]
    cmp al, EXTENT_COUNT
    jae .none
    shl ax, 1
    mov si, ax
    cmp dx, 0ffffh
    jne .allocate
    xor ax, ax
    mov bl, 0b0h
    mov dx, [cs:extent_sizes + si]
    retf
.allocate:
    cmp dx, [cs:extent_sizes + si]
    jne .smaller
%if TEST_MODE = 9
    xor ax, ax
    mov bl, 0a0h
    retf
%endif
    mov bx, [cs:extent_segments + si]
    inc byte [cs:extent_index]
    inc word [cs:allocation_count]
    mov ax, 1
    retf
.smaller:
    xor ax, ax
    mov bl, 0b0h
    mov dx, [cs:extent_sizes + si]
    retf
.none:
    xor ax, ax
    xor dx, dx
    mov bl, 0b1h
    retf
%if TEST_MODE = 1
.forced_failure:
    xor ax, ax
    xor dx, dx
    mov bl, 0a0h
    retf
%endif

xms_release_umb:
    xor si, si
.find_release:
    cmp si, EXTENT_COUNT * 2
    jae .invalid_release
    cmp dx, [cs:extent_segments + si]
    je .released
    add si, 2
    jmp short .find_release
.released:
    inc word [cs:release_count]
    mov ax, [cs:release_count]
    cmp ax, [cs:allocation_count]
    jne .release_done
    call restore_test_ram
.release_done:
    mov ax, 1
    retf
.invalid_release:
    xor ax, ax
    mov bl, 0b2h
    retf

xms_test_status:
    mov ax, [cs:release_count]
    mov bx, [cs:allocation_count]
    mov cx, TEST_MODE
    retf

prepare_test_ram:
; The test-only provider turns the top 64 KiB of QEMU conventional RAM into a
; synthetic upper arena only after SYSINIT has released its temporary blocks.
    cmp byte [cs:ram_prepared], 0
    jne .done
    push ax
    push bx
    push cx
    push es
    mov ax, [cs:first_mcb]
.next_mcb:
    mov es, ax
    cmp byte [es:0], 'Z'
    je .tail
    add ax, [es:3]
    inc ax
    jmp short .next_mcb
.tail:
    mov [cs:saved_tail], ax
    mov bx, [es:3]
    mov [cs:saved_tail_size], bx
    mov cx, 9000h
    sub cx, ax
    dec cx
    cmp bx, cx
    jb .restore_registers
    mov [es:3], cx
    mov byte [cs:ram_prepared], 1
.restore_registers:
    pop es
    pop cx
    pop bx
    pop ax
.done:
    ret

restore_test_ram:
    cmp byte [cs:ram_prepared], 0
    je .done
    push ax
    push es
    mov ax, [cs:saved_tail]
    mov es, ax
    mov ax, [cs:saved_tail_size]
    mov [es:3], ax
    mov byte [cs:ram_prepared], 0
    pop es
    pop ax
.done:
    ret

%if TEST_MODE = 0
extent_segments dw 09400h, 09000h
extent_sizes dw 0100h, 0200h
EXTENT_COUNT equ 2
%elif TEST_MODE = 1
extent_segments dw 09000h
extent_sizes dw 0200h
EXTENT_COUNT equ 1
%elif TEST_MODE = 2
extent_segments dw 09000h, 09100h
extent_sizes dw 0200h, 0200h
EXTENT_COUNT equ 2
%elif TEST_MODE = 3
extent_segments dw 09000h
extent_sizes dw 0002h
EXTENT_COUNT equ 1
%elif TEST_MODE = 4
extent_segments dw 08000h
extent_sizes dw 0100h
EXTENT_COUNT equ 1
%elif TEST_MODE = 5
extent_segments dw 0
extent_sizes dw 0
EXTENT_COUNT equ 0
%elif TEST_MODE = 6
extent_segments dw 0
extent_sizes dw 0
EXTENT_COUNT equ 0
%elif TEST_MODE = 7
extent_segments dw 09000h, 09004h, 09008h, 0900ch, 09010h, 09014h
                dw 09018h, 0901ch, 09020h, 09024h, 09028h, 0902ch
                dw 09030h, 09034h, 09038h, 0903ch, 09040h
extent_sizes times 17 dw 3
EXTENT_COUNT equ 17
%elif TEST_MODE = 8
extent_segments dw 0fffeh
extent_sizes dw 4
EXTENT_COUNT equ 1
%elif TEST_MODE = 9
extent_segments dw 09000h
extent_sizes dw 0200h
EXTENT_COUNT equ 1
%else
%error Unsupported TEST_MODE
%endif

resident_end:
