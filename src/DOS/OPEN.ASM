TITLE	DOS_OPEN - Internal OPEN call for MS-DOS
NAME	DOS_OPEN
; Low level routines for openning a file from a file spec.
;   Also misc routines for sharing errors
;
;   DOS_Open
;   Check_Access_AX
;   SHARE_ERROR
;   SET_SFT_MODE
;   Code_Page_Mismatched_Error		   ; DOS 4.00
;
.xlist
include dosseg.asm

CODE	SEGMENT BYTE PUBLIC  'CODE'
	ASSUME	SS:DOSGROUP,CS:DOSGROUP

.xcref
include dossym.inc
include devsym.inc
include fastopen.inc
include fastxxxx.inc
include ifssym.inc
.cref
.list

Installed = TRUE

	i_need	NoSetDir,BYTE
	i_need	THISSFT,DWORD
	i_need	THISCDS,DWORD
	i_need	CURBUF,DWORD
	i_need	CurrentPDB,WORD
	i_need	CURR_DIR_END,WORD
	I_need	RetryCount,WORD
	I_need	Open_Access,BYTE
	I_need	fSharing,BYTE
	i_need	JShare,DWORD
	I_need	FastOpenFlg,byte
	I_need	EXTOPEN_ON,BYTE 		  ;AN000;; DOS 4.00
	I_need	ALLOWED,BYTE			  ;AN000;; DOS 4.00
	I_need	EXTERR,WORD			  ;AN000;; DOS 4.00
	I_need	EXTERR_LOCUS,BYTE		  ;AN000;; DOS 4.00
	I_need	EXTERR_ACTION,BYTE		  ;AN000;; DOS 4.00
	I_need	EXTERR_CLASS,BYTE		  ;AN000;; DOS 4.00
	I_need	CPSWFLAG,BYTE			  ;AN000;; DOS 4.00
	I_need	EXITHOLD,DWORD			  ;AN000;; DOS 4.00
	I_need	THISDPB,DWORD			  ;AN000;; DOS 4.00
	I_need	SAVE_CX,WORD			  ;AN000;; DOS 4.00

Break	<DOS_Open - internal file access>

; Inputs:
;	[WFP_START] Points to WFP string ("d:/" must be first 3 chars, NUL
;		terminated)
;	[CURR_DIR_END] Points to end of Current dir part of string
;		( = -1 if current dir not involved, else
;		 Points to first char after last "/" of current dir part)
;	[THISCDS] Points to CDS being used
;		(Low word = -1 if NUL CDS (Net direct request))
;	[THISSFT] Points to SFT to fill in if file found
;		(sf_mode field set so that FCB may be detected)
;	[SATTRIB] Is attribute of search, determines what files can be found
;	AX is Access and Sharing mode
;	  High NIBBLE of AL (Sharing Mode)
;		sharing_compat	   file is opened in compatibility mode
;		sharing_deny_none  file is opened Multi reader, Multi writer
;		sharing_deny_read  file is opened Only reader, Multi writer
;		sharing_deny_write file is opened Multi reader, Only writer
;		sharing_deny_both  file is opened Only reader, Only writer
;	  Low NIBBLE of AL (Access Mode)
;		open_for_read	file is opened for reading
;		open_for_write	file is opened for writing
;		open_for_both	file is opened for both reading and writing.
;
;	  For FCB SFTs AL should = sharing_compat + open_for_both
;		(not checked)
; Function:
;	Try to open the specified file
; Outputs:
;	sf_ref_count is NOT altered
;	CARRY CLEAR
;	    THISSFT filled in.
;	CARRY SET
;	    AX is error code
;		error_file_not_found
;			Last element of path not found
;		error_path_not_found
;			Bad path (not in curr dir part if present)
;		error_bad_curr_dir
;			Bad path in current directory part of path
;		error_invalid_access
;			Bad sharing mode or bad access mode or bad combination
;		error_access_denied
;			Attempt to open read only file for writting, or
;			open a directory
;		error_sharing_violation
;			The sharing mode was correct but not allowed
;			generates an INT 24 on compatibility mode SFTs
; DS preserved, others destroyed

	procedure   DOS_Open,NEAR
	DOSAssume   CS,<DS>,"DOS_Open"
	ASSUME	ES:NOTHING

	MOV	[NoSetDir],0
	CALL	Check_Access_AX
	retc
	LES	DI,[THISSFT]
	XOR	AH,AH
; sleaze! move only access/sharing mode in.  Leave sf_isFCB unchanged
	MOV	BYTE PTR ES:[DI.sf_mode],AL ; For moment do this on FCBs too
	PUSH	ES
	LES	SI,[THISCDS]
	CMP	SI,-1
	JNZ	TEST_RE_NET
	POP	ES
;Extended open hooks

	TEST	[EXTOPEN_ON],ext_open_on    ;FT. from extnded open
	JZ	NOEXTOP 		    ;FT. no, do normal
IFS_extopen:
	MOV	AL,byte ptr [SAVE_CX]	    ;FT. al= create attribute
	PUSH	AX			    ;FT. pass create attr to IFS
	MOV	AX,(multNET SHL 8) OR 46    ;FT. issue extended open verb
	INT	2FH			    ;FT.
	POP	BX			    ;FT. trash bx
	MOV	[EXTOPEN_ON],0		    ;FT.
	JNC	update_size		    ;IFS. file may be opened
	return				    ;FT.
NOEXTOP:
;Extended open hooks


IF (NOT Installed) AND 0FFFFh
	transfer NET_SEQ_OPEN
ELSE
	PUSH	AX
	MOV	AX,(multNET SHL 8) OR 22
	INT	2FH
	POP	BX			; clean stack
	return
ENDIF

TEST_RE_NET:
	TEST	ES:[SI.curdir_flags],curdir_isnet
	POP	ES
	JZ	LOCAL_OPEN
;	CALL	IFS_SHARE_CHECK 	;IFS. check IFS share,may create share
;	JC	nomore			;IFS. share violation
;Extended open hooks

	TEST	[EXTOPEN_ON],ext_open_on    ;FT. from extnded open
	JNZ	IFS_extopen		    ;FT. isuue extended open
;Extended open hooks

IF (NOT Installed) AND 0FFFFh
	transfer NET_OPEN
ELSE
	PUSH	AX
	MOV	AX,(multNET SHL 8) OR 22
	INT	2FH
	POP	BX			; clean stack
;	JC	nomore			;IFS. error
update_size:
;	CALL	OWN_SHARE		;IFS. IFS owns share ?
;	JZ	nomore2 		;IFS. yes
;	MOV	AX,3			;IFS. update file size for all SFT
;	LES	DI,ThisSFT		;IFS.
;	call	JShare + 14 * 4 	;IFS. call ShSu
nomore2:
;	CLC
nomore:
	return
ENDIF

LOCAL_OPEN:
	EnterCrit   critDisk

; DOS 3.3 FastOPen 6/16/86

	OR	[FastOpenFlg],FastOpen_Set+Special_Fill_Set   ;  only open can
	invoke	GetPath


; DOS 3.3 FastOPen 6/16/86

	JNC	Open_found
	JNZ	bad_path
	OR	CL,CL
	JZ	bad_path
OpenFNF:
	MOV	AX,error_file_not_found
OpenBadRet:
	AND	BYTE PTR CS:[FastOpenFlg],Fast_yes    ;; DOS 3.3
	STC
	LeaveCrit   critDisk
	JMP	Clear_FastOpen

bad_path:
	MOV	AX,error_path_not_found
	JMP	OpenBadRet

open_bad_access:
	MOV	AX,error_access_denied
	JMP	OpenBadRet

Open_found:
	JZ	Open_Bad_Access 	; test for directories
	OR	AH,AH
	JS	open_ok 		; Devices don't have attributes
	MOV	ES,WORD PTR [CURBUF+2]	; get buffer location
	MOV	AL,ES:[BX].dir_attr
	TEST	AL,attr_volume_id	; can't open volume ids
	JNZ	open_bad_access
	TEST	AL,attr_read_only	; check write on read only
	JZ	open_ok
;
; The file is marked READ-ONLY.  We verify that the open mode allows access to
; the read-only file.  Unfortunately, with FCB's and net-FCB's we cannot
; determine at the OPEN time if such access is allowed.  Thus, we defer such
; processing until the actual write operation:
;
; If FCB, then we change the mode to be read_only.
; If net_FCB, then we change the mode to be read_only.
; If not open for read then error.
;
	SaveReg <DS,SI>
	LDS	SI,[THISSFT]
	MOV	CX,[SI].sf_mode
	TEST	CX,sf_isFCB		; is it FCB?
	JNZ	ResetAccess		; yes, reset the access
	MOV	DL,CL
	AND	DL,sharing_mask
	CMP	DL,sharing_net_FCB	; is it net FCB?
	JNZ	NormalOpen		; no
ResetAccess:
	AND	CX,NOT access_mask	; clear access
	errnz	open_for_read
;	OR	CX,open_for_read	; stick in open_for_read
	MOV	[SI].sf_mode,CX
	JMP	SHORT FillSFT
;
; The SFT is normal.  See if the requested access is open_for_read
;
NormalOpen:
	AND	CL,access_mask		; remove extras
	CMP	CL,open_for_read	; is it open for read?
	JZ	FillSFT
	RestoreReg  <SI,DS>
	JMP	short open_bad_access
;
; All done, restore registers and fill the SFT.
;
FillSFT:
	RestoreReg  <SI,DS>
open_ok:
;;; File Tagging DOS 4.00
;	OR	AH,AH		       ;FT. device ?
;	JS	NORM0		       ;FT. yes, don't do code page matching
;	CMP	[CPSWFLAG],0	       ;FT. code page matching on
;	JZ	NORM0		       ;FT. no
;	CMP	ES:[BX].dir_CODEPG,0   ;FT. code page 0
;	JZ	NORM0		       ;FT. yes do nothing
;	PUSH	AX		       ;FT.
;	invoke	Get_Global_CdPg        ;FT. get global code page
;	CMP	ES:[BX].dir_CODEPG,AX  ;FT. equal to global code page
;	JZ	NORM1		       ;FT. yes
;	call	Code_Page_Mismatched_Error ;FT.
;	CMP	AL,0		       ;FT. ignore ?
;	JZ	NORM1		       ;FT.
;	POP	AX		       ;FT.
;	JMP	open_bad_access        ;FT. set carry and return
NORM1:
;	POP	AX		       ;FT.
NORM0:

;;; File Tagging DOS 4.00
	invoke	DOOPEN			; Fill in SFT
	AND	BYTE PTR CS:[FastOpenFlg],Fast_yes    ;; DOS 3.3
	CALL	DO_SHARE_CHECK		;
	JNC	Share_Ok
	LeaveCrit   critDisk
	JMP	Clear_FastOPen

SHARE_OK:
	MOV	AX,3
	LES	DI,ThisSFT
if installed
	Context DS
	call	DWORD PTR SS:[JShare + 14 * 4]
else
	Call	ShSU
endif
;; DOS 4.00 10/27/86
	LES	DI,ThisSFT			   ; if this is a newly
	CMP	ES:[DI.sf_firclus],0		   ; created file then
	JZ	no_fastseek			   ; do nothing
	MOV	CX,ES:[DI.sf_firclus]		   ; first cluster #
	LES	DI,ES:[DI.sf_devptr]		   ; pointer to DPB
	MOV	DL,ES:[DI.dpb_drive]		   ; drive #
	invoke	FastSeek_Open			   ; call fastseek
no_fastseek:

;; DOS 4.00 10/27/86

	LeaveCrit   critDisk

;
; Finish SFT initialization for new reference.	Set the correct mode.
;
;   Inputs:
;	ThisSFT points to SFT
;
;   Outputs:
;	Carry clear
;   Registers modified: AX.

	entry	SET_SFT_MODE
	DOSAssume   CS,<DS>,"Set_SFT_Mode"
	ASSUME	ES:NOTHING

	LES	DI,ThisSFT
	invoke	DEV_OPEN_SFT
	TEST	ES:[DI.sf_mode],sf_isfcb; Clears carry
	retz				; sf_mode correct
	MOV	AX,[CurrentPDB]
	MOV	ES:[DI.sf_PID],AX	; For FCB sf_PID=PID

Clear_FastOpen:
	return			       ;;;;; DOS 3.3

EndProc DOS_Open

; Called on sharing violations. ES:DI points to SFT. AX has error code
; If SFT is FCB or compatibility mode gens INT 24 error.
; Returns carry set AX=error_sharing_violation if user says ignore (can't
; really ignore).  Carry clear
; if user wants a retry. ES, DI, DS preserved

procedure SHARE_ERROR,NEAR
	DOSAssume   CS,<DS>,"Share_Error"
	ASSUME	ES:NOTHING
	TEST	ES:[DI.sf_mode],sf_isfcb
	JNZ	HARD_ERR
	MOV	CL,BYTE PTR ES:[DI.sf_mode]
	AND	CL,sharing_mask
	CMP	CL,sharing_compat
	JNE	NO_HARD_ERR
HARD_ERR:
	invoke	SHARE_VIOLATION
	retnc				; User wants retry
NO_HARD_ERR:
	MOV	AX,error_sharing_violation
	STC
	return

EndProc SHARE_ERROR


; Input: THISDPB, WFP_Start, THISSFT set
; Functions: check file sharing mode is valid
; Output: carry set, error
;	  carry clear, share ok

procedure DO_SHARE_CHECK,NEAR
	DOSAssume   CS,<DS>,"DO_SHARE__CHECK"
	ASSUME	ES:NOTHING
	EnterCrit   critDisk		; enter critical section

OPN_RETRY:
	MOV	CX,RetryCount		; Get # tries to do
OpenShareRetry:
	SaveReg <CX>			; Save number left to do
	invoke	SHARE_CHECK		; Final Check
	RestoreReg  <CX>		; CX = # left
	JNC	Share_Ok2		; No problem with access
	Invoke	Idle
	LOOP	OpenShareRetry		; One more retry used up
OpenShareFail:
	LES	DI,[ThisSft]
	invoke	SHARE_ERROR
	JNC	OPN_RETRY		; User wants more retry
Share_Ok2:
	LeaveCrit   critDisk		; leave critical section
	return

EndProc DO_SHARE_CHECK


; Input: ES:DI -> SFT
; Functions: check if IFS owns SHARE
; Output: Zero set, use IFS SHARE
;	  otherwise, use DOS SHARE

procedure OWN_SHARE,NEAR
	DOSAssume   CS,<DS>,"OWN_SHARE"
	ASSUME	ES:NOTHING

;	PUSH	DS			;IFS. save reg
;	PUSH	SI			;IFS. save reg
;	LDS	SI,ES:[DI.sf_IFS_HDR]	;IFS. ds:si-> IFS header
;	TEST	[SI.IFS_ATTRIBUTE],IFSUSESHARE	;IFS. save reg
;	POP	SI			;IFS. retore reg
;	POP	DS			;IFS. restore reg
	return				;IFS. return

EndProc OWN_SHARE


; Input: THISCDS -> CDS
; Functions: check if IFS owns SHARE
; Output: Zero set, use IFS SHARE
;	  otherwise, use DOS SHARE

procedure OWN_SHARE2,NEAR
	DOSAssume   CS,<DS>,"OWN_SHARE2"
	ASSUME	ES:NOTHING

;	CMP	WORD PTR [THISCDS],-1	;IFS. UNC ?
;	JZ	ifs_hasit		;IFS. yes
;	PUSH	DS			;IFS. save reg
;	PUSH	SI			;IFS. save reg
;	LDS	SI,[THISCDS]		;IFS. DS:SI -> ThisCDS
;	LDS	SI,[SI.curdir_IFS_HDR]	;IFS. ds:si-> IFS header
;	TEST	[SI.IFS_ATTRIBUTE],IFSUSESHARE	;IFS.
;	POP	SI			;IFS. retore reg
;	POP	DS			;IFS. restore reg
ifs_hasit:
	return				;IFS. return

EndProc OWN_SHARE2


; Input: ES:DI -> SFT
; Functions: set THISDPB
; Output: none

procedure SET_THISDPB,NEAR
	DOSAssume   CS,<DS>,"SET_THISDPB"
	ASSUME	ES:NOTHING

;	PUSH	DS			;IFS. save reg
;	PUSH	SI			;IFS. save reg
;	LDS	SI,[THISCDS]		;IFS. ds:si-> CDS
;	LDS	SI,[SI.CURDIR_DEVPTR]	;IFS. ds:si-> DPB
;	MOV	WORD PTR [THISDPB],SI	;IFS. set THISDPB
;	MOV	WORD PTR [THISDPB+2],DS ;IFS.
;	POP	SI			;IFS. retore reg
;	POP	DS			;IFS. restore reg
	return				;IFS. return

EndProc SET_THISDPB


; Input: ES:DI -> SFT
; Functions: check IFS share
; Output: none

procedure IFS_SHARE_CHECK,NEAR
	DOSAssume   CS,<DS>,"IFS_SHARE_CHECK"
	ASSUME	ES:NOTHING


;	CALL	OWN_SHARE		;IFS. IFS owns share
;	JZ	IFSSHARE		;IFS. yes
;	PUSH	AX			;IFS. save mode
;	CALL	SET_THISDPB		;IFS. set THISDPB for SHARE_VIOLATION
;	CALL	DO_SHARE_CHECK		;IFS. check share
;	POP	AX			;IFS. restore mode and share ok
IFSSHARE:
	return				;IFS. return

EndProc IFS_SHARE_CHECK

; Inputs:
;	AX is mode
;	  High NIBBLE of AL (Sharing Mode)
;		sharing_compat	   file is opened in compatibility mode
;		sharing_deny_none  file is opened Multi reader, Multi writer
;		sharing_deny_read  file is opened Only reader, Multi writer
;		sharing_deny_write file is opened Multi reader, Only writer
;		sharing_deny_both  file is opened Only reader, Only writer
;	  Low NIBBLE of AL (Access Mode)
;		open_for_read	file is opened for reading
;		open_for_write	file is opened for writing
;		open_for_both	file is opened for both reading and writing.
; Function:
;	Check this access mode for correctness
; Outputs:
;	[open_access] = AL input
;	Carry Clear
;		Mode is correct
;		AX unchanged
;	Carry Set
;		Mode is bad
;		AX = error_invalid_access
; No other registers effected

	procedure Check_Access_AX
	DOSAssume   CS,<DS>,"Check_Access"
	ASSUME	ES:NOTHING

	MOV	Open_Access,AL
	PUSH	BX
;
; If sharing, then test for special sharing mode for FCBs
;
	MOV	BL,AL
	AND	BL,sharing_mask
	CMP	fSharing,-1
	JNZ	CheckShareMode		; not through server call, must be ok
	CMP	BL,sharing_NET_FCB
	JZ	CheckAccessMode 	; yes, we have an FCB
CheckShareMode:
	CMP	BL,40h			; is this a good sharing mode?
	JA	Make_Bad_Access
CheckAccessMode:
	MOV	BL,AL
	AND	BL,access_mask
	CMP	BL,2
	JA	Make_Bad_Access
	POP	BX
	CLC
	return

make_bad_access:
	MOV	AX,error_invalid_access
	POP	BX
	STC
	return

EndProc Check_Access_AX

; Input: none
; Function: Issue Code Page Mismatched INT 24 Critical Error
; OutPut: AL =0    ignore
;	     =3    fail

procedure Code_Page_Mismatched_Error,NEAR
	DOSAssume   CS,<DS>,"Code_Page_Mismatched_Error"
	ASSUME	ES:NOTHING

;	PUSH	DS		       ;FT.
;	Context DS		       ;FT. ds=cs
;	MOV	AH,0A9H 	       ;FT. fail,ignore,device,write
;	MOV	DI,error_I24_gen_failure		 ;FT. set error
;	MOV	[EXTERR],error_Code_Page_Mismatched	 ;FT.
;	MOV	[EXTERR_CLASS],errCLASS_NotFnd		 ;FT.
;	MOV	[EXTERR_ACTION],errACT_Abort		 ;FT.
;	MOV	[EXTERR_LOCUS],errLOC_Unk		 ;FT.
;	MOV	word ptr [EXITHOLD + 2],ES		 ;FT. save es:bp
;	MOV	word ptr [EXITHOLD],BP			 ;FT.
;	invoke	NET_I24_ENTRY				 ;FT. issue int 24H
;	POP	DS					 ;FT.
;	return						 ;FT.

EndProc Code_Page_Mismatched_Error
CODE	ENDS
    END
