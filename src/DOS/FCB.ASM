TITLE	FCB - FCB parse calls for MSDOS
NAME	FCB
; Low level routines for parsing names into FCBs and analyzing
;    filename characters
;
;   MakeFcb
;   NameTrans
;   PATHCHRCMP
;   GetLet
;   TESTKANJ
;   NORMSCAN
;   DELIM
;
.xlist
include dosseg.asm


TableLook   equ -1

HIGH_TABLE Segment BYTE PUBLIC 'HIGH_TABLE'
Zero	label byte
HIGH_TABLE ENDS

CODE	SEGMENT BYTE PUBLIC  'CODE'
	ASSUME	SS:DOSGROUP,CS:DOSGROUP

.xcref
include dossym.inc
include devsym.inc
include doscntry.inc			;AN000; 	2/12/KK
.cref
.list

	i_need	Name1,BYTE
	i_need	Creating,BYTE
	i_need	Attrib,BYTE
	i_need	SpaceFlag,BYTE
	i_need	FILE_UCASE_TAB,byte	   ;DOS 3.3
	i_need	COUNTRY_CDPG,byte	;AN000; 	2/12/KK
	i_need	DrvErr,BYTE		;AN000; 	2/12/KK
	i_need	DOS34_FLAG,WORD 	;AN000; 	2/12/KK

	procedure   MakeFcb,NEAR
ScanSeparator	=   1
DRVBIT	EQU	2
NAMBIT	EQU	4
EXTBIT	EQU	8
	MOV	BYTE PTR [SpaceFlag],0
	XOR	DL,DL		; Flag--not ambiguous file name
	TEST	AL,DRVBIT	; Use current drive field if default?
	JNZ	DEFDRV
	MOV	BYTE PTR ES:[DI],0	; No - use default drive
DEFDRV:
	INC	DI
	MOV	CX,8
	TEST	AL,NAMBIT	; Use current name fields as defualt?
	XCHG	AX,BX		; Save bits in BX
	MOV	AL," "
	JZ	FILLB		; If not, go fill with blanks
	ADD	DI,CX
	XOR	CX,CX		; Don't fill any
FILLB:
	REP	STOSB
	MOV	CL,3
	TEST	BL,EXTBIT	; Use current extension as default
	JZ	FILLB2
	ADD	DI,CX
	XOR	CX,CX
FILLB2:
	REP	STOSB
	XCHG	AX,CX		; Put zero in AX
	STOSW
	STOSW			; Initialize two words after to zero
	SUB	DI,16		; Point back at start
	TEST	BL,ScanSeparator; Scan off separators if not zero
	JZ	SKPSPC
	CALL	SCANB		; Peel off blanks and tabs
	CALL	DELIM		; Is it a one-time-only delimiter?
	JNZ	NOSCAN
	INC	SI		; Skip over the delimiter
SKPSPC:
	CALL	SCANB		; Always kill preceding blanks and tabs
NOSCAN:
	CALL	GETLET
	JBE	NODRV		; Quit if termination character
 IF  DBCS
	CALL	TESTKANJ	;AN000;; 2/18/KK
	JNE	NODRV		;AN000;; 2/18/KK
 ENDIF
	CMP	BYTE PTR[SI],":"        ; Check for potential drive specifier
	JNZ	NODRV
	INC	SI		; Skip over colon
	SUB	AL,"@"          ; Convert drive letter to drive number (A=1)
	JBE	BADDRV		; Drive letter out of range

	PUSH	AX
	Invoke	GetVisDrv
	POP	AX
	JNC	HavDrv
	CMP	[DrvErr],error_not_DOS_disk  ; if not FAt drive
	JZ	HavDrv			     ; assume ok
BADDRV:
	MOV	DL,-1
HAVDRV:
	STOSB			; Put drive specifier in first byte
	INC	SI
	DEC	DI		; Counteract next two instructions
NODRV:
	DEC	SI		; Back up
	INC	DI		; Skip drive byte

	entry	NORMSCAN

	MOV	CX,8
	CALL	GETWORD 	; Get 8-letter file name
	CMP	BYTE PTR [SI],"."
	JNZ	NODOT
	INC	SI		; Skip over dot if present
	TEST	[DOS34_FLAG],DBCS_VOLID2
	JZ	VOLOK
	MOVSB			; 2nd byte of DBCS
	MOV	CX,2
	JMP	SHORT contvol
VOLOK:
	MOV	CX,3		; Get 3-letter extension
contvol:
	CALL	MUSTGETWORD
NODOT:
	MOV	AL,DL
	return

NONAM:
	ADD	DI,CX
	DEC	SI
	return

GETWORD:
	CALL	GETLET
	JBE	NONAM		; Exit if invalid character
	DEC	SI
;
; UGH!!! Horrible bug here that should be fixed at some point:
; If the name we are scanning is longer than CX, we keep on reading!
;
MUSTGETWORD:
	CALL	GETLET
;
; If spaceFlag is set then we allow spaces in a pathname
;
	JB	FILLNAM
	JNZ	MustCheckCX
	TEST	BYTE PTR [SpaceFlag],0FFh
	JZ	FILLNAM
	CMP	AL," "
	JNZ	FILLNAM

MustCheckCX:
	JCXZ	MUSTGETWORD
	DEC	CX
	CMP	AL,"*"          ; Check for ambiguous file specifier
	JNZ	NOSTAR
	MOV	AL,"?"
	REP	STOSB
NOSTAR:
	STOSB

 IF   DBCS
	CALL	TESTKANJ
	JZ	NOTDUAL3
	JCXZ	BNDERR		; Attempt to straddle boundry
	MOVSB			; Transfer second byte
	DEC	CX
	JMP	MUSTGETWORD
BNDERR:
	TEST	[DOS34_FLAG],DBCS_VOLID
	JZ	notvolumeid
	TEST	[DOS34_FLAG],DBCS_VOLID2
	JNZ	notvolumeid
	OR	[DOS34_FLAG],DBCS_VOLID2
	JMP	MUSTGETWORD

notvolumeid:
;;	INC	CX		; Undo the store of the first byte
	DEC	DI
	MOV	AL," "          ;PTM.
	STOSB			;PTM.
	INC	SI		;PTM.
	JMP	MUSTGETWORD	;PTM.

NOTDUAL3:
  ENDIF

	CMP	AL,"?"
	JNZ	MUSTGETWORD
	OR	DL,1		; Flag ambiguous file name
	JMP	MUSTGETWORD
FILLNAM:
	MOV	AL," "
	REP	STOSB
	DEC	SI
	return

SCANB:
	LODSB
	CALL	SPCHK
	JZ	SCANB
 IF  DBCS
	CMP	AL,81H		;AN000;; 1ST BYTE OF DBCS BLANK 2/18/KK
	JNE	SCANB_EXIT	;AN000;; 2/18/KK  3/31/KK revoved
	CALL	TESTKANJ	;AN000;; 2/23/KK  3/31/KK revoved
	JE	SCANB_EXIT	;AN000;; 2/18/KK  3/31/KK revoved
	CMP	BYTE PTR [SI],40H;AN000;H ; 2ND BYTE OF DBCS BLANK 2/18/KK 3/31/KK revove
	JNE	SCANB_EXIT	;AN000;; 2/18/KK  3/31/KK revoved
	INC	SI		;AN000;; 2/18/KK  3/31/KK revoved
	JMP	SCANB		;AN000;; 2/18/KK  3/31/KK revoved
    SCANB_EXIT: 		;AN000;; 2/18/KK  3/31/KK revoved
 ENDIF
	DEC	SI
	return
EndProc MakeFCB

;
; NameTrans is used by FindPath to scan off an element of a path.  We must
; allow spaces in pathnames
;
;   Inputs:	DS:SI points to start of path element
;   Outputs:	Name1 has unpacked name, uppercased
;		ES = DOSGroup
;		DS:SI advanced after name
;   Registers modified: DI,AX,DX,CX
procedure   NameTrans,near
	ASSUME	DS:NOTHING,ES:NOTHING
	MOV	BYTE PTR [SpaceFlag],1
	context ES
	MOV	DI,OFFSET DOSGROUP:NAME1
	PUSH	DI
	MOV	AX,'  '
	MOV	CX,5
	STOSB
	REP	STOSW		; Fill "FCB" at NAME1 with spaces
	XOR	AL,AL		; Set stuff for NORMSCAN
	MOV	DL,AL
	STOSB
	POP	DI

	CALL	NORMSCAN
IF DBCS 			;AN000;;KK.
	MOV	AL,[NAME1]	;AN000;;KK. check 1st char
	invoke	testkanj	;AN000;;KK. dbcs ?
	JZ	notdbcs 	;AN000;;KK. no
	return			;AN000;;KK. yes
notdbcs:
ENDIF
	CMP	[NAME1],0E5H
	retnz
	MOV	[NAME1],5	; Magic name translation
	return

EndProc nametrans

Break	<GETLET, DELIM -- CHECK CHARACTERS AND CONVERT>

