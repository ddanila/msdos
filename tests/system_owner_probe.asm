; Conventional MCB, DOS DEVMARK and SFT census. No DR-DOS internals.
; POISON_LOW_SFT is an explicit our-kernel-only disposable-guest experiment.
bits 16
org 100h
start:
    push cs
    pop ds
    call sft_census
    mov ah,52h
    int 21h
    mov bp,[es:bx-2]
    mov cx,512
.arena:
    cmp bp,70h
    jb fail
    cmp bp,0a000h
    jae done
    mov es,bp
    mov al,[es:0]
    cmp al,'M'
    je .valid
    cmp al,'Z'
    jne fail
.valid:
    mov di,bp
    add di,[es:3]
    jc fail
    inc di
    jz fail
    mov dx,mcb
    call print
    mov ax,bp
    call hex
    mov ax,[es:1]
    call hex
    mov ax,[es:3]
    call hex
    call newline
    cmp word [es:1],8
    jne .next
    push bp
    inc bp
.sub:
    cmp bp,di
    jae .sub_done
    mov es,bp
    mov ax,bp
    inc ax
    cmp ax,[es:1]             ; DEVMARK_SEG points just past its header
    jne .gap
    add ax,[es:3]
    jc .gap
    cmp ax,di
    ja .gap
    mov si,ax
    mov dx,submark
    call print
    mov ax,bp
    call hex
    xor ax,ax
    mov al,[es:0]
    call hex
    mov ax,[es:1]
    call hex
    mov ax,[es:3]
    call hex
    call newline
    mov bp,si
    jmp .sub
.gap:
    mov dx,gap
    call print
    mov ax,bp
    call hex
    mov ax,di
    call hex
    call newline
.sub_done:
    pop bp
    mov es,bp
.next:
    cmp byte [es:0],'Z'
    je done
    mov bp,di
    loop .arena_bridge
    jmp fail
.arena_bridge:
    jmp .arena
done:
    mov dx,ending
    call print
    mov ax,4c00h
    int 21h
fail:
    mov dx,error
    call print
    mov ax,4c01h
    int 21h
print:
    push ax
    mov ah,9
    int 21h
    pop ax
    ret
newline:
    push dx
    mov dx,eol
    call print
    pop dx
    ret
hex:
    push ax
    push bx
    push cx
    push dx
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
    jbe .emit
    add dl,7
.emit:
    mov ah,2
    int 21h
    loop .digit
    mov dl,' '
    mov ah,2
    int 21h
    pop dx
    pop cx
    pop bx
    pop ax
    ret
mcb db 'MCB ', '$'
submark db 'SUB ', '$'
gap db 'UNCLASSIFIED ', '$'
eol db 13,10,'$'
ending db 'SYSTEM_OWNER_END',13,10,'$'
error db 'SYSTEM_OWNER_FAIL',13,10,'$'

; Public list-of-lists SFT root. These are live allocations, not a memory
; saving estimate. Bound the walk and report occupied slots and references.
sft_census:
%ifdef LOW_SFT_OFFSET
    ; Our-kernel-only diagnostic: the public SDA identifies its retained DS.
    ; The caller supplies sfTabl's offset from the matching kernel map.
    mov ax,5d06h
    int 21h
    mov ax,ds
    push cs
    pop ds
    mov es,ax
    mov di,LOW_SFT_OFFSET
    mov dx,low_sft_label
    call sft_report
%ifdef POISON_LOW_SFT
    ; Destructive only inside the disposable diagnostic guest. Require a
    ; distinct HMA public owner before invalidating the entire low image.
    push es
    mov ah,52h
    int 21h
    les di,[es:bx+4]
    mov ax,es
    cmp ax,0ffffh
    jne fail
    cmp di,LOW_SFT_OFFSET
    jne fail
    pop es
    mov ax,es
    cmp ax,70h
    jb fail
    cmp ax,0a000h
    jae fail
    mov [low_sft_segment],ax
    mov di,LOW_SFT_OFFSET
    cmp word [es:di+4],5
    jne fail
    mov cx,6+5*59
    mov al,0a5h
    cld
    rep stosb
    call sft_live_handle_test
%endif
%endif
    mov ah,52h
    int 21h
    les di,[es:bx+4]
    mov bx,32
.table:
    mov dx,sft_label
    call sft_report
    cmp word [es:di],0ffffh
    je .done
    les di,[es:di]
    dec bx
    jnz .table
    jmp fail
.done:
    ret
sft_report:
    mov cx,[es:di+4]
    jcxz .bad
    cmp cx,255
    ja .bad
    call print
    mov ax,es
    call hex
    mov ax,di
    call hex
    mov ax,cx
    call hex
    mov si,di
    add si,6
    xor bp,bp
    xor dx,dx
.entry:
    mov ax,[es:si]
    test ax,ax
    jz .empty
    inc bp
    add dx,ax
    jc .bad
.empty:
    add si,59
    loop .entry
    mov ax,bp
    call hex
    mov ax,dx
    call hex
    call newline
    ret
.bad:
    jmp fail
sft_label db 'SFT ', '$'
%ifdef LOW_SFT_OFFSET
low_sft_label db 'LOWSFT ', '$'
%endif
%ifdef POISON_LOW_SFT
sft_live_handle_test:
    ; Resolve stdin through public JFN/SFT services, then prove that DUP and
    ; CLOSE update that HMA entry while the entire low copy stays poisoned.
    xor bx,bx
    mov ax,1220h
    int 2fh
    jc fail
    xor bx,bx
    mov bl,[es:di]
    mov ax,1216h
    int 2fh
    jc fail
    mov ax,es
    cmp ax,0ffffh
    jne fail
    cmp di,LOW_SFT_OFFSET+6
    jb fail
    cmp di,LOW_SFT_OFFSET+301
    jae fail
    mov ax,[es:di]
    mov [sft_references],ax
    xor bx,bx
    mov ah,45h
    int 21h
    jc fail
    mov bx,ax
    mov ax,[sft_references]
    inc ax
    cmp [es:di],ax
    jne fail
    mov ah,3eh
    int 21h
    jc fail
    mov ax,[sft_references]
    cmp [es:di],ax
    jne fail
    mov es,[low_sft_segment]
    mov di,LOW_SFT_OFFSET
    mov cx,301
    mov al,0a5h
    cld
    repe scasb
    jne fail
    mov dx,sft_poison_pass
    call print
    ret
low_sft_segment dw 0
sft_references dw 0
sft_poison_pass db 'LOW_SFT_POISON_PASS',13,10,'$'
%endif
