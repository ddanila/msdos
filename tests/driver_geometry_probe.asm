bits 16
org 100h

%ifndef EXPECT_TYPE
%error EXPECT_TYPE is required
%endif
%ifndef EXPECT_TRACKS
%error EXPECT_TRACKS is required
%endif
%ifndef EXPECT_SPT
%error EXPECT_SPT is required
%endif
%ifndef EXPECT_HEADS
%error EXPECT_HEADS is required
%endif
%ifndef EXPECT_TOTAL
%error EXPECT_TOTAL is required
%endif

    mov bx, 3                   ; DRIVER.SYS adds logical drive C
    mov cx, 0860h               ; generic IOCTL: get device parameters
    mov dx, parameters
    mov ax, 440dh
    int 21h
    jc fail
    cmp byte [parameters+1], EXPECT_TYPE
    jne fail
    cmp word [parameters+4], EXPECT_TRACKS
    jne fail
    cmp word [parameters+15], EXPECT_TOTAL
    jne fail
    cmp word [parameters+20], EXPECT_SPT
    jne fail
    cmp word [parameters+22], EXPECT_HEADS
    jne fail
    mov dx, pass_message
    jmp short print
fail:
    xor ax, ax
    mov al, [parameters+1]
    call print_hex
    mov ax, [parameters+4]
    call print_hex
    mov ax, [parameters+15]
    call print_hex
    mov ax, [parameters+20]
    call print_hex
    mov ax, [parameters+22]
    call print_hex
    mov dx, fail_message
print:
    mov ah, 09h
    int 21h
    mov dx, 0f4h
    mov ax, 10h
    out dx, ax
    mov ax, 4c00h
    int 21h

print_hex:
    mov cx, 4
.digit:
    rol ax, 4
    mov dl, al
    and dl, 0fh
    add dl, '0'
    cmp dl, '9'
    jbe .emit
    add dl, 7
.emit:
    push ax
    mov ah, 02h
    int 21h
    pop ax
    loop .digit
    mov dl, ' '
    mov ah, 02h
    int 21h
    ret

parameters times 64 db 0
pass_message db 'DRIVER_GEOMETRY_PASS', 13, 10, '$'
fail_message db 'DRIVER_GEOMETRY_FAIL', 13, 10, '$'
