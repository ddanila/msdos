; Stable published entries for the development whole-resident-shell layout.
; Initially these five-byte far jumps target the original low service body.
; They do not enable A20 or make a high target safe by themselves.
SHELL_ENTRY_LIST MACRO action
    action lodcom,LODCOM
    action contc,CONTC
    action dskerr,DSKERR
    action int2e,INT_2E
    action headfix,THEADFIX
    action exec,EXT_EXEC
    action remcheck,TREMCHECK
    action diskmsg,READ_DISK_PROC
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
ENDM

SHELL_FAR_TRANSFER MACRO opcode,slot,target
    PUBLIC shell_bridge_&slot,shell_bridge_&slot&_segment
shell_bridge_&slot LABEL BYTE
    db opcode
    dw offset resgroup:target
shell_bridge_&slot&_segment dw 0
ENDM
