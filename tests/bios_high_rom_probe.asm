bits 16
org 100h

start:
    push cs
    pop ds
    mov ax,0e700h
    int 2fh
    cmp ax,0e7ffh
    jne fail
    mov word [entry],high_start
    mov [entry+2],cs
    mov ax,1236h
    mov cx,high_end-high_start+2
    int 2fh
%ifdef EXPECT_HIGH
    or ax,ax
    jz fail
    mov [entry],di
    mov [entry+2],es
    mov bx,di
    mov si,high_start
    mov cx,high_end-high_start
    cld
    rep movsb
    mov [es:bx+high_gate_segment-high_start],cs
    mov [alias_offset],di
    ; Pick a high sentinel different from its existing low alias; never
    ; overwrite the low alias, which belongs to another resident owner.
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
%else
    or ax,ax
    jnz fail
    mov [high_gate_segment],cs
%endif
    mov dx,begin_message
    mov ah,9
    int 21h
    mov [initial_sp],sp
%ifdef TEST_TIMER
    mov ax,351ah
%else
    mov ax,3513h
%endif
    int 21h
    mov [old13],bx
    mov [old13+2],es
    mov dx,hook13
%ifdef TEST_TIMER
    mov ax,251ah
%else
    mov ax,2513h
%endif
    int 21h
    mov byte [hooked],1
    mov [hook_vector+2],cs

    ; Real disk/clock call through the gate and an A20-disabling ROM wrapper.
    push cs
    pop es
%ifdef TEST_TIMER
    xor ax,ax
%else
    mov ax,0201h
%endif
    mov bx,sector
    mov cx,1
    xor dx,dx
    mov bp,0b00bh
    stc
%ifdef USE_TAIL
    push word [cs:supplied_flags]
%endif
    call far [entry]
%ifdef USE_TAIL
    call BIOS_HMA_ROM_RESTORE
%endif
%ifdef TEST_TIMER
    pushf
    pop word [first_flags]
    cmp ax,[rom_ax]
    jne fail
    cmp cx,[rom_cx]
    jne fail
    cmp dx,[rom_dx]
    jne fail
    mov ax,[first_flags]
    xor ax,[rom_flags]
    test ax,0ed5h
    jnz fail
%else
    jc fail
    cmp word [sector+510],0aa55h
    jne fail
%endif
    cmp word [high_seen],1
    jne fail
    cmp sp,[initial_sp]
    jne fail

    ; Both carry outcomes and all ordinary result registers must survive.
    mov byte [synthetic],1
%ifdef USE_SUPPLIED_FLAGS
    mov word [hook_vector],hook13_alternate
%endif
again:
    mov ax,0a111h
    mov bp,0b00bh
    stc
%ifdef USE_TAIL
    push word [cs:supplied_flags]
%endif
    call far [entry]
%ifdef USE_TAIL
    call BIOS_HMA_ROM_RESTORE
%endif
    pushf
    pop word [cs:result_flags]
    cmp sp,[cs:initial_sp]
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
    cmp ax,1234h
    jne fail
    mov ax,es
    cmp ax,2345h
    jne fail
    push cs
    pop ds
    mov ax,[result_flags]
    and ax,0ad5h                ; OF, IF, SF, ZF, AF, PF, CF
    mov bx,0ad4h
    or bl,[carry_result]
    cmp ax,bx
    jne fail
    cmp byte [carry_result],0
    jne checked
    inc byte [carry_result]
    jmp again
checked:
%ifdef USE_SUPPLIED_FLAGS
    cmp word [frame_seen],3
    jne fail
    cmp word [alternate_seen],2
    jne fail
%endif
    cmp word [high_seen],3
    jne fail
    cmp word [input_seen],3
    jne fail
%ifdef EXPECT_HIGH
    cmp word [disabled_seen],3
    jne fail
%endif
    call unhook
    mov dx,pass_message
    mov ah,9
    int 21h
    mov ax,10h
    jmp exit_emulator
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
%ifdef TEST_TIMER
    mov ax,251ah
%else
    mov ax,2513h
%endif
    int 21h
    push cs
    pop ds
    mov byte [hooked],0
.done:
    ret

hook13_alternate:
    pushf
    inc word [cs:alternate_seen]
    popf
    jmp hook13

