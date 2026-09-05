; Run under permanent COMMAND with stdout redirected and an unformatted B:.
; The host selects the configured first response, then Fail on later prompts.
; DOS may
; reject the second open without another callback after the first media error.
; Chain the inherited handler
; and check its returning path without substituting a synthetic DOS error.
bits 16
org 100h

%ifndef FIRST_CRITICAL_RESPONSE
%define FIRST_CRITICAL_RESPONSE 3
%endif
%if FIRST_CRITICAL_RESPONSE != 1 && FIRST_CRITICAL_RESPONSE != 3
%error Only returning Retry and Fail responses are supported by this probe
%endif

start:
    push cs
    pop ds
    mov ax, 3524h
    int 21h
    mov [original24], bx
    mov [original24+2], es
    mov dx, critical_entry
    mov ax, 2524h
%ifndef NO_CRITICAL_HOOK
    int 21h
%endif

    les bx, [34h]              ; process JFN pointer, not COMMAND's PSP
    mov ax, [es:bx]
    mov [handles_before], ax
    cmp ah, [es:bx+2]          ; stdout must differ from inherited stderr
    je failure
.request:
    mov dx, missing_file
    mov ax, 3d00h
    int 21h
    jnc unexpected_open
    mov byte [failure_stage], 'V'
    cmp byte [violations], 0
    jne failure
    les bx, [34h]
    mov ax, [es:bx]
    mov byte [failure_stage], 'J'
    cmp ax, [handles_before]
    jne failure
    dec byte [requests_left]
    jnz .request
    mov byte [failure_stage], 'N'
    cmp word [entries], 0
    je failure
    call restore_vector
    mov dx, success_message
    mov ah, 09h
    int 21h
    mov ax, 4c00h
    int 21h

unexpected_open:
    mov byte [failure_stage], 'O'
    mov bx, ax
    mov ah, 3eh
    int 21h
failure:
    call restore_vector
    mov al, [entries]
    add al, '0'
    mov [entry_digit], al
    mov al, [violations]
    cmp al, 10
    jb .digit
    add al, 7
.digit:
    add al, '0'
    mov [violation_digit], al
    mov dx, failure_message
    mov ah, 09h
    int 21h
    mov ax, 4c01h
    int 21h

restore_vector:
    push ds
    lds dx, [original24]
    mov ax, 2524h
    int 21h
    pop ds
    ret

critical_entry:
    inc word [cs:entries]
    mov [cs:entry_sp], sp
    mov [cs:entry_ss], ss
    mov [cs:entry_ds], ds
    mov [cs:entry_es], es
    mov [cs:entry_si], si
    mov [cs:entry_cx], cx
    pushf
    call far [cs:original24]
    ; The inherited handler returns AL; preserve it while observing the ABI.
    cmp sp, [cs:entry_sp]
    je .stack_ok
    or byte [cs:violations], 1
.stack_ok:
    push ax
    mov ax, ss
    cmp ax, [cs:entry_ss]
    jne .bad_segments
    cmp ax, [cs:original24+2]   ; exercise a stack outside shell residency
    je .bad_segments
    mov ax, ds
    cmp ax, [cs:entry_ds]
    jne .bad_segments
    mov ax, es
    cmp ax, [cs:entry_es]
    je .segments_ok
.bad_segments:
    or byte [cs:violations], 2
.segments_ok:
    cmp si, [cs:entry_si]
    jne .bad_registers
    cmp cx, [cs:entry_cx]
    je .registers_ok
.bad_registers:
    or byte [cs:violations], 4
.registers_ok:
    pop ax
    cmp word [cs:entries], 1
    jne .later_response
    cmp al, FIRST_CRITICAL_RESPONSE
    je .return
    jmp short .bad_result
.later_response:
    cmp al, 3                 ; subsequent observed prompts: Fail
    je .return
.bad_result:
    or byte [cs:violations], 8
.return:
    iret

original24 dd 0
entry_sp dw 0
entry_ss dw 0
entry_ds dw 0
entry_es dw 0
entry_si dw 0
entry_cx dw 0
handles_before dw 0
entries dw 0
violations db 0
requests_left db 2
missing_file db 'B:\NOFILE.TXT', 0
success_message db 'COMMAND_CRITICAL_ABI_PASS', 13, 10, '$'
failure_message db 'COMMAND_CRITICAL_ABI_FAIL entries='
entry_digit db '?'
db ' violations='
violation_digit db '?'
db ' stage='
failure_stage db 'I', 13, 10, '$'