If TableLook
ChType	Macro	ch,bits
	ORG	CharType-Zero+ch
	db	bits
	ENDM

; Private classification data follows the retained low boundary. Every reader
; selects the executing kernel's CS, so DOS=LOW and DOS=HIGH share one owner.
HIGH_TABLE SEGMENT BYTE PUBLIC 'HIGH_TABLE'
	PUBLIC	CharType
Public FCB001S,FCB001E
FCB001S  label byte
CharType    DB	256 dup (-1)
	ChType	".", <LOW (NOT (     fChk))>
	ChType	'"', <LOW (NOT (fFCB+fChk))>
	ChType	"/", <LOW (NOT (fFCB+fChk))>
	ChType	"\", <LOW (NOT (fFCB+fChk))>
	ChType	"[", <LOW (NOT (fFCB+fChk))>
	ChType	"]", <LOW (NOT (fFCB+fChk))>
	ChType	":", <LOW (NOT (fFCB+fChk+fDelim))>
	ChType	"<", <LOW (NOT (fFCB+fChk+fDelim))>
	ChType	"|", <LOW (NOT (fFCB+fChk+fDelim))>
	ChType	">", <LOW (NOT (fFCB+fChk+fDelim))>
	ChType	"+", <LOW (NOT (fFCB+fChk+fDelim))>
	ChType	"=", <LOW (NOT (fFCB+fChk+fDelim))>
	ChType	";", <LOW (NOT (fFCB+fChk+fDelim))>
	ChType	",", <LOW (NOT (fFCB+fChk+fDelim))>
	ChType	0,   <LOW (NOT (fFCB+fChk))>	       ; NUL
	ChType	1,   <LOW (NOT (fFCB+fChk))>	       ; ^A
	ChType	2,   <LOW (NOT (fFCB+fChk))>	       ; ^b
	ChType	3,   <LOW (NOT (fFCB+fChk))>	       ; ^c
	ChType	4,   <LOW (NOT (fFCB+fChk))>	       ; ^d
	ChType	5,   <LOW (NOT (fFCB+fChk))>	       ; ^e
	ChType	6,   <LOW (NOT (fFCB+fChk))>	       ; ^f
	ChType	7,   <LOW (NOT (fFCB+fChk))>	       ; ^g
	ChType	8,   <LOW (NOT (fFCB+fChk))>	       ; ^h
	ChType	9,   <LOW (NOT (fFCB+fChk+fDelim+fSpChk))> ; Tab
	ChType	10,  <LOW (NOT (fFCB+fChk))>	       ; ^j
	ChType	11,  <LOW (NOT (fFCB+fChk))>	       ; ^k
	ChType	12,  <LOW (NOT (fFCB+fChk))>	       ; ^l
	ChType	13,  <LOW (NOT (fFCB+fChk))>	       ; ^m
	ChType	14,  <LOW (NOT (fFCB+fChk))>	       ; ^n
	ChType	15,  <LOW (NOT (fFCB+fChk))>	       ; ^o
	ChType	16,  <LOW (NOT (fFCB+fChk))>	       ; ^p
	ChType	17,  <LOW (NOT (fFCB+fChk))>	       ; ^q
	ChType	18,  <LOW (NOT (fFCB+fChk))>	       ; ^r
	ChType	19,  <LOW (NOT (fFCB+fChk))>	       ; ^s
	ChType	20,  <LOW (NOT (fFCB+fChk))>	       ; ^t
	ChType	21,  <LOW (NOT (fFCB+fChk))>	       ; ^u
	ChType	22,  <LOW (NOT (fFCB+fChk))>	       ; ^v
	ChType	23,  <LOW (NOT (fFCB+fChk))>	       ; ^w
	ChType	24,  <LOW (NOT (fFCB+fChk))>	       ; ^x
	ChType	25,  <LOW (NOT (fFCB+fChk))>	       ; ^y
	ChType	26,  <LOW (NOT (fFCB+fChk))>	       ; ^z
	ChType	27,  <LOW (NOT (fFCB+fChk))>	       ; ^[
	ChType	28,  <LOW (NOT (fFCB+fChk))>	       ; ^\
	ChType	29,  <LOW (NOT (fFCB+fChk))>	       ; ^]
	ChType	30,  <LOW (NOT (fFCB+fChk))>	       ; ^^
	ChType	31,  <LOW (NOT (fFCB+fChk))>	       ; ^_
	ChType	" ", <LOW (NOT (     fChk+fDelim+fSpChk))>
	ChType	255, -1
FCB001E label byte
HIGH_TABLE ENDS
ENDIF
;
; Get a byte from [SI], convert it to upper case, and compare for delimiter.
; ZF set if a delimiter, CY set if a control character (other than TAB).
;
	procedure   GetLet,NEAR
	LODSB
  entry GetLet2 			    ;AN000;; called by uCase
	PUSH	BX
	MOV	BX,OFFSET DOSGROUP:FILE_UCASE_TAB+2
  getget:
	CMP	AL,"a"
	JB	CHK1
	CMP	AL,"z"
	JA	CHK1
	SUB	AL,20H		; Convert to upper case
CHK1:
	CMP	AL,80H		; DOS 3.3
	JB	GOTIT		; DOS 3.3
	SUB	AL,80H		;translate to upper case with this index
;
	XLAT	BYTE PTR CS:[BX]
If TableLook
GOTIT:
	PUSH	AX
	MOV	BX,OFFSET DOSGROUP:CharType
	XLAT	BYTE PTR CS:[BX]

	TEST	AL,fChk
	POP	AX
	POP	BX
	RET
  entry GetLet3 			     ;AN000; called by uCase
	PUSH	BX
	JMP	getget

ELSE
GOTIT:
	POP	BX
	CMP	AL,"."
	retz
	CMP	AL,'"'
	retz
	CALL	PATHCHRCMP
	retz
	CMP	AL,"["
	retz
	CMP	AL,"]"
	retz
ENDIF

entry	DELIM

IF TableLook
	PUSH	AX
	PUSH	BX
	MOV	BX,OFFSET DOSGroup:CharType
	XLAT	BYTE PTR CS:[BX]
	TEST	AL,fDelim
	POP	BX
	POP	AX
	RET
ELSE
	CMP	AL,":"
	retz

	CMP	AL,"<"
	retz
	CMP	AL,"|"
	retz
	CMP	AL,">"
	retz

	CMP	AL,"+"
	retz
	CMP	AL,"="
	retz
	CMP	AL,";"
	retz
	CMP	AL,","
	retz
ENDIF
entry SPCHK
IF  TableLook
	PUSH	AX
	PUSH	BX
	MOV	BX,OFFSET DOSGroup:CharType
	XLAT	BYTE PTR CS:[BX]
	TEST	AL,fSpChk
	POP	BX
	POP	AX
	RET
ELSE
	CMP	AL,9		; Filter out tabs too
	retz
; WARNING! " " MUST be the last compare
	CMP	AL," "
	return
ENDIF
EndProc GetLet

Procedure   PATHCHRCMP,NEAR
	CMP	AL,'/'
	JBE	PathRet
	CMP	AL,'\'
	return
GotFor:
	MOV	AL,'\'
	return
PathRet:
	JZ	GotFor
	return
EndProc PathChrCMP


 IF  DBCS
;---------------------	2/12/KK
; Function: Check if an input byte is in the ranges of DBCS vectors.
;
;   Input:   AL ; Code to be examined
;
;  Output:   ZF = 1 :  AL is SBCS      ZF = 0 : AL is a DBCS leading byte
;
;  Register:  All registers are unchanged except FL
;
procedure   TESTKANJ,NEAR
	call	Chk_DBCS
	jc	TK_DBCS
	cmp	AL,AL		; set ZF
	return
TK_DBCS:
	PUSH	AX
	XOR	AX,AX		;Set ZF
	INC	AX		;Reset ZF
	POP	AX
	return
EndProc TESTKANJ
;
Chk_DBCS	PROC
	PUSH	DS
	PUSH	SI
	PUSH	BX
	Context DS
	MOV	BX,offset DOSGROUP:COUNTRY_CDPG.ccSetDBCS
	LDS	SI,[BX+1]		; set EV address to DS:SI
	ADD	SI,2			; Skip length
DBCS_LOOP:
	CMP	WORD PTR [SI],0 	; terminator ?
	JE	NON_DBCS		; if yes, no DBCS
	CMP	AL,[SI] 		; else
	JB	DBCS01			; check if AL is
	CMP	AL,[SI+1]		; in a range of Ev
	JA	DBCS01			; if yes, DBCS
	STC				; else
	JMP	DBCS_EXIT		; try next DBCS Ev
DBCS01:
	ADD	SI,2
	JMP	DBCS_LOOP
NON_DBCS:
	CLC
DBCS_EXIT:
	POP	BX
	POP	SI
	POP	DS
	RET
Chk_DBCS	ENDP
 ENDIF
CODE	ENDS
    END
