bits 16
org 100h

mov ax, 0e900h
int 2fh
%ifdef EXPECT_INSTALLED
cmp ax, 0ff00h
jne fail
cmp bx, 0
jne fail
%ifdef EXPECT_PARALLEL
cmp dh, 1
jne fail
cmp dl, 1
jne fail
%endif
%ifdef EXPECT_ZERO_DRIVES
cmp cx, 0
jne fail
mov ax, 0e904h
xor bx, bx
int 2fh
cmp ax, 0ff00h
je fail
mov ax, 0e903h
xor bx, bx
mov bh, 0ffh
int 2fh
cmp ax, 0ff00h
je fail
%else
cmp cx, 2
jne fail
%endif
%ifdef EXPECT_PRINTER_OFF
cmp si, 0
jne fail
%endif
%ifdef DO_RECONNECT
mov ax, 0e901h
int 2fh
cmp ax, 0ff00h
jne fail
%endif
%else
cmp ax, 0ff00h
je fail
%endif
mov si, pass_message
jmp short print
fail:
mov si, fail_message
print:
lodsb
test al, al
jz short done
out 0e9h, al
jmp short print
done:
%ifndef NO_QEMU_EXIT
mov dx, 0f4h
mov ax, 10h
out dx, ax
%endif
mov ax, 4c00h
int 21h

pass_message db 'INTERLNK_OFFLINE_PASS',13,10,0
fail_message db 'INTERLNK_OFFLINE_FAIL',13,10,0
