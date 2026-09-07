

PAGE 55,132
NAME	SELECT
TITLE	SELECT - DOS - SELECT.EXE
SUBTTL	SELECT7.asm
.ALPHA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	SELECT7.ASM : Copyright 1988 Microsoft
;
;	DATE:	 August 8/87
;
;	COMMENTS: Assemble with MASM 3.0 (using the /A option)
;
;		  Panel flow is defined in the following files:
;
;		      - SELECT1.ASM
;		      ;AN000; SELECT2.ASM
;		      ;AN000; SELECT3.ASM
;		      ;AN000; SELECT4.ASM
;		      ;AN000; SELECT5.ASM
;		      ;AN000; SELECT6.ASM
;
;
;  Module contains code for :
;	- Format the drives
;	- Copy files
;
DATA	SEGMENT BYTE PUBLIC 'DATA'
DATA	ENDS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.XLIST
	INCLUDE    PANEL.MAC
	INCLUDE    SELECT.INC
	INCLUDE    PAN-LIST.INC
	INCLUDE    CASTRUC.INC
	INCLUDE    STRUC.INC
	INCLUDE    MACROS.INC
	INCLUDE    MACROS7.INC
	INCLUDE    EXT.INC
	INCLUDE    VARSTRUC.INC
	INCLUDE    ROUT_EXT.INC
.LIST
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
								;
	EXTRN	DEALLOCATE_HELP:FAR
	EXTRN	DEALLOCATE_BLOCK:FAR
	EXTRN	ALLOCATE_BLOCK:FAR
	EXTRN	DEALLOCATE_MEMORY_CALL:FAR
	EXTRN	ALLOCATE_MEMORY_CALL:FAR
								;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SELECT	SEGMENT PARA PUBLIC 'SELECT'
	ASSUME	CS:SELECT,DS:DATA
								;
	INCLUDE CASEXTRN.INC
								;
	EXTRN	EXIT_SELECT:near
	EXTRN	CREATE_CONFIG_SYS:NEAR
	EXTRN	CREATE_AUTOEXEC_BAT:NEAR
	EXTRN	CREATE_SHELL_BAT:NEAR
								;
	EXTRN	EXIT_DOS:near
	EXTRN	INSTALL_ERROR:near
	EXTRN	EXIT_SELECT:NEAR
	EXTRN	PROCESS_ESC_F3:near
	EXTRN	EXIT_DOS_CONT:NEAR
								;
	PUBLIC	CONTINUE_360
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	CODE CONTINUES.....
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;INSTALL 360KB DISKETTE;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Display copying files from INSTALL diskette
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CONTINUE_360:
							      ;;;
							      ;;;
     .IF < N_DISKETTE_A eq E_DISKETTE_360 > near
								;
	INIT_PQUEUE		PAN_INSTALL_DOS 		;AN000; initialize queue
	PREPARE_PANEL		SUB_COPYING			;AN000; prepare copying from diskette 2 message
	DISPLAY_PANEL
								;
	.IF < MEM_SIZE eq 256 >
	   DEALLOCATE_MEMORY
	.ENDIF
								;
	;;;S_STR120_1 = "a:*.* c:\path /a  parameter for REPLACE
	MERGE_STRING	     S_STR120_1,M_STR120_1,S_A_STARS,S_INSTALL_PATH
	APPEND_STRING	     S_STR120_1,M_STR120_1,S_SLASH_A
								;
;	.IF < I_DESTINATION eq E_ENTIRE_DISK >
;	.THEN
;	   ;;;S_STR120_3 = "a:*.* c:\ /s /r  parameter for REPLACE
;	   COPY_STRING	     S_STR120_3,M_STR120_3,S_REPLACE_PAR1
;	.ELSE
	   ;;;S_STR120_3 = "a:*.* c:\<path> parameter for REPLACE
	   MERGE_STRING      S_STR120_3,M_STR120_3,S_A_STARS,S_INSTALL_PATH
	   APPEND_STRING     S_STR120_3,M_STR120_3,S_SLASH_R
;	.ENDIF
								;
	;;;change attributes of some files so they are not copied
	CHANGE_ATTRIBUTE     HIDE_STARTUP, E_HIDE_STARTUP
								;
	;;;replace files in drive C: with new files on INSTALL diskette
	EXEC_PROGRAM	     S_REPLACE,S_STR120_3,PARM_BLOCK,EXEC_DIR
	.IF c
	  .IF < MEM_SIZE eq 256 >
	     CALL  GET_OVERLAY					;AN000;DT Get panels
	  .ENDIF
	   HANDLE_ERROR        ERR_COPY_DISK, E_RETURN
	   RESTORE_ATTRIBUTE	HIDE_STARTUP,E_HIDE_STARTUP
	.ENDIF
								;
	;;;S_STR120_1 = "a:*.* C:\<path> /A"                    ;
	;;;copy NEW files on INSTALL diskette to install path	 ;
	EXEC_PROGRAM	     S_REPLACE,S_STR120_1,PARM_BLOCK,EXEC_DIR ;AN000; copy new files
	.IF c
	   .IF < MEM_SIZE eq 256 >
	      CALL  GET_OVERLAY 				;AN000;DT Get panels
	   .ENDIF
	   HANDLE_ERROR        ERR_COPY_DISK, E_RETURN
	   RESTORE_ATTRIBUTE	HIDE_STARTUP,E_HIDE_STARTUP
	.ENDIF
								;
	RESTORE_ATTRIBUTE    HIDE_STARTUP,E_HIDE_STARTUP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Prompt the user to remove the INSTALL (source) diskette
