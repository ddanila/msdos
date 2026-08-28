bits 16
org 100h

%define ERROR_NOT_ENOUGH_MEMORY 8
%define ERROR_ARENA_TRASHED 7

start:
    cli
    mov sp, stack_top
    sti
    push cs
    pop ds
    push cs
    pop es
    mov bx, (program_end - $$ + 100h + 15) / 16
    mov ah, 4ah
    int 21h
    jc fail_01

    mov ax, 08fffh
    mov es, ax
    cmp byte [es:0], 'M'
    jne fail_02
    cmp word [es:1], 8
    jne fail_02
    cmp word [es:3], 0
    jne fail_02
    mov ax, 09000h
    mov es, ax
    cmp byte [es:0], 'M'
    jne fail_02
    cmp word [es:1], 0
    jne fail_02
    cmp word [es:3], 01feh
    jne fail_02
    mov ax, 091ffh
    mov es, ax
    cmp byte [es:0], 'M'
    jne fail_02
    cmp word [es:1], 8
    jne fail_02
    cmp word [es:3], 0200h
    jne fail_02
    mov ax, 09400h
    mov es, ax
    cmp byte [es:0], 'M'
    jne fail_02
    cmp word [es:1], 0
    jne fail_02
    cmp word [es:3], 00feh
    jne fail_02
    mov ax, 094ffh
    mov es, ax
    cmp byte [es:0], 'Z'
    jne fail_02
    cmp word [es:1], 8
    jne fail_02
    cmp word [es:3], 0
    jne fail_02

    mov bx, 1
    mov ax, 5803h
    int 21h
    jc fail_03
    mov bx, 0040h
    call set_strategy
    jc fail_03
    mov bx, 0300h
    mov ah, 48h
    int 21h
    jnc fail_04
    cmp ax, ERROR_NOT_ENOUGH_MEMORY
    jne fail_04
    cmp bx, 01feh
    jne fail_04

    mov bx, 20h
    call allocate
    jc fail_05
    cmp ax, 09001h
    jne fail_05
    mov [block_a], ax
    mov es, ax
    mov word [es:0], 05aa5h
    mov word [es:01feh], 0a55ah
    xor bx, bx
    mov ax, 5803h
    int 21h
    jc fail_06
    cmp word [es:0], 05aa5h
    jne fail_06
    cmp word [es:01feh], 0a55ah
    jne fail_06
    mov bx, 1
    mov ax, 5803h
    int 21h
    jc fail_06

    mov ax, [block_a]
    mov es, ax
    mov bx, 10h
    mov ah, 4ah
    int 21h
    jc fail_07
    mov ax, es
    dec ax
    mov es, ax
    cmp word [es:3], 10h
    jne fail_07
    inc ax
    mov es, ax
    mov bx, 30h
    mov ah, 4ah
    int 21h
    jc fail_08
    mov ax, es
    dec ax
    mov es, ax
    cmp word [es:3], 30h
    jne fail_08
    inc ax
    mov es, ax
    mov bx, 300h
    mov ah, 4ah
    int 21h
    jnc fail_09
    cmp ax, ERROR_NOT_ENOUGH_MEMORY
    jne fail_09
    cmp bx, 01feh
    jne fail_09
    mov ax, es
    dec ax
    mov es, ax
    cmp word [es:3], 01feh
    jne fail_09
    inc ax
    mov es, ax
    mov ah, 49h
    int 21h
    jc fail_09

    mov bx, 0041h
    call set_strategy
    mov bx, 10h
    call allocate
    jc fail_10
    cmp ax, 09401h
    jne fail_10
    call free_ax
    jc fail_10
    mov bx, 0042h
    call set_strategy
    mov bx, 10h
    call allocate
    jc fail_11
    cmp ax, 094efh
    jne fail_11
    call free_ax
    jc fail_11

    mov bx, 0080h
    call set_strategy
    mov bx, 10h
    call allocate
    jc fail_23
    cmp ax, 09001h
    jne fail_23
    call free_ax
    mov bx, 0081h
    call set_strategy
    mov bx, 10h
    call allocate
    jc fail_23
    cmp ax, 09401h
    jne fail_23
    call free_ax
    mov bx, 0082h
    call set_strategy
    mov bx, 10h
    call allocate
    jc fail_23
    cmp ax, 094efh
    jne fail_23
    call free_ax

    xor bx, bx
