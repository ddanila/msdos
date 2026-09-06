; Local COMMAND contract, not a claim that INT 2Eh preserves all registers.
bits 16
org 100h
start:
    cli
    mov ax, cs
    mov ss, ax
    mov sp, stack_end
    sti
    mov ds, ax
    mov es, ax
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
    mov word [command_source], internal
    call run_command
    mov dx, internal_file
    call check_file
    mov word [command_source], external
    call run_command
    mov dx, external_file
    call check_file
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
    mov es, [tail_segment]
    xor di, di
    mov si, [command_source]
    mov cx, 128
    cld
    rep movsb
    mov [caller_sp], sp
    push es
    pop ds
    xor si, si
    int 2eh
    ; The implementation returns CS:IP, but leaves its resident stack selected.
    ; Do not pop anything from that stack or assume DS still belongs to us.
    cli
    mov [cs:return_ss], ss
    mov ax, cs
    mov ss, ax
    mov sp, [cs:caller_sp]
    sti
    mov ds, ax
    mov es, ax
    mov ah, 51h
    int 21h
    mov ax, cs
    cmp bx, ax
    jne fail
    ; The returned stack must belong to the original parent shell, not HMA.
%ifdef EXPECT_CALLER_STACK
    mov ax, cs
%else
    mov ax, [16h]
%endif
    cmp [return_ss], ax
    jne fail
    ret

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
