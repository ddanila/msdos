; Local COMMAND contract, not a claim that INT 2Eh preserves all registers.
bits 16
org 100h
%macro TRACE 1
    push ax
    mov al,%1
    out 0e9h,al
    pop ax
%endmacro
start:
    cli
    mov ax, cs
    mov ss, ax
    mov sp, stack_end
    sti
    mov ds, ax
    mov es, ax
%ifdef EXPECT_LOW_PARAGRAPHS
    call check_low_owner
%endif
%ifdef EXPECT_WHOLE_SHELL
    call check_whole_shell
%endif
%ifdef EXPECT_SHELL_GATES
    call check_shell_gates
%endif
    mov ax, 580eh
    mov cx, 4d55h
    mov si, 2142h
    mov di, 0a55ah
    int 21h
    jc fail
    cmp ax, EXPECT_HMA
    jne fail
    mov bx, (image_end-$$+100h+15)/16
    mov ah, 4ah
    int 21h
    jc fail
    mov bx, 8
    mov ah, 48h
    int 21h
    jc fail
    mov [tail_segment], ax
%ifdef EXPECT_MANAGER_MODES
    mov ax,3567h
    int 21h
    mov di,20
    mov si,manager_signature
    mov cx,manager_signature_end-manager_signature
    cld
    repe cmpsb
    jne fail
    mov ax,[es:18]
    mov [manager_control],ax
    mov [manager_control+2],es
mode_next:
    TRACE 'M'
    push ax
    mov al,[mode_step]
    add al,'0'
    out 0e9h,al
    pop ax
    xor bx,bx
    mov bl,[mode_step]
    mov al,[manager_modes+bx]
    mov ah,1
    call far [manager_control]
%ifdef EXPECT_UMB_BUSY
    pushf
    pop dx
    cmp byte [mode_step],1
    jne .must_accept
    test dx,1
    jz fail
    jmp .policy_checked
.must_accept:
    test dx,1
    jnz fail
.policy_checked:
%else
    jc fail
%endif
    TRACE 'T'
    call check_manager_mode
    TRACE 'Q'
%endif
    mov word [command_source], internal
    call run_command
    mov dx, internal_file
    call check_file
    mov word [command_source], external
    call run_command
    mov dx, external_file
    call check_file
%ifdef EXPECT_MANAGER_MODES
    call check_manager_mode
    inc byte [mode_step]
    cmp byte [mode_step],4
    jb mode_next
%endif
%ifdef EXPECT_LOW_PARAGRAPHS
    call check_low_owner
%endif
%ifdef EXPECT_WHOLE_SHELL
    call check_whole_shell
%endif
%ifdef EXPECT_SHELL_GATES
    call check_shell_gates
%endif
    mov es, [tail_segment]
    mov ah, 49h
    int 21h
    jc fail
    mov dx, passed
    mov ah, 09h
    int 21h
    mov ax, 10h
    jmp exit_guest

run_command:
    TRACE 'C'
    mov es, [tail_segment]
    xor di, di
    mov si, [command_source]
    mov cx, 128
    cld
    rep movsb
    mov [caller_sp], sp
    push es
    pop ds
%ifdef EXPECT_A20_OFF
    call a20_off_begin
    TRACE 'A'
%endif
    xor si, si
    int 2eh
    ; The implementation returns CS:IP, but leaves its resident stack selected.
    ; Do not pop anything from that stack or assume DS still belongs to us.
    cli
    mov [cs:return_ss], ss
    mov [cs:return_sp], sp
    mov ax, cs
    mov ss, ax
    mov sp, [cs:caller_sp]
    sti
    mov ds, ax
    mov es, ax
    TRACE 'R'
%ifdef EXPECT_A20_OFF
    call a20_restore
%endif
    mov ah, 51h
    int 21h
    mov ax, cs
    cmp bx, ax
    jne fail
    ; The returned stack must belong to the original parent shell, not HMA.
%ifdef EXPECT_CALLER_STACK
    mov ax, cs
%else
%ifdef EXPECT_UPPER_STACK_START
    push es
    mov ax,[return_ss]
    cmp ax,0a000h
    jb fail
    add ax,EXPECT_UPPER_STACK_START / 16
    jc fail
    dec ax
    mov es,ax
    cmp byte [es:0],'M'
    je .stack_mcb
    cmp byte [es:0],'Z'
    jne fail
.stack_mcb:
    mov ax,[16h]
    cmp [es:1],ax
    jne fail
    cmp word [es:3],EXPECT_UPPER_PARAGRAPHS
    jne fail
    cmp word [return_sp],EXPECT_UPPER_STACK_START
    jb fail
    cmp word [return_sp],EXPECT_UPPER_STACK_END
    ja fail
    pop es
    ret
%else
    mov ax, [16h]
%endif
%endif
    cmp [return_ss], ax
    jne fail
    ret

%ifdef EXPECT_MANAGER_MODES
check_manager_mode:
    xor ax,ax
    call far [manager_control]
    xor bx,bx
    mov bl,[mode_step]
    cmp ah,[manager_statuses+bx]
    jne fail
    ret
manager_control dd 0
mode_step db 0
manager_modes db 0,1,2,0
%ifdef EXPECT_UMB_BUSY
manager_statuses db 0,0,2,0
%else
manager_statuses db 0,1,3,0
%endif
manager_signature db 'MICROSOFT EXPANDED MEMORY MANAGER 386'
manager_signature_end:
%endif

%ifdef EXPECT_A20_OFF
; Disposable emulator fixture. FFFF:FFF0 is the reserved HMA safety tail.
; Touch its low alias only with IRQs masked, restoring that word before entry
; because it can belong to COMMAND's transient allocation during INT 2Eh.
a20_off_begin:
    cli
    push ax
    push ds
    push es
    xor ax,ax
    mov ds,ax
    mov ax,0ffffh
    mov es,ax
    mov ax,[0ffe0h]
    mov [cs:a20_low_save],ax
    mov ax,[es:0fff0h]
    mov [cs:a20_high_save],ax
    mov byte [cs:a20_saved],1
    mov word [es:0fff0h],05678h
    mov word [0ffe0h],01234h
    in al,92h
    and al,0fch
%ifndef A20_SKIP_DISABLE
    out 92h,al
%endif
    mov ax,[es:0fff0h]
    push ax
    mov ax,[cs:a20_low_save]
    mov [0ffe0h],ax
    pop ax
    cmp ax,01234h
    pop es
    pop ds
    pop ax
    jne fail
    ; No interrupt window or DOS call between the alias proof and INT 2Eh.
    ret

a20_restore:
    push ax
    push es
    in al,92h
    and al,0feh
    or al,2
    out 92h,al
    cmp byte [cs:a20_saved],0
    je .done
    mov ax,0ffffh
    mov es,ax
    mov ax,[cs:a20_high_save]
    mov [es:0fff0h],ax
    mov byte [cs:a20_saved],0
.done:
    pop es
    pop ax
    ret
a20_low_save dw 0
a20_high_save dw 0
a20_saved db 0
%endif

%ifdef EXPECT_LOW_PARAGRAPHS
check_low_owner:
    push es
    mov bx,[16h]
    mov ax,bx
    dec ax
    mov es,ax
    cmp [es:1],bx
    jne fail
    cmp word [es:3],EXPECT_LOW_PARAGRAPHS
    jne fail
    pop es
    ret
%endif

%ifdef EXPECT_WHOLE_SHELL
check_whole_shell:
    push es
    mov bx,[16h]
    mov es,bx
    cmp byte [es:SHELL_HIGH_ACTIVE],EXPECT_HMA
    jne fail
%if EXPECT_HMA
    mov dx,0ffffh
    mov ax,[es:SHELL_HIGH_FIRST_SEG-2]
    sub ax,SHELL_HIGH_FIRST_TARGET
%else
    mov dx,bx
    xor ax,ax
%endif
    SHELL_HIGH_CHECK_GATES
    dec bx
    mov es,bx
%if EXPECT_HMA
    cmp word [es:3],SHELL_HIGH_LOW_PARAGRAPHS
    jne fail
%else
    cmp word [es:3],SHELL_HIGH_LOW_PARAGRAPHS
    jbe fail
%endif
    pop es
    ret
%endif

%ifdef EXPECT_SHELL_GATES
check_shell_gates:
    mov byte [gate_stage],'1'
    mov bx,[16h]
    mov es,bx
    cmp word [es:0ah],SHELL_GATE_LODCOM
    jne fail
    cmp word [es:0eh],SHELL_GATE_CONTC
    jne fail
    cmp word [es:12h],SHELL_GATE_DSKERR
    jne fail
    cmp [es:0ch],bx
    jne fail
    cmp [es:10h],bx
    jne fail
    cmp [es:14h],bx
    jne fail
    mov byte [gate_stage],'2'
    cmp word [es:SHELL_TRANVARS],SHELL_GATE_HEADFIX
    jne fail
    cmp word [es:SHELL_TRANVARS+8],SHELL_GATE_EXEC
    jne fail
    cmp word [es:SHELL_TRANVARS+12],SHELL_GATE_REMCHECK
    jne fail
    mov byte [gate_stage],'3'
    mov di,SHELL_GATE_LODCOM
    mov si,gate_targets
    mov cx,8
