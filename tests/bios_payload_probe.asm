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
    mov [service_target],ax
    mov ax,di
    add ax,ENTRY_NEAR_GATE
    mov [entry],ax
    mov bx,di
    mov si,payload
    mov cx,payload_end-payload
    cld
    rep movsb
%ifdef TEST_UNWIND
    mov [es:bx+unwind_gate_segment-payload],cs
    mov ax,bx
    add ax,ENTRY_HARDERR2
    mov [unwind_entry],ax
    mov [unwind_entry+2],es
%endif
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
%ifdef TEST_DEVICE
    call test_device_request
    jmp report_pass
%endif
    mov ax,3513h
    int 21h
    mov [old13],bx
    mov [old13+2],es
    mov dx,hook13
    mov ax,2513h
    int 21h
    mov byte [hooked],1
%ifdef TEST_INTERRUPT
    call prepare_interrupt
%endif
    push cs
    pop es
    mov di,bds
    mov byte [di+BDS_DRIVENUM],0
    mov word [di+BDS_FLAGS],BDS_FIXED
    mov cx,1
    xor dx,dx
    mov bp,7777h
    mov [saved_sp],sp
%ifdef TEST_INTERRUPT
    mov ax,0201h
    mov bx,copy_destination
%endif
    call disable_entry_a20
%ifdef TEST_INTERRUPT
    int 13h
%else
%ifndef OMIT_ENTRY_A20
    call BIOS_HMA_ROM_RESTORE
%endif
    push word [service_target]
    call far [entry]
%endif
    mov [result_ax],ax
    mov [result_cx],cx
    pushf
    pop word [result_flags]
    cmp sp,[saved_sp]
    jne fail
    cmp bp,7777h
    jne fail
%ifdef TEST_UNWIND
    cmp word [entry_disabled],2
%elifdef TEST_INTERRUPT
    cmp word [entry_disabled],2
%else
    cmp word [entry_disabled],1
%endif
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
%ifdef TEST_INTERRUPT
    cmp word [multiplex_restores],3 ; vector test, entry, and ROM return
    jb fail
%if EXPECTED_ERROR = 0
    cmp word [copy_destination+510],0aa55h
    jne fail
%else
    cmp byte [result_ax+1],20h
    jne fail
%endif
    cmp word [copy_before],0aa55h
    jne fail
    cmp word [copy_after],055aah
    jne fail
    jmp report_pass
%endif
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
%ifdef TEST_UNWIND
    cmp word [result_cx],0123h
    jne fail
%endif
report_pass:
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
%ifdef TEST_INTERRUPT
    cmp byte [multiplex_hooked],0
    je .disk
    lds dx,[old2f]
    mov ax,252fh
    int 21h
    push cs
    pop ds
    mov byte [multiplex_hooked],0
.disk:
%endif
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
disable_entry_a20:
    pushf
    push ax
    push bx
    push ds
    in al,92h
    and al,0fdh
    out 92h,al
    mov ax,0ffffh
    mov ds,ax
    mov bx,[cs:alias_offset]
    mov ax,[bx]
    cmp ax,[cs:alias_value]
    jne .not_disabled
    inc word [cs:entry_disabled]
.not_disabled:
    pop ds
    pop bx
    pop ax
    popf
    ret
%ifdef TEST_UNWIND
low_unwind:
    call disable_entry_a20
    call BIOS_HMA_ROM_RESTORE
    mov ax,200fh
    stc
    jmp far [cs:unwind_entry]
%endif
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
%ifdef TEST_INTERRUPT
%macro BIOS_MULTIPLEX_CHAIN 0
    jmp word [cs:NEXT2F_13]
%endmacro
%macro BIOS_SWAP_VECTOR 2
    xchg %1,[cs:%2]
%endmacro
%macro BIOS_INTERRUPT_JUMP 0
    jmp far [cs:BIOS_HIGH_BLOCK13_ENTRY]
