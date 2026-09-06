; Local DOS device-chain check after deferred provider installation/cancellation.
bits 16
org 100h
%ifndef EMM_MARK_DELTA
%define EMM_MARK_DELTA 0
%endif
    push cs
    pop ds
    mov sp,probe_end
    mov ah,52h
    int 21h
    les si,[es:bx+34]            ; SYSI_DEV, same contract as ANSI driver probe
    mov cx,256
    xor bx,bx
.next:
    cmp si,0ffffh
    je .done
    test word [es:si+4],8000h
    jz .advance
    cmp word [es:si+10],4948h     ; HIMEM$ plus two spaces
    jne .emm
    cmp word [es:si+12],454dh
    jne .emm
    cmp word [es:si+14],244dh
    jne .emm
    cmp word [es:si+16],2020h
    jne .emm
    xor ax,ax
    call mark_size
    mov [himem_paras],ax
%ifdef UMB_GUARD_OFFSET
    mov ax,es
    mov [himem_segment],ax
%endif
.emm:
    cmp word [es:si+10],4d45h
    jne .advance
    cmp word [es:si+12],584dh
    jne .advance
    cmp word [es:si+14],5858h
    jne .advance
    cmp word [es:si+16],3058h
    jne .advance
    inc bx
    mov ax,EMM_MARK_DELTA
    call mark_size
    mov [emm_paras],ax
.advance:
    les si,[es:si]
    loop .next
    mov bx,0ffffh               ; malformed/cyclic chain is never an absent owner
.done:
    mov [owner_count],bx
%ifdef UMB_GUARD_OFFSET
    call check_umb_owner
%endif
%ifdef UMB_OWNER_TEST
    call check_high_umb_owner
%endif
%ifdef UMB_HANDOFF_TEST
    mov si,probe_stack_guard
    mov cx,16
.stack_guard:
    cmp byte [si],5ah
    jne failed
    inc si
    loop .stack_guard
%endif
    push cs
    pop es
    mov bx,(probe_end-$$+100h+15)/16
    mov ah,4ah
    int 21h
    jc failed
    mov bx,0ffffh
    mov ah,48h
    int 21h
    jnc failed
    cmp ax,8
    jne failed
    mov [largest_paras],bx
    mov dx,0e9h
    mov al,'M'
    out dx,al
    mov al,'C'
    out dx,al
    mov ax,cs
    call word_out
    mov ax,[largest_paras]
    call word_out
    mov ax,[himem_paras]
    call word_out
    mov ax,[emm_paras]
    call word_out
    mov dx,0e9h
    mov al,'D'
    out dx,al
    mov al,'O'
    out dx,al
    mov ax,[owner_count]
    call word_out
    mov ax,4c00h
    int 21h

; AX is a known entry displacement from the marked allocation. The historical
; upward-copy witness moves the entry 32 paragraphs but leaves its mark in place.
mark_size:
    push es
    push dx
    or si,si
    jnz failed
    mov dx,es
    sub dx,ax
    mov ax,dx
    dec ax
    mov es,ax
    cmp byte [es:0],'D'
    jne failed
    cmp [es:1],dx
    jne failed
    mov ax,[es:3]
    pop dx
    pop es
    ret
word_out:
    out dx,al
    mov al,ah
    out dx,al
    ret
failed:
    mov dx,0f4h
    mov ax,11h
    out dx,ax
    cli
    hlt
    jmp failed
owner_count dw 0
largest_paras dw 0
himem_paras dw 0
emm_paras dw 0
%ifdef UMB_OWNER_TEST
    %include "tests/emm_umb_owner_probe.inc"
%endif
%ifdef UMB_GUARD_OFFSET
    %include "tests/emm_provider_umb_probe.inc"
%endif
%ifdef UMB_HANDOFF_TEST
probe_stack_guard times 16 db 5ah
%endif
    times 128 db 0
probe_end:
