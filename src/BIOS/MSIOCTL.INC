	%OUT MSIOCTL.SIL...
	INCLUDE IOCTL.INC
;	$SALUT $ioctl$

;==============================================================================
;REVISION HISTORY:
;AN000 - New for DOS Version 4.00 - J.K.
;AC000 - Changed for DOS Version 4.00 - J.K.
;AN00x - PTM number for DOS Version 4.00 - J.K.
;==============================================================================
;AN001 - P58 Diskcopy format fails when error occurs during format op.6/26/87 J.K.
;AN002; - d24  MultiTrack= command added.			   6/29/87 J.K.
;AN003; - p155 Format intermittant failre due to haed settle time  8/18/87 J.K.
;AN004; D113 Disable I/O access to unformatted media		    9/03/87 J.K.
;AN005; P985 Allow I/O access to unformtted media		    9/14/87 J.K.
;AN006; D241 Provide support of Multi-track Format/Verify	    9/23/87 J.K.
;AN007; P1535 Unformatted hard file problem			   10/15/87 J.K.
;AN008; P2590 Change the recommended BPB info. after AFS format    11/20/87 J.K.
;AN009; P2828 Do not retry for multi-track format request	   12/08/87 J.K.
;AN010; P2781 Changeline error behavior incompatibile with DOS 3.3. 1/06/88 J.K.
;AN011; P3178 Set Media ID should update media info in BDS table.   1/21/88 J.K.
;AN012; D490 IOCTL subfunction 63h,43h,64h,44h conflicts with OS2   2/26/88 J.K.
;==============================================================================

;J.K. 10/15/87
;NOTE: GetAccessFlag/SetAccessFlag is unpublished function.
;      This function is intended to give the user to control the
;      BDS table FLAGS of UNFORMATTED_MEDIA bit.
;      GetAccessFlag will show the status -
;	 A_DISKACCESS_CONTROL.DAC_ACCESS_FLAG = 0 DISK I/O not allowed
;						1 DISK I/O allowed
;      SetAccessFlag will Set/Reset the UNFORMATTED_MEDIA bit in FLAGS -
;	 A_DISKACCESS_CONTROL.DAC_ACCESS_FLAG = 0 Allow disk I/O
;						1 Disallow disk I/O
;------------------------------------------------------------------------------

; GENERIC IOCTL DISPATCH TABLES
;
PUBLIC IOREADJUMPTABLE, IOWRITEJUMPTABLE
IOREADJUMPTABLE DB	7			;AN012;maximum number (0 based)
		DW	OFFSET GETDEVICEPARAMETERS		;60h
		DW	OFFSET READTRACK			;61h
		DW	OFFSET VERIFYTRACK			;62h
		dw	Cmd_Err_Proc				;AN012;Overlapped with OS2 subfunction
		dw	Cmd_Err_Proc				;AN012;
		dw	Cmd_Err_Proc				;AN012;
		dw	GetMediaID				;AN000;AN012;66h
		dw	GetAccessFlag				;AN007;AN012;67h Unpublished function

IOWRITEJUMPTABLE DB	7					;AN012;
		DW	OFFSET SETDEVICEPARAMETERS		;40h
		DW	OFFSET WRITETRACK			;41h
		DW	OFFSET FORMATTRACK			;42h
		dw	Cmd_Err_Proc				;AN012;
		dw	Cmd_Err_Proc				;AN012;
		dw	Cmd_Err_Proc				;AN012;
		dw	SetMediaID				;AN000;AN012;46h
		dw	SetAccessFlag				;AN007;AN012;47h Unpublished function
;
; TRACKTABLE CONTAINS A 4-TUPLES (C,H,R,N) FOR EACH SECTOR IN A TRACK
; C = CYLINDER NUMBER, H = HEAD NUMBER, R = SECTOR ID, N = BYTES PER SECTOR
;	N	BYTES PER SECTOR
;      ---	----------------
;	0	      128
;	1	      256
;	2	      512
;	3	     1024
;
	INCLUDE MSIOLIM.INC
	EXTRN SECTORSPERTRACK:WORD, TRACKTABLE:BYTE, MEDIATYPE:BYTE
	EXTRN MEDIA_SET_FOR_FORMAT:BYTE, Had_Format_Error:BYTE, TEMPDPT:DWORD
Dsk_time_out_Err	equ	80h	; Time out error (No media present).
Dsk_change_line_Err	equ	6h	; Change line error
Dsk_illegal_combination equ	0Ch	; Return code of ah=18h function.

; TEMP DISK BASE TABLE. IT HOLDS THE THE CURRENT DPT WHICH IS THEN REPLACED BY
; THE ONE PASSED BY "NEW ROMS" BEFORE WE PERFORM A FORMAT OPERATION. THE OLD
; DPT IS RESTORED IN RESTOREOLDDPT. THE FIRST ENTRY (DISK_SPECIFY_1) IS -1 IF
; THIS TABLE DOES NOT CONTAIN THE PREVIOUSLY SAVED DPT.
; Storage is owned by the retained-low MSIOLDAT.INC block.

;
; GENERIC$IOCTL:
;    PERFORM GENERIC IOCTL REQUEST
;    INPUT:
;	AL	- UNIT NUMBER
;    OUTPUT:
;	IF CARRY SET THEN AL CONTAINS ERROR CODE
;
	PUBLIC GENERIC$IOCTL
GENERIC$IOCTL:
	MESSAGE FTESTDISK,<"GENERIC IOCTL",CR,LF>
	BIOS_LOW_READ LES,BX,<[PTRSAV]>,DS		; ES:BX POINTS TO REQUEST HEADER.
	CALL	SETDRIVE		; DS:DI POINTS TO BDS FOR DRIVE.
;
; AT THIS POINT:
;    ES:BX - POINTS TO THE REQUEST HEADER
;    DS:DI POINTS TO THE BDS FOR THE DRIVE
;
	CMP	ES:[BX].MAJORFUNCTION, RAWIO
	JNE	IOCTL_FUNC_ERR
	MOV	AL, ES:[BX].MINORFUNCTION
	MOV	SI, OFFSET IOREADJUMPTABLE
	TEST	AL, GEN_IOCTL_FN_TST			; TEST OF REQ. FUNCTION
	JNZ	NOTGENERICIOCTLWRITE			;   FUNCTION IS A READ.
	MOV	SI, OFFSET IOWRITEJUMPTABLE
NOTGENERICIOCTLWRITE:
;	 AND	 AL, 0FH
	and	al, 9fH 			;AN000; Try to check other than 6x, 4x.
	CMP	AL, CS:[SI]
	JA	IOCTL_FUNC_ERR
	CBW
	SHL	AX, 1
	INC	SI
	ADD	SI,AX
	LES	BX, ES:[BX].GENERICIOCTL_PACKET
	CALL	CS:[SI]
	JC	FAILGENERIC$IOCTL
	BIOS_JUMP_LOW EXIT,BIOS_LOW_EXIT_ENTRY

FAILGENERIC$IOCTL:
	BIOS_JUMP_LOW ERR$EXIT,BIOS_LOW_ERREXIT_ENTRY

IOCTL_FUNC_ERR:
	BIOS_JUMP_LOW CMDERR,BIOS_LOW_CMDERR_ENTRY
Cmd_Err_Proc:					;AN012;
	pop	dx				;AN012;clear up stack
	pop	dx				;AN012;clear up stack
	jmp	IOCTL_FUNC_ERR			;AN012;Cmd error
;
; GETDEVICEPARAMETERS:
;
; INPUT: DS:DI POINTS TO BDS FOR DRIVE
;	 ES:BX POINTS TO DEVICE PARAMETER PACKET
;
	 PUBLIC GETDEVICEPARAMETERS
GETDEVICEPARAMETERS PROC NEAR
; COPY INFO FROM BDS TO THE DEVICE PARAMETERS PACKET
	MOV	AL, BYTE PTR DS:[DI].FORMFACTOR
	MOV	BYTE PTR ES:[BX].DP_DEVICETYPE, AL
	MOV	AX, WORD PTR DS:[DI].FLAGS
	AND	AX,FNON_REMOVABLE+FCHANGELINE	; MASK OFF OTHER BITS
	MOV	WORD PTR ES:[BX].DP_DEVICEATTRIBUTES, AX
	MOV	AX, WORD PTR DS:[DI].CCYLN
	MOV	WORD PTR ES:[BX].DP_CYLINDERS, AX

; SET MEDIA TYPE TO DEFAULT
	XOR	AL, AL
	MOV	BYTE PTR ES:[BX].DP_MEDIATYPE, AL

; COPY RECOMMENDED BPB
	LEA	SI, BYTE PTR [DI].RBYTEPERSEC
	TEST	BYTE PTR ES:[BX].DP_SPECIALFUNCTIONS, BUILD_DEVICE_BPB
	JZ	USE_BPB_PRESENT
; GET THE CORRECT DISK IN THE DRIVE
	CALL	CHECKSINGLE
; BUILD THE BPB FROM SCRATCH
	IFDEF BIOS_MEDIA_HIGH
	CALL GETBP
	ELSE
	BIOS_CALL_LOW GETBP,BIOS_LOW_GETBP
	ENDIF
	JC	GET_PARM_RET
	LEA	SI,BYTE PTR [DI].BYTEPERSEC
USE_BPB_PRESENT:
	LEA	DI, BYTE PTR [BX].DP_BPB
	MOV	CX, SIZE BPB_TYPE		; FOR NOW USE 'SMALL' BPB
	REP	MOVSB
	CLC
GET_PARM_RET:
	RET
GETDEVICEPARAMETERS ENDP

;
; SETDEVICEPARAMETERS:
;
; INPUT: DS:DI POINTS TO BDS FOR DRIVE
;	 ES:BX POINTS TO DEVICE PARAMETER PACKET
;
	 PUBLIC SETDEVICEPARAMETERS
SETDEVICEPARAMETERS PROC NEAR
; MAKE SURE THE FCHANGED_BY_FORMAT FLAG GETS SET TO KICK DOS INTO LOOKING AT
; THE BPB
	OR	WORD PTR DS:[DI].FLAGS, FCHANGED_BY_FORMAT OR FCHANGED
	TEST	BYTE PTR ES:[BX].DP_SPECIALFUNCTIONS, ONLY_SET_TRACKLAYOUT
	JZ	SHORT SETDEVPARM_1
	JMP	SETTRACKTABLE			; ORIGINALLY TRACKLAYOUT

SETDEVPARM_1:
; COPY INFO FROM THE DEVICE PARAMETERS PACKET TO BDS
	MOV	AL, BYTE PTR ES:[BX].DP_DEVICETYPE
	MOV	BYTE PTR DS:[DI].FORMFACTOR, AL

	MOV	AX, WORD PTR ES:[BX].DP_CYLINDERS
	MOV	WORD PTR DS:[DI].CCYLN, AX

; IF CHANGE LINE IS NOT LOADED THEN IGNORE CHANGELING FLAG
	MOV	AX, WORD PTR ES:[BX].DP_DEVICEATTRIBUTES
	BIOS_LOW_MEM CMP,<[FHAVE96]>,0,DS
	JNZ	HAVE_CHANGE
	AND	AX,NOT FCHANGELINE
HAVE_CHANGE:
; IGNORE ALL BITS EXCEPT NON_REMOVABLE AND CHANGELINE
	AND	AX,FNON_REMOVABLE OR FCHANGELINE
	MOV	CX, WORD PTR DS:[DI].FLAGS
;	 AND	 CX, NOT (FNON_REMOVABLE OR FCHANGELINE OR GOOD_TRACKLAYOUT)
	AND	CX, NOT (FNON_REMOVABLE OR FCHANGELINE OR GOOD_TRACKLAYOUT or UNFORMATTED_MEDIA) ;AN004;AN005;AN007;
	OR	AX, CX
	MOV	WORD PTR DS:[DI].FLAGS, AX

; SET MEDIA TYPE
	MOV	AL, BYTE PTR ES:[BX].DP_MEDIATYPE
	BIOS_LOW_MEM MOV,<MEDIATYPE>,AL,DS
; THE MEDIA CHANGED (MAYBE) SO WE WILL HAVE TO DO A SETDASD THE NEXT TIME
; WE FORMAT A TRACK
	OR	WORD PTR DS:[DI].FLAGS, SET_DASD_TRUE

	SAVEREG <DS,DI,ES,BX>
; FIGURE OUT WHAT WE ARE SUPPOSED TO DO WITH THE BPB

; WERE WE ASKED TO INSTALL A FAKE BPB?
	TEST	BYTE PTR ES:[BX].DP_SPECIALFUNCTIONS, INSTALL_FAKE_BPB
	JNZ	SHORT INSTALLFAKEBPB

; WERE WE RETURNING A FAKE BPB WHEN ASKED TO BUILD A BPB?
	TEST	WORD PTR DS:[DI].FLAGS, RETURN_FAKE_BPB
	JZ	SHORT INSTALLRECOMMENDEDBPB

; WE WERE RETURNING A FAKE BPB BUT WE CAN STOP NOW
	AND	WORD PTR DS:[DI].FLAGS, NOT RETURN_FAKE_BPB
;	 JMP	 DONEWITHBPBSTUFF		;AN008; Comment out this instruction.

INSTALLRECOMMENDEDBPB:
	MOV	CX, SIZE A_BPB
	LEA	DI, BYTE PTR [DI].RBYTEPERSEC
	JMP	SHORT COPYTHEBPB

INSTALLFAKEBPB:
	or	word ptr ds:[di].flags, return_fake_bpb ;AN000; Problem
							;reported by WHS.
	MOV	CX, SIZE BPB_TYPE    ; MOVE 'SMALLER' BPB
	LEA	DI, BYTE PTR [DI].BYTEPERSEC
COPYTHEBPB:
	LEA	SI, BYTE PTR [BX].DP_BPB
; EXCHANGE ES AND DS
	PUSH	ES
	PUSH	DS
	POP	ES
	POP	DS

	REP	MOVSB

DONEWITHBPBSTUFF:
	CALL	RESTOREOLDDPT		; RESTORE THE OLD DPT FROM TEMPDPT
	RESTOREREG <BX,ES,DI,DS>

; SET UP TRACK TABLE (IF NECCESSARY)
SETTRACKTABLE:
	MOV	CX, WORD PTR ES:[BX].DP_TRACKTABLEENTRIES
	BIOS_LOW_MEM MOV,<SECTORSPERTRACK>,CX,DS
	AND	WORD PTR DS:[DI].FLAGS, NOT GOOD_TRACKLAYOUT
	TEST	BYTE PTR ES:[BX].DP_SPECIALFUNCTIONS, TRACKLAYOUT_IS_GOOD
	JZ	UGLYTRACKLAYOUT
	OR	WORD PTR DS:[DI].FLAGS, GOOD_TRACKLAYOUT

UGLYTRACKLAYOUT:
	CMP	CX, MAX_SECTORS_IN_TRACK
	JA	TOOMANYSECTORSPERTRACK
	JCXZ	SECTORINFOSAVED
	MOV	DI, OFFSET TRACKTABLE
	LEA	SI, ES:[BX].DP_SECTORTABLE
	PUSH	ES
	POP	DS
	BIOS_PUSH_DATA_SEG
	POP	ES
STORESECTORINFO:
	INC	DI				; SKIP OVER CYLINDER
	INC	DI				; SKIP OVER HEAD
	LODSW					; GET SECTOR ID
	PUSH	AX				; SAVE IT
	LODSW					; GET SECTOR SIZE
	CALL	SECTORSIZETOSECTORINDEX
	POP	DX				; GET SECTOR ID BACK
	MOV	AL, DL				; AH = SECTOR SIZE INDEX
						; AL = SECTOR ID
	STOSW
	LOOP	STORESECTORINFO

SECTORINFOSAVED:
	CLC
	RET

TOOMANYSECTORSPERTRACK:
	MOV	AL, 0CH
	STC
	RET

SETDEVICEPARAMETERS ENDP

;
; SET MEDIA TYPE FOR FORMAT
; PERFORMS THE INT 13 WITH AH = 18H TO SEE IF THE MEDIUM DESCRIBED IN THE
; BPB AREA IN THE BDS CAN BE HANDLED BY THE ROM.
; ON INPUT, DS:DI -> CURRENT BDS.
; THE STATUS OF THE OPERATION IS RETURNED IN AL
;	- 0 - IF THE SUPPORT IS AVAILABLE, AND THE COMBINATION IS VALID.
;	- 1 - NO ROM SUPPORT
;	- 2 - ILLEGAL COMBINATION
;	- 3 - No media present (ROM support exists but cannot determine now)
; FLAGS ALSO MAY BE ALTERED. ALL OTHER REGISTERS PRESERVED.
; IF THE CALL TO ROM RETURNS NO ERROR, THEN THE CURRENT DPT IS "REPLACED" BY
; THE ONE RETURNED BY THE ROM. THIS IS DONE BY CHANGING THE POINTER IN [DPT]
; TO THE ONE RETURNED. THE ORIGINAL POINTER TO THE DISK BASE TABLE IS STORED
; IN TEMPDPT, UNTIL IT IS RESTORED.
;
	PUBLIC SET_MEDIA_FOR_FORMAT
SET_MEDIA_FOR_FORMAT PROC NEAR
	SAVEREG <CX,DX>
	XOR	AX,AX
	BIOS_LOW_MEM CMP,<[Had_Format_Error]>,1,DS ;Did we have a format error before?
	jne	No_Form_Err		;AN001;
	call	ResetDisk
No_Form_Err:				;AN001;
	BIOS_LOW_MEM CMP,<BYTE PTR [MEDIA_SET_FOR_FORMAT]>,1,DS
	jnz	Do_Set_Media_for_Format
	jmp	SET_MED_RET		; MEDIA ALREADY SET
Do_Set_Media_for_Format:
	SAVEREG <DS,SI>
	MOV	DS,AX
	LDS	SI,DWORD PTR DS:[DSKADR]	; GET POINTER TO DISK BASE TABLE
	BIOS_LOW_MEM MOV,<WORD PTR [DPT]>,SI,DS
	BIOS_LOW_MEM MOV,<WORD PTR [DPT+2]>,DS,ES		; SAVE POINTER TO TABLE
;SB34IOCTL000******************************************************************
;SB	Initialise the head settle time to 0fh.  See the offsets given in
;SB	DSKPRM.INC.  1 LOC.

	mov	ds:[si].DISK_HEAD_STTL, 0Fh
;SB34IOCTL000******************************************************************
	RESTOREREG <SI,DS>
	BIOS_LOW_MEM MOV,<[New_Rom]>,1,DS 	;assume a new ROM.
	XOR	AL,AL
;SB33031****************************************************************
	mov	cx,ds:[di.ccyln]	;get number of cylinders     ;SB  ;3.30*
	dec	cx			;cylinder must be zero based ;SB  ;3.30*
	and	ch,03h			; blank out unnecessary bits
	ror	ch,1			;put in int form	     ;SB  ;3.30*
	ror	ch,1			;			     ;SB  ;3.30*
	xchg	ch,cl			;			     ;SB  ;3.30*
	or	cl,byte ptr ds:[di.seclim] ;get number of sectors    ;SB  ;3.30*
	mov	dl,ds:[di.drivenum]	;get drive number	     ;SB  ;3.30*
	mov	ah,18h			;set media for format	     ;SB  ;3.30*
	SAVEREG <ES,DS,SI,DI>
	BIOS_ROM_INT13			;call rom bios		     ;SB  ;3.30*
;SB33031****************************************************************
	JC	FORMAT_STAT_ERR
; ES:DI POINTS TO A DISK BASE TABLE FOR THIS COMBINATION FOR THIS DRIVE.
	XOR	CX,CX
	MOV	DS,CX				; HAVE DS -> SEGMENT 0
	LDS	SI,DWORD PTR DS:[DSKADR]	; GET CURRENT DISK BASE TABLE
	BIOS_LOW_MEM MOV,<WORD PTR [TEMPDPT]>,SI,DS
	BIOS_LOW_MEM MOV,<WORD PTR [TEMPDPT+2]>,DS,ES	; SAVE IT
	MOV	WORD PTR DS:[DSKADR],DI
	MOV	WORD PTR DS:[DSKADR+2],ES	; REPLACE WITH ONE RETURNED BY ROM
	BIOS_LOW_MEM MOV,<BYTE PTR [MEDIA_SET_FOR_FORMAT]>,1,DS
Skip_Disk_Base_setting:
	XOR	AL,AL			; LEGAL COMBINATION + ROM SUPPORT CODE
	BIOS_LOW_MEM MOV,<[Had_Format_Error]>,al,DS ;reset the flag
	JMP	SHORT POP_STAT_RET

FORMAT_STAT_ERR:
	cmp	byte ptr ds:[di].SECLIM, 36
	jne	FORMAT_STAT_OTHER
	; Some BIOSes do not recognize 36-sector media through AH=18h even
	; though their floppy controller can format it.  Use the established
	; old-ROM path, which installs the requested EOT in the active DPT.
	mov	al, 1
	BIOS_LOW_MEM MOV,<[New_Rom]>,0,DS
	jmp	short Pop_stat_ret
FORMAT_STAT_OTHER:
	cmp	ah, Dsk_illegal_combination	;J.K. illegal combination = 0ch
	je	Format_stat_illegal_comb
	cmp	ah, Dsk_Time_Out_Err		;J.K. = 80h
	je	Format_stat_Time_out
	mov	al, 1				;Function not supported.
	BIOS_LOW_MEM MOV,<[New_Rom]>,0,DS 		;So, it is an old rom.
	jmp	short Pop_stat_ret
Format_stat_illegal_comb:			;J.K. Function supported, but
	MOV	AL,2				;J.K. illegal sect/trk, trk combination.
	jmp	short Pop_stat_ret
Format_stat_Time_out:				;J.K. Function supported, but
	mov	al, 3				;J.K. media not present.
POP_STAT_RET:
	RESTOREREG <DI,SI,DS,ES>
SET_MED_RET:
	RESTOREREG <DX,CX>
	RET

SET_MEDIA_FOR_FORMAT ENDP

;
; FORMATTRACK:
; IF SPECIALFUNCTION BYTE IS 1, THEN THIS IS A STATUS CALL TO SEE IF THERE IS
; ROM SUPPORT FOR THE COMBINATION OF SEC/TRK AND # OF CYLN, AND IF THE
; COMBINATION IS LEGAL. IF SPECIALFUNCTION BYTE IS 0, THEN FORMAT THE TRACK.
;
; INPUT: DS:DI POINTS TO BDS FOR DRIVE
;	 ES:BX POINTS TO FORMAT PACKET
;
; OUTPUT:
;	FOR STATUS CALL:
;	SPECIALFUNCTION BYTE SET TO:
;		0 - ROM SUPPORT + LEGAL COMBINATION
;		1 - NO ROM SUPPORT
;		2 - ILLEGAL COMBINATION
;		3 - no media present	;J.K. 7/8/86
;	CARRY CLEARED.
;
;	FOR FORMAT TRACK:
;		CARRY SET IF ERROR
;
	PUBLIC FORMATTRACK
FORMATTRACK PROC NEAR
	TEST	BYTE PTR ES:[BX].DP_SPECIALFUNCTIONS,STATUS_FOR_FORMAT
	JZ	DO_FORMAT_TRACK
	CALL	SET_MEDIA_FOR_FORMAT	; ALSO MOVES CURRENT DPT TO TEMPDPT
STAT_RET:
	MOV	BYTE PTR ES:[BX].DP_SPECIALFUNCTIONS,AL
	CLC
	RET

DO_FORMAT_TRACK:
	CMP	BYTE PTR DS:[DI].FORMFACTOR, DEV_HARDDISK
	jne	Do_Format_Diskette
	jmp	DoVerifyTrack
Do_Format_Diskette:
	SAVEREG <DS,DI,ES,BX>
;SB34IOCTL001*************************************************************
;SB	check the special functions word to see if DO_FAST_FORMAT has been
;SB	specified.  If so it is an error and we need to finish this operation
;SB	by indicating the error value 1 in register ah and going to the
;SB	the code at DO_MAP_IT to map the error.  This is because we cannot
;SB	allow multitrack format on floppies - 5 LOCS

	test	byte ptr es:[bx].FP_SPECIALFUNCTIONS,DO_FAST_FORMAT
	jz	NO_FAST_FORMAT
	mov	ah, 1
	jmp	DO_MAP_IT
