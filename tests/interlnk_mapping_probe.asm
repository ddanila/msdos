bits 16
org 100h

mov ax, 0e904h
xor bx, bx
int 2fh
cmp ax, 0ff00h
jne fail
cmp dl, 2                       ; first client drive is C:
jne fail
cmp dh, 1                       ; C: now maps server B:
jne fail

mov ax, 0e904h
mov bl, 1
int 2fh
cmp ax, 0ff00h
jne fail
cmp dl, 3                       ; second client drive is D:
jne fail
cmp dh, 0ffh                    ; D: redirection was cancelled
jne fail

mov dx, remote_name
mov ax, 3d00h
int 21h
jc fail
mov bx, ax
mov dx, buffer
mov cx, payload_end - payload
mov ah, 3fh
int 21h
jc fail_close
cmp ax, payload_end - payload
jne fail_close
mov si, payload
mov di, buffer
mov cx, payload_end - payload
repe cmpsb
jne fail_close
mov ah, 3eh
int 21h

mov ax, 0e900h
int 2fh
cmp ax, 0ff00h
jne fail
cmp bx, 1
jne fail
cmp cx, 2
jne fail
cmp dx, 2
jne fail
cmp si, 1
jne fail

mov ax, 0e903h
mov bx, 0002h                  ; restore C:=A:
int 2fh
cmp ax, 0ff00h
jne fail
mov ax, 0e903h
mov bx, 0103h                  ; restore D:=B:
int 2fh
cmp ax, 0ff00h
jne fail
mov ax, 0e900h
int 2fh
cmp bx, 1
jne fail
cmp cx, 2
jne fail
cmp dx, 2
jne fail
cmp si, 1
jne fail
mov ax, 0e904h
xor bx, bx
int 2fh
cmp dh, 0
jne fail
mov ax, 0e904h
mov bl, 1
int 2fh
cmp dh, 1
jne fail

mov si, pass_message
jmp short print

fail_close:
mov ah, 3eh
int 21h
fail:
mov si, fail_message
print:
lodsb
test al, al
jz short done
out 0e9h, al
jmp short print
done:
mov ax, 4c00h
int 21h

remote_name db 'C:\REMOTE2.TXT',0
payload db 'Second Interlnk volume',13,10
payload_end:
buffer times payload_end - payload db 0
pass_message db 'INTERLNK_MAPPING_PASS',13,10,0
fail_message db 'INTERLNK_MAPPING_FAIL',13,10,0
