bits 16
org 100h

mov ax, 0e905h
int 2fh
cmp ax, 0ff00h
jne fail
%ifdef EXPECT_HIGH
cmp bx, 0a000h
jb fail
%else
cmp bx, 0a000h
jae fail
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
mov dx, 0f4h
mov ax, 10h
out dx, ax
mov ax, 4c00h
int 21h

pass_message db 'INTERLNK_PLACEMENT_PASS',13,10,0
fail_message db 'INTERLNK_PLACEMENT_FAIL',13,10,0
