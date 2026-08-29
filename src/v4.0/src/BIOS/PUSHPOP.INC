?stackdepth = 0				;; JWASM: init stack-depth counter (DOSMAC.INC inits
					;; it for DOS; BIOS PUSHPOP.INC relied on MASM
					;; treating the undefined symbol as 0)
	IF1								  ;3.30

SaveReg MACRO	reglist 		;; push those registers
IRP reg,<reglist>
	?stackdepth = ?stackdepth + 1
	PUSH	reg
ENDM
ENDM
.xcref	SaveReg


RestoreReg  MACRO   reglist		;; pop those registers
IRP reg,<reglist>
	?stackdepth = ?stackdepth - 1
	POP	reg
ENDM
ENDM
.xcref	RestoreReg

	ENDIF								  ;3.30
