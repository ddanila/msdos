bits 16
cpu 8086
org 100h
    cld
%ifdef EXPECTED_LANGUAGE
    ; Resident identity is authoritative even when KEYB omits default ID zero
    ; from its human-readable status. Offsets follow CMD/KEYB/KEYBSHAR.INC.
    mov ax,0ad80h
    int 2fh
    cmp ax,0ffffh
    jne fail
    cmp word [es:di+22],EXPECTED_LANGUAGE
    jne fail
    cmp word [es:di+24],EXPECTED_PAGE
    jne fail
    cmp word [es:di+26],EXPECTED_ID
    jne fail
    mov dx,profile_passed
    mov ah,9
    int 21h
    push cs
    pop es
%endif
%ifdef CAPACITY_PROOF
    mov ax,0ad80h
    int 2fh
    cmp ax,0ffffh
    jne fail
    mov ax,[es:di+32] ; KEYB shared-data RESIDENT_END
    cmp ax,0ffffh
    je fail
    push ax
    push es
    mov bx,es
    dec bx
    mov es,bx
    mov bx,[es:3] ; MCB allocation in paragraphs
    pop es
    pop ax
    push ax
    add ax,15
    jc fail
    mov cl,4
    shr ax,cl
    cmp ax,bx
    ja fail
    mov dx,capacity
    mov ah,9
    int 21h
    pop ax
    call hex
    mov dx,newline
    mov ah,9
    int 21h
%endif
%ifdef DOS_INPUT
    ; Replace only this process's stdin with CON; stdout remains serial AUX.
    mov ax,3d00h
    mov dx,console
    int 21h
    jc fail
    mov bx,ax
    xor cx,cx
    mov ah,46h
    int 21h
    jc fail
    mov ah,3eh
    int 21h
%endif
%ifdef INDEX_FROM_ARG
    ; Share identical phase oracles on small legacy disks. Require exactly
    ; one four-digit uppercase hexadecimal starting index.
    cmp byte [80h],5
    jne fail
    cmp byte [81h],' '
    jne fail
    xor bp,bp
    mov si,82h
    mov cx,4
.argument:
    lodsb
    sub al,'0'
    cmp al,9
    jbe .digit
    sub al,7
    cmp al,10
    jb fail
    cmp al,15
    ja fail
.digit:
    xor ah,ah
    shl bp,1
    shl bp,1
    shl bp,1
    shl bp,1
    or bp,ax
    loop .argument
    mov si,expected
%else
    mov si, expected
%ifndef START_INDEX
%define START_INDEX 0
%endif
    mov bp, START_INDEX
%endif
.next:
    mov dx, ready
    mov ah,9
    int 21h
    mov ax,bp
    call hex
    mov dx,newline
    mov ah,9
    int 21h
%ifdef GROUPED_INPUT
    xor dx,dx
    mov dl,[si]
    inc si
    test dx,dx
    jnz .group_nonempty
    ; A zero-output arm step ends with physical Caps on, then Caps off.
    ; This acknowledges the entire key sequence without consuming the accent.
    push es
    mov ax,40h
    mov es,ax
.caps_on:
    test byte [es:17h],40h
    jz .caps_on
    mov dx,armed
    mov ah,9
    int 21h
    mov ax,bp
    call hex
    mov dx,newline
    mov ah,9
    int 21h
.caps_off:
    test byte [es:17h],40h
    jnz .caps_off
    pop es
    jmp .group_done
.group_nonempty:
    push dx
.group_read:
%endif
%ifdef DOS_INPUT
    mov ah,07h
    int 21h
    cmp al,[si]
    jne fail
    test al,al
    jnz .dos_read
    mov ah,07h
    int 21h
    cmp al,[si+1]
    jne fail
.dos_read:
    mov ax,[si]
%else
%ifdef ENHANCED_INPUT
    mov ah,10h
%else
    xor ah,ah
%endif
    int 16h
%endif
    cmp ax,[si]
    jne fail
%ifdef GROUPED_INPUT
    add si,2
    pop dx
    dec dx
    jz .group_done
    push dx
    jmp .group_read
.group_done:
%endif
    ; Let queued break events reach the IRQ handler before checking held bits.
    push ds
    mov ax,40h
    mov ds,ax
    mov bx,[6ch]
.wait:
    mov ax,[6ch]
    sub ax,bx
    cmp ax,2
    jb .wait
    mov al,[17h]
    and al,0fh
    mov ah,[18h]
    and ah,03h
    or al,ah
    mov ah,[96h]
    and ah,0ch
    or al,ah
    pop ds
    test al,al
    jnz fail
%ifdef ENHANCED_INPUT
    mov ah,11h
%else
    mov ah,01h
%endif
    int 16h
    jnz fail
%ifndef GROUPED_INPUT
    add si,2
%endif
    inc bp
    cmp si,expected_end
    jb .next
    mov dx,passed
    mov ah,9
    int 21h
    mov ax,4c00h
    int 21h
fail:
    push ax
    mov dx,failed
    mov ah,9
    int 21h
    pop ax
    call hex
    mov dx,newline
    mov ah,9
    int 21h
    mov ax,4c01h
    int 21h
hex:
    push bx
    push cx
    mov bx,ax
    mov cx,4
.digit:
    rol bx,1
    rol bx,1
    rol bx,1
    rol bx,1
    mov dl,bl
    and dl,15
    add dl,'0'
    cmp dl,'9'
    jbe .print
    add dl,7
.print:
    mov ah,2
    int 21h
    loop .digit
    pop cx
    pop bx
    ret
%ifdef CAPACITY_PROOF
capacity db 'KEYB_CAPACITY ', '$'
%endif
console db 'CON',0
%ifdef GROUPED_INPUT
armed db 'RU_KEY_ARMED ', '$'
%endif
ready db 'RU_KEY_READY ', '$'
passed db 'RU_KEY_PASS',13,10,'$'
failed db 'RU_KEY_FAIL actual=', '$'
newline db 13,10,'$'
expected: incbin 'expected.bin'
expected_end:

%ifdef EXPECTED_LANGUAGE
profile_passed db 'KEYB_PROFILE_PASS',13,10,'$'
%endif