%endmacro
ORIG13 equ low_data+LOW_ORIG13
OLD13 equ low_data+LOW_OLD13
NEXT2F_13 equ low_data+LOW_NEXT2F_13
%include "LOWINT.INC"
prepare_interrupt:
    mov ax,352fh
    int 21h
    mov [old2f],bx
    mov [old2f+2],es
    mov word [NEXT2F_13],multiplex_chain
    mov dx,BIOS_LOW_INT2F13
    mov ax,252fh
    int 21h
    mov byte [multiplex_hooked],1
    ; The public exchange must work with physical A20 off and retain the
    ; original interrupt flags. Its two returned far pointers are distinct.
    mov word [ORIG13],1234h
    mov word [ORIG13+2],4321h
    mov word [OLD13],5678h
    mov word [OLD13+2],8765h
    mov ax,cs
    mov es,ax
    mov dx,hook13
    mov bx,hook13
    mov cx,3333h
    mov si,5555h
    mov di,6666h
    mov bp,7777h
    mov ax,1300h
    call disable_entry_a20
    stc
    std
    int 2fh
    pushf
    pop word [cs:result_flags]
    cld
    cmp ax,1300h
    jne fail
    cmp dx,1234h
    jne fail
    cmp bx,5678h
    jne fail
    cmp cx,3333h
    jne fail
    cmp si,5555h
    jne fail
    cmp di,6666h
    jne fail
    cmp bp,7777h
    jne fail
    mov ax,ds
    cmp ax,4321h
    jne fail
    mov ax,es
    cmp ax,8765h
    jne fail
    push cs
    pop ds
    mov ax,[result_flags]
    and ax,0401h
    cmp ax,0401h
    jne fail
    cmp word [ORIG13],hook13
    jne fail
    cmp word [OLD13],hook13
    jne fail
    mov ax,cs
    cmp [ORIG13+2],ax
    jne fail
    cmp [OLD13+2],ax
    jne fail
    ; This invokes E705h through the newly installed low filter. Restoring
    ; A20 in the filter itself would recurse and prevent this probe passing.
    call BIOS_HMA_ROM_RESTORE
    mov ax,0ffffh
    mov es,ax
    mov bx,[origin]
    mov word [es:bx+SLOT_BIOS_SERVICE_ORIG13_OFFSET],LOW_ORIG13
    mov word [es:bx+SLOT_BIOS_SERVICE_SAVED_VECTOR_GATE],BIOS_HMA_SAVED_VECTOR
    mov [es:bx+SLOT_BIOS_SERVICE_SAVED_VECTOR_GATE+2],cs
    add bx,ENTRY_BLOCK13
    mov [BIOS_HIGH_BLOCK13_ENTRY],bx
    mov [BIOS_HIGH_BLOCK13_ENTRY+2],es
    ; Publish only after the body and every exercised import are bound.
    mov dx,BIOS_LOW_BLOCK13
    mov ax,2513h
    int 21h
    ret
multiplex_chain:
    pushf
    cmp ax,0e705h
    jne .next
    inc word [cs:multiplex_restores]
.next:
    popf
    jmp far [cs:old2f]
old2f dd 0
multiplex_restores dw 0
multiplex_hooked db 0
%endif
%ifdef TEST_DEVICE
; Use the same seven production entry declarations and instruction sequence.
%macro BIOS_DEVICE_ENTRY 4
%2:
%ifndef OMIT_ENTRY_A20
    call BIOS_HMA_ROM_RESTORE
%endif
    jmp far [cs:%3]
%3: dd 0
%endmacro
%include "HIGHDEV.INC"
test_device_request:
    mov ax,[low_segment]
    mov es,ax
    mov word [es:LOW_START_BDS],3072
    mov byte [es:3072+BDS_DRIVELET],0
%if TEST_DEVICE = 2
    mov word [es:3072+BDS_FLAGS],BDS_FIXED
%endif
    mov word [es:LOW_PTRSAV],device_request
    mov [es:LOW_PTRSAV+2],cs
    mov [device_call+2],cs
    ; Pre-publication calls must still use the valid low implementation.
    call exercise_device
    cmp word [fallback_count],1
    jne fail
    cmp word [device_request+3],0100h
    jne fail
    ; Bind the exercised high service and its low completions before exposing
    ; the low stub. This is a private probe table, not the installed DSKTBL.
    mov ax,0ffffh
    mov es,ax
    mov bx,[origin]
    mov word [es:bx+SLOT_BIOS_LOW_EXIT_ENTRY],device_exit
    mov [es:bx+SLOT_BIOS_LOW_EXIT_ENTRY+2],cs
    mov word [es:bx+SLOT_BIOS_LOW_BUSY_ENTRY],device_busy
    mov [es:bx+SLOT_BIOS_LOW_BUSY_ENTRY+2],cs
    mov word [es:bx+SLOT_BIOS_LOW_CMDERR_ENTRY],device_cmderr
    mov [es:bx+SLOT_BIOS_LOW_CMDERR_ENTRY+2],cs
