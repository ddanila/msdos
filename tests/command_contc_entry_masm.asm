; Actual extracted CONTC entry with separate code, owner and caller segments.
; Downstream initialization/body services are stubs; no A20 or DOS reentry test.
.model tiny
ResGroup TEXTEQU <DGROUP>
.386
.code
org 100h
start:
    cli
    mov ax,cs
    mov ss,ax
    mov sp,offset stack_end
    mov ds,ax
    mov word ptr [entry+2],ax
    add ax,20h
    mov [owner_segment],ax
    mov [shell_binding_contc_entry_ds],ax
    mov [shell_binding_contc_body_ds],ax
    mov [shell_binding_pipeoff_ds],ax
IFDEF WRONG_OWNER
    mov [shell_binding_contc_entry_ds],cs
ENDIF
IFDEF WRONG_PIPE_OWNER
    mov [shell_binding_pipeoff_ds],cs
ENDIF
    add ax,20h
    mov [foreign_segment],ax
    sti
next_case:
    movzx bx,byte ptr cs:[case_number]
    mov al,cs:[case_flags+bx]
    mov cs:[owner_flag],al
    mov byte ptr cs:[route],0
    mov ax,cs:[foreign_segment]
    mov ds,ax
    mov es,ax
    mov cs:[saved_sp],sp
    cmp byte ptr cs:[case_routes+bx],2
    jne simple_frame
    push 0246h
    push cs
    push offset nested_return
    push 0246h
    push cs
    push offset failed
    jmp registers
simple_frame:
    push 0246h
    push cs
    push offset returned
registers:
    mov ah,cs:[case_ah+bx]
    mov al,55h
    mov bx,1234h
    mov cx,2345h
    mov dx,3456h
    mov si,4567h
    mov di,5678h
    mov bp,6789h
    jmp dword ptr cs:[entry]
nested_return:
    mov byte ptr cs:[route],2
returned:
    pushf
    pop word ptr cs:[returned_flags]
    cmp sp,cs:[saved_sp]
    jne failed
    cmp bx,1234h
    jne failed
    cmp cx,2345h
    jne failed
    cmp dx,3456h
    jne failed
    cmp si,4567h
    jne failed
    cmp di,5678h
    jne failed
    cmp bp,6789h
    jne failed
    cmp al,55h
    jne failed
    movzx bx,byte ptr cs:[case_number]
    cmp ah,cs:[case_ah+bx]
    jne failed
    mov al,cs:[case_routes+bx]
    cmp al,cs:[route]
    jne failed
    mov ax,es
    cmp ax,cs:[foreign_segment]
    jne failed
    mov ax,ds
    cmp byte ptr cs:[route],3
    je body_owner
    cmp ax,cs:[foreign_segment]
    jne failed
    mov al,cs:[case_flags+bx]
    cmp al,cs:[owner_flag]
    jne failed
    jmp flags_check
body_owner:
    cmp ax,cs:[owner_segment]
    jne failed
    cmp byte ptr cs:[owner_flag],initCtrlC
    jne failed
flags_check:
    mov ax,ss
    mov dx,cs
    cmp ax,dx
    jne failed
    cmp byte ptr cs:[InitFlag],initINIT
    jne failed
    cmp byte ptr cs:[foreign_flag],0A5h
    jne failed
    mov ax,cs:[returned_flags]
    cmp byte ptr cs:[route],2
    jne iret_flags
    test ax,1
    jz failed
    jmp passed_case
iret_flags:
    and ax,0247h
    cmp ax,0246h
    jne failed
passed_case:
    mov al,'C'
    out 0e9h,al
    inc byte ptr cs:[case_number]
    cmp byte ptr cs:[case_number],7
    jb next_case
    mov byte ptr cs:[case_number],0
pipe_case:
    mov al,cs:[case_number]
    mov cs:[owner_pipe],al
    mov byte ptr cs:[owner_echo],5
    mov ax,cs:[foreign_segment]
    mov ds,ax
    mov cs:[saved_sp],sp
    mov ax,0A55Ah
    call ResPipeOff
    cmp sp,cs:[saved_sp]
    jne failed
    cmp ax,0A55Ah
    jne failed
    mov ax,ds
    cmp ax,cs:[foreign_segment]
    jne failed
    cmp byte ptr cs:[owner_pipe],0
    jne failed
    mov al,5
    cmp byte ptr cs:[case_number],0
    je pipe_echo
    mov al,2
pipe_echo:
    cmp al,cs:[owner_echo]
    jne failed
    cmp byte ptr cs:[PipeFlag],0A5h
    jne failed
    cmp byte ptr cs:[EchoFlag],0A5h
    jne failed
    mov al,'P'
    out 0e9h,al
    inc byte ptr cs:[case_number]
    cmp byte ptr cs:[case_number],2
    jb pipe_case
    mov ax,10h
    jmp done
failed:
    mov al,'!'
    out 0e9h,al
    mov ax,11h
done:
    mov dx,0f4h
    out dx,ax
    cli
    hlt

COMMAND_RESIDENT_BINDING equ 1
SHELL_CTRL_STATE TEXTEQU <DS>
include RESBIND.INC
include CONTC_FLAGS.INC
include CONTC_ENTRY.INC
    ; Entry selected shell DS; substitute for the main Ctrl+C body.
    mov byte ptr cs:[route],3
    iret
CONTC endp
init_contc_specialcase:
    mov byte ptr cs:[route],1
    iret

SaveReg MACRO regs
    push regs
ENDM
RestoreReg MACRO regs
    pop regs
ENDM
return MACRO
    ret
ENDM
include PIPEOFF.INC

entry dw offset CONTC,0
owner_segment dw 0
foreign_segment dw 0
saved_sp dw 0
returned_flags dw 0
case_number db 0
route db 0
case_flags db initINIT,initINIT OR initSpecial,initCtrlC,initCtrlC,initCtrlC,initCtrlC,0
case_ah db 0FFh,0FFh,0,1,12,13,55h
case_routes db 0,1,0,2,2,0,3
; Same offsets in three distinct segments. CS carries conflicting state.
InitFlag db initINIT
PipeFlag db 0A5h
EchoFlag db 0A5h
db 509 dup (0)
owner_flag db 0
owner_pipe db 0
owner_echo db 0
db 509 dup (0)
foreign_flag db 0A5h
db 512 dup (0)
stack_end label byte
end start