hook13:
%ifdef USE_SUPPLIED_FLAGS
    ; Entry frame FLAGS must differ from live CF; both are caller inputs.
    pushf
    push bp
    mov bp,sp
    push ax
    mov ax,[ss:bp+8]
    cmp ax,[cs:supplied_flags]
    jne .bad_frame
    test word [ss:bp+2],1
    jz .bad_frame
    inc word [cs:frame_seen]
.bad_frame:
    pop ax
    pop bp
    popf
%endif
    pushf
    cmp bp,0b00bh
    jne .bad_input
    cmp byte [cs:synthetic],0
    je .input_ok
    cmp ax,0a111h
    jne .bad_input
.input_ok:
    inc word [cs:input_seen]
.bad_input:
    popf
    cmp byte [cs:synthetic],0
    jne .synthetic
    pushf
    call far [cs:old13]
    mov [cs:rom_ax],ax
    mov [cs:rom_cx],cx
    mov [cs:rom_dx],dx
    pushf
    pop word [cs:rom_flags]
    pushf
    jmp short .disable
.synthetic:
    push ax
    mov ax,0ad6h
    or al,[cs:carry_result]
    push ax
    popf
    pop ax
    pushf
    mov ax,1111h
    mov bx,2222h
    mov cx,3333h
    mov dx,4444h
    mov si,5555h
    mov di,6666h
    mov bp,7777h
    push ax
    mov ax,1234h
    mov ds,ax
    mov ax,2345h
    mov es,ax
    pop ax
.disable:
    push ax
    in al,92h
    and al,0fdh
    out 92h,al
%ifdef EXPECT_HIGH
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
%endif
    pop ax
%ifdef VECTOR_IRET
    ; Move the captured result flags into the original interrupt frame while
    ; retaining result AX/BP, then exercise the conventional IRET return.
    push bp
    mov bp,sp
    push ax
    mov ax,[ss:bp+2]
    mov [ss:bp+8],ax
    pop ax
    pop bp
    add sp,2
    iret
%else
    popf
    retf 2                      ; preserve returned flags, discard caller FLAGS
%endif

%ifdef OMIT_A20_RESTORE
; Negative control: identical high caller, but no low A20 restoration.
BIOS_HMA_INT13:
    int 13h
    retf
%else
%include "HIGHROM.INC"
%endif

high_start:
%ifdef USE_SUPPLIED_FLAGS
%ifdef USE_TAIL
    pushf
    inc word [ss:high_seen]
    popf
%else
    push word [ss:supplied_flags]
%endif
    push word [ss:hook_vector+2]
    push word [ss:vector_slot_offset]
%else
%ifdef USE_SAVED_VECTOR
    push word [ss:hook_vector+2]
    push word [ss:hook_vector]
%endif
%endif
    db 09ah                     ; FAR CALL to the retained low gate
%ifdef USE_SUPPLIED_FLAGS
%ifdef USE_TAIL
    dw BIOS_HMA_CHAIN_VECTOR
%else
    dw BIOS_HMA_SAVED_VECTOR
%endif
%else
%ifdef USE_SAVED_VECTOR
    dw BIOS_HMA_VECTOR
%else
%ifdef TEST_TIMER
    dw BIOS_HMA_INT1A
%else
    dw BIOS_HMA_INT13
%endif
%endif
%endif
high_gate_segment:
    dw 0                        ; patched after copying to allocated HMA offset
    ; Preserve the ROM result flags and registers while marking high execution.
    pushf
    inc word [ss:high_seen]
    popf
    retf
high_end:

entry dw 0,0
old13 dd 0
hook_vector dw hook13,0
vector_slot_offset dw hook_vector
supplied_flags dw 0246h
frame_seen dw 0
alternate_seen dw 0
input_seen dw 0
hooked db 0
synthetic db 0
carry_result db 0
high_seen dw 0
disabled_seen dw 0
alias_offset dw 0
alias_value dw 0
result_flags dw 0
initial_sp dw 0
rom_ax dw 0
rom_cx dw 0
rom_dx dw 0
rom_flags dw 0
first_flags dw 0
begin_message db 'BIOS_HIGH_ROM_BEGIN',13,10,'$'
pass_message db 'BIOS_HIGH_ROM_PASS',13,10,'$'
fail_message db 'BIOS_HIGH_ROM_FAIL',13,10,'$'
align 16
sector times 512 db 0
