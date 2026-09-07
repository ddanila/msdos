TITLE	SHRPRINT - PRINTF at SHARE level
NAME	SHRPRINT
;
;
.xlist
;
; get the appropriate segment definitions
;
include dosseg.asm

Share	SEGMENT PARA PUBLIC 'SHARE'
	ASSUME	SS:DOSGROUP,CS:SHARE

.xcref
INCLUDE DOSSYM.INC
INCLUDE DEVSYM.INC
.cref
.list
.sall

	I_Need	Proc_ID,WORD
	I_Need	User_ID,WORD

BREAK	<debugging output>

include print.asm

SHARE	ENDS
END
