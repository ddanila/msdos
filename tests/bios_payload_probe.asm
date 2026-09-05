bits 16
org 100h
%include "payload-defs.inc"
start:
    push cs
    pop ds
    mov dx,begin_message
    mov ah,9
    int 21h
    mov ax,1236h
    mov cx,payload_end-payload+2
    int 2fh
    or ax,ax
    jz fail
    mov ax,es
    cmp ax,0ffffh
    jne fail
    mov [origin],di
    mov [entry+2],es
    mov ax,di
    add ax,high_entry-payload
    mov [entry],ax
    mov bx,di
    mov si,payload
    mov cx,payload_end-payload
    cld
    rep movsb
%ifndef OMIT_FIXUPS
    mov si,fixups
    mov cx,FIXUP_COUNT
.fixup:
    lodsw
    mov di,ax
    add di,bx
    add [es:di],bx
    loop .fixup
%endif
%if COPY_MODE = 1
    ; Apply the full pre-386 span only after rebasing.
    mov di,bx
    add di,CPU_PATCH_OFFSET
    mov cx,CPU_PATCH_SIZE
    mov al,90h
    rep stosb
%elif COPY_MODE = 2
    ; Negative control: remove operand-size prefix but leave CX halving.
    mov byte [es:bx+CPU_PATCH_OFFSET+2],90h
%endif
    ; Private low data: real service instructions cannot overwrite live BIOS
    ; state. The BDS likewise belongs to this probe, with a fixed-media flag
    ; selecting the bounded retry path rather than editing the ROM DPT.
    mov ax,cs
    add ax,(low_data-$$+100h)/16
    mov [low_segment],ax
    mov [es:bx+SLOT_BIOS_SERVICE_LOW_SEGMENT],ax
    mov word [es:bx+SLOT_BIOS_SERVICE_INT13_GATE],BIOS_HMA_INT13
    mov [es:bx+SLOT_BIOS_SERVICE_INT13_GATE+2],cs
    mov word [es:bx+SLOT_BIOS_SERVICE_INT1A_GATE],BIOS_HMA_INT1A
    mov [es:bx+SLOT_BIOS_SERVICE_INT1A_GATE+2],cs
    ; Every unused far import traps instead of calling an unbound address.
    mov si,trap_slots
    mov cx,TRAP_SLOT_COUNT
.trap:
    lodsw
    mov di,ax
    add di,bx
    mov word [es:di],unexpected
    mov [es:di+2],cs
    loop .trap
    mov di,bx
    add di,payload_end-payload
    mov [alias_offset],di
    push ds
    xor ax,ax
    mov ds,ax
    mov si,di
    sub si,16
    mov ax,[si]
    pop ds
    mov [alias_value],ax
    not ax
    mov [es:di],ax
    mov dx,ready_message
    mov ah,9
    int 21h
    mov ax,3513h
    int 21h
    mov [old13],bx
    mov [old13+2],es
    mov dx,hook13
    mov ax,2513h
    int 21h
    mov byte [hooked],1
    push cs
    pop es
    mov di,bds
    mov byte [di+BDS_DRIVENUM],0
    mov word [di+BDS_FLAGS],BDS_FIXED
    mov cx,1
    xor dx,dx
    mov bp,7777h
    mov [saved_sp],sp
    call far [entry]
    mov [result_ax],ax
    pushf
    pop word [result_flags]
    cmp sp,[saved_sp]
    jne fail
    cmp bp,7777h
    jne fail
    mov ax,es
    mov dx,cs
    cmp ax,dx
    jne fail
    cmp word [read_count],EXPECTED_READS
    jne fail
    cmp word [reset_count],EXPECTED_RESETS
    jne fail
    cmp word [disabled_seen],EXPECTED_READS+EXPECTED_RESETS
    jne fail
    mov ax,[result_flags]
    and ax,1
    cmp ax,EXPECTED_ERROR
    jne fail
    mov ax,[low_segment]
    mov es,ax
%if EXPECTED_ERROR = 0
    cmp word [es:LOW_DISKSECTOR+510],0aa55h
    jne fail
    cmp byte [es:LOW_TIM_DRV],0
%else
    cmp byte [result_ax+1],20h
    jne fail
    cmp byte [es:LOW_TIM_DRV],0ffh
%endif
    jne fail
    push cs
    pop es
    mov si,copy_source
    mov di,copy_destination
    mov cx,512
    cld
    repe cmpsb
    jne fail
    cmp word [copy_before],0aa55h
    jne fail
    cmp word [copy_after],055aah
    jne fail
    cmp word [copy_si],copy_source+512
    jne fail
    cmp word [copy_di],copy_destination+512
    jne fail
    cmp word [copy_cx],7654h
    jne fail
    call unhook
    mov dx,pass_message
    mov ah,9
    int 21h
    mov ax,10h
    jmp exit_emulator
unexpected:
    call BIOS_HMA_ROM_RESTORE
fail:
    push cs
    pop ds
    call unhook
    mov dx,fail_message
    mov ah,9
    int 21h
    mov ax,11h
exit_emulator:
    mov dx,0f4h
    out dx,ax
    mov ax,4c00h
    int 21h
unhook:
    cmp byte [hooked],0
    je .done
    lds dx,[old13]
    mov ax,2513h
    int 21h
    push cs
    pop ds
    mov byte [hooked],0
.done:
    ret
hook13:
    cmp ah,2
    jne .reset
    inc word [cs:read_count]
    cmp word [cs:read_count],FAIL_READS
    ja .real
    mov ah,20h
    stc
    jmp short .disable
.reset:
    inc word [cs:reset_count]
.real:
    pushf
    call far [cs:old13]
.disable:
    pushf
    push ax
    in al,92h
    and al,0fdh
    out 92h,al
    push ds
    push bx
    mov ax,0ffffh
    mov ds,ax
    mov bx,[cs:alias_offset]
    mov ax,[bx]
    cmp ax,[cs:alias_value]
    jne .not_disabled
    inc word [cs:disabled_seen]
.not_disabled:
    pop bx
    pop ds
    pop ax
    popf
    retf 2
%include "HIGHROM.INC"
origin dw 0
entry dd 0
old13 dd 0
saved_sp dw 0
result_flags dw 0
result_ax dw 0
low_segment dw 0
read_count dw 0
reset_count dw 0
disabled_seen dw 0
alias_offset dw 0
alias_value dw 0
hooked db 0
begin_message db 'BIOS_PAYLOAD_BEGIN',13,10,'$'
ready_message db 'BIOS_PAYLOAD_READY',13,10,'$'
pass_message db 'BIOS_PAYLOAD_PASS',13,10,'$'
fail_message db 'BIOS_PAYLOAD_FAIL',13,10,'$'
%include "payload-tables.inc"
payload:
    incbin "bios-high.bin"
high_entry:
    call payload+ENTRY_READ_SECTOR
    pushf
    push ax
    push cx
    push si
    push di
    push ds
    push es
    push ss
    pop ds
    push ss
    pop es
    mov si,copy_source
    mov di,copy_destination
    mov cx,7654h
    std
    call payload+ENTRY_MOVE
    mov [ss:copy_si],si
    mov [ss:copy_di],di
    mov [ss:copy_cx],cx
    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop ax
    popf
    retf
payload_end:
copy_si dw 0
copy_di dw 0
copy_cx dw 0
copy_source times 256 dw 0a55ah
copy_before dw 0aa55h
copy_destination times 512 db 0
copy_after dw 055aah
bds times 128 db 0
align 16
low_data times 4096 db 0
