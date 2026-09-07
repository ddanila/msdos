	INCLUDE SYSHDR.INC

; include SYSMSG.INC

.xlist
.xcref

	include SYSMSG.INC		;

.cref
.list

	MSG_UTILNAME <SYS>		;

CODE	SEGMENT PARA PUBLIC

ASSUME	CS:CODE,DS:nothing,ES:nothing

	PUBLIC	SYSDISPMSG, SYSLOADMSG, SYSPARSE
	PUBLIC	Data_Space

;;dcl	MSG_SERVICES <MSGDATA>		;

;  MSG_SERVICES <SYS.CL1,SYS.CL2,SYS.CLA,SYS.CLB,SYS.CLC,SYS.CLD>

.xlist
.xcref

	MSG_SERVICES <SYS.CL1,SYS.CL2,SYS.CLA,SYS.CLB,SYS.CLC,SYS.CLD> ;

.cref
.list

;  MSG_SERVICES <LOADmsg,DISPLAYmsg,INPUTmsg,CHARmsg,NOVERCHECKmsg>

.xlist
.xcref

	MSG_SERVICES <LOADmsg,DISPLAYmsg,INPUTmsg,CHARmsg,NOVERCHECKmsg> ;

.cref
.list


false	=	0			;

DateSW	equ	false			;
TimeSW	equ	false			;
CmpxSW	equ	false			;
KeySW	equ	false			;
QusSW	equ	false			;
Val1SW	equ	false			;
Val2SW	equ	false			;
Val3SW	equ	false			;
SwSW	equ	false			;
NumSW	equ	false			;
CAPSW	equ	false			; Perform CAPS if specified


ASSUME	CS:CODE,DS:CODE,ES:nothing

; include parse.asm

;xlist
;xcref

include parse.asm			;

.cref
.list

Data_Space LABEL BYTE			;



CODE	Ends

include msgdcl.inc

	End

