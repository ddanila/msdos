; Development code/data separation. Immediate segment operands travel with
; copied code; they do not dereference a CS-relative low-data variable.
SHELL_OWNER_SEG MACRO target,slot
 IFDEF COMMAND_RESIDENT_BINDING
    push ax
    db 0b8h                     ; MOV AX,imm16
    PUBLIC shell_binding_&slot
shell_binding_&slot DW 0
    mov target,ax
    pop ax
 ELSE
    push cs
    pop target
 ENDIF
ENDM

SHELL_OWNER_REG MACRO target,opcode,slot
 IFDEF COMMAND_RESIDENT_BINDING
    db opcode                   ; MOV AX/BX,imm16
    PUBLIC shell_binding_&slot
shell_binding_&slot DW 0
 ELSE
    mov target,cs
 ENDIF
ENDM

SHELL_BINDING_SLOTS MACRO action
    action fatal_ds
    action fatal_psp
    action ret2e_ds
    action int2e_es
    action int2e_bx
    action lodcom_ds
    action lodcom_ax
    action headfix_ds
    action savhand_es
    action endinit_ds
    action exec_err_ds
    action exec_msg_es
    action exec_pre_ds
    action exec_post_ds
    action exec_wait_ds
    action critical_es
    action critical_ds
    action contc_entry_ds
    action contc_body_ds
    action pipeoff_ds
 IFDEF COMMAND_HIGH_RESIDENT
    action diskmsg_ds
 ENDIF
ENDM
