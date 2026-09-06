;	SCCSID = @(#)comsw.asm	1.1 85/05/14
;	SCCSID = @(#)comsw.asm	1.1 85/05/14

include version.inc
	OPTION NOKEYWORD:<GOTO ECHO ADDR>	;JWASM: free reserved GOTO/ECHO/ADDR -- used as command-handler proc/macro names

; COMMAND's largest disk-loaded message record is 40 bytes. Keep room for the
; formatter terminator without imposing the generic utility workspace size.
COMMAND_MSG_TEMP_BUF_SZ EQU 48

; Shared pipeline storage contract: text, then append flag and output path.
PIPE_TEXT_BYTES EQU 129
PIPE_OUTPUT_PATH_BYTES EQU 64+3+13
PIPE_REDIRECT_BYTES EQU 1+PIPE_OUTPUT_PATH_BYTES


