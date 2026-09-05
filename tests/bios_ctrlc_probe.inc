; Exercise the real DSKSTATCHK request and INT 23h continuation. A temporary
; console supplies one Ctrl-C, validates the low transfer address, and (high
; mode) disables A20 before its device return. No ROM/user code is replaced.
check_ctrlc_path:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    call check_break_api
%if EXPECT_HIGH
    mov ax,1236h
    mov cx,16
    int 2fh
    or ax,ax
    jz fail
    mov [ctrl_alias_offset],di
    push ds
    xor ax,ax
    mov ds,ax
    mov ax,[di-16]
    mov [cs:ctrl_alias_value],ax
    not ax
    mov [es:di],ax
    pop ds
%endif
    mov ax,3523h
    int 21h
    mov [ctrl_old23],bx
    mov [ctrl_old23+2],es
    mov dx,ctrl_handler
    mov ax,2523h
    int 21h
    mov ax,3300h
    int 21h
    mov [ctrl_break],dl
    mov ax,3301h
    mov dl,1
    int 21h
    mov ah,52h
    int 21h
    mov [ctrl_low_owner],es
    add bx,PUB_SYSI_CON
    mov [ctrl_con_field],bx
    mov [ctrl_con_field+2],es
    mov ax,[es:bx]
    mov [ctrl_old_con],ax
    mov ax,[es:bx+2]
    mov [ctrl_old_con+2],ax
    mov word [es:bx],ctrl_device
    mov [es:bx+2],cs
    mov byte [ctrl_pending],1
    mov word [ctrl_hits],0
    mov word [ctrl_reads],0
    mov word [ctrl_disabled],0
    mov byte [ctrl_bad],0
    mov [ctrl_saved_sp],sp
    mov ax,2c00h                  ; ordinary disk-stack dispatch with BREAK=ON
    int 21h
    cmp sp,[ctrl_saved_sp]
    jne fail
    ; Restore normal console before making diagnostic DOS calls.
    les bx,[ctrl_con_field]
    mov ax,[ctrl_old_con]
    mov [es:bx],ax
    mov ax,[ctrl_old_con+2]
    mov [es:bx+2],ax
    mov ax,3301h
    mov dl,[ctrl_break]
    int 21h
    push ds
    lds dx,[ctrl_old23]
    mov ax,2523h
    int 21h
    pop ds
    cmp byte [ctrl_bad],0
    jne ctrl_failed
    cmp word [ctrl_hits],1
    jne ctrl_failed
    cmp word [ctrl_reads],1
    jne ctrl_failed
%if EXPECT_HIGH
    cmp word [ctrl_disabled],1
    jne ctrl_failed
%endif
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

ctrl_failed:
    mov dx,ctrl_failure
    mov ah,9
    int 21h
    mov dl,[ctrl_hits]
    add dl,'0'
    mov ah,2
    int 21h
    mov dl,[ctrl_reads]
    add dl,'0'
    mov ah,2
    int 21h
    mov dl,[ctrl_disabled]
    add dl,'0'
    mov ah,2
    int 21h
    mov dl,[ctrl_bad]
    add dl,'0'
    mov ah,2
    int 21h
    jmp fail

ctrl_handler:
    inc word [cs:ctrl_hits]
    iret                         ; retry the original operation once

%macro ctrl_api_call 1
    mov bx,0abcdh
    mov cx,1234h
    mov si,2345h
    mov di,3456h
    mov bp,4567h
    push es
    push word 5678h
    pop es
    mov [ctrl_api_sp],sp
    stc
    int 21h
    jnc fail
    cmp sp,[ctrl_api_sp]
    jne fail
    cmp cx,1234h
    jne fail
    cmp si,2345h
    jne fail
    cmp di,3456h
    jne fail
    cmp bp,4567h
    jne fail
%if %1
    cmp bx,0abcdh
    jne fail
%endif
    push ax
    mov ax,es
    cmp ax,5678h
    pop ax
    jne fail
    pop es
%endmacro

check_break_api:
    mov ax,3300h
    ctrl_api_call 1
    mov [ctrl_api_old],dl
    mov ax,3301h
    mov dx,5a00h
    ctrl_api_call 1
    cmp dx,5a00h
    jne fail
    mov ax,3302h
    mov dx,5a03h                 ; mask new state to one; return previous zero
    ctrl_api_call 1
    cmp dx,5a00h
    jne fail
    mov ax,3300h
    ctrl_api_call 1
    cmp dl,1
    jne fail
    mov ax,3302h
    mov dx,5a00h
    ctrl_api_call 1
    cmp dx,5a01h
    jne fail
    mov ax,3303h
    mov dx,5a55h
    ctrl_api_call 1
    cmp dx,5a55h
    jne fail
    mov ax,3304h
    ctrl_api_call 1
    cmp dx,5a55h
    jne fail
    mov ax,3305h
    ctrl_api_call 1
    cmp dl,1                    ; this harness boots drive A:
    jne fail
    mov ax,3306h
    ctrl_api_call 0
    cmp bx,1606h
    jne fail
    or dx,dx
    jnz fail
    mov ax,3307h
    ctrl_api_call 1
    cmp al,0ffh
    jne fail
    mov ax,3301h
    mov dl,[ctrl_api_old]
    int 21h
    ret

ctrl_strategy:
    mov [cs:ctrl_request],bx
    mov [cs:ctrl_request+2],es
    retf
ctrl_interrupt:
    push ax
    push bx
    push di
    push ds
    push es
    les bx,[cs:ctrl_request]
    mov word [es:bx+3],0100h
    cmp byte [es:bx+2],5
    je .status
    cmp byte [es:bx+2],4
    je .read
    jmp .done
.status:
    cmp byte [cs:ctrl_pending],0
    je .empty
    mov byte [es:bx+13],3
    jmp .done
.empty:
    or word [es:bx+3],0200h
    jmp .done
.read:
    cmp word [es:bx+18],1
    jne .bad
    mov ax,[es:bx+16]
    cmp ax,[cs:ctrl_low_owner]
    jne .bad
    les di,[es:bx+14]
    mov byte [es:di],3
    mov byte [cs:ctrl_pending],0
    inc word [cs:ctrl_reads]
%if EXPECT_HIGH
    in al,92h
    and al,0fdh
    out 92h,al
    mov ax,0ffffh
    mov ds,ax
    mov di,[cs:ctrl_alias_offset]
    mov ax,[di]
    cmp ax,[cs:ctrl_alias_value]
    jne .bad
    inc word [cs:ctrl_disabled]
%endif
    jmp .done
.bad:
    mov byte [cs:ctrl_bad],1
    mov byte [cs:ctrl_pending],0
.done:
    pop es
    pop ds
    pop di
    pop bx
    pop ax
    retf

ctrl_device dd -1
    dw 8003h,ctrl_strategy,ctrl_interrupt
    db 'CTRLCON '
ctrl_request dd 0
ctrl_old_con dd 0
ctrl_con_field dd 0
ctrl_old23 dd 0
ctrl_low_owner dw 0
ctrl_saved_sp dw 0
ctrl_hits dw 0
ctrl_reads dw 0
ctrl_disabled dw 0
ctrl_alias_offset dw 0
ctrl_alias_value dw 0
ctrl_break db 0
ctrl_pending db 0
ctrl_bad db 0
ctrl_api_old db 0
ctrl_api_sp dw 0
ctrl_failure db 'CTRL_STATUS hits/reads/a20/bad: $'
