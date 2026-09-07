	PAGE	,132			; 
TITLE	IFSFUNC DOS CALLBACK ROUTINES - Routines for ifs
NAME	IFSFDOS
;***********************************************************************************
; IFS DOS Callback Routines
; IFSFDOS
.xlist
.xcref
INCLUDE IFSFSYM.INC
INCLUDE IFSSYM.INC
INCLUDE DOSSYM.INC
INCLUDE DEVSYM.INC
.cref
.list
.sall
AsmVars <IBM, INSTALLED, DEBUG, PATHGEN>
IFSSEG	SEGMENT BYTE PUBLIC 'IFSSEG'
IFSSEG	ENDS
include dosseg.asm
DATA		SEGMENT WORD PUBLIC 'DATA'
	; DOSGROUP data
	Extrn	YEAR:WORD
	Extrn	YRTAB:BYTE
	Extrn	MONTAB:BYTE
DATA		ENDS
IFSSEG	SEGMENT BYTE PUBLIC 'IFSSEG'
	ASSUME	SS:DOSGROUP,CS:IFSSEG
	;IFS Data
	Extrn	IFSFUNC_FLAGS:WORD
	Extrn	DOSCALL@:DWORD
	Extrn	fAssign:BYTE
	Extrn	fPrint:BYTE
BREAK <SET_IFS_DOSCALL@ - prep for ifs dos requests to come to ifsfunc>
;************************************************************************************
; SET_IFS_DOSCALL@
;Called by:
;     IFSFUNCINIT
; Routines called:
;	none
; Inputs:
;	   DS-ifsseg
; Function:
;	replace ifs_doscall@ addresses in all ifs driver headers with
;	ifsfunc address
; Outputs:
;	none
; Notes: all preserved
;************************************************************************************
	procedure   SET_IFS_DOSCALL@,NEAR
ASSUME	DS:IFSSEG
	TEST	IFSFUNC_FLAGS,NO_IFS_DRIVERS
	JZ	SID_20
	transfer ifs_1000
SID_20:
	SaveReg <AX,BX,ES,DI,SI>
	MOV	AH,Get_In_Vars			; Get ptr to ifs hdr chain
	INT	21h				; es:bx -> sysinitvars
	LES	DI,ES:[BX.SYSI_IFS]		; es:di -> 1st ifs driver
	SaveReg <ES,DI>
	LES	DI,ES:[DI.IFS_DOSCALL@]
	MOV	WORD PTR [DOSCALL@],DI
	MOV	WORD PTR [DOSCALL@+2],ES
	RestoreReg <DI,ES>			; 1st driver addr
	MOV	SI,OFFSET IFSFUNC_DOSCALL@
SID_40: 					; *** loop here on ifs_doscall@ fixing
	MOV	WORD PTR ES:[DI.IFS_DOSCALL@],SI
	MOV	WORD PTR ES:[DI.IFS_DOSCALL@+2],DS
	LES	DI,ES:[DI.IFS_NEXT]		; check next fs driver
	CMP	DI,NULL_PTR			; if ptr null, end of ifs drivers
	JNE	SID_40
	MOV	AX,ES
	CMP	AX,NULL_PTR
	JNE	SID_40
SID_1000:
	RestoreReg <SI,DI,ES,BX,AX>
	return
EndProc SET_IFS_DOSCALL@
BREAK <IFSFUNC_DOSCALL@ - DOS Callbacks>
;************************************************************************************
; IFSFUNC_DOSCALL@
;Called by:
;     IFS Drivers
; Routines called:
;	none
; Inputs:
;	   SS-dosgroup
; Function:
; Outputs:
;	none
; Notes: none preserved
;************************************************************************************
	procedure   IFSFUNC_DOSCALL@,FAR
	CMP	AH,33
	JNE	ID_20
	CALL	DOS_RETURN_ASSIGN_MODE
	JMP	SHORT ID_1000
ID_20:
	CMP	AH,34
	JNE	ID_40
	CALL	DOS_TO_NET_DATE
	JMP	SHORT ID_1000
ID_40:
	CMP	AH,35
	JNE	ID_100
	CALL	NET_TO_DOS_DATE
	JMP	SHORT ID_1000
ID_100:
	CALL	CS:[DOSCALL@]
ID_1000:
	RET
EndProc IFSFUNC_DOSCALL@


BREAK <DOS_RETURN_ASSIGN_MODE -- Return Assign Mode>

;************************************************************************************
;
; DOS_RETURN_ASSIGN_MODE
;
; Called by:  IFSFUNC_DOSCALL@
;
; Routines called:   None
;
; Inputs:
;	    BL = macro type
;		 3 - device
;		 4 - drive
; Function:
;	If macro type = 3 (network printer) THEN
;	   BX = fPrint .AND. 1
;	Elseif macro type = 4 (network disk) THEN
;	   BX = fAssign .AND. 1
;	Else set error_invalid_function
;
; Output:
;	Carry clear - BH = mode (0 - off, 1 - on)
;	Carry set   - AL error code
;
; Notes:  This routine needed only for UNC file system.  This is the
;	  only FS that supports pause.
;
;************************************************************************************

	Procedure   DOS_RETURN_ASSIGN_MODE,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	CMP	BL,3			; if (type == drive)
	JZ	DRAM_20
	CMP	BL,4
	JNZ	DRAM_60
	MOV	BH,fAssign		;    t = fAssign;
	JMP	Short DRAM_40		; else
DRAM_20:				; if (type == print)
	MOV	BH,fPrint		;    t = fPrint;
DRAM_40:
	AND	BH,1			;   return t&1;
	transfer ifs_990		; go to general good ret in util
DRAM_60:
	MOV	AL,error_invalid_function
	transfer ifs_980		; go to general bad ret in util
EndProc DOS_RETURN_ASSIGN_MODE

BREAK <DOS_TO_NET_DATE	-- Convert dos date/time to network date>

;************************************************************************************
;
; DOS_TO_NET
;
; Called by:  IFSFUNC_DOSCALL@
;
; Routines called:   None
;
; Inputs:
;	DX = MS-DOS Date
;	CX = MS-DOS Time
; Function:
;	Convert DOS Date Time to Network date
; Outputs:
;	DX:CX = Seconds since 1-1-70
; No other registers Revised
;
;************************************************************************************

FOURYEARS	= (3*365) + 366 	; Days in four years

	procedure DOS_TO_NET_DATE,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	OR	AL,AL			; check where to get dos date/time
	JNZ	DTND_20
	CallInstall DATE16,MultDOS,13	; Get local date/time
	MOV	CX,DX
	XCHG	AX,DX
DTND_20:
	PUSH	DS
	PUSH	SS
	POP	DS
ASSUME	DS:DOSGROUP
	PUSH	[YEAR]			; The routines in DOS (in particular
					;	GET_DATE) do not like [YEAR]
					;	getting changed by the call
					;	to SETYEAR.
	PUSH	SI
	PUSH	BX
	PUSH	AX
	PUSH	CX
	PUSH	DX
	MOV	CL,9
	SHR	DX,CL			; Year to DL
	MOV	CX,DX			; Year in CX (CL)
	POP	DX
	AND	DX,1FFH 		; Mask off year
	SHL	DX,1
	SHL	DX,1
	SHL	DX,1			; Month in DH
	SHR	DL,1
	SHR	DL,1
	SHR	DL,1			; Right justify day in DL
	CallInstall SetYear,MultDOS,27	; Set [YEAR] and # days in FEB
	SHR	CX,1
	SHR	CX,1			; Divide year by 4, chuck remainder
	MOV	AX,FOURYEARS
	MOV	BX,DX			; Get DX out of way
	MUL	CX			; # days in AX
	MOV	CL,BYTE PTR [YEAR]
	AND	CL,3			; Get remainder from / by 4
	MOV	SI,OFFSET DOSGROUP:YRTAB
	MOV	DX,AX
	SHL	CX,1			; Two entries/year
	CallInstall DSum,MultDOS,28,<AX>,<SI>
	MOV	CL,BH			; Month
	DEC	CX			; Make 0 indexed
	MOV	SI,OFFSET DOSGROUP:MONTAB
	CallInstall DSum,MultDOS,28,<AX>,<AX>
	MOV	CL,BL			; day of month
	DEC	CX			; Make 0 indexed
	ADD	CX,DX			; CX is days since 1-1-80
; The following three instructions implement this:
;		CX * 15180H sec/day = (CX * 5180H) + (CX * 10000H)
	MOV	AX,5180h
	MUL	CX			; (DX:AX) = days * 5180h
	ADD	DX,CX			; (DX:AX) = days * 15180h = seconds
	ADD	AX,0A600H
	ADC	DX,012CEH		; Bias by # seconds from 1-1-70 to
					; 1-1-80 (12CEA600H)
	POP	BX			; Get DOS time
	PUSH	AX
	PUSH	DX			; Save date seconds
	PUSH	BX
	MOV	CL,11
	SHR	BX,CL			; BX is hours
	MOV	AX,60
	MUL	BX			; AX hours converted to minutes
					;    5A0H min/day so DX = 0
	POP	BX
	PUSH	BX
	AND	BX,7FFH 		; Mask off hours
	MOV	CL,5
	SHR	BX,CL			; BX is minutes
	ADD	AX,BX			; AX is minutes
	MOV	BX,60
	MUL	BX			; DX:AX is hours:min converted to sec
	POP	BX
	AND	BX,1FH			; BX is seconds/2
	SHL	BX,1			; BX is seconds
	ADD	AX,BX
	ADC	DX,0
	MOV	CX,AX			; DX:CX is DOS time in seconds
	POP	BX
	POP	SI			; BX:SI is DOS Date in seconds
	ADD	CX,SI
	ADC	DX,BX			; DX:CX is NET time
	POP	AX
	POP	BX
	POP	SI
	POP	[YEAR]
	POP	DS
	return
EndProc DOS_TO_NET_DATE
; Inputs:
;	DX:CX = Seconds since 1-1-70
; Function:
;	Convert Network date to DOS Date Time
;    NOTE: WARNING!!!!!!!
;	This routine WILL NOT convert network times > 92CEA5FFH
;	(7FFFFFFF + 12CEA600). If such a time is encountered this
;	routine returns 1-1-80 0:0:0.
; Outputs:
;	DX = MS-DOS Date
;	CX = MS-DOS Time
; No other registers Revised
	procedure NET_TO_DOS_DATE,NEAR
ASSUME	DS:NOTHING,ES:NOTHING
	SUB	CX,0A600H
	SBB	DX,012CEH		; UnBias by # seconds from 1-1-70 to
					; 1-1-80 (12CEA600H)
	JNC	GO_ON
	; Date is before 1-1-80
TO_BIG_LITTLE_TIME:
	XOR	DX,DX
	MOV	CX,DX	; Set 1-1-80 0:0:0
	return
GO_ON:
	TEST	DX,8000H		; Check for high bit
	JNZ	TO_BIG_LITTLE_TIME
	PUSH	DS
	PUSH	SS
	POP	DS
ASSUME	DS:DOSGROUP
	PUSH	[YEAR]			; The routines in DOS (in particular
					;	GET_DATE) do not like [YEAR]
					;	getting changed by the call
					;	to SETYEAR.
	PUSH	AX
	PUSH	BX
	PUSH	SI
	PUSH	BP
	XCHG	AX,CX			; DX:AX # seconds
	MOV	SI,0A8C0h		; (si) = seconds in a half day
					;    15180H/2
; NOTE: The following DIV is the reason we can't convert times with the
;	high bit set (after they're unbiased by 1-1-80 - 1-1-70).
;	If we tried one it MIGHT overflow. The cutoff is
;	actually (A8C0 * FFFF) + A8BF = A8BFFFFF but we choose a smaller
;	number (7FFFFFFF) because it's easier to test for. 7FFFFFFF =
;	about 68 years from 1-1-80 which is 1-1-2048.
	DIV	SI			; (AX) = 2*days
					; (CX) = half-day remainder
	MOV	BX,DX
	XOR	DX,DX
	MOV	CX,DX
	SHR	AX,1			; DX:AX = days
	JNC	NTDD1			; didn't shift off a bit, no extra rem
	ADD	BX,0A8C0h		; did shift bit, adjust remainder
	ADC	CX,0			;   by extra 1/2 day of seconds
	;DX:AX is # days since 1-1-80
	;CX:BX is seconds into that day
NTDD1:
	PUSH	DX
	PUSH	AX
	MOV	DX,CX
	MOV	AX,BX
	MOV	CX,60			; 60 sec/min
	DIV	CX
	;AX is min, DX(DL) is secs
	DIV	CL			; 60 min/hr
	;AH is Min, AL is hrs
	SHR	DL,1			; Div seconds by 2
	AND	DL,1FH			; DL is seconds/2
	MOV	DH,AH			; Copy min to DH
	MOV	CL,5
	SHL	AH,CL			; Low 3 bits of min in high 3 bits
	OR	DL,AH			; DL is now low byte of time
	MOV	CL,3
	SHR	DH,CL			; High 3 bits of min to low 3 bits
	AND	DH,7
	MOV	CL,3
	SHL	AL,CL			; Hours to high 5 bits
	AND	AL,0F8H
	OR	DH,AL			; DX is now DOS time
	MOV	CX,DX
	POP	AX
	POP	DX			; DX:AX days since 1-1-80
	PUSH	CX			; Stash time
	MOV	CX,FOURYEARS
	DIV	CX			; AX # four year increments
					; DX remainder days
	SHL	AX,1
	SHL	AX,1
	SHL	AX,1			; Mult by 8 (AX # 1/2 years)
	MOV	CX,AX
	MOV	SI,OFFSET DOSGROUP:YRTAB
	CallInstall DSlide,MultDOS,29,<AX>,<AX>
	SHR	CX,1			; 1/2 years to whole years
	JNC	SK
	ADD	DX,200			; Extra 1/2 year
SK:
	CallInstall SetYear,multDOS,27
	PUSH	CX
	MOV	CL,1			; At least at first month in year
	MOV	SI,OFFSET DOSGROUP:MONTAB
	CallInstall DSlide,MultDOS,29,<AX>,<AX>
	INC	DX			; Days start at 1
	POP	AX
	MOV	CH,CL
	; DL is day, CH is month, AL is year
	SHL	AL,1			; Year to high 7 bits
	AND	AL,0FEH
	MOV	AH,CH
	MOV	CL,3
	SHR	AH,CL			; High bit of month to bit 0
	AND	AH,1
	OR	AH,AL			; AH is high byte of date
	AND	DL,1FH			; Day is low 5 bits
	MOV	CL,5
	SHL	CH,CL			; Low 3 bits of month to high 3 bits
	AND	CH,0E0H
	OR	DL,CH
	MOV	DH,AH			; Date in DX
	POP	CX			; Time to CX
	POP	BP
	POP	SI
	POP	BX
	POP	AX
	POP	[YEAR]
	POP	DS
	return
EndProc NET_TO_DOS_DATE
IFSSEG	ENDS
END