;	and insert the OPERATING 1 (source) diskette.
;
;;;;;;;;;;SHELL 360KB DISKETTE;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
								;
	.IF < MEM_SIZE eq 256 >
	   CALL  GET_OVERLAY					;AN000;DT Get panels
	.ENDIF
								;
	;;;insert OPERATING 1 diskette in drive A:		;
	INSERT_DISK	SUB_REM_SELECT_360, S_DOS_UTIL1_DISK
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Display copying files
;
;	NOTE:  The REPLACE command is now issued from the hard disk
;	       (since it is not found on any other disk)
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	INIT_PQUEUE		PAN_INSTALL_DOS 		;AN000; initialize queue
	PREPARE_PANEL		SUB_COPYING			;AN000; prepare copying from diskette 2 message
	DISPLAY_PANEL
								;
	.IF < MEM_SIZE eq 256 >
	   DEALLOCATE_MEMORY
	.ENDIF
								;
	;;;S_STR120_1 = "a:*.* c:\path /a  parameter for REPLACE
	MERGE_STRING	     S_STR120_1,M_STR120_1,S_A_STARS,S_INSTALL_PATH
	APPEND_STRING	     S_STR120_1,M_STR120_1,S_SLASH_A
								;
	COMPARE_STRINGS      S_INSTALL_PATH, S_DEST_DRIVE	;AN000; compare to C:\
	.IF < nc >						;AN000; if the same
	    MERGE_STRING	 S_STR120_2,M_STR120_2,S_INSTALL_PATH,S_REPLACE
	.ELSE
	    MERGE_STRING	 S_STR120_2,M_STR120_2,S_INSTALL_PATH,S_SLASH
	    APPEND_STRING	 S_STR120_2,M_STR120_2,S_REPLACE
	.ENDIF
								;
	;;;replace files in drive C: with new files on OPERATING 1 diskette
	EXEC_PROGRAM	     S_STR120_2,S_STR120_3,PARM_BLOCK,EXEC_DIR
	.IF c
	  .IF < MEM_SIZE eq 256 >
	     CALL  GET_OVERLAY					;AN000;DT Get panels
	  .ENDIF
	   HANDLE_ERROR        ERR_COPY_DISK, E_RETURN
	.ENDIF
								;
	;;;S_STR120_1 = "a:*.* C:\<path> /A"                    ;
	;;;copy NEW files on OPERATING 1 diskette to install path
	EXEC_PROGRAM	     S_STR120_2,S_STR120_1,PARM_BLOCK,EXEC_DIR ;AN000; copy new files
	.IF c
	     .IF < MEM_SIZE eq 256 >
		CALL  GET_OVERLAY				;AN000;DT Get panels
	     .ENDIF
	      HANDLE_ERROR	  ERR_COPY_DISK, E_RETURN
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	insert the OPERATING #2 diskette.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
								;
	.IF < MEM_SIZE eq 256 >
	   CALL  GET_OVERLAY					;AN000;DT Get panels
	.ENDIF
								;
	;;; insert OPERATING #2 diskette in drive A:		;
	INSERT_DISK		SUB_INS_OPER2, S_DOS_UTIL2_DISK
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	  Display copying files from OPERATING #2
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	INIT_PQUEUE		PAN_INSTALL_DOS 		;AN000; initialize queue
	PREPARE_PANEL		SUB_COPYING			;AN000; prepare copying from diskette 1 message
	DISPLAY_PANEL
								;
	.IF < MEM_SIZE eq 256 >
	   DEALLOCATE_MEMORY
	.ENDIF
								;
	;;;replace files in drive C: with new files on OPERATING 2 diskette
	EXEC_PROGRAM	     S_STR120_2,S_STR120_3,PARM_BLOCK,EXEC_DIR
	.IF c
	  .IF < MEM_SIZE eq 256 >
	     CALL  GET_OVERLAY					;AN000;DT Get panels
	  .ENDIF
	   HANDLE_ERROR        ERR_COPY_DISK, E_RETURN
	.ENDIF
								;
	;;;S_STR120_1 = "a:*.* C:\<path> /A "                   ;
	;;;copy NEW files on OPERATING 2 diskette to install path
	EXEC_PROGRAM	     S_STR120_2,S_STR120_1,PARM_BLOCK,EXEC_DIR ;AN000; copy new files
	.IF c
	     .IF < MEM_SIZE eq 256 >
		CALL  GET_OVERLAY				;AN000;DT Get panels
	     .ENDIF
	      HANDLE_ERROR	  ERR_COPY_DISK, E_RETURN
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	insert the OPERATING #3 diskette.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
								;
	.IF < MEM_SIZE eq 256 >
	   CALL  GET_OVERLAY					;AN000;DT Get panels
	.ENDIF
								;
	;;; insert OPERATING #3 diskette in drive A:		;
	INSERT_DISK		SUB_REM_UTIL1_360, S_DOS_UTIL3_DISK
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	  Display copying files from OPERATING #3
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	INIT_PQUEUE		PAN_INSTALL_DOS 		;AN000; initialize queue
	PREPARE_PANEL		SUB_COPYING			;AN000; prepare copying from diskette 1 message
	DISPLAY_PANEL
								;
	.IF < MEM_SIZE eq 256 >
	   DEALLOCATE_MEMORY
	.ENDIF
								;
	;;;replace files in drive C: with new files on OPERATING 2 diskette
	EXEC_PROGRAM	     S_STR120_2,S_STR120_3,PARM_BLOCK,EXEC_DIR
	.IF c
	  .IF < MEM_SIZE eq 256 >
	     CALL  GET_OVERLAY					;AN000;DT Get panels
	  .ENDIF
	   HANDLE_ERROR        ERR_COPY_DISK, E_RETURN
	.ENDIF
								;
	;;;S_STR120_1 = "a:*.* C:\<path> /A "                   ;
	;;;copy NEW files on OPERATING 2 diskette to install path
	EXEC_PROGRAM	     S_STR120_2,S_STR120_1,PARM_BLOCK,EXEC_DIR ;AN000; copy new files
	.IF c
	     .IF < MEM_SIZE eq 256 >
		CALL  GET_OVERLAY				;AN000;DT Get panels
	     .ENDIF
	      HANDLE_ERROR	  ERR_COPY_DISK, E_RETURN
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	insert the SELECT diskette.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
								;
	.IF < MEM_SIZE eq 256 >
	   CALL  GET_OVERLAY					;AN000;DT Get panels
	.ELSE
	   ;;; insert the SELECT diskette in drive A		;
	   INSERT_DISK	SUB_REM_SHELL_360, S_DOS_SEL_360
	.ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	  Display copying files from SELECT diskette
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	INIT_PQUEUE		PAN_INSTALL_DOS 		;AN000; initialize queue
	PREPARE_PANEL		SUB_COPYING			;AN000; prepare copying from diskette 1 message
	DISPLAY_PANEL
								;
	.IF < MEM_SIZE eq 256 >
	   DEALLOCATE_MEMORY
	.ENDIF
								;
	;;;replace files in drive C: with new files on SELECT diskette
	EXEC_PROGRAM	     S_STR120_2,S_STR120_3,PARM_BLOCK,EXEC_DIR
	.IF c
	  .IF < MEM_SIZE eq 256 >
	     CALL  GET_OVERLAY					;AN000;DT Get panels
	  .ENDIF
	   HANDLE_ERROR        ERR_COPY_DISK, E_RETURN
	.ENDIF
								;
	;;;S_STR120_1 = "a:*.* C:\<path> /A "                   ;
	;;;copy new files on SELECT diskette to install path	;
	EXEC_PROGRAM	     S_STR120_2,S_STR120_1,PARM_BLOCK,EXEC_DIR;AN000; copy new files
	.IF c
	     .IF < MEM_SIZE eq 256 >
		CALL  GET_OVERLAY				;AN000;DT Get panels
	     .ENDIF
	      HANDLE_ERROR	  ERR_COPY_DISK, E_RETURN
	.ENDIF
								;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	maybe insert the SHELL diskette.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	.IF < f_shell eq e_shell_yes > near
								;
	.IF < MEM_SIZE eq 256 >
	   CALL  GET_OVERLAY					;AN000;DT Get panels
	.ENDIF
								;
	INSERT_DISK	SUB_INS_MSSHELL_A, S_DOS_SHEL_DISK
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	  Display copying files from SHELL diskette
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	INIT_PQUEUE		PAN_INSTALL_DOS 		;AN000; initialize queue
	PREPARE_PANEL		SUB_COPYING			;AN000; prepare copying from diskette 1 message
	DISPLAY_PANEL
								;
	.IF < MEM_SIZE eq 256 >
	   DEALLOCATE_MEMORY
	.ENDIF
								;
	;;;replace files in drive C: with new files on SHELL diskette
	EXEC_PROGRAM	     S_STR120_2,S_STR120_3,PARM_BLOCK,EXEC_DIR
	.IF c
	  .IF < MEM_SIZE eq 256 >
	     CALL  GET_OVERLAY					;AN000;DT Get panels
	  .ENDIF
	   HANDLE_ERROR        ERR_COPY_DISK, E_RETURN
	.ENDIF
								;
	;;;S_STR120_1 = "a:*.* C:\<path> /A "                   ;
	;;;copy NEW files on SHELL diskette to install path
	EXEC_PROGRAM	     S_STR120_2,S_STR120_1,PARM_BLOCK,EXEC_DIR;AN000; copy new files
	.IF c
	     .IF < MEM_SIZE eq 256 >
		CALL  GET_OVERLAY				;AN000;DT Get panels
	     .ENDIF
	      HANDLE_ERROR	  ERR_COPY_DISK, E_RETURN
	.ENDIF

	.endif  	; optional shell support
								

	;Delete select files from C: drive			;
	COMPARE_STRINGS      S_INSTALL_PATH, S_DEST_DRIVE	;AN007; compare to C:\
	.IF <  nc >						;AN007; if installed to the root
	   MERGE_STRING 	S_STR120_1,M_STR120_1,S_C_DRIVE,S_SELDAT_C
	   ERASE_FILE		S_STR120_1
	   MERGE_STRING 	S_STR120_1,M_STR120_1,S_C_DRIVE,S_SELEXE_C
	   ERASE_FILE		S_STR120_1
	.ELSE near						;AN007; else installed to a directory
	   MERGE_STRING 	S_STR120_1,M_STR120_1,S_INSTALL_PATH,S_SELDAT_C
	   ERASE_FILE		S_STR120_1
	   MERGE_STRING 	S_STR120_1,M_STR120_1,S_INSTALL_PATH,S_SELEXE_C
	   ERASE_FILE		S_STR120_1
	   MERGE_STRING 	S_STR120_1,M_STR120_1,S_INSTALL_PATH,S_AUTOEX_C
	   ERASE_FILE		S_STR120_1
	   MERGE_STRING 	S_STR120_1,M_STR120_1,S_INSTALL_PATH,S_CONSYS_C
	   ERASE_FILE		S_STR120_1
	.ENDIF
								;
     .ENDIF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;360KB;;;;360KB;;;;360KB;;;;360KB;;;;360KB;;;;360KB;;;;360KB;;
;
;			End of 360KB support
;
;	Installation completed.  inform user to reboot
;
;	Search for the installed CONFIG.340 , and
;	we issue a different panel to describe the '.340' files.
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
								;
	.IF < MEM_SIZE eq 256 >
	   ALLOCATE_MEMORY
	   CALL    INITIALIZE					;AN000;DT and read them in
	.ENDIF
								;
	INIT_PQUEUE		PAN_COMPLETE1			;AN000; initialize queue
	.IF < I_DESTINATION ne E_ENTIRE_DISK >
	   PREPARE_PANEL	PAN_PARTIAL
	.ELSE
	   FIND_FILE		   S_CONFIG_REN, E_FILE_ATTR	;AN003;GHG Look for '.340' files
	   .IF < c >
	      PREPARE_PANEL	   SUB_COMP_VER 		;AN003;GHG prepare DOS install message
	   .ELSE
	      PREPARE_PANEL	   SUB_COMP_REP 		;AN003;GHG prepare DOS Replace message
	   .ENDIF
	.ENDIF
								;
	PREPARE_PANEL		SUB_COMP_KYS_1
	DISPLAY_PANEL
	SAVE_PANEL_LIST
								;
	GET_FUNCTION		FK_REBOOT			;AN000; User has to reboot
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
PUBLIC GET_OVERLAY
GET_OVERLAY	PROC NEAR
	   .IF < N_DISKETTE_A ne E_DISKETTE_720 >		;AN063;SEH
	       CLEAR_SCREEN
	       DISPLAY_MESSAGE 12				;AN000;DT Insert SELECT diskette
	       .REPEAT
		   GET_FUNCTION 	   FK_ENT		;AN000; get user entered function
		   FIND_FILE		S_DOS_SEL_360, E_FILE_ATTR
		   .LEAVE < nc >
			DISPLAY_MESSAGE 11			;AN000;DT Beep
	       .UNTIL
	   .ENDIF						;AN063;SEH
	   ALLOCATE_MEMORY
	   CALL    INITIALIZE					;AN000;DT and read them in
	   RET
GET_OVERLAY	ENDP
								;
SELECT	ENDS
	END
