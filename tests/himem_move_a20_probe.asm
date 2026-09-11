; SPDX-License-Identifier: MIT
; QEMU regression paired with himem_a20_drop_driver.asm.
bits 16
cpu 8086
org 100h
 mov ax,00e3h
 xor dx,dx
 int 14h
 mov ax,4310h
 int 2fh
 mov [entry],bx
 mov [entry+2],es
 mov ah,7
 call far [entry]
 mov [initial],al
 mov ah,9
 mov dx,16
 call far [entry]
 cmp ax,1
 jne fail
 mov [handle],dx
 ; Arm fault injection only after DOS/HMA startup has completed.
 mov ax,0e7f1h
 int 15h
 mov byte [wanted],1
cycle:
 call set_gate
 call check_gate
 push ds
 pop es
 mov di,buffer
 mov ax,0a55ah
 mov cx,8192
 rep stosw
 mov word [descriptor],4000h
 mov word [descriptor+2],0
 mov word [descriptor+4],0
 mov word [descriptor+6],buffer
 mov [descriptor+8],ds
 mov ax,[handle]
 mov [descriptor+10],ax
 mov word [descriptor+12],0
 mov word [descriptor+14],0
 mov si,descriptor
 mov ah,0bh
 call far [entry]
 cmp ax,1
 jne fail
 call check_gate
 mov di,buffer
 xor ax,ax
 mov cx,8192
 rep stosw
 mov ax,[handle]
 mov [descriptor+4],ax
 mov word [descriptor+6],0
 mov word [descriptor+8],0
 mov word [descriptor+10],0
 mov word [descriptor+12],buffer
 mov [descriptor+14],ds
 mov si,descriptor
 mov ah,0bh
 call far [entry]
 cmp ax,1
 jne fail
 call check_gate
 mov di,buffer
 mov ax,0a55ah
 mov cx,8192
 repe scasw
 jne fail
 ; Direct BIOS calls must preserve A20 and the chained BIOS result too.
 mov ax,ds
 xor dx,dx
 mov cl,12
 mov dx,ax
 shr dx,cl
 mov cl,4
 shl ax,cl
 add ax,buffer
 adc dx,0
 mov [gdt+12h],ax
 mov [gdt+14h],dl
 add ax,4000h
 adc dx,0
 mov [gdt+1ah],ax
 mov [gdt+1ch],dl
 mov word [buffer+4000h],0
 mov si,gdt
 mov cx,128
 mov word [expected_if],200h
 sti
 mov ah,87h
 int 15h
 jc fail
 or ah,ah
 jnz fail
 call check_if
 call check_gate
 cmp word [buffer+4000h],0a55ah
 jne fail
 mov bx,55aah
 mov dx,0cafeh
 xor cx,cx
 mov si,gdt
 mov word [expected_if],0
 cli
 mov ah,87h
 int 15h
 jnc fail
 cmp ah,2
 jne fail
 cmp bx,55aah
 jne fail
 cmp dx,0cafeh
 jne fail
 call check_if
 sti
 call check_gate
 cmp byte [wanted],0
 je passed
 mov byte [wanted],0
 jmp cycle
passed:
 mov al,[initial]
 mov [wanted],al
 call set_gate
 mov dx,[handle]
 mov ah,0ah
 call far [entry]
 cmp ax,1
 jne fail
 mov si,pass_message
 xor bl,bl
 jmp finish
fail:
 mov si,fail_message
 mov bl,1
finish:
 ; Never call DOS on failure: the old HIMEM can have left HMA inaccessible.
 cld
.next:
 lodsb
 or al,al
 jz .exit
 mov ah,1
 xor dx,dx
 int 14h
 jmp .next
.exit:
 mov al,bl
 out 0f4h,al
 cli
 hlt
 jmp .exit
check_if:
 pushf
 pop ax
 and ax,200h
 cmp ax,[expected_if]
 jne fail
 ret
check_gate:
 mov ah,7
 call far [entry]
 cmp al,[wanted]
 jne fail
 ret
set_gate:
 in al,92h
 and al,0fch
 cmp byte [wanted],0
 je .write
 or al,2
.write:
 out 92h,al
 ret
entry dd 0
handle dw 0
initial db 0
wanted db 0
expected_if dw 0
descriptor times 16 db 0
align 2
gdt:
 times 16 db 0
 dw 0ffffh,0
 db 0,93h,0,0
 dw 0ffffh,0
 db 0,93h,0,0
 times 16 db 0
pass_message db 'HIMEM_MOVE_A20_PASS',13,10,0
fail_message db 'HIMEM_MOVE_A20_FAIL',13,10,0
buffer:
