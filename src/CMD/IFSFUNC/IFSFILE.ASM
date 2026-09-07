        PAGE    ,132                            ; 
TITLE   IFS FILE ROUTINES - Routines for IFS dispatch
NAME    IFSFILE
;************************************************************************************
;
; FILE (WFP_START) related Network calls
;
;   IFS_DISK_INFO
;   IFS_SEQ_SET_FILE_ATTRIBUTE
;   IFS_SET_FILE_ATTRIBUTE
;   IFS_SEQ_GET_FILE_INFO
;   IFS_GET_FILE_INFO
;   IFS_SEQ_RENAME
;   IFS_RENAME
;   IFS_SEQ_DELETE
;   IFS_DELETE
;   IFS_SEQ_OPEN
;   IFS_OPEN
;   IFS_SEQ_CREATE
;   IFS_CREATE
;   IFS_SEQ_XOPEN
;   IFS_XOPEN
;   IFS_SEQ_SEARCH_FIRST
;   IFS_SEQ_SEARCH_NEXT
;   IFS_SEARCH_FIRST
;   IFS_SEARCH_NEXT
;   OPEN_CHECK_SEQ
;
; Programming notes:
;   Old redirector segmentation and DOS interface preserved.
;   Routine prologues are accurate for input/output.
;   However, the pseudocode was not kept up to date.
;   Use it for a rough idea of the routine function.
;
.xlist
.xcref
INCLUDE IFSSYM.INC
INCLUDE IFSFSYM.INC
INCLUDE DOSSYM.INC
INCLUDE DEVSYM.INC
INCLUDE DOSCNTRY.INC
.cref
.list
AsmVars <IBM, Installed, DEBUG>
; then define the base code segment of the ifsfunc support first
IFSSEG  SEGMENT BYTE PUBLIC 'IFSSEG'
IFSSEG  ENDS
; include the rest of the segment definitions for normal MSDOS
include dosseg.asm
DATA            SEGMENT WORD PUBLIC 'DATA'
        ;DOSGROUP Data
        Extrn   REN_WFP:WORD
        Extrn   WFP_START:WORD
        Extrn   SATTRIB:BYTE
        Extrn   ATTRIB:BYTE
        Extrn   THISCDS:DWORD
        Extrn   THISSFT:DWORD
        Extrn   DMAADD:DWORD
        Extrn   CDSADDR:DWORD
        Extrn   SAVE_BX:WORD
        Extrn   SAVE_CX:WORD
        Extrn   SAVE_DX:WORD
        Extrn   SAVE_SI:WORD
        Extrn   SAVE_DI:WORD
        Extrn   SAVE_DS:WORD
        Extrn   SAVE_ES:WORD
        Extrn   Name1:BYTE
        Extrn   DEVPT:DWORD
        Extrn   CPSWFLAG:BYTE
        Extrn   COUNTRY_CDPG:BYTE
if debug
        Extrn   BugLev:WORD
        Extrn   BugTyp:WORD
        include bugtyp.asm
endif
DATA            ENDS
; define our own code segment
IFSSEG  SEGMENT BYTE PUBLIC 'IFSSEG'
        ASSUME  SS:DOSGROUP,CS:IFSSEG
        ;IFS Data
        Extrn   IFSR:WORD
        Extrn   IFSDRV:BYTE
        Extrn   IFSPROC_FLAGS:WORD
        Extrn   UNC_FS_HDR:DWORD
        Extrn   THISIFS:DWORD
        Extrn   THISDFL:DWORD
        Extrn   DEVICE_CB@_OFFSET:WORD
        Extrn   SFT_SERIAL_NUMBER:WORD
        Extrn   fAssign:BYTE
BREAK <IFS_DISK_INFO Get disk Info>
;************************************************************************************
; IFS_DISK_INFO
; Input:
;       ES:DI -> CDS  (not NULL)
;       DS    -> DOSGROUP
; Function:
;     Prep IFSRH:
;     *  IFSR_LENGTH      DW     48       ; Total length of request
;     *  IFSR_FUNCTION    DB      4       ; Execute API function
;      + IFSR_RETCODE     DW      ?
;      + IFSR_RETCLASS    DB      ?
;        IFSR_RESV1       DB     16 DUP(0)
;     *  IFSR_APIFUNC     DB      2       ; Disk Attributes
;      + IFSR_ERROR_CLASS DB      ?
;      + IFSR_ERROR_ACTION DB     ?
;      + IFSR_ERROR_LOCUS DB      ?
;      + IFSR_ALLOWED     DB      ?
;      + IFSR_I24_RETRY   DB      ?
;      + IFSR_I24_RESP    DB      ?
;        IFSR_RESV2       DB      ?
;     *+ IFSR_DEVICE_CB@  DD      ?       ; Call CDS_TO_CD to convert CDS to CD
;                                        ; and set this as pointer to it.
;        IFSR_OPEN_CB@    DD      ?
;      + IFSR_ALLOCUNITS  DW      number of allocation units
;      + IFSR_ALLOCSIZE   DW      allocation unit sectors
;      + IFSR_SECTSIZE    DW      sector size
;      + IFSR_AVAILALLOC  DW      free allocation units
;      + IFSR_FSID        DB      file system media id
;        IFSR_RESV3       DB      0
;     CALL routine, CALL_IFS, with pointer to CURDIR_IFSR_HDR
;     IF IFSR_RETCODE = 0 THEN
;        DO
;          Call CD_TO_CDS to update CDS
;          Set:
;             DX = IFSR_AVAILALLOC
;             BX = IFSR_ALLOCUNITS
;             CX = IFSR_SECTSIZE
;             AL = IFSR_ALLOCSIZE
;             AH = IFSR_FSID
;          Clear carry
;        ENDDO
;     ELSE DO
;            Put error code in AX
;            Set carry
;          ENDDO
;     ENDIF
; Output:
;       DX = Number of free allocation units
;       BX = Total Number of allocation units on disk
;       CX = Sector size
;       AL = Sectors per allocation unit
;       AH = Media ID BYTE
;       Carry set if error
; Regs: Segs and DI preserved, others destroyed
;************************************************************************************
        procedure   IFS_DISK_INFO,NEAR
ASSUME  DS:DOSGROUP,ES:NOTHING
        MOV     AX,DI                           ; set ifsDrv for possible I24
        invoke  IFSDrvFromCDS
        ifsr_fcn_def  EXECAPI                   ; define ifsr for diskattr
        ifsr_api_def  DISKATTR
        MOV     CS:IFSPROC_FLAGS,ZERO           ;  & processing flags
        PUSH    ES                              ; set ds:si -> cds
        POP     DS
        MOV     SI,DI
        invoke  PREP_IFSR                       ; init ifsr
        SaveReg <DS,SI>                         ; save for cd_to_cds
        MOV     CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
        invoke  CDS_TO_CD                       ; CDS: sets [THISIFS]
                                                ;           ES:BX -> IFSRH
                                                ;           IFSR_DEVICE_CB@
                                                ;           ds - IFSSEG
        MOV     ES:[BX.IFSR_LENGTH],LENGTH_DISKATTR         ; prep IFSRH
        MOV     ES:[BX.IFSR_FUNCTION],IFSEXECAPI
        MOV     ES:[BX.IFSR_APIFUNC],IFSDISKATTR
        invoke  CALL_IFS                        ; call fs with diskattr request
        JNC     DA_20
        RestoreReg <DI,ES>                      ; error - restore stack
        JMP     FA_1000                         ;         go return
DA_20:
        MOV     DX,ES:[BX.IFSR_AVAILALLOC]      ; no error - load return regs
        MOV     CX,ES:[BX.IFSR_SECTSIZE]
        MOV     AX,ES:[BX.IFSR_ALLOCSIZE]
        MOV     AH,ES:[BX.IFSR_FSID]
        MOV     BX,ES:[BX.IFSR_ALLOCUNITS]                                               ;AM002;
        RestoreReg <DI,ES>                      ; restore cds into es:di
        invoke  CD_TO_CDS
        CLC
        JMP     FA_1000                         ; go ret in file attr routine
                                                ; since it restores ds-dosgroup
EndProc IFS_DISK_INFO

BREAK <IFS_SEQ_SET_FILE_ATTRIBUTE  - Seq Set File Attributes>
;************************************************************************************
; IFS_SEQ_SET_FILE_ATTRIBUTE
; see IFS_GET_FILE_INFO for details
;************************************************************************************
        procedure   IFS_SEQ_SET_FILE_ATTRIBUTE,NEAR
        ifsr_fcn_def  EXECAPI
        ifsr_api_def  FILEATTR
        PUSH    AX                              ; save file attrs
        invoke  CHECK_SEQ                       ; check if this is unc or ifs device
        JC      SA_20                           ; cf=0 unc, cf=1 device
        PUSH    CS                              ; get addressability to IFSSEG
        POP     DS                              ; prep ifsflags for set
ASSUME  DS:IFSSEG
        MOV     IFSPROC_FLAGS,ZERO
        JMP     SHORT SFA_20                    ; cont. in ifs_seq_get_fa
EndProc IFS_SEQ_SET_FILE_ATTRIBUTE
BREAK <IFS_SET_FILE_ATTRIBUTE      - Set File Attributes>
;************************************************************************************
; IFS_SET_FILE_ATTRIBUTE
; see IFS_GET_FILE_INFO for details
;************************************************************************************
        procedure   IFS_SET_FILE_ATTRIBUTE,NEAR
        ifsr_fcn_def  EXECAPI
        ifsr_api_def  FILEATTR
        PUSH    AX                              ; save file attrs
SA_20:
        MOV     CS:IFSPROC_FLAGS,0              ; prep ifsflags
        JMP     SHORT FA_20                     ; cont. in ifs_get_file_info
EndProc IFS_SET_FILE_ATTRIBUTE
BREAK <IFS_SEQ_GET_FILE_INFO       - Seq Get File Attributes>
;************************************************************************************
; IFS_SEQ_GET_FILE_ATTRIBUTE
; see IFS_GET_FILE_INFO for details
;************************************************************************************
        procedure   IFS_SEQ_GET_FILE_INFO,NEAR
        ifsr_fcn_def  EXECAPI
        ifsr_api_def  FILEATTR
        invoke  CHECK_SEQ                       ; check if this is unc or ifs device
        JC      FA_10                           ; cf=0 unc, cf=1 device
        PUSH    CS                              ; prep ifsflags for get & seq
        POP     DS
ASSUME  DS:IFSSEG
        MOV     IFSPROC_FLAGS,ISGET
SFA_20:
        OR      IFSPROC_FLAGS,ISSEQ             ; SEQ - UNC
        invoke  SET_THISIFS_UNC                 ; set thisifs = unc
        invoke  PREP_IFSR                       ; init ifsr
        JMP     SHORT FA_200                    ; cont. in ifs_get_file_info
EndProc IFS_SEQ_GET_FILE_INFO

BREAK <IFS_GET_FILE_INFO           - Get File Attributes>
;************************************************************************************
; GET_FILE_INFO
; Routines called:  DFL_SINGLE_FILE_CHECK
; Inputs:
;       [WFP_START] Points to WFP string ("//" must be first 2 chars, NUL
;               terminated)
;       [THISCDS] Points to CDS being used
;               (Low word = -1 if NUL CDS (dfl))
;       [SATTRIB] is attribute of search (determines what files may be found)
;       AX is new attributes to give to file (already checked for bad bits)
; Function:
;     IF seq call THEN
;        DO
;          Set IFS Header pointer to UNC IFS
;          Set IFSR_DEVICE_CB@ = null
;        ENDDO
;     ELSE DO
;            IF [THISCDS] .NOT. NULL THEN
;                 CALL CDS_TO_CD
;            ELSE DO
;                   CALL DFL_SINGLE_FILE_CHECK
;                   IF have DFL that supports single file fcns THEN
;                      call DFL_TO_DF
;                   ELSE set error - device not IFS or no single file support
;                   ENDIF
;                 ENDDO
;            ENDIF
;          ENDDO
;     IF  no error  THEN
;        DO
;          Prep IFSRH:
;          *  IFSR_LENGTH      DW     66       ; Total length of request
;          *  IFSR_FUNCTION    DB      4       ; Execute API function
;           + IFSR_RETCODE     DW      ?
;           + IFSR_RETCLASS    DB      ?
;             IFSR_RESV1       DB     16 DUP(0)
;          *  IFSR_APIFUNC     DB     15       ; File Attributes - get/set by name
;           + IFSR_ERROR_CLASS DB      ?
;           + IFSR_ERROR_ACTION DB     ?
;           + IFSR_ERROR_LOCUS DB      ?
;           + IFSR_ALLOWED     DB      ?
;           + IFSR_I24_RETRY   DB      ?
;           + IFSR_I24_RESP    DB      ?
;             IFSR_RESV2       DB      ?
;          *+ IFSR_DEVICE_CB@  DD      ?       ; CD/DF
;             IFSR_OPEN_CB@    DD      ?
;          *  IFSR_FUNC        DB      ?       ; 2=get 3=set depends on INT 2FH
;          *  IFSR_RESV3       DB      ?
;          *  IFSR_SUBFUNC     DB      0       ; in-line parms
;          *  IFSR_RESV4       DB      ?
;             IFSR_BUFFER1@    DD      ?       ; not used here
;             IFSR_BUFFER2@    DD      ?       ; not used here
;             IFSR_COUNT       DW      ?       ; not used here
;          *  IFSR_MATCHATTR   DW      ?       ; format 0000000re0advshr
;          *  IFSR_NAME@       DD      ?       ; ASCIIZ file name ptr
;           + IFSR_SIZE        DD      ?       ; file size
;           + IFSR_DATE        DW      ?       ; file date
;           + IFSR_TIME        DW      ?       ; file time
;          *+ IFSR_ATTR        DW      ?       ; file attribute
;                                              ; format 0000000re0advshr
;                                              ; Set to AX on set
;          IF set THEN
;             DO
;               IFSR_FUNC = 3
;               IFSR_ATTR = AX
;             ENDDO
;          ELSE IFSR_FUNC = 2
;          ENDIF
;          CALL routine, CALL_IFS, with pointer to IFS Header
;          IF IFSR_RETCODE = 0 THEN
;             DO
;               IF cds THEN Call CD_TO_CDS
;               IF dfl THEN Call DF_TO_DFL
;               IF  get THEN
;                  DO
;                    AX = IFSR_ATTR
;                    CX = IFSR_TIME
;                    DX = IFSR_DATE
;                    BX:DI = IFSR_SIZE
;                  ENDDO
;               Clear carry
;             ENDDO
;          ELSE DO
;                 AX = IFSR_RETCODE
;                 Set carry
;               ENDDO
;          ENDIF
;        ENDDO
;     ELSE Set carry
;     ENDIF
; Outputs:
;       CARRY CLEAR
;           AX    = ATTR
;           CX    = TIME
;           DX    = DATE
;           BX:DI = SIZE
;       CARRY SET
;           AX is error code
;               error_file_not_found
;                       Last element of path not found
;               error_path_not_found
;                       Bad path (not in curr dir part if present)
;               error_access_denied
;                       Attempt to set an attribute which cannot be set
;                       (attr_directory, attr_volume_ID)
;               error_sharing_violation
;                       Sharing mode of file did not allow the change
;                       (this request requires exclusive write/read access)
;                       (INT 24H generated)
; Regs: DS preserved, others destroyed
;************************************************************************************
        procedure   IFS_GET_FILE_INFO,NEAR
        ifsr_fcn_def  EXECAPI                   ; define ifsr for fileattr
        ifsr_api_def  FILEATTR
FA_10:
        MOV     CS:IFSPROC_FLAGS,ISGET          ;  set for get
FA_20:
ASSUME  DS:DOSGROUP,ES:NOTHING
        CMP     WORD PTR [THISCDS],NULL_PTR     ; determine CDS or DFL
        JE      FA_100
        LDS     SI,[THISCDS]
ASSUME  DS:NOTHING
        TEST    CS:IFSPROC_FLAGS,ISGET
        JZ      FA_40
        SaveReg <DS,SI>                         ; preserve ds:si -> cds
        JMP     SHORT FA_60
FA_40:
        RestoreReg <AX>                         ; want attr on stack to stay on top
        SaveReg <DS,SI,AX>                      ; stack - ax,si,ds
FA_60:
        invoke  PREP_IFSR                       ; clear ifsrh
        MOV     CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
        invoke  CDS_TO_CD                       ; CDS: sets [THISIFS]
                                                ;           ES:BX -> IFSRH
                                                ;           IFSR_DEVICE_CB@
                                                ;           DS - IFSSEG
        OR      IFSPROC_FLAGS,ISCDS
        JMP     FA_200
FA_100:
        invoke  DFL_SINGLE_FILE_CHECK           ; DFL: sets [THISIFS]
                                                ;           ES:BX -> IFSRH
                                                ;           IFSR_DEVICE_CB@
                                                ;           DS - IFSSEG
        JNC     SHORT FA_200
        MOV     AX,error_invalid_function       ; error - invalid fcn
        invoke  SET_EXTERR_INFO                 ;         set error info &
        JMP     FA_980                          ;         go return
FA_200:
        invoke  DRIVE_FROM_CDS                  ; set IFSDrv for possible I24
        MOV     ES:[BX.IFSR_LENGTH],LENGTH_FILEATTR     ; continue prepping ifsr
        MOV     ES:[BX.IFSR_FUNCTION],IFSEXECAPI
        MOV     ES:[BX.IFSR_APIFUNC],IFSFILEATTR
        TEST    IFSPROC_FLAGS,ISGET
        JNZ     FA_220
        MOV     ES:[BX.IFSR_FUNC],FUNC_SET_BY_NAME
        POP     ES:[BX.IFSR_ATTR]               ; retrieve attr from stack
        JMP     SHORT FA_240
FA_220:
        MOV     ES:[BX.IFSR_FUNC],FUNC_GET_BY_NAME ; get file info
FA_240:
        PUSH    DS                              ; save ds - IFSSEG
        PUSH    SS                              ; get ds = dosgroup so can access
        POP     DS                              ; wfp_start, sattrib
ASSUME  DS:DOSGROUP
        MOV     SI,[WFP_START]
        invoke  STRIP_WFP_START
        MOV     ES:WORD PTR [BX.IFSR_NAME@],SI  ; ifsr_name@
        MOV     ES:WORD PTR [BX.IFSR_NAME@+2],DS
        MOV     AL,[SATTRIB]
        XOR     AH,AH
        MOV     ES:[BX.IFSR_MATCHATTR],AX       ; ifsr_matchattr
        POP     DS                              ; restore ds=IFSSEG
ASSUME  DS:IFSSEG

;************************************************
        invoke  CALL_IFS                        ; call ifs with file attr request
;************************************************
        JNC     FA_260
        TEST    IFSPROC_FLAGS,ISCDS             ; request failed -
        JZ      FA_980                          ; go set carry & return
        ADD     SP,4                            ; if cds, restore stack first
        JMP     FA_980
FA_260:                                         ; request successful
        TEST    IFSPROC_FLAGS,ISGET             ; if get - prep return regs with
        JZ      FA_270                          ; file info
        MOV     AX,ES:[BX.IFSR_ATTR]
        MOV     CX,ES:[BX.IFSR_TIME]
        MOV     DX,ES:[BX.IFSR_DATE]
        MOV     DI,ES:WORD PTR [BX.IFSR_SIZE]
        MOV     BX,ES:WORD PTR [BX.IFSR_SIZE+2]
FA_270:
        TEST    IFSPROC_FLAGS,ISCDS             ; if cds - update cds w/cd
        JZ      FA_280
        RestoreReg <DI,ES>                      ; restore cds ptr into es:di
        invoke  CD_TO_CDS                       ; cd-cds
        JMP     SHORT FA_990                    ; go clc & return
FA_280:
        TEST    IFSPROC_FLAGS,ISSEQ
        JNZ     FA_990
        invoke  DF_TO_DFL                       ; update dfl w/df
        JMP     SHORT FA_990
FA_980:
        STC
        JMP     SHORT FA_1000
FA_990:
        CLC
FA_1000:
        PUSH    SS                              ; restore original ds (dosgroup)
        POP     DS                              ; since this routine preserves ds
        return
EndProc IFS_GET_FILE_INFO
BREAK <IFS_SEQ_RENAME Rename>
;************************************************************************************
; IFS_SEQ_RENAME
; see ifs_rename for details
;************************************************************************************
        procedure   IFS_SEQ_RENAME,NEAR
        ifsr_fcn_def  EXECAPI
        ifsr_api_def  RENFILE
        MOV     CS:IFSPROC_FLAGS,ISREN           ; set for rename and cont.
        JMP     SHORT SD_10                      ; in ifs_seq_delete
EndProc IFS_SEQ_RENAME
BREAK <IFS_RENAME Rename>
;************************************************************************************
; IFS_RENAME
; Inputs:
;       [WFP_START] Points to SOURCE WFP string ("//" must be first 2
;               chars, NUL terminated)
;       [REN_WFP] Points to DEST WFP string ("//" must be first 2
;               chars, NUL terminated)
;       [THISCDS] Points to CDS being used
;       [SATTRIB] Is attribute of search, determines what files can be found
; Function:
;     same processing as delete except for following parms:
;          *  IFSR_LENGTH      DB     48
;          *  IFSR_APIFUNC     DB      7       ; Rename file
;          *  IFSR_NAME1@      DD      ?       ; addr of WFP_START
;          *  IFSR_NAME2@      DD      ?       ; addr of REN_WFP
; Outputs:
;       CARRY CLEAR
;           OK
;       CARRY SET
;           AX is error code
;               error_file_not_found
;                       No match for source, or dest path invalid
;               error_not_same_device
;                       Source and dest are on different devices
;               error_access_denied
;                       Directory specified (not simple rename),
;                       Device name given, Destination exists.
;                       NOTE: In third case some renames may have
;                        been done if metas.
;               error_path_not_found
;                       Bad path (not in curr dir part if present)
;                       SOURCE ONLY
;               error_sharing_violation
;                       Deny both access required, generates an INT 24.
; DS preserved, others destroyed
;************************************************************************************
        procedure   IFS_RENAME,NEAR
        ifsr_fcn_def  EXECAPI
        ifsr_api_def  RENFILE
        MOV     CS:IFSPROC_FLAGS,ISREN          ; set for rename
        JMP     SHORT D_20                      ; processing continues in ifs_delete
EndProc IFS_RENAME
BREAK <IFS_SEQ_DELETE Delete>
;************************************************************************************
; IFS_SEQ_DELETE
; see ifs_delete for details
;************************************************************************************
        procedure   IFS_SEQ_DELETE,NEAR
        ifsr_fcn_def  EXECAPI
        ifsr_api_def  DELFILE
        MOV     IFSPROC_FLAGS,0                 ; Clear IFS processing flags
SD_10:
        invoke  CHECK_SEQ                       ; check if this is unc or ifs device
        JC      D_20                            ; cf=0 unc, cf=1 device
SD_20:                                          ; welcome ifs_seq_rename code
        PUSH    CS
        POP     DS
ASSUME  DS:IFSSEG
        OR      IFSPROC_FLAGS,ISSEQ             ; SEQ - UNC
        invoke  SET_THISIFS_UNC                 ;     set [THISIFS] = UNC IFS
        JMP     SHORT D_30                      ;     cont. in ifs_delete
EndProc IFS_SEQ_DELETE
BREAK <IFS_DELETE Delete>
;************************************************************************************
; IFS_DELETE
; Called by:       IFSFUNC Dispatcher
; Routines called: CDS_TO_CD
;                  CD_TO_CDS   CALL_IFS
; Inputs:
;       [WFP_START] Points to WFP string ("//" must be first 2 chars, NUL
;               terminated)
;       [THISCDS] Points to CDS being used
;       [SATTRIB] Is attribute of search, determines what files can be found
; Function:
;     IF INT 2FH call .NOT. SEQ version THEN
;        DO
;          IF [THISCDS] .NOT. NULL  THEN
;             DO
;                 CALL CDS_TO_CD
;                 Set IFS_DEVICE_CB@ as pointer to CD
;                 Set IFS_HDR_PTR = CURDIR_IFS_HDR
;             ENDDO
;          ELSE DO
;                 Set AX = invalid function
;                 Set extended error info
;               ENDDO
;          ENDIF
;        ENDDO
;     ELSE DO
;            Set IFS_DEVICE_CB@ to NULL
;            Set IFS_HDR_PTR = [UNC_FS_HDR]
;          ENDDO
;     ENDIF
;     IF  no error  THEN
;        DO
;          Prep IFSRH:
;          *  IFSR_LENGTH      DW     44       ; Total length of request
;          *  IFSR_FUNCTION    DB      4       ; Execute API function
;           + IFSR_RETCODE     DW      ?
;           + IFSR_RETCLASS    DB      ?
;             IFSR_RESV1       DB     16 DUP(0)
;          *  IFSR_APIFUNC     DB      6       ; Delete file
;           + IFSR_ERROR_CLASS DB      ?
;           + IFSR_ERROR_ACTION DB     ?
;           + IFSR_ERROR_LOCUS DB      ?
;           + IFSR_ALLOWED     DB      ?
;           + IFSR_I24_RETRY   DB      ?
;           + IFSR_I24_RESP    DB      ?
;             IFSR_RESV2       DB      ?
;          *+ IFSR_DEVICE_CB@  DD      ?       ; CD
;             IFSR_OPEN_CB@    DD      ?
;          *  IFSR_MATCHATTR   DW      ?       ; attribute - format 00000000e0a00shr
;          *  IFSR_NAME@       DD      ?       ; filename to delete
;          Call routine, CALL_IFS, with pointer to CURDIR_IFSR_HDR
;          IF IFSR_RETCODE = 0 THEN
;             DO
;               Call CD_TO_CDS or DF_TO_DFL
;               Clear carry
;             ENDDO
;          ELSE DO
;                 AX = IFSR_RETCODE
;                 Set carry
;               ENDDO
;          ENDIF
;        ENDDO
;     ELSE set carry
;     ENDIF
; Outputs:
;       CARRY CLEAR
;               OK
;       CARRY SET
;           AX is error code
;               error_file_not_found
;                       Last element of path not found
;               error_path_not_found
;                       Bad path
;               error_access_denied
;                       Attempt to delete device or directory
; DS preserved, others destroyed
;************************************************************************************
        procedure   IFS_DELETE,NEAR
        ifsr_fcn_def  EXECAPI
        ifsr_api_def  DELFILE
        MOV     CS:IFSPROC_FLAGS,ZERO           ; Clear IFS processing flags
D_20:                                           ; (Welcome ifs_ren)
ASSUME  DS:DOSGROUP
        invoke  DRIVE_FROM_CDS                  ; ds - dosgroup
        CMP     WORD PTR [THISCDS],NULL_PTR     ; CDS must not be null
        JNE     D_30
        MOV     AX,error_invalid_function
        invoke  SET_EXTERR_INFO
        JMP     FA_980                          ; go up, preserve ds, ret w/carry
D_30:                                           ; (Welcome seq ren/del code)
        invoke  PREP_IFSR                       ; zero ifsr, es:bx -> ifsr
        MOV     SI,[WFP_START]
        invoke  STRIP_WFP_START
        TEST    CS:IFSPROC_FLAGS,ISREN
        JZ      D_40                            ; rename
        MOV     ES:WORD PTR [BX.IFSR_NAME1@],SI ; ifsr_name1@ & 2@
        MOV     ES:WORD PTR [BX.IFSR_NAME1@+2],DS
        MOV     SI,[REN_WFP]
        CMP     BYTE PTR DS:[SI+1],":"
        JNE     D_36
        ADD     SI,2
D_36:
        MOV     ES:WORD PTR [BX.IFSR_NAME2@],SI
        MOV     ES:WORD PTR [BX.IFSR_NAME2@+2],DS
        MOV     ES:[BX.IFSR_LENGTH],LENGTH_RENFILE ; ifsr_length
        MOV     ES:[BX.IFSR_APIFUNC],IFSRENFILE    ; ifsr_apifunc
        JMP     SHORT D_60
D_40:                                              ; delete
        MOV     ES:WORD PTR [BX.IFSR_NAME@],SI     ; ifsr_name@
        MOV     ES:WORD PTR [BX.IFSR_NAME@+2],DS
        MOV     ES:[BX.IFSR_LENGTH],LENGTH_DELFILE ; ifsr_length
        MOV     ES:[BX.IFSR_APIFUNC],IFSDELFILE    ; ifsr_apifunc
D_60:
        MOV     AL,[SATTRIB]
        XOR     AH,AH
        MOV     ES:[BX.IFSR_MATCHATTR],AX          ; ifsr_matchattr
        MOV     ES:[BX.IFSR_FUNCTION],IFSEXECAPI   ; ifsr_function
        TEST    CS:IFSPROC_FLAGS,ISSEQ          ; if unc, don't do cds stuff
        JNZ     D_70
        LDS     SI,[THISCDS]
ASSUME  DS:NOTHING
        SaveReg <DS,SI>                         ; preserve ds:si -> cds
        MOV     CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
        invoke  CDS_TO_CD                       ; CDS: sets [THISIFS]
                                                ;           ES:BX -> IFSRH
                                                ;           IFSR_DEVICE_CB@
                                                ;           ds - IFSSEG
D_70:
        invoke  CALL_IFS                        ; call ifs w/request
        JNC     D_80
        TEST    IFSPROC_FLAGS,ISSEQ             ; fs error - restore stack
        JZ      D_75                            ; if not unc - go ret
        JMP     FA_980
D_75:
        ADD     SP,4
        JMP     FA_980
D_80:
        TEST    IFSPROC_FLAGS,ISSEQ             ; fs successful
        JZ      D_90                            ; if seq, just ret
        JMP     FA_990
D_90:                                           ; else -
        RestoreReg <DI,ES>                      ; restore cds ptr into es:di
        invoke  CD_TO_CDS
        JMP     FA_990                          ; go up & ret in fa to preserve ds
EndProc IFS_DELETE
BREAK <IFS_SEQ_OPEN Open>
;************************************************************************************
; see IFS_OPEN for details
;************************************************************************************
        procedure   IFS_SEQ_OPEN,NEAR
        ifsr_fcn_def  EXECAPI                   ; define ifsr for open/create
        ifsr_api_def  OPENFILE
        PUSH    AX                              ; save access/share byte
        MOV     CS:IFSPROC_FLAGS,ISOLDOPEN      ; remember this is old open
        JMP     SHORT SXO_10                    ; cont. in ifs_seq_xopen
EndProc IFS_SEQ_OPEN
BREAK <IFS_OPEN Open>
;************************************************************************************
; IFS_OPEN
; Inputs:
;       [WFP_START] Points to WFP string ("//" must be first 2 chars, NUL
;               terminated)
;       [THISCDS] Points to CDS being used
;       [THISSFT] Points to SFT to fill in if file found
;               (sf_mode field set so that FCB may be detected)
;       ES:DI = [THISSFT]
;       [SATTRIB] Is attribute of search, determines what files can be found
;       AX is Access and Sharing mode
;         High NIBBLE of AL (Sharing Mode)
;               sharing_compat     file is opened in compatibility mode
;               sharing_deny_none  file is opened Multi reader, Multi writer
;               sharing_deny_read  file is opened Only reader, Multi writer
;               sharing_deny_write file is opened Multi reader, Only writer
;               sharing_deny_both  file is opened Only reader, Only writer
;         Low NIBBLE of AL (Access Mode)
;               open_for_read   file is opened for reading
;               open_for_write  file is opened for writing
;               open_for_both   file is opened for both reading and writing.
;         For FCB SFTs AL should = -1
;               (not checked)
; Function:
;     see IFS_XOPEN
; Outputs:
;       sf_ref_count is NOT altered
;       CARRY CLEAR
;           THISSFT filled in.
;       CARRY SET
;           AX is error code
;               error_file_not_found
;                       Last element of path not found
;               error_path_not_found
;                       Bad path
;               error_access_denied
;                       Attempt to open read only file for writting, or
;                       open a directory
;               error_sharing_violation
;                       The sharing mode was correct but not allowed
;                       generates an INT 24 on compatibility mode SFTs
; Regs: DS preserved, others destroyed
;************************************************************************************
        procedure   IFS_OPEN,NEAR
        ifsr_fcn_def  EXECAPI                   ; define ifsr for open/create
        ifsr_api_def  OPENFILE
        PUSH    AX                              ; save access/share mode
        MOV     CS:IFSPROC_FLAGS,ISOLDOPEN      ; set for old open
        JMP     SHORT XO_20                     ; Rest of processing in
                                                ; extended open routine.
EndProc IFS_Open
BREAK <IFS_SEQ_CREATE Open>
;************************************************************************************
; IFS_SEQ_CREATE
; see IFS_CREATE for details
;************************************************************************************
        procedure   IFS_SEQ_CREATE,NEAR
        ifsr_fcn_def  EXECAPI                   ; define ifsr for open/create
        ifsr_api_def  OPENFILE
        PUSH    AX                              ; save attribute
        MOV     CS:IFSPROC_FLAGS,IsOldCreate + IsCreate ; remember is old create
        JMP     SHORT SXO_10                    ; cont. in ifs_seq_xopen
EndProc IFS_SEQ_CREATE
BREAK <IFS_CREATE Create>
;************************************************************************************
; IFS_CREATE
; Inputs:
;       [WFP_START] Points to WFP string ("d:/" must be first 3 chars, NUL
;               terminated)
;       [CURR_DIR_END] Points to end of Current dir part of string
;               ( = -1 if current dir not involved, else
;                Points to first char after last "/" of current dir part)
;       [THISCDS] Points to CDS being used
;       [THISSFT] Points to SFT to fill in if file created
;               (sf_mode field set so that FCB may be detected)
;       ES:DI = [THISSFT]
;       [SATTRIB] Is attribute of search, determines what files can be found
;       AL is Attribute to create
;       AH is 0 if CREATE, non zero if CREATE_NEW
; Function:
;       See IFS_XOPEN for details
; Outputs:
;       sf_ref_count is NOT altered
;       CARRY CLEAR
;           THISSFT filled in.
;               sf_mode = sharing_compat + open_for_both for Non-FCB SFT
;       CARRY SET
;           AX is error code
;               error_path_not_found
;                       Bad path (not in curr dir part if present)
;               error_access_denied
;                       Attempt to re-create read only file , or
;                       create a second volume id or create a dir
;               error_sharing_violation
;                       The sharing mode was correct but not allowed
;                       generates an INT 24
; Regs: DS preserved, others destroyed
;************************************************************************************
        procedure   IFS_CREATE,NEAR
        ifsr_fcn_def  EXECAPI                   ; define ifsr for open/create
        ifsr_api_def  OPENFILE
        PUSH    AX                              ; save attribute
        MOV     CS:IFSPROC_FLAGS,ISOLDCREATE    ; remember is old create
        JMP     SHORT XO_20                     ; cont. in ifs_xopen
EndProc IFS_Create
BREAK <IFS_SEQ_XOPEN Open>
;************************************************************************************
; IFS_SEQ_XOPEN
; see IFS_XOPEN for details
;************************************************************************************
        procedure   IFS_SEQ_XOPEN,NEAR
        ifsr_fcn_def  EXECAPI                   ; define ifsr for open/create
        ifsr_api_def  OPENFILE
        MOV     IFSPROC_FLAGS,0                 ; Clear IFS processing flags
SXO_10:
        invoke  CHECK_SEQ                       ; check if this is unc or ifs device
        JC      XO_20                           ; cf=0 unc, cf=1 device
SXO_20:
        PUSH    CS                              ; ds-ifsseg
        POP     DS
ASSUME  DS:IFSSEG
        OR      IFSPROC_FLAGS,ISSEQ             ; SEQ = UNC
        invoke  SET_THISIFS_UNC                 ; set [THISIFS] = UNC IFS
        invoke  PREP_IFSR                       ; zero out ifsr
        JMP     XO_200                          ; cont. in ifs_xopen
EndProc IFS_SEQ_XOPEN
BREAK <IFS_XOPEN Open>
;************************************************************************************
;
; IFS_XOPEN
;
; Called by:       IFSFUNC dispatcher
;
; Routines called: CALL_IFS    DFL_MATCH
;                  CD_TO_CDS   DFL_TO_DF
;                  CDS_TO_CD   DF_TO_DFL
;                  SFT_TO_SFF
;                  SF_TO_SFT
;
; Inputs:
;       [THISCDS] Set
;       [THISSFT] Set
;       [SAVE_DX] = FLAG: FUNCTION CONTROL, FORMAT=0000000C NNNN EEEE
;                  C 0=VALIDATE CODE PAGE, 1=NO CODE PAGE CHECK
;                  NNNN=DOES NOT EXIST ACTION:  0=FAIL, 1=CREATE
;                  EEEE=EXISTS ACTION        :  0=FAIL, 1=OPEN, 2=REPLACE/OPEN
;       [SAVE_BX] = MODE  OPEN MODE   FORMAT : 0WF00000ISSS0AAA
;                  AAA = ACCESS CODE: 0=READ, 1=WRITE, 2=READ/WRITE
;                                     3=EXECUTE (UNDOCUMENTED)
;                                     7=FCB     (UNDOCUMENTED)
;                  SSS=SHARING MODE : 0=COMPATIBILITY, 1=DENY READ/WRITE
;                                     2=DENY WRITE, 3=DENY READ,
;                                     4=DENY NONE
;                  I 0=PASS HANDLE TO CHILD, 1=NO INHERIT
;                  F 0=INT 24H, 1=RETURN ERROR
;                  ON THIS OPEN AND ANY IO TO THIS HANDLE
;                  W 0=NO COMMIT, 1=AUTO-COMMIT ON WRITE
;       AX        = ATTR  SEARCH/CREATE ATTRIBUTE
;       [SAVE_DS]:[SAVE_SI] = Full path name
;       [SAVE_ES]:[SAVE_DI] = Parameter list
;                             Null list if DI=-1
;
; Function:
;       IF SEQ THEN
;          prep for UNC
;       ELSE DO
;              IF  [THISCDS] .NOT. NULL  THEN
;                 DO
;                   Call CDS_TO_CD
;                   Set IFSR_DEVICE_CB@ as pointer to CD
;                   Set IFS pointer to CURDIR_IFSR_HDR
;                   DFL_FLAG = 0
;                 ENDDO
;              ELSE DO
;                     Call DFL_TO_DF
;                     Set IFSR_DEVICE_CB@ as pointer to DF
;                     Set IFS pointer to DFL_IFSR_HDR
;                     DFL_FLAG = 1
;                   ENDDO
;              ENDIF
;            ENDDO
;       ENDIF
;       Prep IFSRH:
;       *  IFSR_LENGTH      DW     62       ; Request length
;       *  IFSR_FUNCTION    DB      4       ; Execute API function
;        + IFSR_RETCODE     DW      ?
;        + IFSR_RETCLASS    DB      ?
;          IFSR_RESV1       DB     16 DUP(0)
;       *  IFSR_APIFUNC     DB      9       ; Open/Create File
;        + IFSR_ERROR_CLASS DB      ?
;        + IFSR_ERROR_ACTION DB     ?
;        + IFSR_ERROR_LOCUS DB      ?
;        + IFSR_ALLOWED     DB      ?
;        + IFSR_I24_RETRY   DB      ?
;        + IFSR_I24_RESP    DB      ?
;          IFSR_RESV2       DB      ?
;       *+ IFSR_DEVICE_CB@  DD      ?       ; CD/DF
;       *+ IFSR_OPEN_CB@    DD      ?       ; convert SFT to SFF
;                                           ; and set this as pointer to it.
;       *  IFSR_MODE        DW      ?       ; BX - open mode
;       *  IFSR_FLAG        DW      ?       ; AL
;       *  IFSR_CP          DW      ?       ; Global code page
;       *  IFSR_CPSW        DB      0       ; Code page switch flag
;          IFSR_RESV3       DB      0
;       *  IFSR_NAME@       DD      ?       ; ptr to full asciiz filename
;       *  IFSR_PARMS@      DD      ?       ; ES:DI
;       *  IFSR_MATCHATTR   DW      ?       ; CX
;        + IFSR_ACTION      DW      0       ; Action taken code: 1=file opened
;                                           ; 2=file created/opened
;                                           ; 3=file replaced/opened
;
;       CALL routine, CALL_IFS, with IFS pointer
;       IF IFSR_RETCODE = 0 THEN
;          DO
;            IF DFL_FLAG = 0 THEN
;               Call CD_TO_CDS
;            ELSE  Call DF_TO_DFL
;            Call SF_TO_SFT
;            CX = IFSR_ACTION
;          ENDDO
;       ELSE DO   /* error */
;              AX = IFSR_RETCODE
;              Set carry
;            ENDDO
;       ENDIF
;
; Outputs:
;       CX=ACTION TAKEN CODE
;          1 = FILE OPENED
;          2 = FILE CREATED/OPENED
;          3 = FILE REPLACED/OPENED
;       sf_ref_count is NOT altered
;       THISSFT filled in or updated
;       AX set on error:
;               error_file_not_found
;                       Last element of path not found
;               error_path_not_found
;                       Bad path
;               error_access_denied
;                       Attempt to open read only file for writing,
;                       or open a directory
;               error_sharing_violation
;                       The sharing mode was correct but not allowed
;                       generates an INT 24 on compatibility mode SFTs
; DS preserved, others destroyed
;
;************************************************************************************
        procedure   IFS_XOPEN,NEAR
        ifsr_fcn_def  EXECAPI                   ; define ifsr for open/create
        ifsr_api_def  OPENFILE
        PUSH    AX                              ; srch attr/create attr
        MOV     CS:IFSPROC_FLAGS,ZERO           ; Clear IFS processing flags
        JMP     SHORT XO_25                                                              ;AN008; BAF
XO_20:                                          ; (welcome all old open/create calls)
ASSUME  DS:DOSGROUP
        MOV     [SAVE_DI],-1                    ; set no parms list on old calls         ;AN008; BAF
XO_25:                                                                                   ;AN008; BAF
        invoke  PREP_IFSR                       ; zero out ifsr
        MOV     CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
        LEA     SI,COUNTRY_CDPG                 ; load cp and cpsw
        MOV     AX,DS:[SI.ccDosCodePage]        ;      |
        MOV     ES:[BX.IFSR_CP],AX              ;      |
        MOV     AL,[CPSWFLAG]                   ;      |
        MOV     ES:[BX.IFSR_CPSW],AL            ;      |

        CMP     WORD PTR [THISCDS],NULL_PTR     ; determine CDS or DFL
        JE      XO_100
        LDS     SI,[THISCDS]                    ; cds--cds--cds--cds--cds--cds
        MOV     AX,SI                           ; set ifsDrv for possible I24
        invoke  IFSDrvFromCDS
        RestoreReg <AX>                         ; must have ax 1st on stack
        SaveReg <DS,SI,AX>                      ; cds ptr, attr
XO_60:
        invoke  CDS_TO_CD                       ; CDS: sets [THISIFS]
                                                ;           ES:BX -> IFSRH
                                                ;           IFSR_DEVICE_CB@
                                                ;           ds - IFSSEG
        OR      IFSPROC_FLAGS,ISCDS
        JMP     SHORT XO_200                    ; go prep IFSRH
XO_100:
        SaveReg <ES>                            ; if deviceless attach, skip device stuff
        LES     DI,CS:[THISDFL]
        CMP     WORD PTR [THISDFL],NULL_PTR
        RestoreReg <ES>
        JNE     XO_110
        OR      CS:IFSPROC_FLAGS,IsSeq
        CMP     CS:[fAssign],ZERO
        JNE     XO_200
        ADD     SP,2
        MOV     AX,72
        JMP     XO_120
XO_110:
        invoke  DFL_SINGLE_FILE_CHECK           ; DFL: sets [THISIFS]
                                                ;           ES:BX -> IFSRH
                                                ;           IFSR_DEVICE_CB@
                                                ;           ds - IFSSEG
        JNC     XO_200
;;;;;;;;TEST    IFSPROC_FLAGS,ISOLDOPEN+ISOLDCREATE     ; new open also pushes ax        ;AD014;
;;;;;;;;JZ      XO_120                          ;  dfl error                             ;AD014;
        ADD     SP,2                            ;  get saved ax off stack if old
;XO_120:                                                                                 ;AD014;
        MOV     AX,error_invalid_function       ;  set error info and quit
XO_120:
        invoke  SET_EXTERR_INFO
        JMP     FA_980                          ; ret up in FA to preserve DS
XO_200:                                         ; (welcome seq open/create)
        Context DS                              ; get addressability to dosgroup
        invoke  SFT_TO_SFF                      ; SFT: sets IFSR_OPEN_CB@
                                                ;           ES:BX -> IFSRH
                                                ;           ds - IFSSEG
        MOV     ES:[BX.IFSR_LENGTH],LENGTH_OPENFILE ; prep IFRH
        MOV     ES:[BX.IFSR_FUNCTION],IFSEXECAPI
        MOV     ES:[BX.IFSR_APIFUNC],IFSOPENFILE
        POP     AX                              ; restore input AX
        TEST    IFSPROC_FLAGS,ISOLDOPEN         ; check for old open/create
        JZ      XO_220
;;;;;;  OR      AX,OLDOPEN_MODE                 ; why did I do this???? scrap            ;AD006;

        SaveReg <DS,SI>                         ; old redirector does this
        Context DS
        LDS     SI,[THISSFT]
        TEST    DS:[SI.SF_MODE],sf_isFCB
        RestoreReg <SI,DS>
        JZ      XO_210
        MOV     AL,-1
XO_210:

        MOV     ES:[BX.IFSR_MODE],AX
        MOV     ES:[BX.IFSR_FLAG],OLDOPEN_FLAG
        XOR     AH,AH
        JMP     SHORT XO_240
XO_220:
        TEST    IFSPROC_FLAGS,ISOLDCREATE
        JZ      XO_260
        MOV     ES:[BX.IFSR_MODE],OLDCREATE_MODE        ; old create
        MOV     ES:[BX.IFSR_FLAG],OLDCREATE_FLAG
        OR      AH,AH                           ; is this create new??
        JZ      XO_230
        MOV     ES:[BX.IFSR_FLAG],OLDCREATENEW_FLAG
XO_230:
        XCHG    AH,AL
XO_240:
        PUSH    SS                              ; get ds = dosgroup so can access
        POP     DS                              ; wfp_start
ASSUME  DS:DOSGROUP
        MOV     AL,[SATTRIB]
        MOV     ES:[BX.IFSR_MATCHATTR],AX
        JMP     SHORT XO_280                    ; go call FS
XO_260:                                         ; -------extended open/create------------
        Context DS                              ; set ds-dosgroup
;;;;;;;;PUSH    [SAVE_DX]                                                                ;AD012;
;;;;;;;;POP     ES:[BX.IFSR_FLAG]               ; input dx - flag                        ;AD012;
        SaveReg <AX>                            ; check if create, if so set flag
        MOV     AX,[SAVE_DX]
        MOV     ES:[BX.IFSR_FLAG],AX
        MOV     AH,AL
        AND     AX,0FF0H
        CMP     AL,NOTEXIST_ACT_CREATE*16
        RestoreReg <AX>
        JNE     XO_270
        OR      IFSPROC_FLAGS,IsCreate
XO_270:

        PUSH    [SAVE_BX]
        POP     ES:[BX.IFSR_MODE]               ; input bx - mode
        XCHG    AH,AL                           ; attr
        MOV     AL,[SATTRIB]
        MOV     ES:[BX.IFSR_MATCHATTR],AX
;       MOV     DI,[SAVE_DI]                    ; parm list                              ;AD011;
;       CMP     DI,NULL_PTR                     ;  if offset -1, then no parm list       ;AD011;
;       JE      XO_280                          ;    |                                   ;AD011;
;       MOV     ES:WORD PTR[BX.IFSR_PARMS@],DI  ;    |                                   ;AD011;
;       PUSH    [SAVE_ES]                       ;    |                                   ;AD011;
;       POP     ES:WORD PTR[BX.IFSR_PARMS@+2]   ;    |                                   ;AD011;

XO_280:
        MOV     SI,[WFP_START]
        invoke  STRIP_WFP_START
        MOV     WORD PTR ES:[BX.IFSR_NAME@],SI
        MOV     WORD PTR ES:[BX.IFSR_NAME@+2],DS
        PUSH    CS
        POP     DS
ASSUME  DS:IFSSEG
;******************************************************************************
        invoke  CALL_IFS                        ; call fs with open/create request
;******************************************************************************
        JNC     XO_300
        TEST    IFSPROC_FLAGS,ISCDS             ; request FAILED -
        JNZ     XO_290
        JMP     FA_980                          ;   go up, set carry & return
XO_290:
        RestoreReg <SI,DS>                      ;   if cds, restore stack first
        JMP     FA_980
XO_300:                                         ; request SUCCEEDED -
        TEST    IFSPROC_FLAGS,ISOLDOPEN+ISOLDCREATE   ; check for old open/create        ;AN007; BAF
        JNZ     XO_310                                                                   ;AN007; BAF
        SaveReg <DS,SI>                                                                  ;AN007; BAF
        CallInstall Get_User_Stack,multDOS,24   ; Set action take back into CX           ;AN007; BAF
ASSUME  DS:DOSGROUP                                                                      ;AN007; BAF
        MOV     AX,ES:[BX.IFSR_ACTION]          ; action take only if Ext Open           ;AN007; BAF
        MOV     DS:[SI].USER_CX,AX                                                       ;AN007; BAF
        RestoreReg <SI,DS>                                                               ;AN007; BAF
ASSUME  DS:IFSSEG                                                                        ;AN007; BAF
XO_310:                                         ; request SUCCEEDED -                    ;AN007; BAF
        MOV     AX,ES:[BX.IFSR_MATCHATTR]
        invoke  SFF_TO_SFT                      ;   update sft
        TEST    IFSPROC_FLAGS,ISCDS
        JZ      XO_320
        RestoreReg <DI,ES>                      ;   cds-restore cds ptr into es:di
        invoke  CD_TO_CDS                       ;   update cds
        JMP     XO_360
XO_320:
        TEST    IFSPROC_FLAGS,ISSEQ
        JZ      XO_340
        MOV     DI,NULL_PTR                     ;   set seq devptr to null
        SaveReg <DI>                            ;   this for sf_devptr
        RestoreReg <ES>
        JMP     SHORT XO_360
XO_340:
        invoke  DF_TO_DFL                       ;   update dfl
        LES     DI,[THISDFL]                    ;   this for sf_devptr
        XOR     AX,AX                           ;   attr 0 for devices
XO_360:
        Context DS
        LDS     SI,[THISSFT]                    ; set some fields in sft
        MOV     DS:[SI.sf_attr],AL
;;;;;;;;MOV     DS:[SI.sf_attr_hi],AH                                                    ;AD015;
        MOV     WORD PTR DS:[SI.sf_devptr],DI
        MOV     WORD PTR DS:[SI.sf_devptr+2],ES
        TEST    CS:IFSPROC_FLAGS,IsCDS + IsSeq  ; let deviceless attach stuff thru here
        JZ      XO_380
        MOV     AL,CS:[IFSDRV]                  ; drive
        AND     AX,devid_file_mask_drive ; Drive in correct bits
        OR      AX,sf_isnet + devid_file_clean
        MOV     DS:[SI.sf_flags],AX
                                                ; now set sf_name to filename in form:
                                                ; filename ext  (8 char fn spaced out -
                                                ; 3 char ext spaced out)
        SaveReg <CX,DS,SI,DS>                   ; save dssi->sf for later pop & action
        RestoreReg <ES>
        MOV     DI,SI                           ; esdi->sft
        ADD     DI,sf_name                      ; blank out sf_name
        SaveReg <DI>                            ;         |
        MOV     AX,2020H                        ;         |
        MOV     CX,5                            ;         |
        CLD                                     ;         |
        REP     STOSW                           ;         |
        STOSB                                   ;         |
        RestoreReg <DI>                         ;         |
        Context DS
        MOV     SI,[WFP_START]                  ; dssi->wfp_start
        CallInstall DStrlen,multDOS,37          ; get length of full path name (in cx)
        ADD     SI,CX                           ; mov si to end of name
        DEC     SI                              ; si now on null
XO_362:
        DEC     SI                              ; mov back one
        CMP     BYTE PTR DS:[SI],"\"            ; looking for \ just before fn
        JNE     XO_362
        INC     SI                              ; si now pointing to 1st char fn
        MOV     CX,8                            ; esdi -> sf_name
XO_364:
        LODSB
        STOSB
        DEC     CX
        CMP     AL,"."
        JE      XO_368
        OR      AL,AL
        JZ      XO_366
        JCXZ    XO_369
        JMP     SHORT XO_364
XO_366:
        MOV     BYTE PTR ES:[DI-1]," "
        JMP     SHORT XO_378
XO_368:
        MOV     BYTE PTR ES:[DI-1]," "
        ADD     DI,CX
XO_369:
        MOV     CX,3
XO_370:
        LODSB
        STOSB
        DEC     CX
        OR      AL,AL
        JZ      XO_372
        JCXZ    XO_378
        JMP     SHORT XO_370
XO_372:
        MOV     BYTE PTR ES:[DI-1]," "
XO_378:
        RestoreReg <SI,DS,CX>           ; dssi -> sft, cx=action code
        JMP     SHORT XO_500
XO_380:
;;;;;;;;TEST    CS:IFSPROC_FLAGS,ISSEQ                                                   ;AD014;
;;;;;;;;JNZ     XO_500                                                                   ;AD014;
        MOV     DS:[SI.sf_flags],sf_isnet+devid_file_clean+sf_net_spool+devid_device
        SaveReg <CX,DS,SI>                      ; sft ptr, action
        invoke  XCHGP                           ; dssi -> dfl, esdi -> sft
        ADD     DI,sf_name
        ADD     SI,DFL_DEV_NAME ; Skip over path sep, now pointing to name
        MOV     CX,4
        REP     MOVSW
        MOV     AX,2020H
        STOSW
        STOSB
        RestoreReg <SI,DS,CX>                   ; sft ptr, action                        ;AN003/AC005;

XO_500:
        MOV     AX,WORD PTR CS:[THISIFS]        ; set sf_ifs_hdr
        MOV     WORD PTR DS:[SI.SF_IFS_HDR],AX
        MOV     AX,WORD PTR CS:[THISIFS+2]
        MOV     WORD PTR DS:[SI.SF_IFS_HDR+2],AX

        MOV     AX,CS:[SFT_SERIAL_NUMBER]       ; give new sft serial number for
        MOV     DS:[SI.SF_FIRCLUS],AX           ; fcb processing
        INC     CS:[SFT_SERIAL_NUMBER]

        MOV     WORD PTR DS:[SI.SF_POSITION],0
        MOV     WORD PTR DS:[SI.SF_POSITION+2],0

        TEST    CS:IFSPROC_FLAGS,IsCreate       ; if create, set sf time/date
        JZ      XO_520
        push    ds                              ;AN017: SAVE DS   **RPS
        CallInstall DATE16,MultDOS,13
        pop     ds                              ;AN017: SAVE DS   **RPS
        MOV     DS:[SI.SF_TIME],DX
        MOV     DS:[SI.SF_DATE],AX
        MOV     WORD PTR DS:[SI.SF_SIZE],0
        MOV     WORD PTR DS:[SI.SF_SIZE+2],0
XO_520:

        PUSH    SS                              ; Preserve input DS
        POP     DS
        MOV     AX,(multDOS SHL 8) OR 12
        INT     2FH
        return
EndProc IFS_XOPEN
BREAK <IFS_SEQ_SEARCH>
;************************************************************************************
; IFS_SEQ_SEARCH
; Inputs:
;       [WFP_START] Points to WFP string ("d:/" must be first 3 chars, NUL
;               terminated)
;       [SATTRIB] Is attribute of search, determines what files can be found
;       [DMAADD] Points to 53 byte buffer
; Function:
; BECAUSE OF THE STRUCTURE OF SEARCH IT MUST BE RELATIVE TO A CDS SESSION
; Outputs:
;       CARRY SET
;           AX = error_path_not_found
; DS preserved, others destroyed
;************************************************************************************
        procedure   IFS_SEQ_SEARCH_FIRST,NEAR
ASSUME  DS:DOSGROUP,ES:NOTHING
        MOV     AX,error_path_not_found
        STC
        return
EndProc IFS_SEQ_SEARCH_FIRST
;************************************************************************************
; IFS_SEQ_SEARCH_NEXT
; Inputs:
;       [DMAADD] Points to 53 byte buffer returned by DOS_SEARCH_FIRST
;           (only first 21 bytes must have valid information)
; Function:
; BECAUSE OF THE STRUCTURE OF SEARCH IT MUST BE RELATIVE TO A CDS SESSION
; Outputs:
;       CARRY SET
;           AX = error_no_more_files
; DS preserved, others destroyed
;************************************************************************************
        procedure   IFS_SEQ_SEARCH_NEXT,NEAR
ASSUME  DS:DOSGROUP,ES:NOTHING
        JMP     IFS_SEQ_SEARCH_FIRST
EndProc IFS_SEQ_SEARCH_NEXT
BREAK <IFS_SEARCH_FIRST Search for first entry>
;************************************************************************************
;
; IFS_SEARCH_FIRST
;
; Inputs:
;       [WFP_START] Points to WFP string ("//" must be first 2 chars, NUL
;               terminated)
;       [THISCDS] Points to CDS being used may not be NUL
;       [SATTRIB] Is attribute of search, determines what files can be found
;       [DMAADD] Points to 53 byte buffer
;       DS - dosgroup
;
; Function:
;     Prep IFSRH:
;     *  IFSR_LENGTH      DW     50             ; Request length
;     *  IFSR_FUNCTION    DB      4             ; Execute API function
;      + IFSR_RETCODE     DW      ?
;      + IFSR_RETCLASS    DB      ?
;        IFSR_RESV1       DB     16 DUP(0)
;     *  IFSR_APIFUNC     DB      8             ; Search file
;      + IFSR_ERROR_CLASS DB      ?
;      + IFSR_ERROR_ACTION DB     ?
;      + IFSR_ERROR_LOCUS DB      ?
;      + IFSR_ALLOWED     DB      ?
;      + IFSR_I24_RETRY   DB      ?
;      + IFSR_I24_RESP    DB      ?
;        IFSR_RESV2       DB      ?
;     *+ IFSR_DEVICE_CB@  DD      ?             ; CD
;        IFSR_OPEN_CB@    DD      ?             ; null
;     *  IFSR_SUBFUNC     DB      subfunction   ; 1=first, 2=next
;                                               ; 4=last (CP/DOS only)
;     *  IFSR_RESV3       DB      ?             ; DOS Reserved
;     *+ IFSR_CONTINFO@   DD      continuation info address (always set):
;     *                          DB      8 DUP(?)   ; SEARCH FILE NAME
;     *                          DB      3 DUP(?)   ; SEARCH FILE EXTENSION
;     *                          DB      ?          ; SEARCH ATTRIBUTE
;                                DB      8 DUP(?)   ; FSDA
;                                 DIRECTORY ENTRY
;      +                         DB      8 DUP(?)   ; FOUND FILE NAME
;      +                         DB      3 DUP(?)   ; FOUND FILE EXTENSION
;      +                         DB      ?          ; FOUND ATTRIBUTE LOW  ??? DB/DD
;      +                         DW      ?          ; FILE CODE PAGE (OR 0)
;      +                         DW      ?          ; RESERVED
;      +                         DB      ?          ; FOUND ATTRIBUTE HIGH
;      +                         DB      5  DUP(?)  ; RESERVED
;      +                         DW      ?          ; FILE TIME
;      +                         DW      ?          ; FILE DATE
;      +                         DW      ?          ; MEANING FILE SYSTEM SPECIFIC
;                                                   ; (STARTING CLUSTER IN FAT)
;      +                         DD      ?          ; FILE SIZE
;  following on search first only
;     *  IFSR_MATCHATTR   DW      ; search attribute  ; format 0000000re0advshr
;     *  IFSR_NAME@       DD      ; asciiz name to process
;
;     IF search first THEN
;        DO
;          IFSR_SUBFUNC = 1
;          Get CDS from [THISCDS]
;          Call CDS_TO_CD
;        ENDDO
;     ELSE DO
;            IFSR_SUBFUNC = 2
;            Get CDS from drive byte in DMAADD
;            Call CDS_TO_CD
;          ENDDO
;     ENDIF
;     CALL routine, CALL_IFS, with pointer to CURDIR_IFSR_HDR
;     IF IFSR_RETCODE = 0 THEN
;        DO
;          Call CD_TO_CDS
;          DMAADD = IFSR_CONTINFO
;          Clear carry
;        ENDDO
;     ELSE DO   {error}
;            AX = error code
;            Set carry
;          ENDDO
;     ENDIF
;
; Outputs:
;       CARRY CLEAR
;           The 53 bytes ot DMAADD are filled in as follows:
;
;           Drive Byte (A=1, B=2, ...) High bit = 1   --|
;           11 byte search name with Meta chars in it   |  From
;           Search Attribute Byte, attribute of search  |  Server
;           WORD LastEnt value                          |
;           WORD DirStart ------------------------------|
;           DWORD Local CDS
;           32 bytes of the directory entry found
;       CARRY SET
;           AX = error code
;               error_no_more_files
;                       No match for this file
;               error_access_denied
;                       Device name given
;               error_path_not_found
;                       Bad path
; DS preserved, others destroyed
;
;************************************************************************************
        procedure   IFS_SEARCH_FIRST,NEAR
        ifsr_fcn_def  EXECAPI                   ; define ifsr for search
        ifsr_api_def  SEARCHFILE
        MOV     CS:IFSPROC_FLAGS,ZERO
        invoke  PREP_IFSR                       ; zero ifsr
ASSUME  DS:DOSGROUP
        LES     DI,[DMAADD]                     ; esdi -> dmaadd
        LDS     SI,[THISCDS]                    ; dssi -> cds

        invoke  DRIVE_FROM_CDS                  ; set ifsdrv (0-based)
        MOV     AL,CS:[IFSDRV]                  ; put 1-based drive # in dmaadd
        INC     AL
        OR      AL,80H                          ; turn on ifs indicator
        STOSB

        SaveReg <DS,SI>                         ; preserve ds:si -> cds
        MOV     CS:DEVICE_CB@_OFFSET,IFSR_DEVICE_CB@
        invoke  CDS_TO_CD                       ; CDS: sets [THISIFS]
                                                ;           ES:BX -> IFSRH
                                                ;           IFSR_DEVICE_CB@
                                                ;           ds - IFSSEG
        PUSH    DS                              ; save ds-ifsseg
        Context DS                              ; ds-dosgroup
        MOV     SI,[WFP_START]
        invoke  STRIP_WFP_START                 ; remove leading d:\ if present
        MOV     ES:WORD PTR[BX.IFSR_NAME@],SI
        MOV     ES:WORD PTR[BX.IFSR_NAME@+2],DS
        MOV     AL,[SATTRIB]
        XOR     AH,AH
        MOV     ES:[BX.IFSR_MATCHATTR],AX
        POP     DS
ASSUME  DS:IFSSEG,ES:IFSSEG
        MOV     AL,IFSSEARCH_FIRST
        JMP     SHORT SN_60                     ; rest of processing is in
                                                ; search_next routine
EndProc IFS_SEARCH_FIRST

BREAK <IFS_SEARCH_NEXT Search for next>
;************************************************************************************
; IFS_SEARCH_NEXT
; Inputs:
;       [DMAADD] Points to 53 byte buffer returned by DOS_SEARCH_FIRST
;           (only first 21 bytes must have valid information)
; Function:
;       Look for subsequent matches
; Outputs:
;       CARRY CLEAR
;           The 53 bytes at DMAADD are updated for next call
;               (see NET_SEARCH_FIRST)
;       CARRY SET
;           AX = error code
;               error_no_more_files
;                       No more files to find
; DS preserved, others destroyed
;************************************************************************************
        procedure   IFS_SEARCH_NEXT,NEAR
ASSUME  DS:DOSGROUP,ES:NOTHING
        ifsr_fcn_def  EXECAPI                   ; define ifsr for search
        ifsr_api_def  SEARCHFILE
        MOV     CS:IFSPROC_FLAGS,ZERO           ; clear processing flags
        invoke  PREP_IFSR                       ; zero out ifsr
SN_20:
        LDS     SI,[DMAADD]
        LODSB
        AND     AL,NOT 80H                      ; turn off ifs indicator
        DEC     AL                              ; make 0-based
        MOV     CS:[IFSDRV],AL                  ; set this for possible i24
        CallInstall GetCDSFromDrv,multDOS,23,AX,AX
ASSUME  DS:NOTHING
        JNC     SN_40
        MOV     AX,error_invalid_drive          ;   no cds, set error &
        invoke  SET_EXTERR_INFO
        JMP     FA_1000                         ; ret up in FA to preserve DS
SN_40:                                          ; (welcome lock)
        SaveReg <DS,SI>                         ; save cds ptr
        invoke  CDS_TO_CD                       ; CDS: sets [THISIFS]
                                                ;           ES:BX -> IFSRH
                                                ;           IFSR_DEVICE_CB@
                                                ;           ds - IFSSEG
        MOV     AL,IFSSEARCH_NEXT               ; start with subfunc=search next
;       TEST    IFSPROC_FLAGS,ISADD                                                      ;AD011;
;       JZ      SN_60                                                                    ;AD011;
;       INC     AL                              ; inc subfunc to search same             ;AD011;
SN_60:
        MOV     ES:[BX.IFSR_SUBFUNC],AL
        MOV     ES:[BX.IFSR_LENGTH],LENGTH_SEARCHFILE
        MOV     ES:[BX.IFSR_FUNCTION],IFSEXECAPI
        MOV     ES:[BX.IFSR_APIFUNC],IFSSEARCHFILE
        PUSH    DS
        Context DS
        MOV     AX,WORD PTR [DMAADD]
        INC     AX
        MOV     ES:WORD PTR[BX.IFSR_CONTINFO@],AX
        MOV     AX,WORD PTR [DMAADD+2]
        MOV     ES:WORD PTR[BX.IFSR_CONTINFO@+2],AX
        POP     DS
ASSUME  DS:IFSSEG
        invoke  CALL_IFS                        ; call FS
        RestoreReg <DI,ES>                      ; restore cds ptr into es:di
        JC      SN_1000
        invoke  CD_TO_CDS
        CLC
SN_1000:
        JMP     FA_1000                         ; go up & preserve ds, ret
EndProc IFS_SEARCH_NEXT
BREAK <OPEN_CHECK_DEVICE  - check that device to be opened is real>
;************************************************************************************
; CHECK_OPEN_DEVICE
; Inputs:
;       [WFP_START]
; Function:
; Outputs:
;************************************************************************************
        procedure   OPEN_CHECK_DEVICE,NEAR
ASSUME  DS:DOSGROUP,ES:NOTHING
        MOV     SI,[WFP_START]                  ; dssi -> path to open
;       invoke  PARSE_DEVICE_PATH               ; dssi -> device name (asciiz)
        PUSH    SS                              ; Now check if this device is real
        POP     ES
        MOV     DI,OFFSET DOSGROUP:NAME1
        MOV     CX,4
        REP     MOVSW                           ; Transfer name to NAME1
        MOV     AX,2020H
        STOSW
        STOSB
        PUSH    ES
        POP     DS
ASSUME  DS:DOSGROUP
        MOV     [ATTRIB],attr_hidden + attr_system + attr_directory
                                ; Must set this to something interesting
                                ; to call DEVNAME.
        CallInstall DEVNAME,multDOS,35
        JNC     OCD_120
        MOV     AX,error_file_not_found
        transfer ifs_980
OCD_120:
        transfer ifs_990
EndProc OPEN_CHECK_DEVICE
IFSSEG  ENDS
    END
