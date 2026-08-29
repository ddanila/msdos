CallInstall MACRO   name,mpx,fn,save,restore
IF Installed
    IFNB    <save>
	SaveReg <save>
    ENDIF
	MOV	AX,(mpx SHL 8) + fn
	INT	2Fh
    IFNB    <restore>
	RestoreReg  <restore>
    ENDIF
ELSE
	Invoke	name
ENDIF
ENDM
BREAK	MACRO	subtitle
	SUBTTL	subtitle
	PAGE
ENDM
.xcref	break

BREAK <SaveReg - save a set of registers>

?stackdepth = 0			; init stack-depth tracker (jwasm: MASM left it implicit 0)
SaveReg MACRO	reglist 		;; push those registers
IRP reg,<reglist>
	?stackdepth = ?stackdepth + 1
	PUSH	reg
ENDM
ENDM
.xcref	SaveReg

BREAK <RestoreReg - unsave some registers>

RestoreReg  MACRO   reglist		;; pop those registers
IRP reg,<reglist>
	?stackdepth = ?stackdepth - 1
	POP	reg
ENDM
ENDM
.xcref	RestoreReg
