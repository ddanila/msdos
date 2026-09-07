

PAGE	60,132
NAME	SELECT
TITLE	SELECT1 - DOS - SELECT.EXE
SUBTTL	select1.asm
.ALPHA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	SELECT1.ASM : Copyright 1988 Microsoft
;
;	DATE:	 July 4/87
;
;	COMMENTS: Assemble with MASM 3.0 (using the /A option)
;
;		  Panel flow is defined in the following files:
;
;			      SELECT1.ASM
;			      SELECT2.ASM
;			      SELECT3.ASM
;			      SELECT4.ASM
;			      SELECT5.ASM
;			      SELECT6.ASM
;
_TEXT	segment byte public 'CODE'
	extrn	gget_status:far
_TEXT	ends
_DATA	segment word public 'DATA'
_DATA	ends
CONST	segment word public 'CONST'
CONST	ends
_BSS	segment word public 'BSS'
_BSS	ends
								;
DGROUP	  GROUP   CONST,_BSS,_DATA
								;
DATA	  SEGMENT BYTE PUBLIC 'DATA'                            ;AN000; Segment for Data values
DATA	  ENDS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.XLIST
	INCLUDE PANEL.MAC
	INCLUDE SELECT.INC
	INCLUDE CASTRUC.INC
	INCLUDE STRUC.INC
	INCLUDE MACROS.INC
	INCLUDE EXT.INC
	INCLUDE VARSTRUC.INC
	INCLUDE ROUT_EXT.INC
	INCLUDE PAN-LIST.INC
.LIST
								;
	EXTRN	PM_BASECHAR:BYTE
	EXTRN	PM_BASEATTR:BYTE
	EXTRN	CRD_CCBVECOFF:WORD
	EXTRN	CRD_CCBVECSEG:WORD
								;
	EXTRN	ALLOCATE_MEMORY_CALL:FAR
	EXTRN	DEALLOCATE_MEMORY_CALL:FAR
	EXTRN	VIDEO_CHECK:FAR
	EXTRN	EXIT_SELECT:NEAR
	EXTRN	EXIT_SELECT2:NEAR
	EXTRN	ABORT_SELECT:NEAR
	EXTRN	HANDLE_F3:NEAR
								;
	PUBLIC	CHECK_VERSION
	PUBLIC	INTRO_SCREEN
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SELECT	SEGMENT PARA PUBLIC 'SELECT'
	ASSUME	CS:SELECT,DS:DATA
								;
	PUBLIC	BCHAR
	DB	'BCHAR='
