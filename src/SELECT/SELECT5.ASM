

PAGE 55,132
NAME	SELECT
TITLE	SELECT - DOS - SELECT.EXE
SUBTTL	SELECT5.asm
.ALPHA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	SELECT5.ASM : Copyright 1988 Microsoft
;
;	DATE:	 August 8/87
;
;	COMMENTS: Assemble with MASM 3.0 (using the /A option)
;
;		  Panel flow is defined in the following files:
;
;		      - SELECT1.ASM
;		      - SELECT2.ASM
;		      - SELECT3.ASM
;		      - SELECT4.ASM
;		      - SELECT5.ASM
;		      - SELECT6.ASM
;
;  Module contains code for :
;	- VDISK screen
;	- CONFIG.SYS screen
;	- Fixed disk partition screen
;	- Date/Time screen
;
DATA	SEGMENT BYTE PUBLIC 'DATA'
	EXTRN	SEL_FLG:BYTE
	EXTRN	EXEC_DEALLOC:BYTE
	EXTRN	EXEC_FDISK:BYTE
	EXTRN	EXEC_ERR:BYTE
	EXTRN	BCHAR:BYTE
DATA	       ENDS
								;
.XLIST
	INCLUDE    PANEL.MAC
	INCLUDE    SELECT.INC
	INCLUDE    CASTRUC.INC
	INCLUDE    STRUC.INC
	INCLUDE    MACROS.INC
	INCLUDE    EXT.INC
	INCLUDE    VARSTRUC.INC
	INCLUDE    ROUT_EXT.INC
	INCLUDE    PAN-LIST.INC
.LIST
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
								;
	EXTRN	DEALLOCATE_HELP:FAR
	EXTRN	ALLOCATE_HELP:FAR
	EXTRN	DEALLOCATE_BLOCK:FAR
	EXTRN	ALLOCATE_BLOCK:FAR
	EXTRN	DEALLOCATE_MEMORY_CALL:FAR
	EXTRN	ALLOCATE_MEMORY_CALL:FAR
	EXTRN	PM_BASECHAR:BYTE
	EXTRN	PM_BASEATTR:BYTE
	EXTRN	CRD_CCBVECOFF:WORD
	EXTRN	CRD_CCBVECSEG:WORD
								;
								;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SELECT	SEGMENT PARA PUBLIC 'SELECT'                            ;AN000;segment for far routine
	ASSUME	CS:SELECT,DS:DATA
								;
	INCLUDE CASEXTRN.INC
								;
	EXTRN	CREATE_AUTOEXEC_BAT:NEAR
	EXTRN	CREATE_CONFIG_SYS:NEAR
	EXTRN	CREATE_SHELL_BAT:NEAR
	EXTRN	SCAN_INFO_CALL:NEAR
	EXTRN	DATE_TIME_SCREEN:NEAR
								;
	PUBLIC	FIRST_DISK_SCREEN
	PUBLIC	VDISK_SCREEN
	EXTRN	PROCESS_ESC_F3:near
	EXTRN	FORMAT_DISK_SCREEN:near
	EXTRN	EXIT_DOS:near
	EXTRN	INSTALL_ERROR:near
	EXTRN	EXIT_SELECT:NEAR
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;  ------------------------------------Ŀ
;  -VDISK_SCREEN			-
;  -					-
;  --------------------------------------
;
;  The VDISK PARAMETERS SCREEN is presented if the user selected to
;  install virtual disk support and the user wants to view/change parameters.
;  Note.The view/change parameters condition is not specified in the May 5, 1987
;  Functional Specification.
;  The screen gets parameters for the VDISK command.
;  Valid keys are ENTER, ESC, F1, F3 and ASCII characters.
;  Note.User entered parameter values are not checked for validity.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
VDISK_SCREEN:
	.IF < F_VDISK eq E_VDISK_NO >				;AN000; if VDISK support not required
	   GOTO 		CONFIG_SYS_SCREEN		;AN000;    goto the next screen (CONFIG.SYS)
	.ENDIF
								;
	INIT_PQUEUE		PAN_VDISK			;AN000; initialize queue
	PREPARE_PANEL		PAN_HBAR			;AN000; prepare horizontal bar
	PREPARE_CHILDREN					;AN000; prepare child panels
	INIT_STRING		STR_VDISK,S_VDISK,M_VDISK	;AN000; get new parameters for VDISK
	DISPLAY_PANEL						;AN000; display VDISK panel
								;
	GET_STRING		STR_VDISK,S_VDISK,M_VDISK,FK_TEXT     ;AN000; get new parameters for VDISK
								;
	.IF < N_USER_FUNC eq E_ENTER >				;AN000; if user entered ENTER key
	   COPY_STRING		S_VDISK, M_VDISK, S_USER_STRING ;AN000;    save new parameters for VDISK
	   PUSH_HEADING 	VDISK_SCREEN			;AN000;    save screen address on SELECT STACK
	   GOTO 		CONFIG_SYS_SCREEN		;AN000;    goto the next screen (CONFIG.SYS)
	.ELSE
	   GOTO 		PROCESS_ESC_F3			;AN000; user entered ESC or F3, take action
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;  ------------------------------------Ŀ
;  -CONFIG_SYS_SCREEN			-
;  -					-
;  --------------------------------------
;
;  The CONFIG.SYS PARAMETERS SCREEN is presented if the user selected to
;  view/change SELECT generated commands ( F_REVIEW = 2 ).
;  The screen gets parameters for CONFIG.SYS commands ( BREAK, BUFFERS,
;  FCBS, FILES, LASTDRIVE, STACKS, VERIFY ).
;  The TAB key is used to move to the next item on the parameter list.
;  If the cursor is on the last item in the parameter list, TAB key
;  will cause the cursor to wrap around to the first item of the parameter list.
;  When the TAB key is depressed, the current parameter value is saved in
;  a temporary location.  The temporary parameter values are copied to actual
;  values only when the ENTER key is depressed.
;  Valid keys are ENTER, ESC, F1, F3, TAB and ASCII characters.
;  Note.User entered parameter values are not checked for validity.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CONFIG_SYS_SCREEN:
	COPY_STRING		ST_BREAK, MT_BREAK, S_BREAK	;AN000; copy BREAK par to temp location
	COPY_STRING		ST_BUFFERS,MT_BUFFERS,S_BUFFERS ;AN000; copy BUFFERS par to temp location
	COPY_STRING		ST_FCBS, MT_FCBS, S_FCBS	;AN000; copy FCBS par to temp location
	COPY_STRING		ST_FILES, MT_FILES, S_FILES	;AN000; copy FILES par to temp location
	COPY_STRING		ST_LASTDRIVE,MT_LASTDRIVE,S_LASTDRIVE ;AN000; copy LASTDRIVE par to temp location
	COPY_STRING		ST_STACKS, MT_STACKS, S_STACKS	;AN000; copy STACKS par to temp location
	COPY_STRING		ST_VERIFY, MT_VERIFY, S_VERIFY	;AN000; copy VERIFY par to temp location
								;
	INIT_PQUEUE		PAN_CONFIG_PARS 		;AN000; initialize queue
	PREPARE_PANEL		PAN_HBAR			;AN000; prepare horizontal bar
	PREPARE_CHILDREN					;AN000; prepare child panels
	INIT_STRING		STR_BREAK, ST_BREAK, MT_BREAK	;AN000; display BREAK parameters
	INIT_STRING		STR_BUFFERS,ST_BUFFERS,MT_BUFFERS     ;AN000; display BUFFERS parameters
	INIT_STRING		STR_FCBS, ST_FCBS, MT_FCBS	;AN000; display FCBS parameters
	INIT_STRING		STR_FILES, ST_FILES, MT_FILES	;AN000; display FILES parameters
	INIT_STRING		STR_LASTDRIVE,ST_LASTDRIVE,MT_LASTDRIVE      ;AN000; display LASTDRIVE parameters
	INIT_STRING		STR_STACKS,ST_STACKS, MT_STACKS ;AN000; display STACKS parameters
	INIT_STRING		STR_VERIFY,ST_VERIFY, MT_VERIFY ;AN000; display VERIFY parameters
	DISPLAY_PANEL						;AN000; display CONFIG.SYS parameters panel
								;
	INIT_VAR		N_COUNTER, 1
								;
	.REPEAT 						;AN000; repeat code block
								;
	   .SELECT
								;
	   .WHEN < N_COUNTER eq 1 >
	      GET_STRING	STR_BREAK,ST_BREAK,MT_BREAK,FK_TAB    ;AN000; get new parameter for BREAK
	      COPY_STRING	ST_BREAK,MT_BREAK,S_USER_STRING ;AN000;    save new BREAK parameter
								;
	   .WHEN < N_COUNTER eq 2 >
	      GET_STRING	STR_BUFFERS,ST_BUFFERS,MT_BUFFERS,FK_TAB    ;AN000; get new parameter for BUFFERS
	      COPY_STRING	ST_BUFFERS,MT_BUFFERS,S_USER_STRING   ;AN000; save new BUFFERS parameter
								;
	   .WHEN < N_COUNTER eq 3 >
	      GET_STRING	STR_FCBS,ST_FCBS,MT_FCBS,FK_TAB ;AN000;    get new parameter for FCBS
	      COPY_STRING	ST_FCBS, MT_FCBS, S_USER_STRING ;AN000;    save new FCBS parameter
								;
	   .WHEN < N_COUNTER eq 4 >
	      GET_STRING	STR_FILES,ST_FILES,MT_FILES,FK_TAB    ;AN000; get new parameter for FILES
	      COPY_STRING	ST_FILES,MT_FILES,S_USER_STRING ;AN000;  save new FILES parameter
								;
	   .WHEN < N_COUNTER eq 5 >
	      GET_STRING	STR_LASTDRIVE,ST_LASTDRIVE,MT_LASTDRIVE, FK_TAB ;AN000; get new parameter for LASTDRIVE
	      COPY_STRING	ST_LASTDRIVE,MT_LASTDRIVE,S_USER_STRING 	;AN000;save new LASTDRIVE parameter
								;
	   .WHEN < N_COUNTER eq 6 >
	      GET_STRING	STR_STACKS,ST_STACKS,MT_STACKS,FK_TAB ;AN000;get new parameter for STACKS
	      COPY_STRING	ST_STACKS,MT_STACKS,S_USER_STRING     ;AN000;  save new STACKS parameter
								;
	   .OTHERWISE
	      GET_STRING	STR_VERIFY,ST_VERIFY,MT_VERIFY,FK_TAB ;AN000;get new parameter for VERIFY
	      COPY_STRING	ST_VERIFY,MT_VERIFY,S_USER_STRING     ;AN000;	 save new VERIFY parameter
								;
	   .ENDSELECT
								;
	   INC_VAR		N_COUNTER			;AN000;    inc counter
								;
	   .IF < N_COUNTER a 7 >				;AC000;JW;    if counter > 8
	      INIT_VAR		N_COUNTER, 1			;AN000;       set counter = 1
	   .ENDIF
								;
	.UNTIL < N_USER_FUNC eq E_ENTER > or near		;AN000; break if loop if ENTER entered
	.UNTIL < N_USER_FUNC eq E_ESCAPE > or near		;AN000; or ESCAPE entered
	.UNTIL < N_USER_FUNC eq E_F3 > near			;AN000; or F3 entered
								;
	.IF < N_USER_FUNC eq E_ENTER > near			;AN000; if user entered ENTER key
	   COPY_STRING		S_BREAK, M_BREAK, ST_BREAK	;AN000;    save BREAK  parameter
	   COPY_STRING		S_BUFFERS,M_BUFFERS, ST_BUFFERS ;AN000;   save BUFFERS parameter
	   COPY_STRING		S_FCBS, M_FCBS, ST_FCBS 	;AN000;    save FCBS parameter
	   COPY_STRING		S_FILES, M_FILES, ST_FILES	;AN000;    save FILES parameter
	   COPY_STRING		S_LASTDRIVE,M_LASTDRIVE,ST_LASTDRIVE  ;AN000;save LASTDRIVE  parameter
	   COPY_STRING		S_STACKS, M_STACKS, ST_STACKS	;AN000;    save STACKS parameter
	   COPY_STRING		S_VERIFY, M_VERIFY, ST_VERIFY	;AN000;    save VERIFY parameter
	   PUSH_HEADING 	CONFIG_SYS_SCREEN		;AN000;    save screen address on SELECT STACK
	   GOTO 		FIRST_DISK_SCREEN		;AN000;    goto the first fixed disk screen
	.ELSE
	   GOTO 		PROCESS_ESC_F3			;AN000; user entered ESC or F3, take action
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;  ------------------------------------Ŀ
;  -FIRST_DISK_SCREEN			-
;  -					-
;  --------------------------------------
;
;  The PARTITION FIXED DISK SCREEN is presented if the first fixed drive
;  exists and is completely unused.
;  When SELECT is invoked, the system configuration is checked and if fixed
;  disks exist, the fixed disk status is obtained and variables are initialized.
;  The screen allows the user to create partitions for the fixed drive.
;  If the user chooses to let SELECT define partition sizes, the first fixed
;  disk will be partitioned as follows:
;     -  A Primary DOS partition is created using the entire disk.
;  SELECT will partition the second fixed disk if it exists as follows:
;     - An Extended DOS partition is created using the entire disk space and a
;	logical drive is created using the entire Extended DOS partition.
;  Valid keys are ENTER, ESC, F1, F3, cursor up/down, 1/2.
;  Note.After FDISK, the partitions have to formatted.	Since the system is going
;  to reboot, SELECT must know if the user had created his own partitions or not
;  so that the partitions can be automatically formatted. The MENU parameter
;  in the AUTOEXEC.BAT file is changed FDISK.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
FIRST_DISK_SCREEN:
	.IF < I_DEST_DRIVE ne E_DEST_DRIVE_C >	or
	.IF < N_DISK_1 eq E_DISK_INV >				;AN000; if first fixed disk not present
	   GOTO 		DATE_TIME_SCREEN		;AN000;    goto DATE_TIME screen
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;  ------------------------------------Ŀ
;  -MAKE_BACKUP_DISKETTE		-
;  -					-
;  -					-
;  --------------------------------------
;
;	WE NEED TO MAKE A DUPLICATE OF THE SELECT/SHELL DISKETTE 
;	FOR R/W PURPOSES!
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
MAKE_BACKUP_DISKETTE:
								;
	   .REPEAT
	      .REPEAT
								;
		 INIT_PQUEUE	      PAN_INSTALL_DOS		;AN000; initialize queue
		 PREPARE_PANEL	      PAN_DISKCOPY
		 PREPARE_PANEL	      PAN_HBAR
		 PREPARE_CHILDREN
		 DISPLAY_PANEL
								;
		 GET_FUNCTION	      FK_ENT_ESC_F3		;AN002;GHG get user entered function (ENTER or ESC )
								;
		.IF < N_USER_FUNC ne E_ENTER >			;AN002;GHG if user entered ENTER key
		   GOTO 		 PROCESS_ESC_F3 	;AN002;GHG    exit to DOS command line
		.ENDIF
								;
		FIND_FILE	     S_AUTO_REBOOT, E_FILE_ATTR ;AN000;DT Look for AUTOEXEC.BAT (INSTALL diskette)
		   .LEAVE < nc >
		   HANDLE_ERROR 	ERR_DOS_DISK, E_RETURN
								;
	      .UNTIL
								;
	      .IF < MEM_SIZE ne 256 > near
		 CALL	 HOOK_INT_2F
	      .ELSE
		 DEALLOCATE_MEMORY
		 CALL	 HOOK_INT_2F_256KB
	      .ENDIF
								;
	      INIT_VAR		   N_DSKCPY_ERR,E_DSKCPY_OK
	      EXEC_PROGRAM	   S_DISKCOPY,S_DISKCOPY_PARM,PARM_BLOCK,EXEC_NO_DIR;AN000; control will not return
	      .IF < c >
		 MOV   EXEC_ERR,TRUE
	      .ENDIF
	      CALL	RESTORE_INT_2F
								;
	   .UNTIL < N_DSKCPY_ERR ne E_DSKCPY_RETRY > near
								;
	   .IF < MEM_SIZE eq 256 > near
	       CLEAR_SCREEN
	       DISPLAY_MESSAGE 12				;AN000;DT Insert SELECT diskette
	       .REPEAT
		   CALL GET_ENTER_KEY				;AN000; get user entered function
		   FIND_FILE		S_DOS_SEL_360, E_FILE_ATTR
		   .LEAVE < nc >
		      DISPLAY_MESSAGE 11			;AN000;DT Beep
	       .UNTIL
	       ALLOCATE_MEMORY
	       CALL    INITIALIZE				;AN000;DT and read them in
	       INITIALIZE_BCHAR BCHAR				;AN000;Initialize the background character
	       INSERT_DISK	SUB_INSTALL_COPY, S_DOS_COM_360
	   .ENDIF
	   .IF < EXEC_ERR eq TRUE >
	      HANDLE_ERROR	ERR_GENERAL, E_RETURN
	      GOTO		MAKE_BACKUP_DISKETTE
	   .ENDIF
	   CALL 		CURSOROFF			;AN000; set cursor off
								;
	OR  SEL_FLG,INSTALLRW					;AN000; indicate INSTALL diskette is R/W
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; - Create the CONFIG.340, AUTOEXEC.340, and SHELL.BAT on the	-
; - INSTALL COPY diskette in drive A:				-
;  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	CREATE_CONFIG		S_CONFIG_NEW, N_RETCODE
	.IF c
	   GOTO 		INSTALL_ERROR
	.ENDIF
								;
	INIT_VAR		N_HOUSE_CLEAN,E_CLEAN_YES	;AN000; set to perform cleanup on exit
								;
	CREATE_AUTOEXEC 	S_AUTO_NEW,E_DEST_SHELL,N_RETCODE     ;AN000; create autoexec with SHELL commands
	.IF c
	   GOTO 		INSTALL_ERROR
	.ENDIF
								;
	CREATE_SHELL   S_SHELL_NEW, N_RETCODE
	.IF c
	   GOTO        INSTALL_ERROR
	.ENDIF
								;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;  ------------------------------------Ŀ
;  -DISK_PARTITION_OPTION		-
;  -					-
;  -					-
;  --------------------------------------
;
;	If the first fixed disk is not new (existing partition)
;	goto different screen.	Else present screen with partition
;	options.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	.IF < N_DISK_1 eq E_DISK_VAL_PART >			;AN000; if first disk has partitions
	   GOTO 		BOTH_DISK_SCREEN		;AN000;    goto next screen (BOTH_DISK)
	.ENDIF
								;
DISK_PARTITION_OPTION:
	INIT_VAR		N_DISK_NUM, '1'
	INIT_CHAR		N_DISK_NUM, E_DISK_ROW, E_DISK_COL, SUB_FIXED_1 ;AN000; display the disk number     JW
								;
	INIT_PQUEUE		PAN_FIXED_FIRST 		;AN000; initialize queue
	PREPARE_PANEL		SUB_FIXED_1			;AN000; prepare fixed disk 1 message
	PREPARE_PANEL		PAN_HBAR			;AN000; prepare horizontal bar
	PREPARE_CHILDREN					;AN000; prepare child panels
	INIT_SCROLL		SCR_FIXED_FIRST, F_PARTITION
	DISPLAY_PANEL						;AN000; display first fixed disk partition screen
								;
	GET_SCROLL		SCR_FIXED_FIRST,F_PARTITION,FK_SCROLL ;AN000; get user selected option for creating partitions
								;
	PROCESS_F3
	PROCESS_ESC
								;
	COPY_WORD		F_PARTITION, I_USER_INDEX
	.IF < F_PARTITION eq E_PART_DEFAULT >
	   INIT_VAR		N_FORMAT_MODE, E_FORMAT_SELECT
	.ELSE
	   INIT_VAR		N_FORMAT_MODE, E_FORMAT_NEW
	.ENDIF
								;
	SAVE_PARAMETERS 	S_SELECT_TMP, N_RETCODE
	.IF c
	   GOTO        INSTALL_ERROR
	.ENDIF
								;
	CHANGE_AUTOEXEC 	S_AUTO_REBOOT, S_AUTO_FDISK
	.IF c
	   GOTO        INSTALL_ERROR
	.ENDIF
								;
	.IF < MEM_SIZE eq 256 >
	    DEALLOCATE_MEMORY
	.ENDIF
								;
	.IF < F_PARTITION eq E_PART_USER > near 		;AN000; if user selected to define his own partition sizes
								;
	   SAVE_PANEL_LIST					;AN000;     save panel list for test team
	   INIT_VAR		S_STR120_1, 0
	   APPEND_STRING	S_STR120_1,M_STR120_1,S_SLASH_Q ;AN000;DT add /Q parameter (no insert disk at end)
	   CALL 		CURSORON			;AN000;     set cursor to show
	   EXEC_PROGRAM 	S_FDISK,S_STR120_1,PARM_BLOCK,EXEC_NO_DIR   ;AN000; control will not return
	   .IF c
	      GOTO		FDISK_ERROR
	   .ENDIF
								;
	   GOTO 		FDISK_REBOOT
       .ENDIF
								;
	INIT_VAR		N_WORD_1, 1
	SCAN_DISK_TABLE 	E_DISK_1, N_WORD_1, N_RETCODE
	.IF < N_RETCODE eq 0 > and
	.IF < N_NAME_PART eq E_FREE_MEM_DISK >
	   WORD_TO_CHAR 	N_SIZE_PART, S_STR120_2
	   MERGE_STRING 	S_STR120_1,M_STR120_1,SC_1,SC_PRI
	   APPEND_STRING	S_STR120_1,M_STR120_1,S_STR120_2
	   APPEND_STRING	S_STR120_1,M_STR120_1,S_SLASH_Q ;AN000;DT add /Q parameter (no insert disk at end)
	   EXEC_PROGRAM 	S_FDISK,S_STR120_1,PARM_BLOCK,EXEC_NO_DIR
	   .IF c
	      GOTO		FDISK_ERROR
	   .ENDIF
	.ENDIF
								;
	.IF < N_DISK_2 eq E_DISK_NO_PART > near
	   INIT_VAR		N_WORD_1, 1
	   SCAN_DISK_TABLE	E_DISK_2, N_WORD_1, N_RETCODE
	   .IF < N_RETCODE eq 0 > and near
	   .IF < N_NAME_PART eq E_FREE_MEM_DISK > near
	      WORD_TO_CHAR	N_SIZE_PART, S_STR120_2
	      MERGE_STRING	S_STR120_1,M_STR120_1,SC_2,SC_EXT
	      APPEND_STRING	S_STR120_1,M_STR120_1,S_STR120_2
	      APPEND_STRING	S_STR120_1,M_STR120_1,SC_LOG
	      APPEND_STRING	S_STR120_1,M_STR120_1,S_STR120_2
	      APPEND_STRING	S_STR120_1,M_STR120_1,S_SLASH_Q ;AN000;DT add /Q parameter (no insert disk at end)
	      EXEC_PROGRAM	S_FDISK,S_STR120_1,PARM_BLOCK,EXEC_NO_DIR
	      .IF c
		 GOTO		FDISK_ERROR
	      .ENDIF
	   .ENDIF
	.ENDIF
								;
FDISK_REBOOT:
       .IF < MEM_SIZE eq 256 >
	    CLEAR_SCREEN
	    DISPLAY_MESSAGE 9
	.ELSE
	    CALL		 CURSOROFF			;AN000;      set to hide cursor
	    INIT_PQUEUE 	    PAN_REBOOT			;AN000; initialize queue
	    PREPARE_PANEL	    SUB_REBOOT_KEYS
	    DISPLAY_PANEL
	    SAVE_PANEL_LIST					;AN000;     save panel list for test team
	.ENDIF
								;
	GET_FUNCTION		FK_REBOOT			;AN000; Reboot
								;
FDISK_ERROR:
       .IF < MEM_SIZE eq 256 > near
	  CLEAR_SCREEN
	  DISPLAY_MESSAGE 12					;AN000;DT Insert SELECT diskette
								;
	  .REPEAT
	     GET_FUNCTION	     FK_ENT			;AN000; get user entered function
	     FIND_FILE		  S_DOS_SEL_360, E_FILE_ATTR
	    .LEAVE < nc >
	       DISPLAY_MESSAGE 11				;AN000;DT Beep
	  .UNTIL
								;
	  ALLOCATE_MEMORY
	  CALL	  INITIALIZE					;AN000;DT and read them in
	.ENDIF
	.IF < SUB_ERROR eq 1 >					;AN023; If error is because no Primary DOS partition
	   CALL 	  CURSOROFF				;AN023;   set cursor off
	   GOTO 	  DISK_PARTITION_OPTION 		;AN023;   return to partition options
	.ENDIF
	GOTO	       INSTALL_ERROR
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;  ------------------------------------Ŀ
;  -BOTH_DISK_SCREEN			-
;  -					-
;  -					-
;  --------------------------------------
;
;	Ask user if they want to change the existing partition
;	layout or leave it the same (for both disks if 2nd exists).
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
BOTH_DISK_SCREEN:
BOTH_DISK_PART_OPTION:
								;
	.IF < N_DISK_1_S2 eq E_SPACE_EDOS > or
	.IF < N_DISK_1_S2 eq E_SPACE_DISK >
	   INIT_VAR		N_DISK_NUM, '1'
	.ELSEIF < N_DISK_2_S2 eq E_SPACE_EDOS > or
	.IF < N_DISK_2_S2 eq E_SPACE_DISK >
	   INIT_VAR		N_DISK_NUM, '2'
	.ELSE
	   GOTO 		DATE_TIME_SCREEN		;AN000; no more partitions to be created
	.ENDIF
								;
	INIT_CHAR		N_DISK_NUM, E_DISK_ROW, E_DISK_COL, SUB_FIXED_1 ;AN000; display the disk number     JW
	INIT_PQUEUE		PAN_FIXED_BOTH			;AN000; initialize queue
	PREPARE_PANEL		SUB_FIXED_1			;AN000; prepare fixed disk message JW
	PREPARE_PANEL		PAN_HBAR			;AN000; prepare horizontal bar
	PREPARE_CHILDREN					;AN000; prepare child panels
	INIT_SCROLL		SCR_FIXED_BOTH, F_PARTITION
	DISPLAY_PANEL						;AN000; display first fixed disk partition screen
								;
	GET_SCROLL		SCR_FIXED_BOTH,F_PARTITION,FK_SCROLL  ;AN000; get user selected option for creating partitions
								;
	PROCESS_ESC
	PROCESS_F3
								;
	COPY_WORD		F_PARTITION, I_USER_INDEX
	CHANGE_AUTOEXEC 	S_AUTO_REBOOT, S_AUTO_FDISK
	.IF c
	   GOTO 		INSTALL_ERROR
	.ENDIF
								;
	.IF < F_PARTITION eq E_PART_USER > near 		;AN000; if user will define his own partition
								;
	   .IF < MEM_SIZE eq 256 >
	      DEALLOCATE_MEMORY
	   .ENDIF
								;
	   INIT_VAR		N_FORMAT_MODE, E_FORMAT_USED
	   SAVE_PARAMETERS	S_SELECT_TMP, N_RETCODE
	   SAVE_PANEL_LIST					;AN000;     save panel list for test team
	   INIT_VAR		S_STR120_1, 0
	   APPEND_STRING	S_STR120_1,M_STR120_1,S_SLASH_Q ;AN000;DT add /Q parameter (no insert disk at end)
	   CALL 		CURSORON			;AN000;     set to show cursor
	   EXEC_PROGRAM 	S_FDISK,S_STR120_1,PARM_BLOCK,EXEC_NO_DIR   ;AN000; control will not return
	   .IF c
	      .IF < SUB_ERROR eq 2 >				;AN034; SEH If user made no changes to partition
		 CALL		CURSOROFF			;AN034; SEH Set cursor off
		 GOTO		BOTH_DISK_SCREEN		;AN034; SEH Go to previous screen
	      .ELSE						;AN034; SEH
		 GOTO		FDISK_ERROR
	      .ENDIF						;AN034; SEH
	   .ENDIF
								;
	   GOTO 		FDISK_REBOOT
	.ELSE
	   GOTO 		DATE_TIME_SCREEN		;AN000; no more partitions to be created
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;  GET KEY ROUTINE (256KB)
;
; Input: none
;
; Output: none
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
PUBLIC GET_ENTER_KEY						;AN063;SEH
GET_ENTER_KEY PROC NEAR
GEKEY_AGN:
	MOV	AH,0
	INT	16H						;AN000;DT get keystroke
	CMP	AL,13						;AN000;DT If ENTER the continue
	JE	GEKEY_EXIT
	DISPLAY_MESSAGE  11					;AN000;DT BEEP
	JMP	GEKEY_AGN
								;
GEKEY_EXIT:
	RET
GET_ENTER_KEY ENDP
								;
								;
SELECT	ENDS
	END
