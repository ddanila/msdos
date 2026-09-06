; Observe arena/backing totals and a hash of the mixed ROM parent.
bits 16
org 100h
    cmp byte [80h],0
    je observe
    mov ah,0dh
    int 21h
    mov ax,4c00h
    int 21h
observe:
    mov ax,5802h
    int 21h
    jc fail
    mov [old_link],al
    mov ax,5803h
    mov bx,1
    int 21h
    jc fail
    mov ah,52h
    int 21h
    mov ax,[es:bx-2]
    mov cx,1024
arena:
    mov es,ax
    cmp byte [es:0],'M'
    je .valid
    cmp byte [es:0],'Z'
    jne fail
.valid:
    cmp ax,0a000h
    jb .next
    cmp word [es:1],0
    jne .next
    mov dx,[es:3]
    add [upper],dx
    jc fail
.next:
    cmp byte [es:0],'Z'
    je arenas_done
    add ax,[es:3]
    inc ax
    loop arena
    jmp fail
arenas_done:
    mov ax,5803h
    xor bx,bx
    mov bl,[old_link]
    int 21h
    jc fail
    mov ah,42h
    int 67h
    or ah,ah
    jnz fail
    mov [ems_free],bx
    mov [ems_total],dx
    mov ax,0c800h
    mov es,ax
    xor si,si
    xor dx,dx
    mov cx,3000h
hash:
    xor ax,ax
    mov al,[es:si]
    rol dx,1
    xor dx,ax
    inc si
    loop hash
    mov [rom_hash],dx
    mov dx,label_upper
    mov ax,[upper]
    call field
    mov dx,label_free
    mov ax,[ems_free]
    call field
    mov dx,label_total
    mov ax,[ems_total]
    call field
    mov dx,label_rom
    mov ax,[rom_hash]
    call field
    mov dx,passed
    mov ah,09h
    int 21h
    mov ax,4c00h
    int 21h
field:
    push ax
    mov ah,09h
    int 21h
    pop ax
    mov bx,ax
    mov cx,4
.hex:
    rol bx,4
    mov dl,bl
    and dl,15
    add dl,'0'
    cmp dl,'9'
    jbe .emit
    add dl,7
.emit:
    mov ah,02h
    int 21h
    loop .hex
    mov dx,newline
    mov ah,09h
    int 21h
    ret
fail:
    push cs
    pop ds
    mov dx,failed
    mov ah,09h
    int 21h
    mov ax,4c01h
    int 21h
old_link db 0
upper dw 0
ems_free dw 0
ems_total dw 0
rom_hash dw 0
label_upper db 'UMB_SUBPAGE_FREE_PARAS=','$'
label_free db 'UMB_SUBPAGE_EMS_FREE=','$'
label_total db 'UMB_SUBPAGE_EMS_TOTAL=','$'
label_rom db 'UMB_SUBPAGE_ROM_HASH=','$'
newline db 13,10,'$'
passed db 'UMB_SUBPAGE_PROBE_PASS',13,10,'$'
failed db 'UMB_SUBPAGE_PROBE_FAIL',13,10,'$'
