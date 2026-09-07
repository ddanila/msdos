 page 80,132
TITLE	COMMAND Transient Initialized DATA

fmt macro   name,string,args
	local	a
a	db  string
PUBLIC	name
name	dw  offset trangroup:a
irp val,<args>
	dw  offset trangroup:val
endm
endm

btab	macro	b,sym
    db	b
    dw	    offset trangroup:sym
    endm

BREAK	MACRO	subtitle
	SUBTTL	subtitle
	PAGE
ENDM

.xlist
.xcref
	INCLUDE comsw.asm
	INCLUDE comseg.asm
	INCLUDE EA.inc
	INCLUDE dirent.inc
.list
.cref

;
; WARNING: DO NOT INCLUDE DOSSYM.INC BECAUSE IT DESTROYS THE MACRO 'FMT' THAT
; has been defined above - RS.
;
	INCLUDE CURDIR.INC
	INCLUDE ERROR.INC
	INCLUDE ifequ.asm
	INCLUDE comequ.asm

TRANSPACE	SEGMENT PUBLIC BYTE
	EXTRN	arg_buf:BYTE
	EXTRN	bwdbuf:byte
	EXTRN	bytes_free:WORD
	EXTRN	charbuf:byte
	EXTRN	copy_Num:WORD
	EXTRN	cpyflag:BYTE
	EXTRN	DATE_OUTPUT:BYTE
	EXTRN	Dir_Num:WORD
	EXTRN	DRIVE_OUTPUT:BYTE
	EXTRN	file_size_high:WORD
	EXTRN	file_size_low:WORD
	EXTRN	major_ver_num:WORD
	EXTRN	minor_ver_num:WORD
	EXTRN	one_char_val:BYTE
	EXTRN	PARSE1_OUTPUT:BYTE
	EXTRN	srcbuf:byte
	EXTRN	string_ptr_2:WORD
	EXTRN	system_cpage:word
	EXTRN	TIME_OUTPUT:BYTE
	EXTRN	vol_drv:BYTE
	EXTRN	vol_serial:dword
TRANSPACE	ENDS

TRANCODE	SEGMENT PUBLIC BYTE
	EXTRN	$CALL:NEAR
	EXTRN	$CHDIR:NEAR
	EXTRN	$EXIT:NEAR
	EXTRN	$FOR:NEAR
	EXTRN	$IF:NEAR
	EXTRN	$MKDIR:NEAR
	EXTRN	$RMDIR:NEAR
	EXTRN	ADD_NAME_TO_ENVIRONMENT:NEAR
	EXTRN	ADD_PROMPT:NEAR
	EXTRN	build_dir_for_prompt:near
	EXTRN	CATALOG:NEAR
	EXTRN	CHCP:NEAR
	EXTRN	CLS:NEAR
	EXTRN	CNTRLC:NEAR
	EXTRN	COPY:NEAR
	EXTRN	CRENAME:NEAR
	EXTRN	CRLF2:NEAR
	EXTRN	CTIME:NEAR
	EXTRN	CTTY:NEAR
	EXTRN	DATE:NEAR
	EXTRN	ECHO:NEAR
	EXTRN	ERASE:NEAR
	EXTRN	GOTO:NEAR
	EXTRN	IFERLEV:NEAR
	EXTRN	IFEXISTS:NEAR
	EXTRN	IFNOT:NEAR
	EXTRN	LOADHIGH:NEAR
	EXTRN	PATH:NEAR
	EXTRN	PAUSE:NEAR
	EXTRN	PRINT_B:NEAR
	EXTRN	PRINT_BACK:NEAR
	EXTRN	PRINT_DATE:NEAR
	EXTRN	PRINT_CHAR:NEAR
	EXTRN	PRINT_DRIVE:NEAR
	EXTRN	PRINT_EQ:NEAR
	EXTRN	PRINT_ESC:NEAR
	EXTRN	PRINT_G:NEAR
	EXTRN	PRINT_L:NEAR
	EXTRN	PRINT_TIME:NEAR
	EXTRN	PRINT_VERSION:NEAR
	EXTRN	SHIFT:NEAR
	EXTRN	TCOMMAND:NEAR
	EXTRN	REM_HANDLER:NEAR
	EXTRN	TRUENAME:NEAR
	EXTRN	TYPEFIL:NEAR
	EXTRN	VERSION:NEAR
	EXTRN	VOLUME:NEAR
	EXTRN	VERIFY:NEAR
;
; WARNING!!! No code may appear after this label!!!!
;
PUBLIC	TranCodeLast
TranCodeLast	LABEL	BYTE
TRANCODE	ENDS

; Data for transient portion

TRANDATA	SEGMENT PUBLIC BYTE

	PUBLIC	accden_ptr
	PUBLIC	acrlf_ptr
	PUBLIC	arg_buf_ptr
	PUBLIC	badbat_ptr
	PUBLIC	badcd_ptr
	PUBLIC	badCPmes_ptr
	PUBLIC	badcurdrv
	PUBLIC	baddat_ptr
	PUBLIC	baddev_ptr
	PUBLIC	baddrv_ptr
	PUBLIC	badlab_ptr
	PUBLIC	badmkd_ptr
	PUBLIC	badnam_ptr
	PUBLIC	bad_on_off_ptr
	PUBLIC	badPmes_ptr
	PUBLIC	badrmd_ptr
	PUBLIC	badtim_ptr
	PUBLIC	batext
	PUBLIC	bytmes_ptr
	PUBLIC	CLSSTRING
	PUBLIC	comext
	PUBLIC	COMSPECSTR
	PUBLIC	COMTAB
	PUBLIC	copied_ptr
	PUBLIC	cp_active_ptr
	PUBLIC	cp_not_all_ptr
	PUBLIC	cp_not_set_ptr
	PUBLIC	ctrlcmes_ptr
	PUBLIC	curdat_mo_day
	PUBLIC	curdat_ptr
	PUBLIC	curdat_yr
	PUBLIC	curtim_hr_min
	PUBLIC	curtim_ptr
	PUBLIC	curtim_sec_hn
	PUBLIC	dback_ptr
	PUBLIC	del_Y_N_ptr
	PUBLIC	devwmes_ptr
	PUBLIC	dirdattim_ptr
	PUBLIC	dirdat_mo_day
	PUBLIC	dirdat_yr
	PUBLIC	dirhead_ptr
	PUBLIC	dirmes_ptr
	PUBLIC	dirtim_hr_min
	PUBLIC	dirtim_sec_hn
	PUBLIC	disp_file_size_ptr
	PUBLIC	dmes_ptr
	PUBLIC	echomes_ptr
	PUBLIC	enverr_ptr
	PUBLIC	eurdat_ptr
	PUBLIC	exeext
	PUBLIC	extend_buf_off
	PUBLIC	extend_buf_ptr
	PUBLIC	extend_buf_seg
	PUBLIC	extend_buf_sub
	PUBLIC	file_name_ptr
	PUBLIC	FILE_OPTIONAL2
	PUBLIC	fornestmes_ptr
	PUBLIC	fuldir_ptr
	PUBLIC	IFTAB
	PUBLIC	inBdev_ptr
	PUBLIC	inornot_ptr
	PUBLIC	Inv_code_page
	PUBLIC	inval_path_ptr
	PUBLIC	japdat_ptr
	PUBLIC	Losterr_ptr
	PUBLIC	md_exists_ptr
	PUBLIC	msg_cont_flag
	PUBLIC	msg_disp_class
	PUBLIC	needbat_ptr
	PUBLIC	newdat_format
	PUBLIC	newdat_ptr
	PUBLIC	newtim_ptr
	PUBLIC	NLSFUNC_ptr
	PUBLIC	nospace_ptr
	PUBLIC	no_values
	PUBLIC	nulpath_ptr
	PUBLIC	offmes_ptr
	PUBLIC	onmes_ptr
	PUBLIC	overwr_ptr
	PUBLIC	PARSE_BREAK
	PUBLIC	PARSE_CHCP
	PUBLIC	PARSE_CHDIR
	PUBLIC	PARSE_CTTY
	PUBLIC	PARSE_DATE
	PUBLIC	PARSE_ERASE
	PUBLIC	PARSE_MRDIR
	PUBLIC	PARSE_RENAME
	PUBLIC	PARSE_TIME
	PUBLIC	PARSE_VOL
	PUBLIC	PATH_TEXT
	PUBLIC	pausemes_ptr
	PUBLIC	pipeEmes_ptr
	PUBLIC	promptdat_moday
	PUBLIC	promptdat_ptr
	PUBLIC	promptdat_yr
	PUBLIC	PROMPT_TABLE
	PUBLIC	PROMPT_TEXT
	PUBLIC	promtim_hr_min
	PUBLIC	promtim_ptr
	PUBLIC	promtim_sec_hn
	PUBLIC	renerr_ptr
	PUBLIC	SLASH_P_SYN
	PUBLIC	SLASH_P_SWITCH
	PUBLIC	string_buf_ptr
	PUBLIC	suremes_ptr
	PUBLIC	switch_list
	PUBLIC	syntmes_ptr
	PUBLIC	tab_ptr
	PUBLIC	TRANDATAEND
	PUBLIC	usadat_ptr
	PUBLIC	verimes_ptr
	PUBLIC	vermes_ptr
	PUBLIC	volmes_ptr
	PUBLIC	volmes_ptr_2
	PUBLIC	volsermes_ptr
	PUBLIC	WEEKTAB
	PUBLIC	xa_cp

INCLUDE tranmsg.asm

CLSSTRING DB	4,01BH,"[2J"            ; ANSI Clear screen

PROMPT_TABLE LABEL BYTE
	btab	"B",Print_B
	btab	"D",PRINT_DATE
	btab	"E",PRINT_ESC
	btab	"G",PRINT_G
	btab	"H",PRINT_BACK
	btab	"L",PRINT_L
	btab	"N",PRINT_DRIVE
	btab	"P",build_dir_for_prompt
	btab	"Q",PRINT_EQ
	btab	"T",PRINT_TIME
	btab	"V",PRINT_VERSION
	btab	"_",CRLF2
	btab	"$",PRINT_CHAR
	DB	0				; NUL TERMINATED

IFTAB	LABEL	BYTE				; Table of IF conditionals
	DB	3,"NOT"                         ; First byte is count
	DW	OFFSET TRANGROUP:IFNOT
	DB	10,"ERRORLEVEL"
	DW	OFFSET TRANGROUP:IFERLEV
	DB	5,"EXIST"
	DW	OFFSET TRANGROUP:IFEXISTS
	DB	0

; Table for internal command names
COMTAB	DB	3,"DIR",fSwitchAllowed+fCheckDrive
	DW	OFFSET TRANGROUP:CATALOG	; In TCMD1.ASM
	DB	8,"LOADHIGH",fSwitchAllowed
	DW	OFFSET TRANGROUP:LOADHIGH
	DB	2,"LH",fSwitchAllowed
	DW	OFFSET TRANGROUP:LOADHIGH
	DB	4,"CALL",fSwitchAllowed
	DW	OFFSET TRANGROUP:$CALL		; In TBATCH2.ASM
	DB	4,"CHCP",fSwitchAllowed
	DW	OFFSET TRANGROUP:CHCP		; In TCMD2B.ASM
	DB	6,"RENAME",fSwitchAllowed+fCheckDrive  ;AC018; P3903
	DW	OFFSET TRANGROUP:CRENAME	; In TCMD1.ASM
	DB	3,"REN",fSwitchAllowed+fCheckDrive     ;AC018; P3903
	DW	OFFSET TRANGROUP:CRENAME	; In TCMD1.ASM
	DB	5,"ERASE",fSwitchAllowed+fCheckDrive
	DW	OFFSET TRANGROUP:ERASE		; In TCMD1.ASM
	DB	3,"DEL",fSwitchAllowed+fCheckDrive
	DW	OFFSET TRANGROUP:ERASE		; In TCMD1.ASM
	DB	4,"TYPE",fSwitchAllowed+fCheckDrive  ;AC018; P3903
	DW	OFFSET TRANGROUP:TYPEFIL	; In TCMD1.ASM
	DB	3,"REM",fSwitchAllowed
	DW	OFFSET TRANGROUP:REM_HANDLER	; In TCODE.ASM
	DB	4,"COPY",fSwitchAllowed+fCheckDrive
	DW	OFFSET TRANGROUP:COPY		; In COPY.ASM
	DB	5,"PAUSE",fSwitchAllowed
	DW	OFFSET TRANGROUP:PAUSE		; In TCMD1.ASM
	DB	4,"DATE",fSwitchAllowed
	DW	OFFSET TRANGROUP:DATE		; In TPIPE.ASM
	DB	4,"TIME",fSwitchAllowed         ;AC018; P3903
	DW	OFFSET TRANGROUP:CTIME		; In TPIPE.ASM
	DB	3,"VER",fSwitchAllowed		;AN100; allow /? switch
	DW	OFFSET TRANGROUP:VERSION	; In TCMD2.ASM
	DB	3,"VOL",fSwitchAllowed+fCheckDrive   ;AC018; P3903
	DW	OFFSET TRANGROUP:VOLUME 	; In TCMD1.ASM
	DB	2,"CD",fSwitchAllowed+fCheckDrive    ;AC018; P3903
	DW	OFFSET TRANGROUP:$CHDIR 	; In TENV.ASM
	DB	5,"CHDIR",fSwitchAllowed+fCheckDrive ;AC018; P3903
	DW	OFFSET TRANGROUP:$CHDIR 	; In TENV.ASM
	DB	2,"MD",fSwitchAllowed+fCheckDrive    ;AC018; P3903
	DW	OFFSET TRANGROUP:$MKDIR 	; In TENV.ASM
	DB	5,"MKDIR",fSwitchAllowed+fCheckDrive ;AC018; P3903
	DW	OFFSET TRANGROUP:$MKDIR 	; In TENV.ASM
	DB	2,"RD",fSwitchAllowed+fCheckDrive    ;AC018; P3903
	DW	OFFSET TRANGROUP:$RMDIR 	; In TENV.ASM
	DB	5,"RMDIR",fSwitchAllowed+fCheckDrive ;AC018; P3903
	DW	OFFSET TRANGROUP:$RMDIR 	; In TENV.ASM
	DB	5,"BREAK",fSwitchAllowed        ;AC018; P3903
	DW	OFFSET TRANGROUP:CNTRLC 	; In TUCODE.ASM
	DB	6,"VERIFY",fSwitchAllowed       ;AC018; P3903
	DW	OFFSET TRANGROUP:VERIFY 	; In TUCODE.ASM
	DB	3,"SET",fSwitchAllowed
	DW	OFFSET TRANGROUP:ADD_NAME_TO_ENVIRONMENT; In TENV.ASM
	DB	6,"PROMPT",fSwitchAllowed
	DW	OFFSET TRANGROUP:ADD_PROMPT	; In TENV.ASM
	DB	4,"PATH",fSwitchAllowed
	DW	OFFSET TRANGROUP:PATH		; In TCMD2.ASM
	DB	4,"EXIT",fSwitchAllowed
	DW	OFFSET TRANGROUP:$EXIT		; In TCMD2.ASM
	DB	4,"CTTY",fCheckDrive+fSwitchAllowed
	DW	OFFSET TRANGROUP:CTTY		; In TCMD2.ASM
	DB	4,"ECHO",fSwitchAllowed
	DW	OFFSET TRANGROUP:ECHO		; In TUCODE.ASM
	DB	4,"GOTO",fSwitchAllowed
	DW	OFFSET TRANGROUP:GOTO		; In TBATCH.ASM
	DB	5,"SHIFT",fSwitchAllowed
	DW	OFFSET TRANGROUP:SHIFT		; In TBATCH.ASM
	DB	2,"IF",fSwitchAllowed
	DW	OFFSET TRANGROUP:$IF		; In TBATCH.ASM
	DB	3,"FOR",fSwitchAllowed
	DW	OFFSET TRANGROUP:$FOR		; In TBATCH.ASM
	DB	3,"CLS",fSwitchAllowed
	DW	OFFSET TRANGROUP:CLS		; In TCMD2.ASM
	DB	8,"TRUENAME",fSwitchAllowed+fCheckDrive  ;AN000; P3903 changed
	DW	OFFSET TRANGROUP:TRUENAME
	DB	0				; Terminate command table


comext	dB	".COM"
exeext	dB	".EXE"
batext	dB	".BAT"

switch_list	DB	"YVBAPW"                ; flags we can recognize


XA_cp	Label	  byte				;AN030; list for one extended attribute
	DW	  1
	DB	  EAISBINARY			;AN030; type
	DW	  EASYSTEM			;AN030; flags
	DB	  2				;AN030; name length
	DB	  "CP"                          ;AN030; name




PUBLIC	BatBufLen
BatBufLen   DW	BatLen

; *****************************************************
; EMG 4.00
; DATA STARTING HERE WAS ADDED BY EMG FOR 4.00
; FOR IMPLEMENTATION OF COMMON PARSE ROUTINE
; *****************************************************

;
; COMMON PARSE BLOCKS
;

;
; Indicates no value list for PARSE.
;

NO_VALUES	DW	0			;AN000;  no values

;
; PARSE control block for a required file specification (upper cased)
;

FILE_REQUIRED	LABEL	BYTE
		DW	0200H			;AN000;  filespec - required
		DW	1			;AN000;  capitalize - file table
		DW	TRANGROUP:PARSE1_OUTPUT ;AN000;  result buffer
		DW	TRANGROUP:NO_VALUES
		DB	0			;AN000;  no keywords

;
; PARSE control block for an optional file specification (upper cased)
; or drive number
;

FILE_OPTIONAL	LABEL	BYTE
		DW	0301H			;AN000;  filespec or drive number
						;	 optional
		DW	1			;AN000;  capitalize - file table
		DW	TRANGROUP:PARSE1_OUTPUT ;AN000;  result buffer
		DW	TRANGROUP:NO_VALUES
		DB	0			;AN000;  no keywords

;
; PARSE control block for an optional file specification (upper cased)
;

FILE_OPTIONAL2	LABEL	BYTE
		DW	0201H			;AN000;  filespec or drive number
						;	 optional
		DW	1			;AN000;  capitalize - file table
		DW	TRANGROUP:PARSE1_OUTPUT ;AN000;  result buffer
		DW	TRANGROUP:NO_VALUES
		DB	0			;AN000;  no keywords

;
; PARSE control block for an optional /P switch
;

SLASH_P_SWITCH	LABEL	BYTE
		DW	0			;AN000;  no match flags
		DW	2			;AN000;  capitalize - char table
		DW	TRANGROUP:PARSE1_OUTPUT ;AN000;  result buffer
		DW	TRANGROUP:NO_VALUES
		DB	1			;AN000;  1 keyword
SLASH_P_SYN	DB	"/P",0                  ;AN000;  /P switch



; PARSE BLOCK FOR BREAK, VERIFY, ECHO

;
; The following parse control block can be used for any command which
; needs only the optional "ON" and "OFF" keywords as operands.  Allows
; the equal sign as an additional delimiter.  Returns verified result
; in PARSE1_OUTPUT.  Currently used for the BREAK, VERIFY, and	ECHO
; internal commands.
;

PARSE_BREAK	LABEL	BYTE
		DW	TRANGROUP:BREAK_PARMS
		DB	0			;AN032; no extra delimiter

BREAK_PARMS	LABEL	BYTE
		DB	0,1			;AN000;  1 positional parm
		DW	TRANGROUP:BREAK_CONTROL1
		DB	0			;AN000;  no switches
		DB	0			;AN000;  no keywords

BREAK_CONTROL1	LABEL	BYTE
		DW	2001H			;AN000;  string value - optional
		DW	2			;AN000;  capitalize - char table
		DW	TRANGROUP:PARSE1_OUTPUT ;AN000;  result buffer
		DW	TRANGROUP:BREAK_VALUES
		DB	0			;AN000;  no keywords

BREAK_VALUES	LABEL	BYTE
		DB	3
		DB	0			;AN000;  no ranges
		DB	0			;AN000;  no numeric values
		DB	2			;AN000;  2 string values
		DB	0			;AN000;  returned if ON
		DW	TRANGROUP:BREAK_ON	;AN000;  point to ON string
		DB	'f'                     ;AN000;  returned if OFF
		DW	TRANGROUP:BREAK_OFF	;AN000;  point to OFF string

BREAK_ON	DB	"ON",0
BREAK_OFF	DB	"OFF",0

;
; PARSE BLOCK FOR CHCP
;

;
; The following parse control block can be used for any command which
; needs only one optional three digit decimal parameter for operands.
; Returns verified result in PARSE1_OUTPUT.  Currently used for the
; CHCP internal command.
;
CHCP_MINVAL	EQU	100
CHCP_MAXVAL	EQU	999

PARSE_CHCP	LABEL	BYTE
		DW	TRANGROUP:CHCP_PARMS
		DB	0			;AN000;  no extra delimiter

CHCP_PARMS	LABEL	BYTE
		DB	0,1			;AN000;  1 positional parm
		DW	TRANGROUP:CHCP_CONTROL1
		DB	0			;AN000;  no switches
		DB	0			;AN000;  no keywords

CHCP_CONTROL1	LABEL	BYTE
		DW	8001H			;AN000;  numeric value - optional
		DW	0			;AN000;  no function flags
		DW	TRANGROUP:PARSE1_OUTPUT ;AN000;  result buffer
		DW	TRANGROUP:CHCP_VALUES
		DB	0			;AN000;  no keywords

CHCP_VALUES	LABEL	BYTE
		DB	1
		DB	1			;AN000;  1 range
		DB	1			;AN000;  returned if result
		DD	CHCP_MINVAL,CHCP_MAXVAL ;AN000;  minimum & maximum value
		DB	0			;AN000;  no numeric values
		DB	0			;AN000;  no string values


;
; PARSE BLOCK FOR DATE
;

;
; The following parse control block can be used for any command which
; needs only an optional date string as an operand.  Returns unverified
; result in DATE_OUTPUT.  Currently used for the DATE internal command.
;

PARSE_DATE	LABEL	BYTE
		DW	TRANGROUP:DATE_PARMS
		DB	0			;AN000;  no extra delimiter

DATE_PARMS	LABEL	BYTE
		DB	0,1			;AN000;  1 positional parm
		DW	TRANGROUP:DATE_CONTROL1
		DB	0			;AN000;  no switches
		DB	0			;AN000;  no keywords

DATE_CONTROL1	LABEL	BYTE
		DW	1001H			;AN000;  date - optional
		DW	0			;AN000;  no function flags
		DW	TRANGROUP:DATE_OUTPUT	;AN000;  result buffer
		DW	TRANGROUP:NO_VALUES
		DB	0			;AN000;  no keywords

;
; PARSE BLOCK FOR TIME
;

;
; The following parse control block can be used for any command which
; needs only an optional time string as an operand.  Returns unverified
; result in TIME_OUTPUT.  Currently used for the TIME internal command.
;

PARSE_TIME	LABEL	BYTE
		DW	TRANGROUP:TIME_PARMS
		DB	0			;AN000;  no extra delimiter

TIME_PARMS	LABEL	BYTE
		DB	0,1			;AN000;  1 positional parm
		DW	TRANGROUP:TIME_CONTROL1
		DB	0			;AN000;  no switches
		DB	0			;AN000;  no keywords

TIME_CONTROL1	LABEL	BYTE
		DW	0801H			;AN000;  TIME - optional
		DW	0			;AN000;  no function flags
		DW	TRANGROUP:TIME_OUTPUT	;AN000;  result buffer
		DW	TRANGROUP:NO_VALUES
		DB	0			;AN000;  no keywords


;
; PARSE BLOCK FOR VOL
;

;
; The following parse control block can be used for any command which
; needs only an optional drive letter as an operand.  Returns unverified
; drive number (one based) in DRIVE_OUTPUT.  Currently used for the VOL
; internal command.
;

PARSE_VOL	LABEL	BYTE
		DW	TRANGROUP:VOL_PARMS
		DB	0			;AN000;  no extra delimiter

VOL_PARMS	LABEL	BYTE
		DB	0,1			;AN000;  1 positional parm
		DW	TRANGROUP:DRIVE_CONTROL1
		DB	0			;AN000;  no switches
		DB	0			;AN000;  no keywords

DRIVE_CONTROL1	LABEL	BYTE
		DW	0101H			;AN000;  DRIVE - optional
		DW	1			;AN000;  capitalize - file table
		DW	TRANGROUP:DRIVE_OUTPUT	;AN000;  result buffer
		DW	TRANGROUP:NO_VALUES
		DB	0			;AN000;  no keywords


;
; PARSE BLOCK FOR MKDIR, RMDIR, TYPE
;

;
; The following parse control block can be used for any command which
; needs only one required file specification as an operand.  Returns a
; pointer to the unverified string in PARSE1_OUTPUT.  Currently used
; for the MKDIR, RMDIR, and TYPE internal commands.
;

PARSE_MRDIR	LABEL	BYTE
		DW	TRANGROUP:MRDIR_PARMS
		DB	0			;AN000;  no extra delimiter