.low_strategy_loop:
    push bx
    call set_strategy
    jc fail_24_pop
    mov bx, 10h
    call allocate
    jc fail_24_pop
    cmp ax, 09000h
    jae fail_24_pop
    call free_ax
    pop bx
    inc bx
    cmp bx, 3
    jb .low_strategy_loop

    mov bx, 0040h
    call set_strategy
    mov bx, 01feh
    call allocate
    jc fail_12
    mov [block_a], ax
    cmp ax, 09001h
    jne fail_12
    mov bx, 00feh
    call allocate
    jc fail_12
    mov [block_b], ax
    cmp ax, 09401h
    jne fail_12
    mov bx, 1
    call allocate
    jnc fail_12
    cmp ax, ERROR_NOT_ENOUGH_MEMORY
    jne fail_12
    or bx, bx
    jnz fail_12
    mov ax, [block_b]
    call free_ax
    mov ax, [block_a]
    call free_ax

    mov bx, 20h
    call allocate
    jc fail_13
    mov [block_a], ax
    mov bx, 20h
    call allocate
    jc fail_13
    mov [block_b], ax
    mov bx, 20h
    call allocate
    jc fail_13
    mov [block_c], ax
    mov ax, [block_b]
    call free_ax
    mov bx, 0041h
    call set_strategy
    mov bx, 10h
    call allocate
    jc fail_13
    cmp ax, [block_b]
    jne fail_13
    call free_ax
    mov ax, [block_a]
    call free_ax
    mov ax, [block_c]
    call free_ax

    mov bx, 0040h
    call set_strategy
    mov bx, 10h
    call allocate
    jc fail_14
    mov [block_a], ax
    mov ax, 09011h
    mov es, ax
    mov byte [es:0], 'X'
    mov bx, 1
    call allocate
    jnc fail_14_restore
    cmp ax, ERROR_ARENA_TRASHED
    jne fail_14_restore
    mov byte [es:0], 'M'
    mov ax, [block_a]
    call free_ax
    jmp short corruption_done
fail_14_restore:
    mov byte [es:0], 'M'
    jmp fail_14
corruption_done:

    mov bx, 0080h
    call set_strategy
    mov bx, 0300h
    call allocate
    jc fail_15
    cmp ax, 09000h
    jae fail_15
    call free_ax
    mov bx, 0000h
    call set_strategy
    mov bx, 10h
    call allocate
    jc fail_15
    cmp ax, 09000h
    jae fail_15
    call free_ax

    xor bx, bx
    mov ax, 5803h
    int 21h
    jc fail_16
    mov bx, 0040h
    call set_strategy
    mov bx, 10h
    call allocate
    jc fail_16
    cmp ax, 09000h
    jae fail_16
    call free_ax
    mov bx, 1
    mov ax, 5803h
    int 21h
    jc fail_16

    mov bx, 0040h
    call set_strategy
    push cs
    pop es
    mov bx, exec_parameters
    mov dx, child_name
    mov ax, 4b00h
    int 21h
    jc fail_17
    mov ah, 4dh
    int 21h
    cmp ax, 002ah
    jne fail_18
    mov ax, 09000h
    mov dx, 091ffh
    call verify_free_extent
    jc fail_21
    mov ax, 09400h
    mov dx, 094ffh
    call verify_free_extent
    jc fail_22
    mov bx, 01feh
    call allocate
    jc fail_19
    mov [block_a], ax
    mov bx, 00feh
    call allocate
    jc fail_20
    mov [block_b], ax
    mov ax, [block_b]
    call free_ax
    mov ax, [block_a]
    call free_ax

    mov dx, pass_message
    mov cx, pass_message_end - pass_message
    jmp print_and_exit

allocate:
    mov ah, 48h
    int 21h
    ret
free_ax:
    mov es, ax
    mov ah, 49h
    int 21h
    ret
set_strategy:
    mov ax, 5801h
    int 21h
    ret
verify_free_extent:
    mov es, ax
.next:
    cmp ax, dx
    je .valid
    ja .invalid
    cmp byte [es:0], 'M'
    jne .invalid
    cmp word [es:1], 0
    jne .invalid
    add ax, [es:3]
    inc ax
    mov es, ax
    jmp short .next
.valid:
    clc
    ret
.invalid:
    stc
    ret

%macro fail_label 1
fail_%1:
    mov byte [failure_code], %1
    jmp fail
%endmacro
fail_label 01
fail_label 02
fail_label 03
fail_label 04
fail_label 05
fail_label 06
fail_label 07
fail_label 08
fail_label 09
fail_label 10
fail_label 11
fail_label 12
fail_label 13
fail_label 14
fail_label 15
fail_label 16
fail_label 17
fail_label 18
fail_label 19
fail_label 20
fail_label 21
fail_label 22
fail_label 23
fail_label 24

fail_24_pop:
    pop bx
    jmp fail_24

fail:
    mov al, [failure_code]
    mov ah, al
    and al, 0fh
    shr ah, 1
    shr ah, 1
    shr ah, 1
    shr ah, 1
    add ax, '00'
    cmp ah, '9'
    jbe .high_ready
    add ah, 7
.high_ready:
    cmp al, '9'
    jbe .low_ready
    add al, 7
.low_ready:
    mov [fail_digits], ah
    mov [fail_digits + 1], al
    mov dx, fail_message
    mov cx, fail_message_end - fail_message
print_and_exit:
    mov bx, 1
    mov ah, 40h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

block_a dw 0
block_b dw 0
block_c dw 0
failure_code db 0
child_name db 'UMBCHILD.COM', 0
empty_tail db 0, 13
exec_parameters:
    dw 0
    dw empty_tail, 0
    dw 0, 0
    dw 0, 0
pass_message db 'UMB_LIFECYCLE_PASS', 13, 10
pass_message_end:
fail_message db 'UMB_LIFECYCLE_FAIL_'
fail_digits db '00', 13, 10
fail_message_end:
stack_space times 512 db 0
stack_top:
program_end:
