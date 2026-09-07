	PAGE	,132				; 
TITLE	IFSFUNC DIRECTORY ROUTINES - Routines for IFS driver dispatch
NAME	NETDIR
;************************************************************************************
; DIRECTORY related IFS driver calls
;   IFS_RMDIR
;   IFS_MKDIR
;   IFS_CHDIR
; Programming notes:
;   Old redirector segmentation preserved.
;   Directory routines do not generate critical errors.
.xlist
.xcref
INCLUDE IFSSYM.INC
INCLUDE IFSFSYM.INC
INCLUDE DOSSYM.INC
INCLUDE DEVSYM.INC
.cref
.list
AsmVars <IBM, Installed, Debug>
; define the base code segment of the network support first
ifsseg	SEGMENT BYTE PUBLIC 'ifsseg'
ifsseg	ENDS
; include the rest of the segment definitions for normal MSDOS
include dosseg.asm
DATA		SEGMENT WORD PUBLIC 'DATA'
	; DOSGROUP data
	Extrn	WFP_START:WORD
	Extrn	THISCDS:DWORD
DATA		ENDS
; define our own code segment
ifsseg	SEGMENT BYTE PUBLIC 'ifsseg'
	ASSUME	SS:DOSGROUP,CS:ifsseg
	;IFS Data
	Extrn	IFSR:WORD
	Extrn	DEVICE_CB@_OFFSET:WORD
BREAK <IFS_RMDIR Remove an IFS Directory>
;************************************************************************************
; IFS_RMDIR
;Called by:
;     IFSFUNC Dispatcher
; Routines called:
;	CDS_TO_CD
;	CALL_IFS
; Inputs:
;	[WFP_START] Points to WFP string
;	[THISCDS]   Points to CDS being used
; Function:
;	Prep IFSRH as follows:	(* indicate which fields set)
;	*  IFSR_LENGTH	    DW	   42	    ; Request length
;	*  IFSR_FUNCTION    DB	    4	    ; Execute API function
;	   IFSR_RETCODE     DW	    ?
;	   IFSR_RETCLASS    DB	    ?
;	   IFSR_RESV1	    DB	   16 DUP(0)
;	*  IFSR_APIFUNC     DB	    4	    ; Remove Directory
;	   IFSR_ERROR_CLASS DB	    ?
;	   IFSR_ERROR_ACTION DB     ?
;	   IFSR_ERROR_LOCUS DB	    ?
;	   IFSR_ALLOWED     DB	    ?
;	   IFSR_I24_RETRY   DB	    ?
;	   IFSR_I24_RESP    DB	    ?
;	   IFSR_RESV2	    DB	    ?
;	*  IFSR_DEVICE_CB@  DD	    ?	    ; Call CDS_TO_CD to convert CDS to CD
;					   ; and set this as pointer to it.
;	   IFSR_OPEN_CB@    DD	    ?
;	*  IFSR_NAME@	    DD	    ?	    ; [WFP_START]
;	CALL routine, CALL_IFS, with pointer to CURDIR_IFSR_HDR
;	IF IFSR_RETCODE = 0 THEN
;	   Call CD_TO_CDS
;	   Clear carry
;	ELSE
;	   Set carry
;	   Put error code in AX
;	ENDIF
; Outputs:
;	Carry clear:	      CDS FSDA updated
;	Carry set on error:   error_path_not_found (bad path)
;			      error_access_denied  (file/device not empty)
; Notes: DS preserved, others destroyed
;************************************************************************************
	procedure   IFS_RMDIR,NEAR
	entry	IFS_SEQ_RMDIR
	ifsr_fcn_def  EXECAPI			; define ifsr fields for rmdir
	ifsr_api_def  RMDIR
	PUSH	DS				; preserve DS
	invoke	PREP_IFSR			; init ifsr, sets es:bx -> ifsr
	MOV	ES:[BX.IFSR_APIFUNC],IFSRMDIR
	JMP	SHORT CHDIR_10			; go finish in ifs_chdir
EndProc IFS_RMDIR
BREAK <IFS_MKDIR Create an IFS Directory>
;************************************************************************************
; IFS_MKDIR
; Called by:	   IFSFUNC Dispatcher
; Routines called: CDS_TO_CD
;		   CALL_IFS
; Inputs:
;	[WFP_START] Points to WFP string
;	[THISCDS]   Points to CDS being used.  Not NULL.
; Function:
;	Prep IFSRH as follows:	(* indicate which fields set)
;	*  IFSR_LENGTH	    DW	   42	    ; Request length
;	*  IFSR_FUNCTION    DB	    4	    ; Execute API function
;	   IFSR_RETCODE     DW	    ?
;	   IFSR_RETCLASS    DB	    ?
;	   IFSR_RESV1	    DB	   16 DUP(0)
;	*  IFSR_APIFUNC     DB	    3	    ; Create Directory
;	   IFSR_ERROR_CLASS DB	    ?
;	   IFSR_ERROR_ACTION DB     ?
;	   IFSR_ERROR_LOCUS DB	    ?
;	   IFSR_ALLOWED     DB	    ?
;	   IFSR_I24_RETRY   DB	    ?
;	   IFSR_I24_RESP    DB	    ?
;	   IFSR_RESV2	    DB	    ?
;	*  IFSR_DEVICE_CB@  DD	    ?	    ; Call CDS_TO_CD to convert CDS to CD
;					   ; and set this as pointer to it.
;	   IFSR_OPEN_CB@    DD	    ?
;	*  IFSR_NAME@	    DD	    ?	    ; [WFP_START]
;	CALL routine, CALL_IFS, with pointer to CURDIR_IFSR_HDR
;	IF IFSR_RETCODE = 0 THEN
;	   Call CD_TO_CDS
;	   Clear carry
;	ELSE
;	   Set carry
;	   Put error code in AX
;	ENDIF
; Outputs:
;	Carry clear:	     CDS FSDA updated
;	Carry set on error:  error_path_not_found (bad path)
;			     error_access_denied
;			      (Attempt to re-create read only file , or
;			       create a second volume id or create a dir)
; Notes: DS preserved, others destroyed
;************************************************************************************
	procedure   IFS_MKDIR,NEAR
	entry	IFS_SEQ_MKDIR
	ifsr_fcn_def  EXECAPI			; define ifsr fields for mkdir
	ifsr_api_def  MKDIR
	PUSH	DS				; preserve DS
	invoke	PREP_IFSR			; init ifsr, sets es:bx -> ifsr
	MOV	ES:[BX.IFSR_APIFUNC],IFSMKDIR
	JMP	SHORT CHDIR_10			; go finish in ifs_chdir
EndProc IFS_MKDIR
BREAK <IFS_CHDIR Check for validity and change directory>
;************************************************************************************
; IFS_CHDIR
; Called by:	   IFSFUNC Dispatcher
; Routines called: CDS_TO_CD
;		   CD_TO_CDS
;		   CALL_IFS
; Inputs:
;	[WFP_START] Points to WFP string
;	[THISCDS]   Points to CDS being used.  Not NUL.
; Function:
;	Prep IFSRH as follows:	(* indicate which fields set)
;	*  IFSR_LENGTH	    DW	   42	    ; Request length
;	*  IFSR_FUNCTION    DB	    4	    ; Execute API function
;	   IFSR_RETCODE     DW	    ?
;	   IFSR_RETCLASS    DB	    ?
;	   IFSR_RESV1	    DB	   16 DUP(0)
;	*  IFSR_APIFUNC     DB	    5	    ; Change Directory
;	   IFSR_ERROR_CLASS DB	    ?
;	   IFSR_ERROR_ACTION DB     ?
;	   IFSR_ERROR_LOCUS DB	    ?
;	   IFSR_ALLOWED     DB	    ?
;	   IFSR_I24_RETRY   DB	    ?
;	   IFSR_I24_RESP    DB	    ?
;	   IFSR_RESV2	    DB	    ?
;	*  IFSR_DEVICE_CB@  DD	    ?	    ; Call CDS_TO_CD to convert CDS to CD
;					   ; and set this as pointer to it.
;	   IFSR_OPEN_CB@    DD	    ?
;	*  IFSR_NAME@	    DD	    ?	    ; [WFP_START]
;	CALL routine, CALL_IFS, with pointer to CURDIR_IFSR_HDR
;	IF IFSR_RETCODE = 0 THEN
;	   Call CD_TO_CDS to update CDS
;	   Clear carry
;	ELSE
;	   Set carry
;	   Put error code in AX
;	ENDIF
; Outputs:
;	Carry clear: CDS updated.
;	Carry set on error:  error_path_not_found (bad path)
;			     error_access_denied
; Notes: DS preserved, others destroyed
;************************************************************************************
	procedure   IFS_CHDIR,NEAR
	ifsr_fcn_def  EXECAPI			; define ifsr fields for chdir
	ifsr_api_def  CHDIR
	PUSH	DS				; preserve DS
	invoke	PREP_IFSR			; init ifsr, sets es:bx -> ifsr
	MOV	ES:[BX.IFSR_APIFUNC],IFSCHDIR
CHDIR_10:					; Welcome rmdir/mkdir code
	MOV	ES:[BX.IFSR_LENGTH],LENGTH_CHDIR
	MOV	ES:[BX.IFSR_FUNCTION],IFSEXECAPI
						; ds -> dosgroup
	MOV	SI,WORD PTR [WFP_START] 	; to access thiscds & wfp
	invoke	STRIP_WFP_START 		; ditch leading d:\
	MOV	WORD PTR ES:[BX.IFSR_NAME@],SI
	MOV	WORD PTR ES:[BX.IFSR_NAME@+2],DS
	LDS	SI,[THISCDS]
	SaveReg <DS,SI>
	MOV	DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
	CMP	SI,NULL_PTR			; skip cds work if cds null
	JE	CHDIR_20
	invoke	CDS_TO_CD			; CDS: sets [THISIFS]
						;	    IFSR_DEVICE_CB@
						;	    ds - ifsseg
CHDIR_20:
	SaveReg <CS>				; make sure ds = ifsseg
	RestoreReg <DS>
;************************************************
	invoke	CALL_IFS			; call fs with dir request
;************************************************
	RestoreReg <DI,ES>			; restore cds ptr into es:di
	JC	CHDIR_1000
	CMP	DI,NULL_PTR			; skip cds work if cds null
	JE	CHDIR_40
	invoke	CD_TO_CDS			; update cds

CHDIR_40:
	CLC
CHDIR_1000:					; finished
	POP	DS				; restore DS
	return
EndProc IFS_CHDIR
ifsseg	ENDS
    END
