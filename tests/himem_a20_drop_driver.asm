; SPDX-License-Identifier: MIT
; Test-only BIOS shim, loaded before HIMEM. Model the IBM AT A20 side effect.
bits 16
cpu 8086
org 0
 dd 0ffffffffh
 dw 8000h
 dw strategy, interrupt
 db 'A20DROP$'
request dd 0
old15 dd 0
armed db 0
strategy:
 mov [cs:request],bx
 mov [cs:request+2],es
 retf
handler:
 cmp ax,0e7f1h
 jne .dispatch
 mov byte [cs:armed],1
 iret
.dispatch:
 cmp byte [cs:armed],0
 je chain
 cmp ah,87h
 jne chain
 jcxz synthetic_error
 pushf
 call far [cs:old15]
 jmp drop
synthetic_error:
 ; A zero-word call is deliberately failed by this fixture.
 mov ah,2
 stc
drop:
 pushf
 push ax
 in al,92h
 and al,0fch
 out 92h,al
 pop ax
 popf
 retf 2
chain:
 jmp far [cs:old15]
interrupt:
 push ax
 push bx
 push ds
 push es
 les bx,[cs:request]
 mov word [es:bx+3],8103h
 cmp byte [es:bx+2],0
 jne done
 pushf
 cli
 xor ax,ax
 mov ds,ax
 mov ax,[54h]
 mov [cs:old15],ax
 mov ax,[56h]
 mov [cs:old15+2],ax
 mov word [54h],handler
 mov [56h],cs
 popf
 mov word [es:bx+3],100h
 mov word [es:bx+14],resident_end
 mov [es:bx+16],cs
done:
 pop es
 pop ds
 pop bx
 pop ax
 retf
resident_end:
