; Stable published entries for the development whole-resident-shell layout.
; Initially the far jumps target the low fallback service body. Whole-resident
; builds prepend a retained A20 restore call before entering the high copy.
IFDEF COMMAND_HIGH_RESIDENT
 IFNDEF COMMAND_RESIDENT_BINDING
    .ERR <whole shell requires resident bindings>
 ENDIF
 IFDEF COMMAND_CRITICAL_SPLIT
    .ERR <whole shell and independent critical split are mutually exclusive>
 ENDIF
 IFDEF COMMAND_CRITICAL_RECLAIM
    .ERR <whole shell and independent critical reclaim are mutually exclusive>
 ENDIF
ENDIF
SHELL_ENTRY_LIST MACRO action
    action lodcom,LODCOM
    action contc,CONTC
    action dskerr,DSKERR
    action int2e,INT_2E
    action headfix,THEADFIX
    action exec,EXT_EXEC
    action remcheck,TREMCHECK
    action diskmsg,READ_DISK_PROC
 IFDEF COMMAND_HIGH_RESIDENT
    action lodcom1,LODCOM1
    action endinit,ENDINIT
    action loadcom,shell_loadcom_far
    action chksum,shell_chksum_far
    action rprint,shell_rprint_far
 ENDIF
ENDM

SHELL_ENTRY_ALIAS MACRO slot,target
 IFDEF COMMAND_RESIDENT_BINDING
    SHELL_ENTRY_&target TEXTEQU <shell_gate_&slot>
 ELSE
    SHELL_ENTRY_&target TEXTEQU <target>
 ENDIF
ENDM
SHELL_ENTRY_LIST SHELL_ENTRY_ALIAS

SHELL_GATE_EXTERN MACRO slot,target
    EXTRN shell_gate_&slot:BYTE
    EXTRN shell_gate_&slot&_segment:WORD
ENDM

; Outgoing service transfers to separately placed initialization/fallback code.
SHELL_BRIDGE_LIST MACRO action
    action init,init_contc_specialcase
    action xlat,hma_in_char_xlat_high
    action kanj,hma_test_kanj_high
    action getmsg,shell_getmsg_fallback
    action dispmsg,shell_dispmsg_fallback
 IFDEF COMMAND_HIGH_RESIDENT
    action int21,shell_int21_low
    action int2f,shell_int2f_low
 ENDIF
ENDM

SHELL_INT MACRO vector
 IFDEF COMMAND_HIGH_RESIDENT
    IF vector EQ 2fh
        call shell_int2f_bridge
    ELSEIF vector EQ 21h
        call shell_int21_bridge
    ELSE
        .ERR <unsupported whole-shell interrupt vector>
    ENDIF
 ELSE
    int vector
 ENDIF
ENDM

SHELL_FAR_TRANSFER MACRO opcode,slot,target
    PUBLIC shell_bridge_&slot,shell_bridge_&slot&_segment
shell_bridge_&slot LABEL BYTE
    db opcode
    dw offset resgroup:target
shell_bridge_&slot&_segment dw 0
ENDM