NO_FAST_FORMAT:
;SB34IOCTL001*************************************************************
	CALL	SET_MEDIA_FOR_FORMAT	; ALSO MOVES CURRENT DPT TO TEMPDPT
	CMP	AL,1		; DO WE HAVE ROM SUPPORT FOR sector/trk, # trks combination?
	JZ	Need_Set_DASD	;Old ROM.
	cmp	al,3		;time out error?
	jnz	No_Set_DASD	;No, fine.(At this point, don't care about the illegal combination.)
	jmp	Format_Failed
Need_Set_DASD:
	CALL	SETDASD 	;AH=17h, INT 13h
;
; STORE CYLINDER,HEAD IN TRACK TABLE
;			***** ASSUMPTION *******
;	SINCE FORMAT REQUESTS ON FIXED MEDIA ARE CONVERTED TO VERIFIES, WE
;	ASSUME THAT WE ARE FORMATTING A FLOPPY AND HENCE HAVE 255 OR LESS
;	TRACKS AND HEADS. WE THEREFORE MUST CHANGE THE CYLINDER, HEAD DATA
;	FROM THE REQUEST PACKET SIZE TO THAT OF THE TRACKTABLE (SEE INT 13
;	INTERFACE IN IBM'S TECH REF.).

NO_SET_DASD:
; CHECK TO ENSURE CORRECT DISK IS IN DRIVE
	CALL	CHECKSINGLE

	MOV	AX, WORD PTR ES:[BX].FP_CYLINDER
	BIOS_LOW_MEM MOV,<WORD PTR [TRKNUM]>,AX,DS
	MOV	CX, WORD PTR ES:[BX].FP_HEAD
	BIOS_LOW_MEM MOV,<BYTE PTR [HDNUM]>,CL,DS
	MOV	AH,CL

	PUSH	DI					; SAVE PTR TO BDS
	MOV	DI, OFFSET TRACKTABLE
	BIOS_PUSH_DATA_SEG
	POP	ES
	BIOS_LOW_READ MOV,CX,<SECTORSPERTRACK>,DS
STORECYLINDERHEAD:
	STOSW
	INC	DI					; SKIP SECTOR ID
	INC	DI					; SKIP SECTOR SIZE
	LOOP	STORECYLINDERHEAD
	POP	DI					; RESTORE PTR TO BDS

	MOV	CX, MAXERR			; SET UP RETRY COUNT
FORMATRETRY:
	PUSH	CX
	MOV	BX, OFFSET TRACKTABLE
	BIOS_PUSH_DATA_SEG
	POP	ES
	BIOS_LOW_READ MOV,AX,<SECTORSPERTRACK>,DS
	MOV	AH, ROMFORMAT
	CALL	TO_ROM
	POP	CX
	JNC	FORMATOK
	call	resetdisk
	BIOS_LOW_MEM MOV,<[Had_Format_Error]>,1,DS
	push	ax
	push	cx
	push	dx
	call	Set_Media_For_Format
	cmp	al, 1
	jnz	While_Err
	call	SetDASD
While_Err:
	pop	dx
	pop	cx
	pop	ax
	LOOP	FORMATRETRY
;SB33106*******************************************************************
Format_Failed:
	BIOS_LOW_MEM MOV,<[Had_Format_Error]>,1,DS	;set the format error flag.
	cmp	ah, Dsk_Change_Line_Err 	;=06h. Convert change line
	jne	Do_Map_it			;error to Time Out error.
	mov	ah, Dsk_Time_Out_Err		;=80h
;SB33106*******************************************************************
Do_Map_it:
	CALL	MAPERROR
	RESTOREREG <BX,ES,DI,DS>
	RET

FORMATOK:
	BIOS_LOW_MEM MOV,<[Had_Format_Error]>,0,DS 	;reset the format error flag.
	RESTOREREG <BX,ES,DI,DS>

DOVERIFYTRACK:
	CALL	VERIFYTRACK
	RET

FORMATTRACK ENDP

VerifyTrack_Err:				;AN006;
	mov	ah, 1				;AN006;
	call	MapError			;AN006;
	ret					;AN006;

;
; VERIFYTRACK:
;
; INPUT: DS:DI POINTS TO BDS FOR DRIVE
;	 ES:BX POINTS TO VERIFY PACKET
;
	PUBLIC VERIFYTRACK
VERIFYTRACK PROC NEAR
	BIOS_LOW_MEM MOV,<RFLAG>,ROMVERIFY,DS
	MOV	AX, WORD PTR ES:[BX].VP_CYLINDER
	BIOS_LOW_MEM MOV,<CURTRK>,AX,DS
	MOV	AX, WORD PTR ES:[BX].VP_HEAD

;	****** ASSUMPTION ******
;	WE ASSUME THAT WE HAVE LESS THAN 256 HEADS, AND THAT THE REQUEST
;	HEADER DATA STRUCTURE IS UNNECCESSARILY BIG
	BIOS_LOW_MEM MOV,<CURHD>,AL,DS
	BIOS_LOW_READ MOV,CX,<SECTORSPERTRACK>,DS		;CL = sectors/track
;SB34IOCTL005*************************************************************
;SB
;SB	Check SPECIALFUNCTIONS to see if DO_FAST_FORMAT has been specified
;SB	If not we should go to the normal track verification routine.  If
;SB	fast format has been specified we should get the number of tracks
;SB	to be verified and check it to see if it is > 255.  If it is then
;SB	it is an error and we should go to VerifyTrack_Err. If not multiply
;SB	the number of tracks by the sectors per track to get the total
;SB	number of sectors to be verified.  This should also be less than
;SB	equal to 255 otherwise we go to same error exit.  If everything
;SB	is okay we initalise cx to the total sectors. use ax as a temporary
;SB	register.  9 LOCS

	test	byte ptr es:[bx].FP_SPECIALFUNCTIONS,DO_FAST_FORMAT
	jz	Norm_VerifyTrack
	mov	ax,es:[bx].FP_TRACKCOUNT	;ax <- tracks to be verify
	cmp	ax,0FFh
	ja	VerifyTrack_Err 		;#tracks > 255
	mul	cl
	cmp	ax,0FFh 			;#sectors > 255
	ja	VerifyTrack_Err
	mov	cx,ax				;#sectors to verify
;SB34IOCTL005*************************************************************

;Set the multi track request flag
	test	word ptr [di].Flags, fNON_REMOVABLE	;AN009;hard disk?
	jz	Norm_VerifyTrack			;AN009;
	BIOS_LOW_MEM TEST,<Multrk_Flag>,MULTRK_ON,DS		;AN009;MultiTrack operation = on?
	jz	Norm_VerifyTrack			;AN009;
	BIOS_LOW_MEM MOV,<Multitrk_Format_Flag>,1,DS		;AN009; then set the flag
Norm_VerifyTrack:				;AN006;
	XOR	AX, AX				;1st sector
; USE 0:0 AS THE TRANSFER ADDRESS FOR VERIFY
	XOR	BX, BX
	MOV	ES, BX
	CALL	TRACKIO
	BIOS_LOW_MEM MOV,<Multitrk_Format_Flag>,0,DS		;AN009;Reset the flag.
	RET
VERIFYTRACK ENDP

;
; READTRACK:
;
; INPUT: DS:DI POINTS TO BDS FOR DRIVE
;	 ES:BX POINTS TO READ PACKET
;
	PUBLIC READTRACK
READTRACK:
	BIOS_LOW_MEM MOV,<RFLAG>,ROMREAD,DS
	JMP	READWRITETRACK

;
; WRITETRACK:
;
; INPUT: DS:DI POINTS TO BDS FOR DRIVE
;	 ES:BX POINTS TO WRITE PACKET
;
	PUBLIC WRITETRACK
WRITETRACK:
	BIOS_LOW_MEM MOV,<RFLAG>,ROMWRITE,DS
	JMP	READWRITETRACK
;
; READWRITETRACK:
;
; INPUT:
;    DS:DI POINTS TO BDS FOR DRIVE
;    ES:BX POINTS TO WRITE PACKET
;    RFLAG - 2 FOR READ, 3 FOR WRITE
;
	PUBLIC READWRITETRACK
READWRITETRACK PROC NEAR
	MOV	AX, WORD PTR ES:[BX].TRWP_CYLINDER
	BIOS_LOW_MEM MOV,<CURTRK>,AX,DS
	MOV	AX, WORD PTR ES:[BX].TRWP_HEAD

;	****** ASSUMPTION ******
;	WE ASSUME THAT WE HAVE LESS THAN 256 HEADS, AND THAT THE REQUEST
;	HEADER DATA STRUCTURE IS UNNECCESSARILY BIG
	BIOS_LOW_MEM MOV,<CURHD>,AL,DS
	MOV	AX, WORD PTR ES:[BX].TRWP_FIRSTSECTOR
	MOV	CX, WORD PTR ES:[BX].TRWP_SECTORSTOREADWRITE
	LES	BX, ES:[BX].TRWP_TRANSFERADDRESS
	CALL	TRACKIO
	RET
READWRITETRACK ENDP


;
; TRACKIO:
;    PERFORMS TRACK READ/WRITE/VERIFY
;
;   INPUT:
;      RFLAG	- 2 = READ
;		  3 = WRITE
;		  4 = VERIFY
;      AX	- INDEX INTO TRACK TABLE OF FIRST SECTOR TO IO
;      CX	- NUMBER OF SECTORS TO IO
;      ES:BX	- TRANSFER ADDRESS
;      DS:DI	- POINTER TO BDS
;      CURTRK	- CURRENT CYLINDER
;      CURHD	- CURRENT HEAD
;
	PUBLIC TRACKIO
TRACKIO PROC NEAR
; PROCEDURE `DISK' WILL POP STACK TO SPSAV AND RETURN IF ERROR
	BIOS_LOW_SAVE_SP <SPSAV>
; ENSURE CORRECT DISK IS IN DRIVE
	CALL	CHECKSINGLE
; SEE IF WE HAVE ALREADY SET THE DISK BASE TABLE
	BIOS_LOW_MEM CMP,<BYTE PTR [MEDIA_SET_FOR_FORMAT]>,1,DS
	JZ	DPTALREADYSET
;
; SET UP TABLES AND VARIABLES FOR I/O
;
	SAVEREG <AX,CX>
	CALL	IOSETUP
	RESTOREREG <CX,AX>
;
; POINT SI AT THE TABLE ENTRY OF THE FIRST SECTOR TO BE IO'D
;
DPTALREADYSET:
	MOV	SI, OFFSET TRACKTABLE
	SHL	AX, 1
	SHL	AX, 1
	ADD	SI, AX
;
; WE WANT:
;    CX TO BE THE NUMBER OF TIMES WE HAVE TO LOOP
;    DX TO BE THE NUMBER OF SECTORS WE READ ON EACH ITERATION
	MOV	DX, 1
	TEST	WORD PTR DS:[DI].FLAGS, GOOD_TRACKLAYOUT
	JZ	IONEXTSECTOR

; HEY! WE CAN READ ALL THE SECTORS IN ONE BLOW
	XCHG	DX, CX

IONEXTSECTOR:
	PUSH	CX
	PUSH	DX
; SKIP OVER THE CYLINDER AND HEAD IN THE TRACK TABLE
	INC	SI
	INC	SI
; GET SECTOR ID FROM TRACK TABLE
	BIOS_LOW_LODSB
	BIOS_LOW_MEM MOV,<CURSEC>,AL,DS
;*** For a Fixed disk multi-track disk I/O - J.K. 4/14/86
;Assumptions: 1). In the input CX (# of sectors to go) to TRACKIO, only CL is
;valid.  2). Sector size should be set to 512 bytes. 3). GOODTRACKLAYOUT.
;
	test	word ptr [di].Flags, fNon_Removable	;Fixed disk? - J.K.
	jz	IOREMOVABLE				;no -J.K.
	BIOS_LOW_MEM TEST,<MulTrk_Flag>,MULTRK_ON,DS		;AN002; Allow multi-track operation?
	jz	IORemovable				;AN002; No, don't do that.
	BIOS_LOW_MEM MOV,<[seccnt]>,dx,DS 			;# of sectors to I/O -J.K.
	mov	ax, dx					;J.K.
	call	disk					;J.K.
	pop	dx					;J.K.
	pop	cx					;J.K.
	clc						;J.K.
	ret						;J.K.
IOREMOVABLE:						;J.K.
; GET SECTOR SIZE INDEX FROM TRACK TABLE AND SAVE IT
	BIOS_LOW_LODSB
	PUSH	AX
; PATCH SECTOR SIZE IN DPT
	PUSH	SI
	PUSH	DS
	BIOS_LOW_READ LDS,SI,<DPT>,ES
	MOV	BYTE PTR DS:[SI].DISK_SECTOR_SIZ,AL
	BIOS_LOW_READ MOV,AL,<[EOT]>,DS
	MOV	[SI].DISK_EOT,AL	; SET UP THE MAX NUMBER OF SEC/TRACK
	POP	DS
	MOV	AL, DL
DOTHEIO:
	BIOS_LOW_MEM MOV,<[SECCNT]>,AX,DS		; SET UP THE COUNT OF SECTORS TO I/O
	CALL	DISK
; ADVANCE BUFFER POINTER BY ADDING SECTOR SIZE
	POP	SI
	POP	AX
	CALL	SECTORSIZEINDEXTOSECTORSIZE
	ADD	BX, AX
	POP	DX
	POP	CX
	IFDEF BIOS_SERVICE_SEPARATE_DATA
	; LOOP only has an 8-bit displacement on 8086/286. Keep its flags contract
	; while the explicit low-data operations enlarge the track-service body.
	LOOP	TrackHighAgain
	JMP	SHORT TrackHighDone
TrackHighAgain:
	JMP	IONEXTSECTOR
TrackHighDone:
	ELSE
	LOOP	IONEXTSECTOR
	ENDIF
	BIOS_LOW_MEM CMP,<byte ptr [Media_Set_For_Format]>,1,DS	;AN001;
	je	No_Need_Done				;AN001;
	CALL	DONE			; SET TIME OF LAST ACCESS, AND RESET
No_Need_Done:				;AN001;
	CLC				; ENTRIES IN DPT.
	RET

TRACKIO ENDP
;
; THE SECTOR SIZE IN BYTES NEEDS TO BE CONVERTED TO AN INDEX VALUE FOR THE IBM
; ROM. (0=>128, 1=>256,2=>512,3=>1024). IT IS ASSUMED THAT ONLY THESE VALUES
; ARE PERMISSIBLE.
; ON INPUT   AX CONTAINS SECTOR SIZE IN BYTES
; ON OUTPUT  AL CONTAINS INDEX
;
	PUBLIC SECTORSIZETOSECTORINDEX
SECTORSIZETOSECTORINDEX PROC NEAR
	CMP	AH,2			; EXAMINE UPPER BYTE ONLY
	JA	ONEK
	MOV	AL,AH			; VALUE IN AH IS THE INDEX!
	RET
ONEK:
	MOV	AL,3
	RET
SECTORSIZETOSECTORINDEX ENDP

SECTORSIZEINDEXTOSECTORSIZE PROC NEAR
	MOV	CL, AL
	MOV	AX,128
	SHL	AX, CL
	RET
SECTORSIZEINDEXTOSECTORSIZE ENDP

;
; SET UP THE ROM FOR FORMATTING.
; WE HAVE TO TELL THE ROM BIOS WHAT TYPE OF DISK IS IN THE DRIVE.
; ON INPUT   - DS:DI - POINTS TO BDS
;
	PUBLIC SETDASD
SETDASD:
; SEE IF WE HAVE PREVIOUSLY SET DASD TYPE
;SB33114******************************************************************
	BIOS_LOW_MEM CMP,<[Had_Format_Error]>,1,DS
	je	DoSetDasd
;SB33114******************************************************************
	TEST	WORD PTR DS:[DI].FLAGS, SET_DASD_TRUE
	JZ	DASDHASBEENSET
	AND	WORD PTR DS:[DI].FLAGS, NOT SET_DASD_TRUE
;SB33115******************************************************************
DoSetDasd:
	BIOS_LOW_MEM MOV,<[Had_Format_Error]>,0,DS ;reset it
;SB33115******************************************************************
	BIOS_LOW_MEM MOV,<[GAP_PATCH]>,50H,DS	; FORMAT GAP FOR 48TPI DISKS
	CMP	BYTE PTR DS:[DI].SECLIM,36
	JNE	NOT_2880_DASD
	BIOS_LOW_MEM MOV,<[GAP_PATCH]>,53H,DS	; 2.88 MB format gap
	JMP	SHORT DASDHASBEENSET	; AH=17h has no 2.88 MB media code
NOT_2880_DASD:
	MOV	AL,4
	CMP	BYTE PTR DS:[DI].FORMFACTOR,DEV_3INCH720KB
	JZ	DO_SET
	CMP	BYTE PTR DS:[DI].FORMFACTOR, DEV_5INCH96TPI
	JZ	GOT_BIG
	MOV	AL,1			; 160/320K IN A 160/320K DRIVE
	JMP	SHORT DO_SET
GOT_BIG:
	MOV	AL,2			; 160/320K IN A 1.2 MEG DRIVE
	BIOS_LOW_MEM CMP,<MEDIATYPE>,0,DS
	JNE	DO_SET
	MOV	AL,3			; 1.2MEG IN A 1.2MEG DRIVE
	BIOS_LOW_MEM MOV,<[GAP_PATCH]>,54H,DS
DO_SET:
	push	ds				;AN003;
	push	si				;AN003;
;SB34IOCTL002****************************************************************
;SB	Get the disk parameter table address (dword address) from the location
;SB	0:[DSKADR] and fix the head settle time in this to be 0fh. 4 LOCS

	xor	si, si
	mov	ds, si
	lds	si, dword ptr ds:[DSKADR]
	mov	ds:[si].DISK_HEAD_STTL, 0Fh
;SB34IOCTL002****************************************************************
	pop	si				;AN003;
	pop	ds				;AN003;
;SB33032******************************************************************
	mov	AH, 17h 		; set command to Set DASD type;SB ;3.30*
	mov	DL, [di].DriveNum	; set drive number	      ;SB ;3.30*
	BIOS_ROM_INT13			; call rom-bios 	      ;SB ;3.30*
;SB33032******************************************************************
DASDHASBEENSET:
	MOV	AH,BYTE PTR [DI].SECLIM
	BIOS_LOW_MEM MOV,<[FORMT_EOT]>,AH,DS
	RET

;
; THIS ROUTINE IS CALLED IF AN ERROR OCCURS WHILE FORMATTING OR VERIFYING.
; IT RESETS THE DRIVE, AND DECREMENTS THE RETRY COUNT.
; ON ENTRY - DS:DI - POINTS TO BDS FOR THE DRIVE
;	     BP    - CONTAINS RETRY COUNT
; ON EXIT    FLAGS INDICATE RESULT OF DECREMENTING RETRY COUNT
;
AGAIN:
	CALL	RESETDISK

;(deleted section here, as requested by D.L.)

	DEC	BP			; DECREMENT RETRY COUNT
	RET


; RESET THE DRIVE.
; WE ALSO SET [STEP_DRV] TO -1 TO FORCE THE MAIN DISK ROUTINE TO USE THE
; SLOW HEAD SETTLE TIME FOR THE NEXT OPERATION. THIS IS BECAUSE THE RESET
; OPERATION MOVES THE HEAD TO CYLINDER 0, SO WE NEED TO DO A SEEK THE NEXT
; TIME AROUND - THERE IS A PROBLEM WITH 3.5" DRIVES IN THAT THE HEAD DOES
; NOT SETTLE DOWN IN TIME, EVEN FOR READ OPERATIONS!!
;
	PUBLIC RESETDISK
RESETDISK:
	SAVEREG <AX>
;SB33033******************************************************************
	xor	AH, AH			; set command to reset disk   ;SB ;3.30*
	BIOS_ROM_INT13			; call the rom-bios	      ;SB ;3.30*
;SB33033******************************************************************
	BIOS_LOW_MEM MOV,<[STEP_DRV]>,-1,DS	; ZAP UP THE SPEED
	RESTOREREG <AX>
	RET

;
; THIS ROUTINE SETS UP THE DRIVE PARAMETER TABLE WITH THE VALUES NEEDED FOR
; FORMAT, DOES AN INT 13. VALUES IN DPT ARE RESTORED AFTER A VERIFY IS DONE.
;
; ON ENTRY  -	DS:DI - POINTS TO BDS FOR THE DRIVE
;		ES:BX - POINTS TO TRKBUF
;		AL    - NUMBER OF SECTORS
;		AH    - INT 13 FUNCTION CODE
;		CL    - SECTOR NUMBER FOR VERIFY
; ON EXIT   -	DS,DI,ES,BX REMAIN UNCHANGED.
;		AX AND FLAGS ARE THE RESULTS OF THE INT 13
;
	PUBLIC TO_ROM
TO_ROM:
	SAVEREG <DS,DI,ES,BX,SI>
	BIOS_LOW_MEM TEST,<BYTE PTR [NEW_ROM]>,1,DS
	JNZ	GOT_VALID_DPT
	PUSH	AX
	MOV	DX,DS			; SAVE DS:DI-> BDS
	XOR	AX,AX
	MOV	DS,AX
	LDS	SI,DWORD PTR DS:[DSKADR]	; GET POINTER TO DISK BASE TABLE
	BIOS_LOW_MEM MOV,<WORD PTR [DPT]>,SI,DS
	BIOS_LOW_MEM MOV,<WORD PTR [DPT+2]>,DS,ES		; SAVE POINTER TO TABLE
	BIOS_LOW_READ MOV,AL,<[FORMT_EOT]>,DS
	MOV	[SI].DISK_EOT,AL
	BIOS_LOW_READ MOV,AL,<[GAP_PATCH]>,DS
	MOV	[SI].DISK_FORMT_GAP,AL	; IMPORTANT FOR FORMAT
	MOV	[SI].DISK_HEAD_STTL,15	; ASSUME WE ARE DOING A SEEK OPERATION
; SET UP MOTOR START CORRECTLY FOR 3.5" DRIVES.
	PUSH	ES
	MOV	ES,DX
	CMP	BYTE PTR ES:[DI].FORMFACTOR,FFSMALL	; IS IT A 3.5" DRIVE?
	JNZ	MOTORSTRTOK
	MOV	AL,4
	XCHG	AL,[SI].DISK_MOTOR_STRT
MOTORSTRTOK:
	POP	ES
;----------------------------------------------------------------------------
; THE FOLLOWING TWO LINES ARE NO LONGER NECESSARY SINCE THEY ARE ONLY USEFUL
; FOR A VERIFY OPERATION.
;	MOV	AL,CS:[SECTOR_SIZ_IND]
;	MOV	[SI].DISK_SECTOR_SIZ,AL ; IMPORTANT FOR VERIFY
;----------------------------------------------------------------------------
	MOV	DS,DX			; RESTORE DS:DI-> BDS
	POP	AX
GOT_VALID_DPT:
;SB33034*******************************************************************
	BIOS_LOW_READ MOV,dx,<[trknum]>,DS 	; set track number	      ;SB ;3.30*
	mov	ch,dl			; set low 8 bits in ch	      ;SB ;3.30*
	mov	DL, ds:[di].DriveNum	; set drive number	      ;SB ;3.30*
	BIOS_LOW_READ MOV,DH,<[HDNUM]>,DS		; set head number	      ;SB ;3.30*
	BIOS_ROM_INT13			; call the rom-bios  routines ;SB ;3.30*
;SB33034*******************************************************************
	RESTOREREG <SI,BX,ES,DI,DS>
	RET

;
; GET THE OWNER OF THE PHYSICAL DRIVE REPRESENTED BY THE LOGICAL DRIVE IN BL.
; THE ASSUMPTION IS THAT WE **ALWAYS** KEEP TRACK OF THE OWNER OF A DRIVE!!
; IF THIS IS NOT THE CASE, THE SYSTEM MAY HANG, JUST FOLLOWING THE LINKED LIST.
;
	PUBLIC	IOCTL$GETOWN
IOCTL$GETOWN:
	CALL	SETDRIVE
	MOV	AL,BYTE PTR [DI].DRIVENUM	; GET PHYSICAL DRIVE NUMBER
	BIOS_PUSH_DATA_SEG
	POP	DS
	IFDEF BIOS_SERVICE_SEPARATE_DATA
	MOV DI,WORD PTR DS:[START_BDS]
	ELSE
	MOV	DI,WORD PTR START_BDS
	ENDIF
OWN_LOOP:
	CMP	BYTE PTR [DI].DRIVENUM,AL
	JNE	GETNEXTBDS
	TEST	WORD PTR [DI].FLAGS,FI_OWN_PHYSICAL
	JNZ	DONE_GETOWN
GETNEXTBDS:
	MOV	BX,WORD PTR [DI].LINK+2
	MOV	DI,WORD PTR [DI].LINK
	MOV	DS,BX
	JMP	SHORT OWN_LOOP
DONE_GETOWN:
	JMP	SHORT EXIT_OWN

;
; SET THE OWNERSHIP OF THE PHYSICAL DRIVE REPRESENTED BY THE LOGICAL DRIVE IN
; BL TO BL.
;
	PUBLIC IOCTL$SETOWN
IOCTL$SETOWN:
	CALL	SETDRIVE
	BIOS_LOW_MEM MOV,<BYTE PTR [FSETOWNER]>,1,DS	; SET FLAG FOR CHECKSINGLE TO
						; LOOK AT.
	CALL	CHECKSINGLE			; SET OWNERSHIP OF DRIVE
	BIOS_LOW_MEM MOV,<BYTE PTR [FSETOWNER]>,0,DS	; RESET FLAG
	XOR	BX,BX
	MOV	ES,BX
	MOV	CL,-1
	MOV	BYTE PTR ES:[LSTDRV],CL 	; SET UP SDSB AS WELL

EXIT_OWN:
; IF THERE IS ONLY ONE LOGICAL DRIVE ASSIGNED TO THIS PHYSICAL DRIVE, RETURN
; 0 TO USER TO INDICATE THIS.
	XOR	CL,CL
	TEST	WORD PTR [DI].FLAGS,FI_AM_MULT
	JZ	EXIT_NO_MULT
	MOV	CL,BYTE PTR [DI].DRIVELET	; GET LOGICAL DRIVE NUMBER
	INC	CL				; GET IT 1-BASED
EXIT_NO_MULT:
	BIOS_LOW_READ LDS,BX,<[PTRSAV]>,ES
	MOV	BYTE PTR [BX].UNIT,CL
	BIOS_JUMP_LOW EXIT,BIOS_LOW_EXIT_ENTRY


;
; MOVES THE OLD DPT THAT HAD BEEN SAVED IN TEMPDPT BACK TO DPT. THIS IS DONE
; ONLY IF THE FIRST BYTE OF TEMPDPT IS NOT -1.
; ALL REGISTERS (INCLUDING FLAGS) ARE PRESERVED.
;
	PUBLIC RESTOREOLDDPT
RESTOREOLDDPT:
; IF WE HAVE ALREADY RESTORED THE DISK BASE TABLE EARLIER, DO NOT DO IT
; AGAIN.
	PUSH	AX
	XOR	AL,AL
; RESET FLAG AND GET CURRENT FLAG SETTING
	BIOS_LOW_MEM MOV,<[Had_Format_Error]>,al,DS
	BIOS_LOW_MEM XCHG,<BYTE PTR [MEDIA_SET_FOR_FORMAT]>,AL,DS
	OR	AL,AL
	JZ	DONTRESTORE
	SAVEREG <SI,DS,ES>
	BIOS_LOW_READ LDS,SI,<[TEMPDPT]>,ES
	XOR	AX,AX
	MOV	ES,AX				; HAVE ES -> SEGMENT 0
	MOV	WORD PTR ES:[DSKADR],SI
	MOV	WORD PTR ES:[DSKADR+2],DS
GOTCURRENTDPT:
	RESTOREREG <ES,DS,SI>
DONTRESTORE:
	POP	AX
	CLC				; CLEAR CARRY
	RET

;******************************************************************************
;AN000;  Get Media ID
;*******************************************************************************
;									       *
; Function: Get the volume label, the system id and the serial number from     *
;	    the media that has the extended boot record.		       *
;	    For the conventional media, this routine will return "Unknown      *
;	    media type" error to DOS.                                          *
;									       *
; Input :   DS:DI -> BDS table for this drive.				       *
;	    ES:BX -> Request packet (= A_Media_ID_INFO structure)	       *
;									       *
; Output:   The request packet filled with the information, if not carry.      *
;	    If carry set, then AL contains the device driver error number      *
;	    that will be returned to DOS.				       *
;	    Register DS,DX,AX,CX,DI,SI destroyed.			       *
; Subroutines to be called:						       *
;	BOOT_IO:NEAR							       *
;									       *
; Logic:								       *
;	/*To recognize the extended boot record, this logic will actually  */  *
;	/*access the boot sector even if it is a hard disk.		    */ *
;	/*NOTE:the valid extended bpb is recognized by looking at the mediabyte*
;	/*field of BPB and the extended Boot Signature. 		       *
;									       *
; {									       *
;	Get logical drive number from BDS table;			       *
;	RFLAG = Read operation; 					       *
;	BOOT_IO;		 /*Get the media boot record into the buffer*/ *
;	IF (no error) THEN						       *
;	     IF (extended boot record) THEN				       *
;		{ set Volume Label, Volume Serial number and System id	       *
;		  of the Request packet to those of the boot record;	       *
;		};							       *
;	     ELSE		  /*Not an extended BPB */		       *
;		{ set Register AL to "Unknown media.." error code;	       *
;		  set Carry bit;					       *
;		};							       *
;	ELSE								       *
;	     Exit;		 /*Already error code is set in the register AL*
;									       *
; Expected LOC: 40 (New)						       *
;*******************************************************************************

GetMediaID	proc	near			;AN000;
	call	Changeline_Chk			;AN010;
	mov	al, DS:[DI].DRIVELET		;AN000; logical drive number
	BIOS_LOW_MEM MOV,<RFlag>,ROMREAD,DS		;AN000; read operation
	call	Boot_IO 			;AN000; read boot sector into cs:DiskSector
;	$IF	NC				;AN000;
	JC $IOCTL$IF1
	   BIOS_LOW_READ MOV,cl,<MediaByte>,DS		;AN000; Mediabyte in BPB
	   and	   cl, 0F0h			;AN000;
	   cmp	   cl, 0F0h			;AN000; Is it a valid BPB?
;	   $IF	   E,AND			;AN000;
	   JNE $IOCTL$IF2
	      BIOS_LOW_MEM CMP,<Ext_Boot_Sig>,EXT_BOOT_SIGNATURE,DS ;AN000; =90h
;	   $IF	   E				;AN000; Extended Boot Record
	   JNE $IOCTL$IF2
	      BIOS_PUSH_DATA_SEG				;AN000;
	      pop  ds				;AN000;
	      mov  si, offset Boot_Serial_L	;AN000;
	      mov  di, bx			;AN000;
	      add  di, MI_SERIAL		;AN000;
	      mov  cx, BOOT_SERIAL_SIZE+BOOT_VOLUME_LABEL_SIZE+BOOT_SYSTEM_ID_SIZE
	      rep  movsb			;AN000;
;	   $ELSE				;AN000;
	   JMP SHORT $IOCTL$EN2
$IOCTL$IF2:
	      mov   al, ERROR_UNKNOWN_MEDIA	;AN000; =7
	      stc				;AN000;
;	   $ENDIF	;End Extended Boot Record check.
$IOCTL$EN2:
;	$ENDIF	;Read boot sector failed. Hard error.
$IOCTL$IF1:
	ret					;AN000;
GetMediaID	endp

;******************************************************************************
;AN000;  Set Media ID
;*******************************************************************************
;									       *
; Function: Set the volume label, the system id and the serial number of       *
;	    the media that has the extended boot record.		       *
;	    For the conventional media, this routine will return "Unknown      *
;	    media.." error to DOS.                                             *
;	    This routine will also set the corresponding informations in       *
;	    the BDS table.						       *
;									       *
; Input :   DS:DI -> BDS table for this drive.				       *
;	    ES:BX -> Request packet (= A_Media_ID_INFO structure)	       *
;									       *
; Output:   The extended boot record in the media will be set according to     *
;	    the Request packet. 					       *
;	    If carry set, then AL contains the device driver error number      *
;	    that will be returned to DOS.				       *
;									       *
; Subroutines to be called:						       *
;	BOOT_IO:NEAR							       *
;									       *
; Logic:								       *
;									       *
;									       *
; {									       *
;	Get Drive_Number from BDS;					       *
;	RFLAG = "Read operation";					       *
;	BOOT_IO;							       *
;	IF (no error) THEN						       *
;	     IF (extended boot record) THEN				       *
;		{ set Volume Label, Volume Serial number and System id	       *
;		  of the boot record to those of the Request packet;	       *
;		  RFLAG = "Write operation";				       *
;		  Get Drive Number from BDS;				       *
;		  BOOT_IO;	  /*Write it back*/			       *
;		};							       *
;	     ELSE		  /*Not an extended BPB */		       *
;		{ set Register AL to "Unknown media.." error code;	       *
;		  set Carry bit;					       *
;		  Exit; 	 /*Return back to caller */		       *
;		};							       *
;	ELSE								       *
;	     Exit;		 /*Already error code is set */ 	       *
;									       *
; Expected LOC: 45 (New)						       *
;*******************************************************************************

SetMediaID	proc	near
	call	Changeline_Chk			;AN010;
	mov	al, DS:[DI].DRIVELET		;AN000; logical drive number
	mov	dl, al				;AN000; save it for the time being.
	BIOS_LOW_MEM MOV,<RFlag>,ROMREAD,DS		;AN000; read operation
	push	dx				;AN000; save drive number
	call	Boot_IO 			;AN000; read boot sector into cs:DiskSector
	pop	dx				;AN000; restore drive number
;	$IF	NC				;AN000;
	JC $IOCTL$IF6
	   BIOS_LOW_READ MOV,cl,<MediaByte>,DS		;AN000; Mediabyte in BPB
	   and	   cl, 0F0h			;AN000;
	   cmp	   cl, 0F0h			;AN000; Is it a valid BPB?
;	   $IF	   E,AND			;AN000;
	   JNE $IOCTL$IF7
	      BIOS_LOW_MEM CMP,<Ext_Boot_Sig>,EXT_BOOT_SIGNATURE,DS ;AN000; =41 (=29h)
;	   $IF	   E				;AN000; Extended Boot Record
	   JNE $IOCTL$IF7
	      push ds				;AN011; save BDS pointer
	      push di				;AN011;
	      push es				;AN000;
	      pop  ds				;AN000;Now DS-> Request packet
	      BIOS_PUSH_DATA_SEG				;AN000;
	      pop  es				;AN000;Now ES -> Boot Record
	      mov  di, offset Boot_Serial_L	;AN000;
	      mov  si, bx			;AN000;
	      add  si, MI_Serial		;AN000;
	      mov  cx, BOOT_SERIAL_SIZE+BOOT_VOLUME_LABEL_SIZE+BOOT_SYSTEM_ID_SIZE
	      rep  movsb			;AN000;
	      pop  di				;AN011;Restore BDS pointer
	      pop  ds				;AN011;
	IFDEF BIOS_MEDIA_HIGH
	CALL Mov_Media_IDs
	ELSE
	BIOS_CALL_LOW Mov_Media_IDs,BIOS_LOW_MEDIA_IDS
	ENDIF
	      mov  al, dl			;AN000; set drive number for Boot_IO
	      BIOS_LOW_MEM MOV,<RFlag>,ROMWRITE,DS		;AN000;
	      call Boot_IO			;AN000; write it back.
	      BIOS_LOW_MEM MOV,<[TIM_DRV]>,-1,DS		;AN011; Make sure chk$media check the driver
;	   $ELSE				;AN000;
	   JMP SHORT $IOCTL$EN7
$IOCTL$IF7:
	      mov   al, ERROR_UNKNOWN_MEDIA	;AN000; =7
	      stc				;AN000;
;	   $ENDIF	;End Extended Boot Record check.
$IOCTL$EN7:
;	$ENDIF	;Read boot sector failed. Hard error.
$IOCTL$IF6:
	ret					;AN000;
SetMediaID	endp

;******************************************************************************
;AN000;  Boot_IO
;*******************************************************************************
;									       *
; Function: Read/Write the boot record into Boot sector.		       *
;									       *
; Input :								       *
;	    AL=logical drive number					       *
;	    RFLAG = operation (read/write)				       *
;									       *
; Output:   For read operation, the boot record of the drive specified in BDS  *
;	    be read into the DISKSECTOR buffer. 			       *
;	    For write operation, the DISKSECTOR buffer image will be written   *
;	    to the drive specified in BDS.				       *
;	    If carry set, then AL contains the device driver error number      *
;	    that will be returned to DOS.				       *
;	    AX,CX,DX register destroyed.				       *
;	    If carry set, then AL will contain the error code from DISKIO.     *
;									       *
; Subroutines to be called:						       *
;	DISKIO:NEAR							       *
;									       *
; Logic:								       *
;									       *
; {									       *
;	First_Sector = 0;	 /*logical sector 0 is the boot sector */      *
;	SectorCount = 1;	 /*read 1 sector only */		       *
;	Buffer = DISKSECTOR;	 /*read it into the disksector buffer */       *
;	Call DISKIO (RFLAG, Drive_Number,First_Sector,SectorCount,Buffer);     *
; }									       *
; Expected LOC: 6 (New) 						       *
;*******************************************************************************
Boot_IO 	proc	near			;AN000;
	push	ds				;AN000;
	push	es				;AN000;
	push	di				;AN000;
	push	bx				;AN000;
;SB34IOCTL003**************************************************************
;SB	Call DISKIO to read/write the boot sector. The parameters which
;SB	need to be initialised for this subroutine out here are
;SB		- transfer address to cs:DiskSector
;SB		- low sector needs to be initalised to 0. This is a reg. param
;SB		- hi sector in cs:[Start_Sec_H] needs to be initialised to 0.
;SB		- number of sectors <-- 1
;SB	7 LOCS

	BIOS_LOAD_DATA_SEG DI
	mov	ds, di
	mov	es, di
	mov	di, offset DiskSector	;es:di -> transfer address
	xor	dx, dx			;first sector (H) -> 0
	IFDEF BIOS_SERVICE_SEPARATE_DATA
	mov DS:[Start_Sec_H],dx
	ELSE
	mov	[Start_Sec_H], dx	;start sector (H) -> 0
	ENDIF
	mov	cx, 01			;one sector
	call	DISKIO
;SB34IOCTL003**************************************************************
	pop	bx				;AN000;
	pop	di				;AN000;
	pop	es				;AN000;
	pop	ds				;AN000;
	ret					;AN000;
Boot_IO 	endp				;AN000;

;*******************************************************************************
;AN010;  Changeline_Chk
;*******************************************************************************
;When the user calls Get/Set media ID call before DOS establishes the media    *
;by calling "Media$Chk", the change line activity of the drive is going to be  *
;lost.	This routine will check the change line activity and will save the     *
;history in the flags.							       *
;									       *
; Function: Check the change line error activity			       *
;									       *
; Input :  DS:DI -> BDS table.						       *
;									       *
; Output:   FLAG in BDS table will be updated if change line occurs.	       *
;									       *
; Subroutines to be called:						       *
;	SET_CHANGED_DL							       *
;									       *
;*******************************************************************************
Changeline_Chk	proc	near			;AN010;
	mov	dl, byte ptr ds:[di].DRIVENUM	;AN010;
	or	dl, dl				;AN010;Fixed disk?
	js	Chln_Chk_Ret			;AN010;Yes, skip it.
	BIOS_LOW_MEM CMP,<[fHave96]>,1,DS 		;AN011;This ROM support change line?
	jne	Chln_Chk_Ret			;AN011;
	BIOS_CALL_LOW HasChange,BIOS_LOW_HASCHANGE
	jz	Chln_Chk_Ret			;AN011;do nothing
;SB34IOCTL004*****************************************************************
;SB	Execute the ROM disk interrupt to check changeline activity. 2 LOCS

	mov	ah, 16h
	BIOS_ROM_INT13
;SB34IOCTL004*****************************************************************
	jnc	Chln_Chk_Ret			;AN010;no change line activity?
	BIOS_LOW_MEM MOV,<word ptr [FLAGBITS]>,FCHANGED,DS ;AN010;
	BIOS_CALL_LOW SET_CHANGED_DL,BIOS_LOW_SET_CHANGED
Chln_Chk_Ret:					;AN010;
	ret					;AN010;
Changeline_Chk	endp				;AN010;

;******************************************************************************
;AN007;  GetAccessFlag
;*******************************************************************************
;									       *
; Function: Get the status of UNFORMATTED_MEDIA bit of FLAGS in BDS table      *
;									       *
; Input :								       *
;	    es:bx -> A_DISKACCESS_CONTROL structure			       *
;	    ds:di -> BDS table						       *
;									       *
; Output:   A_DISKACCESS_CONTROL.DAC_ACCESS_FLAG = 0 if disk I/O not allowed.  *
;						 = 1 if disk I/O allowed.      *
;*******************************************************************************
GetAccessFlag	proc					    ;AN007;
	test	word ptr ds:[di].FLAGS, UNFORMATTED_MEDIA   ;AN007;Is it unformtted media?
	jz	GAF_Allowed				    ;AN007;No, formatted media
	mov	es:[bx].DAC_ACCESS_FLAG, 0		    ;AN007;
	jmp	short GAF_Done				    ;AN007;
GAF_Allowed:						    ;AN007;
	mov	es:[bx].DAC_ACCESS_FLAG, 1		    ;AN007;
GAF_Done:						    ;AN007;
	ret						    ;AN007;
GetAccessFlag	endp					    ;AN007;

;******************************************************************************
;AN007;  SetAccessFlag
;*******************************************************************************
;									       *
; Function: Set/Reset the UNFORMATTED_MEDIA bit of FLAGS in BDS table	       *
;									       *
; Input :								       *
;	    es:bx -> A_DISKACCESS_CONTROL structure			       *
;	    ds:di -> BDS table						       *
;									       *
; Output:   UNFORMTTED_MEDIA bit modified according to the user request        *
;*******************************************************************************
SetAccessFlag	proc					    ;AN007;
	cmp	es:[bx].DAC_ACCESS_FLAG, 0		    ;AN007;
	jne	SAF_Allow_Access			    ;AN007;
	or	word ptr ds:[di].FLAGS, UNFORMATTED_MEDIA   ;AN007;
	jmp	short SAF_Done				    ;AN007;
SAF_Allow_Access:					    ;AN007;
	and	word ptr ds:[di].FLAGS, not UNFORMATTED_MEDIA ;AN007;
SAF_Done:						    ;AN007;
	ret						    ;AN007;
SetAccessFlag	endp					    ;AN007;


