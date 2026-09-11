; SPDX-License-Identifier: MIT
; Wait for the actual editor, then type, save and exit through BIOS keys.
bits 16
org 100h
jmp install
old1c: dd 0
phase: db 0
pause: dw 0
keys: dw 4700h,2c7ah,3c00h,011bh
handler:
 pushf
 push ax
 push bx
 push cx
 push si
 push di
 push ds
 push es
 push cs
 pop ds
 cld
 cmp byte [phase],5
 jae done
 cmp byte [phase],0
 jne ticking
 mov ax,0b800h
 mov es,ax
 mov di,160
 mov si,marker
 mov cx,11
scan:
 lodsb
 cmp al,[es:di]
 jne done
 add di,2
 loop scan
 mov byte [phase],1
 mov word [pause],36
 jmp done
ticking:
 dec word [pause]
 jnz done
 mov ax,40h
 mov es,ax
 mov bx,[es:1ch]
 mov di,bx
 add di,2
 cmp di,3eh
 jb in_range
 mov di,1eh
in_range:
 cmp di,[es:1ah]
 je busy
 xor ax,ax
 mov al,[phase]
 dec ax
 shl ax,1
 mov si,ax
 mov ax,[keys+si]
 mov [es:bx],ax
 mov [es:1ch],di
 inc byte [phase]
 mov word [pause],18
 jmp done
busy:
 mov word [pause],1
done:
 pop es
 pop ds
 pop di
 pop si
 pop cx
 pop bx
 pop ax
 popf
 jmp far [cs:old1c]
marker: db 'DWED_MARKER'
resident_end:
install:
 mov ax,351ch
 int 21h
 mov [old1c],bx
 mov [old1c+2],es
 mov dx,handler
 mov ax,251ch
 int 21h
 mov dx,(resident_end-$$+100h+15)/16
 mov ax,3100h
 int 21h