%if TEST_DEVICE = 3
    add bx,ENTRY_IOCTL
    mov [BIOS_HIGH_IOCTL_ENTRY],bx
    mov [BIOS_HIGH_IOCTL_ENTRY+2],es
    mov ax,BIOS_DEVICE_IOCTL
%else
    add bx,ENTRY_REMOVABLE
    mov [BIOS_HIGH_REMOVABLE_ENTRY],bx
    mov [BIOS_HIGH_REMOVABLE_ENTRY+2],es
    mov ax,BIOS_DEVICE_REMOVABLE
%endif
    pushf
    cli
    mov [device_target],ax
    popf
    mov word [device_request+18],2
    call disable_entry_a20
    call exercise_device
    cmp word [entry_disabled],1
    jne fail
    cmp word [fallback_count],1
    jne fail
%if TEST_DEVICE = 3
    cmp word [device_request+18],0
    jne fail
    cmp word [device_request+3],8103h
%elif TEST_DEVICE = 2
    cmp word [device_request+3],0300h
%else
    cmp word [device_request+3],0100h
%endif
    jne fail
    push cs
    pop es
    ret
exercise_device:
    mov [saved_sp],sp
    mov ax,1111h
    mov bx,2222h
    mov cx,3333h
    mov dx,4444h
    mov si,5555h
    mov di,6666h
    mov bp,7777h
    mov ds,ax
    mov es,bx
    call far [cs:device_call]
    cmp sp,[cs:saved_sp]
    jne fail
    cmp ax,1111h
    jne fail
    cmp bx,2222h
    jne fail
    cmp cx,3333h
    jne fail
    cmp dx,4444h
    jne fail
    cmp si,5555h
    jne fail
    cmp di,6666h
    jne fail
    cmp bp,7777h
    jne fail
    mov ax,ds
    cmp ax,1111h
    jne fail
    mov ax,es
    cmp ax,2222h
    jne fail
    push cs
    pop ds
    ret
device_dispatch:
    ; MSBIO1 saves this frame before decoding the request and tail-dispatching.
    push si
    push ax
    push cx
    push dx
    push di
    push bp
    push ds
    push es
    push bx
    mov ax,[cs:low_segment]
    mov ds,ax
    xor ax,ax                    ; logical drive 0, media 0
    mov cx,2
    cld
    jmp [cs:device_target]
device_fallback:
    inc word [cs:fallback_count]
device_exit:
    mov ah,1
    jmp device_complete
device_busy:
    mov ah,3
    jmp device_complete
device_cmderr:
    mov al,3
    sub [cs:device_request+18],cx
    mov ah,81h
device_complete:
    mov [cs:device_request+3],ax
    pop bx
    pop es
    pop ds
    pop bp
    pop di
    pop dx
    pop cx
    pop ax
    pop si
    retf
device_call dw device_dispatch,0
device_target dw device_fallback
fallback_count dw 0
device_request times 32 db 0     ; major function 0 is invalid for disk IOCTL
%endif
origin dw 0
entry dd 0
service_target dw 0
entry_disabled dw 0
old13 dd 0
saved_sp dw 0
result_flags dw 0
result_ax dw 0
result_cx dw 0
unwind_sp dw 0
unwind_entry dd 0
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
%ifdef TEST_UNWIND
    mov [ss:unwind_sp],sp
    push ax
    push es
    mov ax,[ss:low_segment]
    mov es,ax
    mov ax,[ss:unwind_sp]
    mov [es:LOW_SPSAV],ax
    mov word [es:LOW_SECCNT],0123h
    mov byte [es:LOW_MEDIA_SET_FOR_FORMAT],1 ; no ROM DPT edit in this probe
    pop es
    pop ax
    push word 1234h
    push word 5678h
    db 09ah
    dw low_unwind
unwind_gate_segment:
    dw 0
    jmp $                       ; unreachable: HARDERR2 unwinds this call
%endif
    ret
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
