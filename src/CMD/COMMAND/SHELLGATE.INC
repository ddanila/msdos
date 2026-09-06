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