MRDIR_PARMS	LABEL	BYTE
		DB	1,1			;AN000;  1 positional parm
		DW	TRANGROUP:FILE_REQUIRED
		DB	0			;AN000;  no switches
		DB	0			;AN000;  no keywords

;
; PARSE BLOCK FOR CHDIR, TRUENAME
;

;
; The following parse control block can be used for any command which
; needs only one optional file specification an operand.  Returns a
; pointer to the unverified string in PARSE1_OUTPUT.  Currently used
; for the CHDIR and TRUENAME internal commands.
;

PARSE_CHDIR	LABEL	BYTE
		DW	TRANGROUP:CHDIR_PARMS
		DB	0			;AN000;  no extra delimiter

CHDIR_PARMS	LABEL	BYTE
		DB	0,1			;AN000;  1 positional parm
		DW	TRANGROUP:FILE_OPTIONAL
		DB	0			;AN000;  no switches
		DB	0			;AN000;  no keywords

;
; PARSE BLOCK FOR ERASE
;

;
; The following parse control block is used for the DEL/ERASE internal
; commands.  This command has one required file specification and an
; optional switch (/p) as operands. The verified switch or unverified
; file specification is returned in PARSE1_OUTPUT.
;

PARSE_ERASE	LABEL	BYTE
		DW	TRANGROUP:ERASE_PARMS
		DB	0			;AN000;  no extra delimiter

ERASE_PARMS	LABEL	BYTE
		DB	1,1			;AN000;  1 positional parm
		DW	TRANGROUP:FILE_REQUIRED
		DB	1			;AN000;  1 switch
		DW	TRANGROUP:SLASH_P_SWITCH
		DB	0			;AN000;  no keywords

;
; PARSE BLOCK FOR RENAME
;

;
; The following parse control block can be used for any command which
; needs only two required file specifications as operands.  Returns
; pointers to the unverified string in PARSE1_OUTPUT.
; Currently used for the RENAME internal command.
;

PARSE_RENAME	LABEL	BYTE
		DW	TRANGROUP:RENAME_PARMS
		DB	0			;AN000;  no extra delimiter

RENAME_PARMS	LABEL	BYTE
		DB	2,2			;AN000;  2 positional parms
		DW	TRANGROUP:FILE_REQUIRED
		DW	TRANGROUP:FILE_REQUIRED
		DB	0			;AN000;  no switches
		DB	0			;AN000;  no keywords

;
; PARSE BLOCK FOR CTTY
;

;
; The following parse control block can be used for any command which
; needs one required device name as an operand.  Returns a pointer to
; unverified string in PARSE1_OUTPUT. Currently used for the CTTY
; internal command.
;

PARSE_CTTY	LABEL	BYTE
		DW	TRANGROUP:CTTY_PARMS
		DB	0			;AN000;  no extra delimiter

CTTY_PARMS	LABEL	BYTE
		DB	1,1			;AN000;  1 positional parm
		DW	TRANGROUP:CTTY_CONTROL1
		DB	0			;AN000;  no switches
		DB	0			;AN000;  no keywords

CTTY_CONTROL1	LABEL	BYTE
		DW	2000H			;AN000;  string value - required
		DW	11H			;AN000;  capitalize - file table
						;AN000;  remove colon at end
		DW	TRANGROUP:PARSE1_OUTPUT ;AN000;  result buffer
		DW	TRANGROUP:NO_VALUES
		DB	0			;AN000;  no keywords

TRANDATA	ENDS

TRANCODE	SEGMENT PUBLIC BYTE

.xlist
.xcref

INCLUDE SYSMSG.INC

.list
.cref

ASSUME DS:TRANGROUP,ES:TRANGROUP,CS:TRANGROUP

MSG_UTILNAME <COMMAND>				;AN000; define utility name

MSG_SERVICES <COMT,COMMAND.CLF,COMMAND.CL1,COMMAND.CL2> ;AN000; The transient messages

include msgdcl.inc

TRANCODE	ENDS

TRANDATA	SEGMENT PUBLIC BYTE

	PUBLIC	RE_OUT_APP
	PUBLIC	RE_OUTSTR

RE_OUT_APP	DB	0			; output redirection appends
RE_OUTSTR	DB	PIPE_OUTPUT_PATH_BYTES DUP (0)	; path restored after EXEC

TRANDATAEND	LABEL	BYTE

TRANDATA	ENDS

	END