BCHAR	DB	' '
								;
	INCLUDE CASEXTRN.INC
								;
	EXTRN	EXIT_DOS:NEAR
	EXTRN	EXIT_DOS_CONT:NEAR
	EXTRN	PROCESS_ESC_F3:NEAR
	EXTRN	WORKSPACE_SCREEN:NEAR
	EXTRN	DATE_TIME_SCREEN:NEAR
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Beginning of code
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CHECK_VERSION:
	INIT_VAR		N_HOUSE_CLEAN,E_CLEAN_NO	;AN000; no files to be erased on exit
								;
	CHECK_DOS_VERSION					;AN000; check DOS version
		;;;check for DOS version 4.00			;
		.IF c						;AN000; if incorrect DOS version
		    DISPLAY_MESSAGE	1
		    GOTO		EXIT_DOS_CONT
		.ENDIF						;AN000;    EXIT
								;
	CHECK_DEFAULT_DRIVE					;AN000; check if default drive is A:
		;;;check if default drive is A: 		;
		.IF c						;AN000; if default drive not A:
		   DISPLAY_MESSAGE	4
		   GOTO 		EXIT_DOS_CONT
		.ENDIF						;AN000;    EXIT
								;
	SCAN_PARAMETERS  N_SELECT_MODE
		;;;scan command line before probing installation media ;
	       .IF < N_SELECT_MODE EQ E_SELECT_INV >
		   DISPLAY_MESSAGE	6
		   GOTO 		EXIT_SELECT2
		.ENDIF
								;
	CHECK_DISKETTE		N_DISKETTE_A,N_DISKETTE_B,N_DISKETTE_TOT,P_STR120_1
		;;;get diskette media type and no of drives	;
		;;;N_DISKETTE_A & B - media type 360k,720k, etc ;
		;;;N_DISKETTE_TOT - number of drives		;
								;
	CHECK_DISK		E_DISK_1,N_DISK_1,N_DISK_1_S1,N_DISK_1_S2,DISK_1_TABLE
		;;;get partition status for 1st fixed disk	;
		;;;N_DISK_1 - disk status			;
		;;;N_DISK_1_S1 - detailed disk status word 1	;
		;;;N_DISK_1_S2 - detailed disk status word 2	;
		;;;DISK_1_TABLE - status of all partitions	;
								;
	CHECK_DISK		E_DISK_2,N_DISK_2,N_DISK_2_S1,N_DISK_2_S2,DISK_2_TABLE
		;;;get partition status for 2nd fixed disk	;
		;;;N_DISK_2 - disk status			;
		;;;N_DISK_2_S1 - detailed disk status byte 1	;
		;;;N_DISK_2_S2 - detailed disk status byte 2	;
		;;;DISK_2_TABLE - status of all partitions	;
								;
	CHECK_VALID_MEDIA    N_DISKETTE_A,N_DISKETTE_B,N_DISKETTE_TOT,N_DISK_1,N_DEST_DRIVE,I_DEST_DRIVE,N_DRIVE_OPTION
		;;;check if disk/diskette combination is valid	;
		;;;also determine default install drive 	;
		;;;N_DEST_DRIVE - default/user drive choice	;
		;;;I_DEST_DRIVE - drive A: or B: or C:		;
		;;;N_DRIVE_OPTION - which drive options are avail
		.IF c
		   DISPLAY_MESSAGE	5
		   GOTO 		EXIT_DOS_CONT
		.ENDIF
								;
	GET_INSTALLED_MEM   MEM_SIZE
								;
	CHECK_MACHINE	    MACHINE_TYPE, PS2_FLAG
								;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;  If this is reboot after FDISK, load parameters in SELECT.TMP
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
     .IF < N_SELECT_MODE eq E_SELECT_FDISK > and
     .IF < N_DISKETTE_A ne E_DISKETTE_360 >
	 CALL		     SCAN_INFO_CALL
     .ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	CHECK_DISPLAY						;AN000; determine display type
		.IF < ACTIVE eq EGA > or
		.IF < ALTERNATE eq EGA > or
		.IF < ACTIVE eq LCD > or
		.IF < ALTERNATE eq LCD >
		   INIT_VAR	N_DISPLAY, E_CPSW_DISP
		.ELSE
		   INIT_VAR	N_DISPLAY, E_NOCPSW_DISP
		.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Read in SELECT.DAT data (all but the help)
;
;	This will read in the panels, the scroll fields,
;	the color index (COLOR or MONO), and (EVENTUALLY)
;	the input fields.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	SET_DISPLAY_MODE					;AC084; SEH call moved before video information requested ;AN000; set display to 80 col and 25 lines
	CALL	PCGVIDO_CALL					;AN000;get video information
	ALLOCATE_MEMORY 					;AN000;allocate enough memory for SELECT.DAT
	.IF   < NC >
	   CALL  INITIALIZE					;AN000;read all panels, color, scroll
	   .IF	 < NC > 					;AN000;check if error condition occurred
	      INITIALIZE_BCHAR BCHAR				;AN000;Initialize the background character
	      JMP  MEMORY_ALLOCATED
	    .ELSE
	      JMP  EXIT_SELECT					;AN000;terminate SELECT without affecting memory
	   .ENDIF
	 .ELSE
	   DISPLAY_MESSAGE 20					;AN067;SEH insufficient memory
	   JMP	ABORT_SELECT
	.ENDIF
MEMORY_ALLOCATED:
  ;;;	CALL	CURSOROFF					;AN000;deactive cursor
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Commence the heart of the SELECT installation routine.
;	At the initial portion of the code, a system hardware
;	check out is performed.  The peripherals are established,
;	the display type is determined, and checks are made against
;	disk media installed.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
   ;;;	CALL	CURSOROFF
								;
	.IF < ACTIVE eq EGA >					;AN000; if active display = EGA
	   COPY_STRING		S_STR120_1,M_STR120_1,S_PREP_EGA;AN000;    set parameter for EGA.CPI
	.ELSEIF < ACTIVE eq LCD >				;AN000; elseif active display = LCD
	   COPY_STRING		S_STR120_1,M_STR120_1,S_PREP_LCD;AN000;    set parameter for LCD.CPI
	.ELSE							;AN000; else
	   INIT_VAR		S_STR120_1, 0			;AN000;    set parameter = null
	.ENDIF
								;
	.IF < S_STR120_1 gt 0 > 				;AN000; if parameter is not null
	   EXEC_PROGRAM 	S_MODE,S_STR120_1,PARM_BLOCK,EXEC_DIR ;AN000;GHG exec MODE CON CP PREP((850)...)
	   EXEC_PROGRAM 	S_MODE,S_CP_SEL,PARM_BLOCK,EXEC_DIR   ;AN000;GHG   execute MODE CON CP SEL=850
	.ENDIF
								;
	INIT_VAR		F_PARTITION, E_PART_DEFAULT
	INIT_VAR		F_FORMAT, E_FORMAT_FAT
	.IF < N_SELECT_MODE eq E_SELECT_FDISK >
	   INIT_VAR		I_DEST_DRIVE, E_DEST_DRIVE_C
	   GOTO 		DATE_TIME_SCREEN
	.ENDIF
								;
	CHECK_EXPANDED_MEMORY	N_XMA, N_MOD80			;AN000; check if expanded memory is present
	GET_NUMBER_PORTS	N_PARALLEL, N_SERIAL		;AN000; get number of parallel/serial ports
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Initialize pre-defined country and keyboard information
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	GET_DOS_COUNTRY 	P_STR120_1, N_COUNTRY		;AN000; get current DOS country
	GET_COUNTRY_INDEX	N_COUNTRY, N_CTY_LIST,I_COUNTRY ;AN000; get index into country table
	GET_COUNTRY_DEFAULTS	N_CTY_LIST, I_COUNTRY		;AN000; get default data for specified country
	.IF < N_DISPLAY eq E_CPSW_DISP >
	   .IF < N_CPSW eq E_CPSW_NOT_VAL >			;AN000; if cpsw not valid
	      INIT_VAR		F_CPSW, E_CPSW_NA		;AN000;    set cpsw = not available
	   .ELSEIF < N_CPSW eq E_CPSW_NOT_REC > 		;AN000; else if cpsw not recommended
	      INIT_VAR		F_CPSW, E_CPSW_NO		;AN000;    set cpsw = no
	   .ELSE						;AN000; else
	      INIT_VAR		F_CPSW, E_CPSW_YES		;AN000;    set cpsw = yes
	   .ENDIF
	.ELSE
	   INIT_VAR		F_CPSW, E_CPSW_NA
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	  If country is SWISS:
;	     then get keyboard from an input field
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	COMPARE_STRINGS 	S_KEYBOARD,S_SWISS		;AN000;GHG is default KB=SF?
	.IF <NC>
	   RETURN_STRING	STR_SWISS_KEYB,S_KEYBOARD,M_KEYBOARD+2
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Establish the default keyboard indice based on the
;	existing keyboard string.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	GET_KEYBOARD_INDEX	S_KEYBOARD,N_KYBD_LIST,I_KEYBOARD,N_KYBD_ALT;AN000; get kybd info
	.IF < N_KYBD_ALT eq E_KYBD_ALT_YES > near
	   GET_ALT_KYBD_TABLE	S_KEYBOARD,ALT_TAB_PTR,ALT_KYB_ID     ;AN000; get ptr to alt kybd
	   COPY_BYTE		ALT_KYB_ID_PREV, ALT_KYB_ID	;AN000; set prev id = current id
	   INIT_VAR		I_KYBD_ALT, 2			;AN090; set index into alt kybd list = 2
	   GET_ALT_KEYBOARD	ALT_TAB_PTR,ALT_KYB_ID,I_KYBD_ALT,S_KYBD_ALT;AN000; get alt kybd id
	.ELSE
	   INIT_VAR		ALT_KYB_ID_PREV, 0		;AN000; set prev alt kyb id = 0
	.ENDIF
								;
	INIT_VAR		N_KYB_LOAD, E_KYB_LOAD_UND	;AN000; set KEYB loaded status = undefined
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Initialize installation variables to default values
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	.IF < MEM_SIZE eq 256 >
	   INIT_VAR		   I_WORKSPACE, E_WORKSPACE_MIN ;AN000; set workspace option = minimum DOS	JW
	   COPY_STRING		   S_FILES, M_FILES, D_FILES_2	;AN000; set FILES = 20
	.ELSE
	   INIT_VAR		   I_WORKSPACE, E_WORKSPACE_BAL ;AN000; set workspace option = balance DOS
	   COPY_STRING		   S_FILES, M_FILES, D_FILES_1	;AN000; set FILES = 20
	.ENDIF
	INIT_VAR		N_WORK_PREV, 0			;AN000; set previous workspace option=undefined
	COPY_STRING		S_BREAK, M_BREAK, S_ON		;AN000; set BREAK = ON
	COPY_STRING		S_CPSW, M_CPSW, S_OFF		;AN000; set CPSW = OFF
	COPY_STRING		S_LASTDRIVE,M_LASTDRIVE,D_LASTDRIVE_1 ;AN000; set LASTDRIVE = E
	INIT_VAR		S_STACKS, 0			;AN000; set STACKS = null (spaces)
	COPY_STRING		S_VERIFY, M_VERIFY, S_OFF	;AN000; set VERIFY = OFF
	COPY_STRING		S_PROMPT, M_PROMPT,  D_PROMPT_1 ;AN000; set PROMPT = $P$G
	COPY_STRING		S_DOS_LOC,M_DOS_LOC,D_DOS_LOC_1 ;AN000; set DOS location = DOS
	INIT_VAR		S_INSTALL_PATH, 0		;AN000; set install path = null
	INIT_VAR		F_SHELL,E_SHELL_NO		;AN000; set SHELL = no
	.IF < MEM_SIZE eq 256 >
	    COPY_STRING 	    S_SHELL, M_SHELL, D_SHELL_1 ;AN000; set SHELL parameter = /R
	.ELSE
	    COPY_STRING 	    S_SHELL, M_SHELL, D_SHELL_2 ;AN000; set SHELL parameter = /R
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	INIT_VAR		F_SHARE, E_SHARE_NO		;AN000; set SHARE = no
	INIT_VAR		S_SHARE, 0			;AN000; set SHARE parameter = null
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Continue initialization ...
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	INIT_VAR		F_VDISK, E_VDISK_NO		;AN000; set VDISK = no
	INIT_VAR		S_VDISK, 0			;AN000; set VDISK field = null (spaces)
	.IF < N_XMA eq E_XMA_PRESENT >				;AN000; if expanded memory present
	   INIT_VAR		F_XMA, E_XMA_NO 		;AN000;    set XMA = no (default)
	   INIT_VAR		S_XMAEM, 0			;AN000;    set XMAEM field=null (spaces)
	   COPY_STRING		S_XMA2EMS,M_XMA2EMS,D_XMA2EMS_1 ;AN000;  & XMA2EMS field=FRAME=(D000,C800,CC00)
	.ELSE							;AN000; else
	   INIT_VAR		F_XMA, E_XMA_NA 		;AN000;    set XMA = no
	.ENDIF
	INIT_VAR		F_REVIEW, E_REVIEW_ACCEPT	;AN000; set review option = accept selection
	INIT_VAR		I_CTY_KYBD, E_CTY_KB_PREDEF	;AN000; set country support=pre-defined support
								;
	.IF < ACTIVE eq CGA > or				;AN000; if CGA adaptor
	.IF < ALTERNATE eq CGA >
	   INIT_VAR		F_GRAFTABL, E_GRAFTABL_YES	;AN000;    set GRAFTABL = yes
	.ELSE							;AN000; else
	   INIT_VAR		F_GRAFTABL, E_GRAFTABL_NA	;AN000;    set GRAFTABL = not available
	.ENDIF
								;
	INIT_VAR		N_NUMPRINT, MIN_NUMPRINT	;AN000; set number of printers = 0
	INIT_VAR		I_PRINTER, 1			;AN000; set index into printer list = 1
	INIT_VAR		I_PORT, 1			;AN000; set port number = 1
	INIT_VAR		I_REDIRECT, 1			;AN000; set redirect port number = 1
								;
	CALL			HOOK_INT_23			;AN074; SEH don't allow ctrl-break
	CALL			CURSOROFF			;AN054; SEH moved from earlier in code
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;  ------------------------------------Ŀ
;  -WELCOME_SCREEN			-
;  -					-
;  --------------------------------------
;
;  The WELCOME screen is always presented.
;  The screen does not have help, F3 function or input variables.
;  Valid keys are ENTER and ESC.
;  ESC key will return control to the DOS command line.
;  If installing from 360KB diskettes, must prompt for INSTALL diskette
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
WELCOME_SCREEN:
								;
       .IF < N_DISKETTE_A eq E_DISKETTE_360 >
	   INSERT_DISK		SUB_REM_DOS_A, S_DOS_COM_360	;AN000; Insert the INSTALL diskette
       .ENDIF
								;
WELCOME_SCREEN2:
	INIT_PQUEUE		PAN_WELCOME			;AN000; initialize queue
	PREPARE_PANEL		SUB_CONT_OPTION 		;AN000; prepare continue or cancel
	PREPARE_PANEL		PAN_HBAR			;AN000; prepare horizontal bar
	PREPARE_CHILDREN					;AN000; prepare child panels
	DISPLAY_PANEL						;AN000; display WELCOME panel
								;
	GET_FUNCTION		FK_ENT_ESC_F3			;AN000; get user entered function
	.IF < N_USER_FUNC eq E_F3 >				;AN000;DT if user entered F3 key
	    GOTO	     EXIT_DOS
	.ELSEIF < N_USER_FUNC eq E_ENTER >			;AN000; if user entered ENTER key
	   FIND_FILE	       S_PRINT_FILE, E_FILE_ATTR	;AN001; check to make sure they did not switch
	   .IF < c >
	      INSERT_DISK      SUB_REM_DOS_A, S_PRINT_FILE
	   .ENDIF
	   GOTO 		INTRO_SCREEN			;AN000;    go to next screen
	.ELSE							;AN000; else
	   CALL 		HANDLE_F3			;AN001;GHG exit to DOS command line
	   .IF < C >
	       GOTO		EXIT_DOS
	   .ELSE
	       GOTO		WELCOME_SCREEN2
	   .ENDIF
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;  ------------------------------------Ŀ
;  -INTRO_SCREEN			-
;  -					-
;  --------------------------------------
;
;  The INTRODUCTION screen is always presented.
;  The screen does not have help, F3 function or any variables.
;  Valid keys are ENTER and ESC.
;  ESC key will return control to the DOS command line.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
INTRO_SCREEN:
	INIT_PQUEUE		PAN_INTRO			;AN000; initialize queue
	PREPARE_PANEL		PAN_HBAR			;AN000; prepare horizontal bar
	PREPARE_CHILDREN					;AN000; prepare child panels
	DISPLAY_PANEL						;AN000; display INTRODUCTION panel
								;
	GET_FUNCTION		FK_ENT_ESC_F3			;AN000; get user entered function
	.IF < N_USER_FUNC eq E_F3 >				;AN027;SEH  Added to prevent going to Welcome Screen
	    GOTO	     EXIT_DOS				;AN027;SEH     when F3 hit
								; (ENTER or ESC)
	.ELSEIF < N_USER_FUNC eq E_ENTER >			;AN000; if user entered ENTER key
	   GOTO 		WORKSPACE_SCREEN		;AN000;    go to next screen
	.ELSE							;AN000; else
	   GOTO 		WELCOME_SCREEN2 		;AN001;GHG;    exit to DOS command line
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	ROUTINE TO SCAN SELECT.TMP FILE
;
;	Broken down into a subroutine for code savings...
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		PUBLIC	SCAN_INFO_CALL
SCAN_INFO_CALL	PROC	NEAR
	SCAN_INFO_FILE	 F_SHELL, N_FORMAT_MODE,N_DISK1_MODE,I_DESTINATION,S_INSTALL_PATH,S_SELECT_TMP,P_STR120_1,M_STR120_1
		;;;F_SHELL - shell installation flag
		;;;N_FORMAT_MODE - partition & format option	:
		;;;    new(select),new(user),used(user) 	;
		;;;N_DISK1_MODE - 1st disk status - new or used ;
		;;;I_DESTINATION - destination on c:   disk option
		;;;S_INSTALL_PATH - DOS install path		;
		;;;S_SELECT_TMP -  file for FDISK parameters	;
								;
	       .IF < N_SELECT_MODE eq E_SELECT_INV >		;AN000; if SELECT mode not MENU or FDISK
		  DISPLAY_MESSAGE	6
		  GOTO			EXIT_DOS_CONT
	       .ENDIF						;AN000;    EXIT
								;
	       .IF < N_SELECT_MODE eq E_SELECT_FDISK > and	;AN000; if SELECT mode is FDISK
	       .IF < N_FORMAT_MODE eq E_SELECT_INV > or 	;AN000; and format and disk status
	       .IF < N_DISK1_MODE eq E_SELECT_INV >		;AN000; not available from SELECT.TMP
		  DISPLAY_MESSAGE	6
		  GOTO			EXIT_DOS_CONT
	       .ENDIF						;AN000;     EXIT
	       RET
SCAN_INFO_CALL	ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SELECT	ENDS
	END
