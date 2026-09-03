;	SCCSID = @(#)comsw.asm	1.1 85/05/14
;	SCCSID = @(#)comsw.asm	1.1 85/05/14

include version.inc
	OPTION NOKEYWORD:<GOTO ECHO ADDR>	;JWASM: free reserved GOTO/ECHO/ADDR -- used as command-handler proc/macro names

; COMMAND's largest disk-loaded message record is 40 bytes. Keep room for the
; formatter terminator without imposing the generic utility workspace size.
COMMAND_MSG_TEMP_BUF_SZ EQU 48