.gate:
    cmp byte [es:di],0eah
    jne fail
    lodsw
    cmp [es:di+1],ax
    jne fail
    cmp [es:di+3],bx
    jne fail
    add di,5
    loop .gate
%ifdef EXPECT_SHELL_BRIDGES
    mov byte [gate_stage],'B'
%macro CHECK_BRIDGE 1
    cmp byte [es:SHELL_BRIDGE_%1],9ah
    jne fail
    cmp word [es:SHELL_BRIDGE_%1+1],ax
    jne fail
    cmp word [es:SHELL_BRIDGE_%1+3],dx
    jne fail
%endmacro
%if EXPECT_HMA
    mov ax,[es:SHELL_POINTER_XLAT]
    mov dx,[es:SHELL_POINTER_XLAT+2]
    cmp dx,0ffffh
    jne fail
%else
    mov ax,SHELL_FALLBACK_XLAT
    mov dx,bx
%endif
    CHECK_BRIDGE XLAT
%if EXPECT_HMA
    mov ax,[es:SHELL_POINTER_KANJ]
    mov dx,[es:SHELL_POINTER_KANJ+2]
    cmp dx,0ffffh
    jne fail
%else
    mov ax,SHELL_FALLBACK_KANJ
%endif
    CHECK_BRIDGE KANJ
%if EXPECT_HMA
    mov ax,[es:SHELL_POINTER_XLAT]
    add ax,SHELL_DELTA_GETMSG
%else
    mov ax,SHELL_FALLBACK_GETMSG
%endif
    CHECK_BRIDGE GETMSG
%if EXPECT_HMA
    mov ax,[es:SHELL_POINTER_XLAT]
    add ax,SHELL_DELTA_DISPMSG
%else
    mov ax,SHELL_FALLBACK_DISPMSG
%endif
    CHECK_BRIDGE DISPMSG
%endif
    mov byte [gate_stage],'4'
    xor ax,ax
    mov es,ax
    cmp word [es:2eh*4],SHELL_GATE_INT2E
    jne fail
    cmp [es:2eh*4+2],bx
    jne fail
    mov byte [gate_stage],'5'
    mov ax,122eh
    mov dl,8
    int 2fh
    cmp di,SHELL_GATE_DISKMSG
    jne fail
    mov ax,es
    cmp ax,[16h]
    jne fail
    push cs
    pop es
    mov byte [gate_stage],'6'
    ret
gate_targets dw SHELL_GATE_TARGETS
gate_status db 'GATE_STAGE='
gate_stage db '0',13,10,'$'
%endif

check_file:
    mov ax, 3d00h
    int 21h
    jc fail
    mov bx, ax
    mov dx, received
    mov cx, 32
    mov ah, 3fh
    int 21h
    jc fail
    cmp ax, expected_end-expected
    jne fail
    mov ah, 3eh
    int 21h
    jc fail
    mov si, expected
    mov di, received
    mov cx, expected_end-expected
    cld
    repe cmpsb
    jne fail
    ret

fail:
    TRACE 'F'
    push cs
    pop ds
%ifdef EXPECT_A20_OFF
    call a20_restore
    sti
%endif
%ifdef EXPECT_SHELL_GATES
    mov dx,gate_status
    mov ah,09h
    int 21h
%endif
    mov dx, failure
    mov ah, 09h
    int 21h
    mov ax, 11h
exit_guest:
    mov dx, 0f4h
    out dx, ax
    cli
    hlt

tail_segment dw 0
command_source dw 0
caller_sp dw 0
return_ss dw 0
return_sp dw 0
internal:
    db internal_end-internal-2
    db 'ECHO OWNER_OK>I2EINT.TXT',13
internal_end:
    times 128-($-internal) db 0
external:
    db external_end-external-2
    db 'COMMAND.COM /C ECHO OWNER_OK>I2EEXT.TXT',13
external_end:
    times 128-($-external) db 0
internal_file db 'I2EINT.TXT',0
external_file db 'I2EEXT.TXT',0
expected db 'OWNER_OK',13,10
expected_end:
received times 32 db 0
passed db 'COMMAND_INT2E_OWNER_PASS',13,10,'$'
failure db 'COMMAND_INT2E_OWNER_FAIL',13,10,'$'
    times 256 db 0
stack_end:
image_end:
