TITLE	EXTATTR- Extended Attributes
NAME	EXTATTR
;
; Get or Set Extended Attributes by handle
;
;
;   GetSetEA
;   Set_Output
;   Search_EA
;   Copy_QEA
;   Set_one_EA
;   Get_one_EA
;   Get_Value
;   GSetDevCdpg
;   Get_max_EA_size
;
.xlist
;
;
; get the appropriate segment definitions
;
include dosseg.asm

CODE	SEGMENT BYTE PUBLIC  'CODE'
	ASSUME	SS:DOSGROUP,CS:DOSGROUP

.xcref
INCLUDE DOSSYM.INC
INCLUDE DEVSYM.INC
include EA.inc
.cref
.list
.sall


;	I_need	XA_from,BYTE

;	I_need	XA_TABLE,BYTE
;	I_need	XA_TEMP,WORD
;	I_need	XA_COUNT,WORD
;	I_need	XA_DEVICE,BYTE
	I_need	XA_TYPE,BYTE
	I_need	SAVE_ES,WORD
	I_need	SAVE_DI,WORD
	I_need	SAVE_DS,WORD
	I_need	SAVE_SI,WORD
	I_need	SAVE_CX,WORD
	I_need	SAVE_BX,WORD
;	I_need	XA_handle,WORD
;	I_need	CPSWFLAG,BYTE
;	I_need	XA_PACKET,BYTE
;	I_need	MAX_EA_SIZE,WORD
;	I_need	MAX_EANAME_SIZE,WORD
;	I_need	THISSFT,DWORD
;IF DBCS
;	I_need	DBCS_PACKET,BYTE
;ENDIF
BREAK <GetSet_EA get or set extended attributes by handle>
;      Input: [XA_type] = function code, (e.g., get,set)
;	      [ThisSFT] points to SFT
;	      ES:BP points to drive parameter block
;	      [XA_from] = By_Create or By_EA
;	      [SAVE_ES]:[SAVE_DI]  points to get/set list
;	      [SAVE_DS]:[SAVE_SI]  points to get query list
;	      [SAVE_CX] = size of buffer
;	      [XA_device]= 1 device, 0 file
;	      [XA_handle] for device
;	Function: Get or Set extended attributes by handle
;	Output: carry set: error
;		carry clear: extended attributes are successfully get/set
;			     extended attribute cluster may be created
procedure   GetSet_XA,near
	ASSUME	CS:DOSGROUP,DS:NOTHING,ES:NOTHING,SS:DOSGROUP


	LES    DI,DWORD PTR [SAVE_DI]  ;AN000;;FT. ES:DI -> query list
;;	MOV    [SAVE_BX],2	       ;AN000;;FT. size returned
;;	XOR    DX,DX		       ;AN000;;FT. dx=0, codepage id

	CMP    [XA_type],2	       ;AN000;;FT. get EA  ?
	JNZ    eaname		       ;AN000;;FT. no
getEAs:
	CMP    [SAVE_CX],0	       ;AN000;;FT. get max data size
	JNZ    notmax		       ;AN000;;FT. no
;;	CALL   Get_max_EA_size	       ;AN000;;FT.

	MOV    CX,2		       ;AN000;;FT. FAKE FAKE..............
	JNC    set_user_cx	       ;AN000;;FT.
	JMP    OKexit		       ;AN000;;FT. error
notmax:
	CMP    [SAVE_CX],1	       ;AN000;;FT. buffer size =1   ?
	JNZ    goodsiz		       ;AN000;;FT. no
errout:
	JMP    insuff_space	       ;AN000;;FT. no error
goodsiz:
	MOV    WORD PTR ES:[DI],0      ;AN000;FT. FAKE FAKE ...............
	MOV    CX,2		       ;AN000;FT. FAKE FAKE ...............
	JMP    set_user_cx	       ;AN000;FT. FAKE FAKE ...............

eaname:
	CMP    [XA_type],3	       ;AN000;;FT. get EA name?`
	JZ     geteaname	       ;AN000;;FT. yes
	JMP    setea		       ;AN000;;FT.
geteaname:
;	MOV    [SAVE_SI],-1	       ;AN000;;FT. make get all
	CMP    [SAVE_CX],0	       ;AN000;;FT. get max data size
	JNZ    notmax		       ;AN000;;FT. no
	MOV    CX,2		       ;AN000;;FT. FAKE FAKE ......................
;;	MOV    CX,[MAX_EANAME_SIZE]    ;AN000;;FT. get name size
set_user_cx:
	invoke get_user_stack	       ;AN000;;FT. get user stack
	MOV    [SI.user_CX],CX	       ;AN000;;FT.
	JMP    OKexit		       ;AN000;;FT. exit

getsome:
setea:
	JMP    OKexit		       ;AN000;;FT. FAKE FAKE ..........
 insuff_space:			       ;AN000;;FT.
;	MOV    AX,error_not_enough_memory	 ;AN000;FT. insufficient memory err
;	STC
OKexit:
	return

EndProc GetSet_XA


; Input: [SAVE_ES]:[SAVE_DI] points to buffer
;	 [SAVE_BX]= returned size
;	 DX= returned count
; Function: set returned size and count
; Output: none
;procedure   Set_Output,NEAR
;	ASSUME	CS:DOSGROUP,DS:NOTHING,ES:NOTHING,SS:DOSGROUP
;	LES    DI,DWORD PTR [SAVE_DI]  ;FT. es:di -> count
;	MOV    ES:[DI],DX	       ;FT.
;	MOV    BX,[SAVE_BX]	       ;FT. cx=size returned
;	invoke get_user_stack	       ;FT. get user stack
;	MOV    [SI.user_CX],BX	       ;FT.
;	return			       ;FT.
;EndProc Set_Output


; Input: DS:SI= query EA addr
; Function: search the EA
; Output: carry clear
;	 DX= EA ID (0 codpage, 1  Filetype, etc.)
;	 ES:DI points to found entry
;	  carry set, not found, AL= reason code
;procedure   Search_EA,NEAR
;	ASSUME	CS:DOSGROUP,DS:NOTHING,ES:NOTHING,SS:DOSGROUP
;	PUSH   CX				 ;FT. save entry count
;	MOV    AL,EARCNOTFOUND			 ;FT. preset error code
;	MOV    BL,[SI.QEA_NAMELEN]		 ;FT.	     ?
;	CMP    [XA_TYPE],4			 ;FT. set    ?
;	JNZ    gettyp				 ;FT. no
;	MOV    BL,[SI.EA_NAMELEN]		 ;FT.	     ?
;gettyp:
;	OR     BL,BL				 ;FT.
;	JZ     not_found			 ;FT.
;	PUSH   CS				 ;FT. ds:si-> EA entry addr
;	POP    ES				 ;FT.
;	MOV    DI,OFFSET DOSGROUP:XA_TABLE	 ;FT.
;	MOV    CX,XA_COUNT			 ;FT. cx= number of EA entries
;	XOR    DX,DX				 ;FT. dx=0, codepage id
;
;start_find:
;	PUSH   CX				 ;FT. save entry count
;	MOV    CL,BL				 ;FT.
;	XOR    CH,CH				 ;FT. get name len
;	PUSH   SI				 ;FT.
;	PUSH   DI				 ;FT.
;	CMP    [XA_TYPE],4			 ;FT. set    ?
;	JNZ    gettyp2				 ;FT. no
;	ADD    SI,EA_NAME			 ;FT.
;	JMP    short updi			 ;FT.
;gettyp2:
;	ADD    SI,QEA_NAME			 ;FT. compare EA names
;updi:
;	ADD    DI,EA_NAME			 ;FT.
;	REP    CMPSB				 ;FT.
;	POP    DI				 ;FT.
;	POP    SI				 ;FT.
;	POP    CX				 ;FT.
;	JNZ    not_matched			 ;FT. name not matched
;	MOV    AL,EARCDEFBAD			 ;FT. preset error code
;	PUSH   SI				 ;FT.
;	PUSH   DI				 ;FT.
;	CMPSB					 ;FT. compare type
;	JNZ    not_matched2			 ;FT. type not matched
;	CMPSW					 ;FT. compare flags
;	JNZ    not_matched2			 ;FT. flag not matched
;	POP    DI				 ;FT.
;	POP    SI				 ;FT. found one
;	JMP    SHORT found_one			 ;FT.
;not_matched:
;	DEC    CX				 ;FT. end of table
;	JZ     not_found			 ;FT. yes
;	MOV    AL,ES:[DI.EA_NAMELEN]		 ;FT.
;	XOR    AH,AH				 ;FT.
;
;	ADD    DI,EA_NAME			 ;FT.
;	ADD    DI,AX				 ;FT. es:di -> next EA entry
;	INC    DX				 ;FT. increment EA ID
;	JMP    start_find			 ;FT.
;not_matched2:
;	POP    DI				 ;FT.
;	POP    SI				 ;FT.
;	JMP    not_matched			 ;FT.
;not_found:
;	STC					 ;FT.
;found_one:
;	POP    CX				 ;FT.
;	return					 ;FT.
;EndProc Search_EA
; Input: ES:DI= buffer address
;	 DS:SI= EA entry address
;	 [SAVE_CX]= buffer size
;	 AL = reason code
; Function: move one query entry to buffer
; Output: carry clear
;	    DS:SI points to next entry
;	    ES:DI points to next entry
;	    [SAVE_CX],[SAVE_BX], updated
;	  carry set, insufficient memory error
;procedure   COPY_QEA,NEAR
;	ASSUME	CS:DOSGROUP,DS:NOTHING,ES:NOTHING,SS:DOSGROUP
;	PUSH   CX				 ;FT.
;	MOV    DL,AL				 ;FT.
;	MOV    CX,EA_NAME -EA_TYPE		 ;FT.
;
;	MOV    BL,[SI.QEA_NAMELEN]		 ;FT.
;	XOR    BH,BH				 ;FT.
;	ADD    CX,BX				 ;FT. cx= query EA size
;	CMP    CX,[SAVE_CX]			 ;FT. > buffer size
;	JA     sizeshort2			 ;FT. yes
;	PUSH   CX				 ;FT.
;	LODSB					 ;FT. move type
;	STOSB					 ;FT.
;	LODSW					 ;FT.
;	STOSW					 ;FT. move flag
;	MOV    AL,DL				 ;FT. move RC
;	STOSB					 ;FT.
;
;	LODSB					 ;FT. move name len
;	MOV    CL,AL				 ;FT.
;	STOSB					 ;FT.
;	XOR    AX,AX				 ;FT. zero value length
;	STOSW					 ;FT.
;	OR     CL,CL				 ;FT.
;	JZ     zeroname 			 ;FT.
;	XOR    CH,CH				 ;FT.
;
;	REP    MOVSB				 ;FT. move EA to buffer
;zeroname:
;	POP    CX				 ;FT.
;	ADD    [SAVE_BX],CX			 ;FT. bx=bx+entry size
;	SUB    [SAVE_CX],CX			 ;FT. update buffer size
;	CLC					 ;FT.
;	JMP    SHORT okget2			 ;FT.
;
;sizeshort2:
;	MOV    AX,error_not_enough_memory	 ;FT.  error
;	STC					 ;FT.
;okget2:
;	POP    CX				 ;FT.
;	return				    ;FT.
;EndProc COPY_QEA
; Input: ES:DI= found EA entry addr
;	 DS:SI= source EA entry address
;	 DX= EA ID (0 codpage, 1  Filetype, etc.)
; Function: set one EA
; Output: carry clear
;	    EA set
;	  carry set, AL= reason code
;procedure   SET_ONE_EA,NEAR
;	ASSUME	CS:DOSGROUP,DS:NOTHING,ES:NOTHING,SS:DOSGROUP
;	PUSH   CX				 ;FT.
;	MOV    AL,EARCDEFBAD			 ;FT.  prseet error code
;	MOV    BX,[SI.EA_VALLEN]		 ;FT.
;	CMP    BX,ES:[DI.EA_VALLEN]		 ;FT.  length equal ?
;	JNZ    notset				 ;FT.  no
;	PUSH   DS				 ;FT.
;	PUSH   SI				 ;FT.
;	MOV    AL,[SI.EA_NAMELEN]		 ;FT.
;	XOR    AH,AH				 ;FT.
;	ADD    SI,EA_NAME			 ;FT.
;	ADD    SI,AX				 ;FT.
;	CMP    DX,0				 ;FT.
;	JNZ    set_filetyp			 ;FT.
;	LODSW					 ;FT.
;	CMP    [XA_DEVICE],0			 ;FT. device ?
;	JZ     notdevice			 ;FT. no
;	OR     AX,AX				 ;FT. code page 0 ?
;	JZ     NORM0				 ;FT. yes
;
;	CALL   GSetDevCdPg			 ;FT.
;	JNC    welldone 			 ;FT.
;	CMP    [CPSWFLAG],0			 ;FT. code page matching on
;	JZ     NORM0				 ;FT. no
;	invoke SAVE_WORLD			 ;FT. save all regs
;	LDS    SI,[THISSFT]			 ;FT. ds:si -> sft
;	LDS    SI,[SI.sf_devptr]		 ;FT. ds:si -> device header
;	MOV    BP,DS				 ;FT. save all regs
;	invoke Code_Page_Mismatched_Error	 ;FT.
;	CMP    AL,0				 ;FT. ignore ?
;	JZ     NORM1				 ;FT.
;	invoke RESTORE_WORLD			 ;FT. save all regs
;NORM0:
;	MOV    AL,EARCDEVERROR			 ;FT.
;	STC					 ;FT.
;	JMP    SHORT sdone			 ;FT.
;NORM1:
;	invoke RESTORE_WORLD			 ;FT. save all regs
;	JMP    SHORT welldone			 ;FT.
;notdevice:
;	LDS    SI,[THISSFT]			 ;FT.
;	MOV    [SI.sf_CodePage],AX		 ;FT. set codepege
;	JMP    SHORT welldone			 ;FT.
;set_filetyp:
;	LODSB					 ;FT.
;	LDS    SI,[THISSFT]			 ;FT. set filtype
;	MOV    [SI.sf_ATTR_HI],AL		 ;FT.
;
;welldone:
;	XOR    AL,AL				 ;FT.  success
;sdone:
;	POP    SI				 ;FT.
;	POP    DS				 ;FT.
;notset:
;	POP    CX				 ;FT.
;	 return 				  ;FT.
;EndProc SET_ONE_EA
; Input: ES:DI= buffer address
;	 DS:SI= EA entry address
;	 [SAVE_CX]= buffer size available
;	 [SAVE_BX]= size returned
;	 DX= EA ID (0 codpage, 1  Filetype, etc.)
; Function: move one EA entry to the buffer
; Output: carry clear
;	    DS:SI points to next entry
;	    ES:DI points to next entry
;	    [SAVE_CX],BX, updated
;	  carry set, insufficient memory error
;procedure   GET_ONE_EA,NEAR
;	ASSUME	CS:DOSGROUP,DS:NOTHING,ES:NOTHING,SS:DOSGROUP
;	PUSH   CX				 ;FT.
;	CMP    [XA_TYPE],2			 ;FT. type 2 ?
;	JZ     gtyp2				 ;FT. yes
;	MOV    CX,QEA_NAME - QEA_TYPE		 ;FT.
;	JMP    SHORT addnmlen			 ;FT.
;gtyp2:
;	MOV    CX,EA_NAME - EA_TYPE		 ;FT. cx = EA entry size
;	ADD    CX,[SI.EA_VALLEN]		 ;FT.
;addnmlen:
;	MOV    AL,[SI.EA_NAMELEN]		 ;FT.
;	XOR    AH,AH				 ;FT.
;	ADD    CX,AX				 ;FT.
;	CMP    CX,[SAVE_CX]			 ;FT. > buffer size
;	JA     sizeshort			 ;FT. yes
;	PUSH   CX				 ;FT.
;	LODSB					 ;FT. move type
;	STOSB					 ;FT.
;	LODSW					 ;FT.
;	STOSW					 ;FT. move flag
;	LODSB					 ;FT. EA list need RC
;	CMP    [XA_TYPE],2			 ;FT.
;	JNZ    norc				 ;FT.
;	STOSB					 ;FT.
;norc:
;	LODSB					 ;FT. move name len
;	STOSB					 ;FT.
;	MOV    CL,AL				 ;FT.
;	XOR    CH,CH				 ;FT.
;	LODSW					 ;FT. EA list need value len
;	CMP    [XA_TYPE],2			 ;FT.
;	JNZ    novalen				 ;FT.
;	STOSW					 ;FT.
;novalen:
;
;	REP    MOVSB				 ;FT. move EA to buffer
;	CMP    [XA_TYPE],2			 ;FT.
;	JNZ    novalue				 ;FT.
;	CALL   GET_VALUE			 ;FT. get value for type 2
;novalue:
;	POP    CX				 ;FT.
;	ADD    [SAVE_BX],CX			 ;FT. add entry size
;	LES    DI,DWORD PTR [SAVE_DI]		 ;FT.
;	ADD    DI,[SAVE_BX]			 ;FT. es:di -> next entry
;	SUB    [SAVE_CX],CX			 ;FT. update buffer size
;	CLC					 ;FT.
;	JMP    SHORT okget			 ;FT.
;
;sizeshort:
;	MOV    AX,error_not_enough_memory	 ;FT.  error
;	STC					 ;FT.
;okget:
;	POP    CX				 ;FT.
;	return				    ;FT.
;EndProc GET_ONE_EA
; Input: DX= EA ID (0 codpage, 1 Filetype, etc.)
;	 [THISSFT]= points to SFT
;	 ES:DI= buffer address of EA value
;	 [XA_DEVICE]=0 file, 1 device
; Function: get attribute
; Output: none
;procedure   GET_VALUE,NEAR
;	ASSUME	CS:DOSGROUP,DS:NOTHING,ES:NOTHING,SS:DOSGROUP
;	PUSH   DS			     ;FT. save ds:si
;	PUSH   SI			     ;FT.
;	LDS    SI,[ThisSFT]		     ;FT. ds:si -> SFT
;
;	CMP    DX,0			     ;FT. code page ?
;	JNZ    eafiltyp 		     ;FT. no
;	CMP    [XA_DEVICE],0		     ;FT. device ?
;	JZ     notdev			     ;FT. no
;	CALL   GSetDevCdPg		     ;FT. do ioctl invoke
;	JNC    okcdpg			     ;FT. error ?
;	PUSH   DI			     ;FT.
;	XOR    AX,AX			     ;FT. make code page 0
;	LES    DI,DWORD PTR [SAVE_DI]	     ;FT.
;	ADD    DI,[SAVE_BX]		     ;FT. es:di -> beginning of entry
;	MOV    ES:[DI.EA_RC],EARCNOTFOUND    ;FT.
;	POP    DI			     ;FT.
;	JMP    SHORT okcdpg		     ;FT.
;notdev:
;	MOV    AX,[SI.sf_CodePage]	     ;FT. get code page from  sft
;okcdpg:
;	STOSW				     ;FT. put in buffer
;	JMP    SHORT gotea		     ;FT.
;eafiltyp:
;	MOV    AL,[SI.sf_ATTR_HI]	     ;FT. get high attribute
;	STOSB				     ;FT. put in buffer
;
;gotea:
;	POP    SI			     ;FT. retore regs
;	POP    DS			     ;FT.
;	return				     ;FT.
;EndProc GET_VALUE
; Input:    [XA_handle] = device handle
;	    [XA_type] = 4 , set
;	    AX= code page (set)
;			2,3 get
; Function: get or set device code page
; Output:   carry clear, AX= device code page (get)
;	    carry set, error
;procedure   GSetDevCdPg,near
;	ASSUME	CS:DOSGROUP,DS:NOTHING,ES:NOTHING,SS:DOSGROUP
;	invoke SAVE_WORLD	       ;FT. save all regs
;	CMP    [XA_type],4	       ;FT. set ?
;	JZ     setpg		       ;FT. yes
;	MOV    CX,6AH		       ;FT. get selected code page
;	JMP    SHORT dogset	       ;FT.
;setpg:
;	MOV    CX,4AH		       ;FT. set code page
;IF  DBCS
;
;	invoke Save_World	       ;FT. save all regs
;	MOV    BX,AX		       ;FT. bx= code page id
;	MOV    AL,7		       ;FT. get DBCS vectors
;	MOV    DX,-1		       ;FT. get current country
;	MOV    CX,5		       ;FT. minimum size
;	MOV    DI,OFFSET DOSGROUP:DBCS_PACKET	;FT.
;	PUSH   CS		       ;FT.
;	POP    ES		       ;FT.
;	invoke $GetExtCntry	       ;FT. get DBCS vectors
;	JC     nlsfunc_err	       ;FT. error
;	LDS    SI,DWORD PTR DBCS_PACKET+1     ;FT.
;	LODSW				      ;FT. get vector length
;	MOV    CX,AX			      ;FT. cx=length
;
;	MOV    DI,OFFSET DOSGROUP:XA_PACKET+4	;FT.
;	PUSH   CS		       ;FT.
;	POP    ES		       ;FT.
;	REP    MOVSB			      ;FT.
;	CLC				      ;FT.
;nlsfunc_err:
;	invoke RESTORE_WORLD	       ;FT. restore all regs
;	JC     deverr		       ;FT.
;
;ENDIF
;	MOV    WORD PTR [XA_PACKET+2],AX  ;FT.
;dogset:
;	MOV    BX,[XA_handle]	       ;FT. set up handle
;	PUSH   CS		       ;FT. ds:dx -> packet
;	POP    DS		       ;FT.
;	MOV    DX,OFFSET DOSGROUP:XA_PACKET  ;FT.
;	MOV    AX,440CH 	       ;FT. IOCTL to char device by handle
;	invoke $IOCTL			     ;FT. issue get code page
;	JC     deverr			     ;FT. error
;	invoke RESTORE_WORLD		     ;FT. restore all regs
;	MOV    AX,WORD PTR [XA_PACKET+2]     ;FT. get code page
;	return				     ;FT.
;deverr:
;	invoke RESTORE_WORLD		     ;FT. restore all regs
;	return				     ;FT. exit
;EndProc GSetDevCdPg

; Input:    DS:SI -> query list
;
; Function: get max size
; Output:   CX= size
;	    carry set error
;procedure   Get_max_EA_size,NEAR
;	ASSUME	CS:DOSGROUP,DS:NOTHING,ES:NOTHING,SS:DOSGROUP
;	CMP    [SAVE_SI],0FFFFH 	     ;FT. get all ?
;	JNZ    scan_query		     ;FT. no
;	MOV    CX,[MAX_EA_SIZE] 	     ;FT. get max EA size
;	JMP    SHORT gotit		     ;FT.
;scan_query:
;	LDS    SI,DWORD PTR [SAVE_SI]	     ;FT. ds:si -> query list
;	LODSW				     ;FT. ax= number of entries
;	MOV    [SAVE_CX],AX		     ;FT.
;	XOR    CX,CX			     ;FT. set initial size to 0
;	OR     AX,AX			     ;FT. if no entris
;	JZ     gotit			     ;FT.    then return
;	MOV    CX,2			     ;FT. at lesat 2
;NEXT_QEA:
;	CALL   Search_EA		     ;FT. search EA
;	JC     serror			     ;FT. wrong EA
;	ADD    CX,size EA		     ;FT. get EA size
;	ADD    CL,ES:[DI.EA_NAMELEN]	     ;FT.
;	ADC    CH,0			     ;FT.
;	ADD    CX,ES:[DI.EA_VALLEN]	     ;FT.
;	DEC    CX			     ;FT.
;	DEC    [SAVE_CX]		     ;FT. end of entris
;	JZ     gotit			     ;FT. no
;	MOV    AL,[SI.QEA_NAMELEN]	     ;FT. update to next QEA
;	XOR    AH,AH			     ;FT. update to next QEA
;	ADD    SI,AX			     ;FT. update to next QEA
;	ADD    SI,size QEA		     ;FT.
;	DEC    SI			     ;FT.
;	JMP    next_QEA 		     ;FT. do next
;serror:
;	MOV    AX,error_invalid_data	     ;FT. set initial size to 0
;gotit: 				      ;FT.
;	return				     ;FT. exit				;AN000;;FT. exit
;
;EndProc Get_max_EA_size		      ;FT. exit
CODE	ENDS
END
