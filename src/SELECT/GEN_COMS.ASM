PAGE	55,132
NAME	SELECT
TITLE	SELECT - SELECT.EXE
SUBTTL	GEN_COMS
.ALPHA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	GEN_COMS.ASM : Copyright 1988 Microsoft
;
;	DATE:	 August 8/87
;
;	COMMENTS: Assemble with MASM 3.0 (using the -A option)
;
;	Module contains code for :
;		- creation of AUTOEXEC file
;		- creation of CONFIG file
;		- creation of DOSSHELL.BAT
;
;
;	 DATA SEGMENT
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DATA	SEGMENT BYTE PUBLIC 'DATA'
								;
SC_CD		DW	MC_CD
PC_CD		DB	'@CD '
MC_CD		EQU	$ - PC_CD
								;
SC_BREAK	DW	MC_BREAK
PC_BREAK	DB	'BREAK='
MC_BREAK	EQU	$ - PC_BREAK
								;
SC_CPSW 	DW	MC_CPSW
PC_CPSW 	DB	'CPSW='
MC_CPSW 	EQU	$ - PC_CPSW
								;
SC_VERIFY	DW	MC_VERIFY
PC_VERIFY	DB	'VERIFY '
MC_VERIFY	EQU	$ - PC_VERIFY
								;
SC_COUNTRY	DW	MC_COUNTRY
PC_COUNTRY	DB	'COUNTRY='
MC_COUNTRY	EQU	$ - PC_COUNTRY
								;
SC_COUNTRY_SYS	DW	MC_COUNTRY_SYS
PC_COUNTRY_SYS	DB	'COUNTRY.SYS'
MC_COUNTRY_SYS	EQU	$ - PC_COUNTRY_SYS
								;
SC_BUFFERS	DW	MC_BUFFERS
PC_BUFFERS	DB	'BUFFERS='
MC_BUFFERS	EQU	$ - PC_BUFFERS
								;
SC_SLASH_X	DW	MC_SLASH_X				;AC046;SEH changed from /E
PC_SLASH_X	DB	' /X'                                   ;AC046;SEH
MC_SLASH_X	EQU $ - PC_SLASH_X				;AC046;SEH
								;
SC_FCBS 	DW	MC_FCBS
PC_FCBS 	DB	'FCBS='
MC_FCBS 	EQU	$ - PC_FCBS
								;
SC_FILES	DW	MC_FILES
PC_FILES	DB	'FILES='
MC_FILES	EQU	$ - PC_FILES
								;
SC_LASTDRIVE	DW	MC_LASTDRIVE
PC_LASTDRIVE	DB	'LASTDRIVE='
MC_LASTDRIVE	EQU	$ - PC_LASTDRIVE
								;
SC_STACKS	DW	MC_STACKS
PC_STACKS	DB	'STACKS='
MC_STACKS	EQU	$ - PC_STACKS
								;
SC_SHELL	DW	MC_SHELL
PC_SHELL	DB	'SHELL='
MC_SHELL	EQU	$ - PC_SHELL
								;
SC_SHELL_1	DW	MC_SHELL_1
PC_SHELL_1	DB	'COMMAND.COM'                           ;AC037; SEH  Split the original SC_SHELL_1 into
MC_SHELL_1	EQU	$ - PC_SHELL_1				;AC037; SEH    3 parts
								;
SC_SHELL_2	DW	MC_SHELL_2				;AN037; SEH  Used for diskettes only
PC_SHELL_2	DB	' /MSG'                                 ;AN037; SEH
MC_SHELL_2	EQU	$ - PC_SHELL_2				;AN037; SEH
								;
SC_SHELL_3	DW	MC_SHELL_3				;AN037; SEH  Use for diskettes and hardfile
PC_SHELL_3	DB	' /P /E:256  '                          ;AN037; SEH  Two spaces required for CR and LF
MC_SHELL_3	EQU	$ - PC_SHELL_3 - 2			;AN037; SEH
								;
SC_DEVICE	DW	MC_DEVICE
PC_DEVICE	DB	'DEVICE='
MC_DEVICE	EQU	$ - PC_DEVICE
								;
SC_XMAEM_SYS	DW	MC_XMAEM_SYS
PC_XMAEM_SYS	DB	'XMAEM.SYS '
MC_XMAEM_SYS	EQU	$ - PC_XMAEM_SYS
								;
SC_XMA2EMS_SYS	DW	MC_XMA2EMS_SYS
PC_XMA2EMS_SYS	DB	'XMA2EMS.SYS '
MC_XMA2EMS_SYS	EQU	$ - PC_XMA2EMS_SYS
								;
SC_ANSI_SYS	DW	MC_ANSI_SYS
PC_ANSI_SYS	DB	'ANSI.SYS '
MC_ANSI_SYS	EQU	$ - PC_ANSI_SYS
								;
SC_VDISK_SYS	DW	MC_VDISK_SYS
PC_VDISK_SYS	DB	'RAMDRIVE.SYS '
MC_VDISK_SYS	EQU	$ - PC_VDISK_SYS
								;
SC_DISPLAY_SYS	DW	MC_DISPLAY_SYS
PC_DISPLAY_SYS	DB	'DISPLAY.SYS CON=('
MC_DISPLAY_SYS	EQU	$ - PC_DISPLAY_SYS
								;
		PUBLIC	SC_DISPLAY_EGA
SC_DISPLAY_EGA	DW	MC_DISPLAY_EGA
PC_DISPLAY_EGA	DB	'EGA.CPI)'
MC_DISPLAY_EGA	EQU	$ - PC_DISPLAY_EGA
								;
		PUBLIC	SD_DISPLAY_EGA
SD_DISPLAY_EGA	DW	MD_DISPLAY_EGA
PD_DISPLAY_EGA	DB	'EGA'
MD_DISPLAY_EGA	EQU	$ - PD_DISPLAY_EGA
								;
		PUBLIC	SC_DISPLAY_LCD
SC_DISPLAY_LCD	DW	MC_DISPLAY_LCD
PC_DISPLAY_LCD	DB	'LCD.CPI)'
MC_DISPLAY_LCD	EQU	$ - PC_DISPLAY_LCD
								;
		PUBLIC	SD_DISPLAY_LCD
SD_DISPLAY_LCD	DW	MD_DISPLAY_LCD
PD_DISPLAY_LCD	DB	'LCD'
MD_DISPLAY_LCD	EQU	$ - PD_DISPLAY_LCD
								;
SC_PRINTER_SYS	DW	MC_PRINTER_SYS
PC_PRINTER_SYS	DB	'PRINTER.SYS '
MC_PRINTER_SYS	EQU	$ - PC_PRINTER_SYS
								;
SC_LPT		DW	MC_LPT
PC_LPT		DB	'LPT'
MC_LPT		EQU	$ - PC_LPT
								;
SC_COM		DW	MC_COM					;AN011; SEH
PC_COM		DB	'COM'                                   ;AN011; SEH
MC_COM		EQU	$ - PC_COM				;AN011; SEH
								;
SC_EQUAL_OPEN	DW	MC_EQUAL_OPEN
PC_EQUAL_OPEN	DB	'=('
MC_EQUAL_OPEN	EQU	$ - PC_EQUAL_OPEN
								;
SC_437		DW	MC_437
PC_437		DB	',437,'
MC_437		EQU	$ - PC_437
								;
SC_COMMA	DW	MC_COMMA
PC_COMMA	DB	','
MC_COMMA	EQU	$ - PC_COMMA
								;
SC_INSTALL	DW	MC_INSTALL
PC_INSTALL	DB	'INSTALL='
MC_INSTALL	EQU	$ - PC_INSTALL
								;
SC_KEYB_C	DW	MC_KEYB_C
PC_KEYB_C	DB	'KEYB.COM '
MC_KEYB_C	EQU	$ - PC_KEYB_C
								;
SC_KEYBOARD_SYS DW	MC_KEYBOARD_SYS
PC_KEYBOARD_SYS DB	'KEYBOARD.SYS'
MC_KEYBOARD_SYS EQU	$ - PC_KEYBOARD_SYS
								;
SC_KEYB_SWITCH	DW	MC_KEYB_SWITCH
PC_KEYB_SWITCH	DB	' /ID:'
MC_KEYB_SWITCH	EQU	$ - PC_KEYB_SWITCH
								;
SC_SHARE	DW	MC_SHARE
PC_SHARE	DB	'SHARE.EXE '
MC_SHARE	EQU	$ - PC_SHARE
								;
SC_FASTOPEN	DW	MC_FASTOPEN
PC_FASTOPEN	DB	'FASTOPEN.EXE '
MC_FASTOPEN	EQU	$ - PC_FASTOPEN
								;
SC_NLSFUNC	DW	MC_NLSFUNC
PC_NLSFUNC	DB	'NLSFUNC.EXE '
MC_NLSFUNC	EQU	$ - PC_NLSFUNC
								;
SC_ECHO 	DW	MC_ECHO
PC_ECHO 	DB	'@ECHO OFF  '                           ;AN000;  TWO SPACES REQUIRED FOR CR,LF
MC_ECHO 	EQU	$ - PC_ECHO - 2
								;
SC_PATH 	DW	MC_PATH
PC_PATH 	DB	'PATH '
MC_PATH 	EQU	$ - PC_PATH
								;
SC_APPEND	DW	MC_APPEND
PC_APPEND	DB	'APPEND '
MC_APPEND	EQU	$ - PC_APPEND
								;
SC_PROMPT	DW	MC_PROMPT
PC_PROMPT	DB	'PROMPT '
MC_PROMPT	EQU	$ - PC_PROMPT
								;
SC_SET_COMSPEC	DW	MC_SET_COMSPEC
PC_SET_COMSPEC	DB	'SET COMSPEC='
MC_SET_COMSPEC	EQU	$ - PC_SET_COMSPEC
								;
SC_COMMAND_COM	DW	MC_COMMAND_COM
PC_COMMAND_COM	DB	'COMMAND.COM'
MC_COMMAND_COM	EQU	$ - PC_COMMAND_COM
								;
SC_GRAPHICS	DW	MC_GRAPHICS
PC_GRAPHICS	DB	'GRAPHICS '
MC_GRAPHICS	EQU	$ - PC_GRAPHICS
								;
SC_GRAFTABL	DW	MC_GRAFTABL
PC_GRAFTABL	DB	'GRAFTABL '
MC_GRAFTABL	EQU	$ - PC_GRAFTABL
								;
;SC_DATE	 DW	 MC_DATE				;
;PC_DATE	 DB	 'DATE  '                               ;  TWO SPACES REQUIRED FOR CR,LF
;MC_DATE	 EQU	 $ - PC_DATE - 2			;
								;
;SC_TIME	 DW	 MC_TIME				;
;PC_TIME	 DB	 'TIME  '                               ;  TWO SPACES REQUIRED FOR CR,LF
;MC_TIME	 EQU	 $ - PC_TIME - 2			;
								;
SC_VER		DW	MC_VER
PC_VER		DB	'VER  '                                 ;AN000;  TWO SPACES REQUIRED FOR CR,LF
MC_VER		EQU	$ - PC_VER - 2
								;
SC_MODE_CON	DW	MC_MODE_CON
PC_MODE_CON	DB	'MODE CON CP PREP=(('
MC_MODE_CON	EQU	$ - PC_MODE_CON
								;
SC_MODE_COM	DW	MC_MODE_COM
PC_MODE_COM	DB	'MODE COM'
MC_MODE_COM	EQU	$ - PC_MODE_COM
								;
SC_MODE_LPT	DW	MC_MODE_LPT
PC_MODE_LPT	DB	'MODE LPT'
MC_MODE_LPT	EQU	$ - PC_MODE_LPT
								;
SC_EQUAL_COM	DW	MC_EQUAL_COM
PC_EQUAL_COM	DB	'=COM'
MC_EQUAL_COM	EQU	$ - PC_EQUAL_COM
								;
SC_PREPARE	DW	MC_PREPARE
PC_PREPARE	DB	' CP PREP=(('
MC_PREPARE	EQU	$ - PC_PREPARE
								;
SC_CLOSE_BRAC	DW	MC_CLOSE_BRAC
PC_CLOSE_BRAC	DB	') '
MC_CLOSE_BRAC	EQU	$ - PC_CLOSE_BRAC
								;
SC_KEYB_A	DW	MC_KEYB_A
PC_KEYB_A	DB	'KEYB '
MC_KEYB_A	EQU	$ - PC_KEYB_A
								;
SC_COMMAS	DW	MC_COMMAS
PC_COMMAS	DB	',,'
MC_COMMAS	EQU	$ - PC_COMMAS
								;
SC_CHCP 	DW	MC_CHCP
PC_CHCP 	DB	'CHCP '
MC_CHCP 	EQU	$ - PC_CHCP
								;
SC_DRIVE_C	DW	MC_DRIVE_C
PC_DRIVE_C	DB	'@C:  '
MC_DRIVE_C	EQU	$ - PC_DRIVE_C - 2
								;
SC_SHELLC_1	DW	MC_SHELLC_1
PC_SHELLC_1	DB	'@SHELLB DOSSHELL',E_CR,E_LF            ;AC019;SEH
		DB	'@IF ERRORLEVEL 255 GOTO END',E_CR,E_LF
		DB	':COMMON  '
MC_SHELLC_1	EQU	$ - PC_SHELLC_1 - 2			;AN000; 2 SPACES FOR ASCII-Z CONVERSION
								;
SC_SHELLC_2	DW	MC_SHELLC_2
PC_SHELLC_2	DB	':END  '
MC_SHELLC_2	EQU	$ - PC_SHELLC_2 - 2
								;
SC_SHELLC	DW	MC_SHELLC
PC_SHELLC	DB	'@SHELLC '
MC_SHELLC	EQU	$ - PC_SHELLC
								;
SC_SHELLP	DW	MC_SHELLP
PC_SHELLP	DB	'DOSSHELL  '                            ;AC019;SEH
MC_SHELLP	EQU	$ - PC_SHELLP - 2
								;
SC_PRINT_COM	DW	MC_PRINT_COM
PC_PRINT_COM	DB	'PRINT /D:'                             ;AC011; SEH
MC_PRINT_COM	EQU	$ - PC_PRINT_COM			;AN011; SEH
								;
SC_AT_SIGN	DW	MC_AT_SIGN
PC_AT_SIGN	DB	'@'
MC_AT_SIGN	EQU	$ - PC_AT_SIGN
								;
S_DOS_PATH	DW	M_DOS_PATH
P_DOS_PATH	DB	50 DUP(?)
M_DOS_PATH	EQU	$ - P_DOS_PATH
								;
DATA		ENDS						;AN000;DATA
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	INCLUDE EXT.INC
	INCLUDE STRUC.INC
	INCLUDE MACROS.INC
	INCLUDE ROUT_EXT.INC
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SELECT	SEGMENT PARA PUBLIC 'SELECT'                            ;AN000;segment for far routine
	ASSUME	CS:SELECT,DS:DATA
								;
	PUBLIC	CREATE_CONFIG_SYS
	PUBLIC	CREATE_AUTOEXEC_BAT
	PUBLIC	CREATE_SHELL_BAT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Create AUTOEXEC.BAT file
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CREATE_AUTOEXEC_BAT	PROC
								;
	;;;install to B:, install path	= null			;
	;;;install to root of C:, install path = c:\		;
	;;;install to directory in C:, install path = c:\path\	;
	.IF < I_DEST_DRIVE eq E_DEST_DRIVE_B >			;AN000; if install to drive B:
	.THEN
	   INIT_VAR		S_DOS_PATH,0			;AN000;    set path = null
	.ELSE							;AN000; else
	   COPY_STRING		S_DOS_PATH,M_DOS_PATH,S_INSTALL_PATH;AN000;set path = user defined path
	   .IF < S_DOS_PATH gt M_DEST_DRIVE >			;AN000;   if install is not to root of drive C:
	   .THEN
	      APPEND_STRING	S_DOS_PATH,M_DOS_PATH,S_SLASH	;AN000;      append back slash
	   .ENDIF
	.ENDIF
								;
	;;;write @ECHO OFF					;
	WRITE_LINE		SC_ECHO 			;AN000; write ECHO OFF command
								;
	;;;write SET COMSPEC=<path>\COMMAND.COM 		;
	.IF < I_DEST_DRIVE ne E_DEST_DRIVE_C >			;AC043;SEH COMSPEC formerly after PROMPT ;AN111; if install destination is drive B: or A: JW
	   MERGE_STRING 	   SC_LINE,MC_LINE,SC_SET_COMSPEC,S_DRIVE_A  ;AC043;SEH
	.ELSE							;AC043;SEH
	   MERGE_STRING 	   SC_LINE,MC_LINE,SC_SET_COMSPEC,S_DOS_PATH	 ;AC043;SEH
	.ENDIF							;AC043;SEH
	APPEND_STRING		SC_LINE,MC_LINE, SC_COMMAND_COM ;AC043;SEH
	WRITE_LINE		SC_LINE 			;AC043;SEH ;AN000; write SET COMSPEC command
								;
	;;;write VERIFY <parameter>				;
	.IF < S_VERIFY gt 0 >					;AN000; if field length > zero
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,SC_VERIFY,S_VERIFY
	   WRITE_LINE		SC_LINE 			;AN000;    write VERIFY command
	.ENDIF
								;
	;;;write PATH <parameter>				;
	.IF < F_PATH eq E_PATH_YES > and			;AN000; if PATH command required
	.IF < S_PATH gt 0 >					;AN000; and field length > zero
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,SC_PATH, S_PATH
	   WRITE_LINE		SC_LINE 			;AN000;    write PATH command
	.ENDIF
								;
	;;;write APPEND <parameter>
	;;;write APPEND <path>					;
	.IF < F_APPEND eq E_APPEND_YES >			;AN000; if APPEND command required
	   .IF < S_APPEND_P gt 0 >				;AN000; and field length > zero    JW
	   .THEN
	      MERGE_STRING	   SC_LINE,MC_LINE,SC_APPEND,S_APPEND_P
	      WRITE_LINE	   SC_LINE			;AN000;    write APPEND command    JW
	   .ENDIF
	   .IF < S_APPEND gt 0 >				;AN000; and field length > zero
	   .THEN
	      MERGE_STRING	   SC_LINE,MC_LINE,SC_APPEND,S_APPEND
	      WRITE_LINE	   SC_LINE			;AN000;    write APPEND command
	   .ENDIF
	.ENDIF
								;
	;;;write PROMPT <parameter>				;
	.IF < F_PROMPT eq E_PROMPT_YES > and			;AN000; if PROMPT command required
	.IF < S_PROMPT gt 0 >					;AN000; and field length > zero
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,SC_PROMPT,S_PROMPT
	   WRITE_LINE		SC_LINE 			;AN000;    write PROMPT command
	.ENDIF
								;
	;;;write <path>\GRAPHICS <parameter>			;
	.IF < F_GRAPHICS eq E_GRAPHICS_YES >			;AN000; if GRAPHICS command is to be included
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,S_DOS_PATH,SC_GRAPHICS
	   APPEND_STRING	SC_LINE, MC_LINE, S_GRAPHICS
	   WRITE_LINE		SC_LINE 			;AN000;    write GRAPHICS command
	.ENDIF
								;
	;;;init S_STR120_1 to primary code page 		;
	;;;init S_STR120_2 to secondary code page		;
	WORD_TO_CHAR		N_CP_PRI, S_STR120_1		;AN000; primary code page in ASCII-N format
	WORD_TO_CHAR		N_CP_SEC, S_STR120_2		;AN000; secondary code page in ASCII-N format
								;
	;;;write <path>\GRAFTABL <primary code page>		;
	.IF < F_GRAFTABL eq E_GRAFTABL_YES >			;AN000; if GRAFTABL command required
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,S_DOS_PATH,SC_GRAFTABL
	   APPEND_STRING	SC_LINE, MC_LINE, S_STR120_1
	   WRITE_LINE		SC_LINE 			;AN000;    write GRAFTABL command
	.ENDIF
								;
	;;;write VER						;
	WRITE_LINE		SC_VER				;AN000; write VER command
								;
	;;;S_STR120_1 = primary code page			;
	;;;S_STR120_2 = secondary code apge			;
	;;;init S_STR120_3 to code page list			;
	INIT_VAR	     S_STR120_3, 0
	.IF < N_CP_PRI eq 0 > or				;AN000;   if primary code page is 0 or 437
	.IF < N_CP_PRI eq 437 >
	.THEN							;AN000;      no action
	.ELSE							;AN000;   else
	   APPEND_STRING	S_STR120_3,M_STR120_3,S_STR120_1;AN000;      append code page to cp list
	.ENDIF
								;
	.IF < N_CP_SEC eq 0 > or				;AN000;   if secondary code page is 0 or 437
	.IF < N_CP_SEC eq 437 >
	.THEN							;AN000;      no action
	.ELSE							;AN000;   else
	   .IF < S_STR120_3 ne 0 >				;AN000;      if primary code page is in cp list
	   .THEN
	      APPEND_STRING	S_STR120_3, M_STR120_3, S_SPACE ;AN000; 	append space to cp list
	   .ENDIF
	   APPEND_STRING	S_STR120_3,M_STR120_3,S_STR120_2;AN000;      append code page to cp list
	.ENDIF
								;
	;;;S_STR120_3 = code page list				;
	;;;write MODE CON CODEPAGE PREPARE ((<cp list>) <path>\<display>.CPI
	.IF < F_CPSW eq E_CPSW_YES > near			;AN000; if code page switching required
	.THEN
	   .IF < S_STR120_3 ne 0 > near 			;AN000;   if primary/secondary code pages are not 0 or 437
	   .THEN
	      MERGE_STRING	SC_LINE,MC_LINE,SC_MODE_CON,S_STR120_3
	      APPEND_STRING	SC_LINE, MC_LINE, SC_CLOSE_BRAC ;AN000;      append close bracket
	      APPEND_STRING	SC_LINE, MC_LINE,S_DOS_PATH	;AN000;      append path
	      .IF < ACTIVE eq EGA > or				;AN000;      if EGA adaptor
	      .IF < ALTERNATE eq EGA >
	      .THEN
		 APPEND_STRING	SC_LINE, MC_LINE, SC_DISPLAY_EGA;AN000; 	append	EGA.CPI)
	      .ELSEIF < ACTIVE eq LCD > or			;AN000;      if LCD adaptor
	      .IF < ALTERNATE eq LCD >
	      .THEN
		 APPEND_STRING	SC_LINE, MC_LINE, SC_DISPLAY_LCD;AN000; 	append LCD.CPI)
	      .ENDIF
	      WRITE_LINE	SC_LINE 			;AN000;      write MODE CON CODEPAGE command
	   .ENDIF
	.ENDIF
								;
	;;;S_STR120_3 = cp list 				;
	;;;write MODE LPT1 CODEPAGE PREPARE=((<cp list>) <path>\<cp paramaeters.CPI>)
	;;;write MODE LPT2 CODEPAGE PREPARE=((<cp list>) <path>\<cp paramaeters.CPI>)
	;;;write MODE LPT3 CODEPAGE PREPARE=((<cp list>) <path>\<cp paramaeters.CPI>)
	;;;N_WORD_1 = parallel port number			;
	INIT_VAR		N_WORD_1, 1			;AN000; set port number = 1
	.IF < F_CPSW eq E_CPSW_YES > near			;AN000; if code page switching required
	.THEN
	   .REPEAT						;AN000;    repeat code block
	      GET_PRINTER_PARAMS 0, N_WORD_1, N_RETCODE 	;AN000;       get printer parameters
	      .IF < N_RETCODE eq 1 > and near			;AN000;       if valid return
	      .IF < N_PRINTER_TYPE eq E_PARALLEL > and near	;AN000; 	 and parallel printer
	      .IF < S_CP_DRIVER gt 0 > and near 		;AN000; 	 and driver and prepare
	      .IF < S_CP_PREPARE gt 0 > near			;AN000; 	 parameters valid
	      .THEN
		 COPY_STRING	SC_LINE, MC_LINE, SC_MODE_LPT	;AN000; 	 append MODE LPT
		 WORD_TO_CHAR	N_WORD_1, S_STR120_2
		 APPEND_STRING	SC_LINE, MC_LINE, S_STR120_2	;AN000; 	 append lpt number
		 APPEND_STRING	SC_LINE, MC_LINE, SC_PREPARE	;AN000; 	 append CODEPAGE PREPARE
		 APPEND_STRING	SC_LINE, MC_LINE, S_STR120_3	;AN000; 	 append cp list
		 APPEND_STRING	SC_LINE, MC_LINE, SC_CLOSE_BRAC ;AN000; 	 append close bracket
		 APPEND_STRING	SC_LINE, MC_LINE, S_DOS_PATH	;AN000; 	 append path
		 APPEND_STRING	SC_LINE, MC_LINE, S_CP_PREPARE	;AN000; 	 append driver parameters
		 APPEND_STRING	SC_LINE, MC_LINE, SC_CLOSE_BRAC ;AN000; 	 append close bracket
		 WRITE_LINE	SC_LINE 			;AN000;    write PRINTER.SYS command
	      .ENDIF
	      INC_VAR		N_WORD_1			;AN000;       inc printer number
	   .UNTIL < N_WORD_1 gt 3 > near			;AN000;    end of repeat block
	.ENDIF
								;
	;;;write serial printer parameters and redirection command
	;;;write MODE COMx:<parameter>				;
	;;;write MODE LPTy=COMx 				;
	;;;N_WORD_1 = serial port number			;
	INIT_VAR		N_WORD_1, 4			;AN000; set port number = 4
	INIT_VAR		N_WORD_2, 1			;AN000; set serial port number = 1
	.REPEAT 						;AN000; repeat code block
	   GET_PRINTER_PARAMS 0, N_WORD_1, N_RETCODE		;AN000;    get printer parameters
	   .IF < N_RETCODE eq 1 > and near			;AN000;    if valid return
	   .IF < N_PRINTER_TYPE eq E_SERIAL > and near		;AN000;       and serial printer
	   .IF < S_MODE_PARM gt 0 > near			;AN000;       and mode parameters present
	   .THEN
	      COPY_STRING	SC_LINE, MC_LINE, SC_MODE_COM	;AN000;       append MODE COM
	      WORD_TO_CHAR	N_WORD_2, S_STR120_3		;AN000;       S_STR120_3 = serial port number
	      APPEND_STRING	SC_LINE, MC_LINE, S_STR120_3	;AN000;       append serial port number
	      APPEND_STRING	SC_LINE, MC_LINE, S_COLON	;AN000;       append colon
	      APPEND_STRING	SC_LINE, MC_LINE, S_MODE_PARM	;AN000;       append mode parameters
	      WRITE_LINE	SC_LINE 			;AN000;       write MODE COMx command
	      .IF < I_REDIRECT gt 1 >				;AN000;       if printer redirection
	      .THEN
		 COPY_STRING	SC_LINE,MC_LINE,SC_MODE_LPT	;AN000; 	 append MODE LPT
		 DEC_VAR	I_REDIRECT			;AN000; 	 first item in list is 'None'
		 WORD_TO_CHAR	I_REDIRECT, S_STR120_2		;AN000; 	 convert LPT no to chars
		 APPEND_STRING	SC_LINE,MC_LINE,S_STR120_2	;AN000; 	 append parallel port
		 APPEND_STRING	SC_LINE,MC_LINE,SC_EQUAL_COM	;AN000; 	 append =COM
		 APPEND_STRING	SC_LINE,MC_LINE,S_STR120_3	;AN000; 	 append serial port number
		 WRITE_LINE	SC_LINE 			;AN000; 	 write MODE LPTx=COMy command
	      .ENDIF
	   .ENDIF
	   INC_VAR		N_WORD_1			;AN000;    inc printer number
	   INC_VAR		N_WORD_2			;AN000;    inc serial port number
	.UNTIL < N_WORD_1 gt 7 > near				;AN000; end of repeat block
								;
	;;;write KEYB <keyboard>,,<path>\KEYBOARD.SYS		;
	.IF < N_KYBD_VAL eq E_KYBD_VAL_YES > near		;AN000;    if kybd id is valid
	.THEN
	   COPY_STRING	     SC_LINE, MC_LINE, SC_KEYB_A	;AN000;       copy KEYB
	   APPEND_STRING     SC_LINE, MC_LINE, S_KEYBOARD	;AN000;       append kybd id
	   APPEND_STRING     SC_LINE, MC_LINE, SC_COMMAS	;AN000;       append ,,
	   APPEND_STRING     SC_LINE,MC_LINE, S_DOS_PATH	;AN000;       append install path
	   APPEND_STRING     SC_LINE,MC_LINE,SC_KEYBOARD_SYS	;AN000;       append \KEYBOARD.SYS
	   .IF < N_KYBD_ALT ne E_KYBD_ALT_NO > and		;AN002;       if alternate keyboard valid	 JW
	   .IF < I_KYBD_ALT eq 2 >				;AN002;       and not default setting		 JW
	   .THEN
	      APPEND_STRING	SC_LINE, MC_LINE,SC_KEYB_SWITCH ;AN002;       append keyb id switch '/ID:'       JW
	      APPEND_STRING	SC_LINE, MC_LINE, S_KYBD_ALT	;AN002;       append alternate keyboard id	 JW
	      APPEND_STRING	SC_LINE, MC_LINE, S_SPACE	;AN090;JPW add space so last char not overwritten
	   .ENDIF
	   WRITE_LINE	     SC_LINE				;AN000;       write KEYB command
	.ENDIF
								;
	;;;write CHCP <primary code page>			;
	.IF < F_CPSW eq E_CPSW_YES >				;AN000; if code page switching required
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,SC_CHCP,S_STR120_1
	   WRITE_LINE		SC_LINE 			;AN000;    write CHCP command
	.ENDIF
								;
	;;;write 'PRINT /D:LPTx' or 'PRINT /D:COMx'             ;AC066;SEH moved print stmt.  NOTE: PRINT AND SHELL STMTS MUST BE LAST IN AUTOEXEC.BAT
	.IF < I_WORKSPACE ne E_WORKSPACE_MIN > and near 	;AC066;SEH ;AN011; SEH
	.IF < I_DEST_DRIVE eq E_DEST_DRIVE_C > and near 	;AC066;SEH ;AN015; JW	 If install to fixed disk
	.IF < N_NUMPRINT gt 0 > near				;AC066;SEH ;AN011; SEH
	.THEN							;AC066;SEH ;AN011; SEH
	   GET_PRINTER_PARAMS	1, 0, N_RETCODE 		;AC066;SEH ;AN011; SEH	 get parameters for 1st printer selected
	   .IF < N_RETCODE ne 0 > near				;AC066;SEH ;AN011; SEH	 if valid return
	   .THEN						;AC066;SEH ;AN011; SEH
	      .IF < N_PRINTER_TYPE eq E_PARALLEL >		;AC066;SEH ;AN011; SEH	 LPT1, LPT2 or LPT3
	      .THEN						;AC066;SEH ;AN011; SEH
		 MERGE_STRING	SC_LINE, MC_LINE, SC_PRINT_COM, SC_LPT;AC066;SEH ;AN011; SEH   'PRINT /D:LPT'
		 COPY_WORD	N_WORD_1, I_PORT		;AC066;SEH ;AN011; SEH	 get LPT number (1-3)
	      .ELSE						;AC066;SEH ;AN011; SEH	 serial printer
		 .IF < I_REDIRECT gt 1 >			;AC066;SEH ;AN011; SEH	 check if redirected to LPT
		 .THEN						;AC066;SEH ;AN011; SEH
		    MERGE_STRING   SC_LINE, MC_LINE, SC_PRINT_COM, SC_LPT  ;AC066;SEH ;AN011; SEH   'PRINT /D:LPT'
		    COPY_WORD	N_WORD_1, I_REDIRECT		;AC066;SEH ;AN011; SEH	 gives LPT printer redirected to ---
		    DEC 	N_WORD_1			;AC066;SEH ;AN011; SEH	 but must subtract off value 'none' to get port#
		 .ELSE						;AC066;SEH ;AN011; SEH	 serial port that hasn't been redirected
		    MERGE_STRING   SC_LINE, MC_LINE, SC_PRINT_COM, SC_COM  ;AC066;SEH ;AN011; SEH   'PRINT /D:COM'
		    COPY_WORD	N_WORD_1, I_PORT		;AC066;SEH ;AN011; SEH	 value of COM port
		 .ENDIF 					;AC066;SEH ;AN011; SEH
	      .ENDIF						;AC066;SEH ;AN011; SEH
	      WORD_TO_CHAR	N_WORD_1, S_STR120_3		;AC066;SEH ;AN011; SEH
	      APPEND_STRING	SC_LINE, MC_LINE, S_STR120_3	;AC066;SEH ;AN011; SEH	 add on the com or lpt number to the string
	      WRITE_LINE	SC_LINE 			;AC066;SEH ;AN011; SEH	 write 'PRINT /D:LPTx' or 'PRINT /D:COMx'  x=number
	   .ENDIF						;AC066;SEH ;AN011; SEH
	.ENDIF							;AC066;SEH ;AN011; SEH
								;
	;;;write SHELL <parameter>				;
	.IF < N_DEST eq E_DEST_SHELL > and			;AN000; if preparing for SHELL diskette
	.IF < F_SHELL eq E_SHELL_YES >				;AN000; if SHELL support required
	.THEN
	   WRITE_LINE		SC_SHELLP
	.ENDIF
								;
	RET
CREATE_AUTOEXEC_BAT	ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Create CONFIG.SYS file
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CREATE_CONFIG_SYS	PROC
								;
	;;;install to B:, install path	= null			;
	;;;install to root of C:, install path = c:\		;
	;;;install to directory in C:, install path = c:\path\	;
	.IF < I_DEST_DRIVE eq E_DEST_DRIVE_B >			;AN000; if install to drive B:
	.THEN
	   INIT_VAR		S_DOS_PATH,0			;AN000;    set path = null
	.ELSE							;AN000; else
	   COPY_STRING		S_DOS_PATH,M_DOS_PATH,S_INSTALL_PATH;AN000;set path = user defined path
	   .IF < S_DOS_PATH gt M_DEST_DRIVE >			;AN000;    if install is not under root of C:
	   .THEN
	      APPEND_STRING	S_DOS_PATH,M_DOS_PATH,S_SLASH	;AN000;       append back slash to path
	   .ENDIF
	.ENDIF
								;
	;;;write BREAK=<parameter>				;
	.IF < S_BREAK gt 0 >					;AN000; if field length > zero
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,SC_BREAK,S_BREAK
	   WRITE_LINE		SC_LINE 			;AN000;    write BREAK command
	.ENDIF
								;
	;;;write COUNTRY=<country>,,<path>\COUNTRY.SYS		;
	.IF < N_COUNTRY eq 1 >					;AN000; if country is US (001)
	.THEN							;AN000;    no action
	.ELSE							;AN000; else
	   WORD_TO_CHAR 	N_COUNTRY, S_STR120_1		;AN000;    S_STR120_1 = country in ASCII
	   MERGE_STRING 	SC_LINE,MC_LINE,SC_COUNTRY,S_STR120_1
	   APPEND_STRING	SC_LINE, MC_LINE, SC_COMMAS
	   APPEND_STRING	SC_LINE, MC_LINE,S_DOS_PATH
	   APPEND_STRING	SC_LINE, MC_LINE,SC_COUNTRY_SYS
	   WRITE_LINE		SC_LINE 			;AN000;    write COUNTRY command
	.ENDIF
								;
	;;;write BUFFERS=<parameter>				;
	;;;write BUFFERS=<parameter> /E if expanded memory support
	.IF < S_BUFFERS gt 0 >					;AN000; if field lengh > zero
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,SC_BUFFERS,S_BUFFERS
	   .IF < N_XMA eq E_XMA_PRESENT > and			;AN000;    if expanded memory present
	   .IF < F_XMA eq E_XMA_YES >				;AN000;       and is to be used
	   .THEN
	      APPEND_STRING	SC_LINE, MC_LINE, SC_SLASH_X	;AC046;SEH    append /X to command   (formerly /E)
	   .ENDIF
	   WRITE_LINE		SC_LINE 			;AN000;    write BUFFERS command
	.ENDIF
								;
	;;;write FCBS=<parameter>				;
	.IF < S_FCBS gt 0 >					;AN000; if field length > zero
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE, SC_FCBS,S_FCBS
	   WRITE_LINE		SC_LINE 			;AN000;    write FCBS command
	.ENDIF
								;
	;;;write FILES=<parameter>				;
	.IF < S_FILES gt 0 >					;AN000; if field length > zero
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,SC_FILES,S_FILES
	   WRITE_LINE		SC_LINE 			;AN000;    write FILES command
	.ENDIF
								;
	;;;write LASTDRIVE=<parameter>				;
	.IF < S_LASTDRIVE gt 0 >				;AN000; if field length > zero
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,SC_LASTDRIVE,S_LASTDRIVE
	   WRITE_LINE		SC_LINE 			;AN000;    write LASTDRIVE command
	.ENDIF
								;
	;;;write STACKS=<parameter>				;
	.IF < S_STACKS gt 0 >					;AN000; if field length > zero
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,SC_STACKS,S_STACKS
	   WRITE_LINE		SC_LINE 			;AN000;    write STACKS command
	.ENDIF
								;
	;;;write SHELL=<path>\COMMAND.COM /MSG /P /E:256	;
	.IF < I_DEST_DRIVE ne E_DEST_DRIVE_C >			;AN111; if install destination is drive B: or A: JW
	   MERGE_STRING 	SC_LINE,MC_LINE,SC_SHELL,S_DRIVE_A
	   APPEND_STRING	SC_LINE,MC_LINE,SC_SHELL_1	;AN037;SEH
	   APPEND_STRING	SC_LINE,MC_LINE,SC_SHELL_2	;AN037;SEH Only diskettes get /MSG in SHELL command
	.ELSE
	   MERGE_STRING 	SC_LINE,MC_LINE,SC_SHELL,S_DOS_PATH
	   APPEND_STRING	SC_LINE,MC_LINE,SC_SHELL_1	;AC037;SEH
	.ENDIF
	APPEND_STRING		SC_LINE, MC_LINE, SC_SHELL_3	;AC037;SEH
	WRITE_LINE		SC_LINE 			;AN000; write SHELL command
								;
	;;;init S_STR120_1 to DEVICE=<path>\			;
	MERGE_STRING		S_STR120_1,M_STR120_1,SC_DEVICE,S_DOS_PATH
								;
	;;;S_STR120_1 = DEVICE=<path>\				;
	;;;write DEVICE=<path>\XMAEM.SYS<parameter>		;
	;;;write DEVICE=<path>\XMA2EMS.SYS<parameter>		;
	.IF < N_XMA eq E_XMA_PRESENT > near and 		;AC000; if expanded memory present JW
	.IF < F_XMA eq E_XMA_YES >				;AN000;    and support to be included
	.THEN
	   .IF < N_MOD80 eq E_IS_MOD80 >
	   .THEN
	      MERGE_STRING	   SC_LINE,MC_LINE,S_STR120_1,SC_XMAEM_SYS
	      APPEND_STRING	   SC_LINE, MC_LINE, S_XMAEM
	      WRITE_LINE	   SC_LINE			;AN000; write XMAEM command
	   .ENDIF
	   MERGE_STRING 	SC_LINE,MC_LINE,S_STR120_1,SC_XMA2EMS_SYS
	   APPEND_STRING	SC_LINE, MC_LINE, S_XMA2EMS
	   WRITE_LINE		SC_LINE 			;AN000;    write XMA2EMS command
	.ENDIF
								;
	;;;S_STR120_1 = DEVICE=<path>\				;
	;;;write DEVICE=<path>\ANSI.SYS 			;
	;;;write DEVICE=<path>\ANSI.SYS /X ,additional parameter based on workspace option
	.IF < F_ANSI eq E_ANSI_YES >				;AN000; if ANSI support required
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,S_STR120_1,SC_ANSI_SYS
	   APPEND_STRING	SC_LINE, MC_LINE, S_ANSI
	   WRITE_LINE		SC_LINE 			;AN000;    write ANSI command
	.ENDIF
								;
	;;;S_STR120_1 = DEVICE=<path>\				;
	;;;write DEVICE=<path>\RAMDRIVE.SYS <parameter>		;
	.IF < F_VDISK eq E_VDISK_YES >				;AN000; if VDISK support required
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,S_STR120_1,SC_VDISK_SYS
	   APPEND_STRING	SC_LINE, MC_LINE, S_VDISK
	   WRITE_LINE		SC_LINE 			;AN000;    write VDISK command
	.ENDIF
								;
	;;;init S_STR120_2 to number of designates		;
	WORD_TO_CHAR		N_DESIGNATES, S_STR120_2	;AN000; set S_STR120_2 = no. of designates
								;
	;;;S_STR120_1 = DEVICE=<path>\				;
	;;;write DEVICE=<path>\DISPLAY.SYS CON=(<display>,437,<desig>)
	.IF < F_CPSW eq E_CPSW_YES > near			;AN000; if code page switching required
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,S_STR120_1,SC_DISPLAY_SYS
	   .IF < ACTIVE eq EGA > or				;AN000;    if EGA adaptor
	   .IF < ALTERNATE eq EGA >
	   .THEN
	      APPEND_STRING	SC_LINE, MC_LINE, SD_DISPLAY_EGA;AN001;GHG    set display to EGA
	   .ELSEIF < ACTIVE eq LCD > or 			;AN000;    if LCD adaptor
	   .IF < ALTERNATE eq LCD >
	   .THEN
	      APPEND_STRING	SC_LINE, MC_LINE, SD_DISPLAY_LCD;AN001;GHG    set display to LCD
	   .ENDIF
	   APPEND_STRING	SC_LINE, MC_LINE, SC_437	;AN000;    append hardware code page
	   APPEND_STRING	SC_LINE, MC_LINE, S_STR120_2	;AN000;    append no of designates
	   APPEND_STRING	SC_LINE, MC_LINE, SC_CLOSE_BRAC
	   WRITE_LINE		SC_LINE 			;AN000;    write DISPLAY.SYS command
	.ENDIF
								;
	;;;S_STR120_1 = DEVICE=<path>\				;
	;;;S_STR120_2 = number of designates			;
	;;;write DEVICE=<path>\PRINTER.SYS LPT1=(<cdp parameters>,437,<desig>)
	;;;				   LPT2=(<cdp parameters>,437,<desig>)
	;;;				   LPT3=(<cdp parameters>,437,<desig>)
	;;;N_WORD_1 = parallel port number			;
	;;;N_WORD_2 set if driver is prepared			;
	INIT_VAR		N_WORD_1, 1			;AN000; set port number = 1
	INIT_VAR		N_WORD_2, 0			;AN000; set driver status = false
	.IF < F_CPSW eq E_CPSW_YES > near			;AN000; if code page switching required
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,S_STR120_1,SC_PRINTER_SYS
	   .REPEAT						;AN000;    repeat code block
	      GET_PRINTER_PARAMS 0, N_WORD_1, N_RETCODE 	;AN000;       get printer parameters
	      .IF < N_RETCODE eq 1 > and near			;AN000;       if valid return
	      .IF < S_CP_DRIVER gt 0 > and near 		;AN000; 	 and driver and prepare
	      .IF < S_CP_PREPARE gt 0 > near			;AN000; 	 parameters valid
	      .THEN
		 APPEND_STRING	SC_LINE, MC_LINE, SC_LPT	;AN000; 	 append LPT
		 WORD_TO_CHAR	N_WORD_1, S_STR120_3
		 APPEND_STRING	SC_LINE, MC_LINE, S_STR120_3	;AN000; 	 append lpt number
		 APPEND_STRING	SC_LINE, MC_LINE, SC_EQUAL_OPEN ;AN000; 	 append =(
		 APPEND_STRING	SC_LINE, MC_LINE, S_CP_DRIVER	;AN000; 	 append driver parameters
		 APPEND_STRING	SC_LINE, MC_LINE, SC_COMMA	;AN000; 	 append comma
		 APPEND_STRING	SC_LINE, MC_LINE, S_STR120_2	;AN000; 	 append no of designates
		 APPEND_STRING	SC_LINE, MC_LINE, SC_CLOSE_BRAC ;AN000; 	 append close bracket
		 INIT_VAR	N_WORD_2, 1			;AN000; 	 set driver status = valid
	      .ENDIF
	      INC_VAR		N_WORD_1			;AN000;       inc printer number
	   .UNTIL < N_WORD_1 gt 3 > near			;AN000;    end of repeat block
	   .IF < N_WORD_2 eq 1 >				;AN000; if driver status is valid
	   .THEN
	      WRITE_LINE	SC_LINE 			;AN000;    write PRINTER.SYS command
	   .ENDIF
	.ENDIF
								;
	;;;init S_STR120_1 to INSTALL=<path>\			;
	MERGE_STRING		S_STR120_1,M_STR120_1,SC_INSTALL,S_DOS_PATH
								;
	;;;write INSTALL=<path>\KEYB.COM US,,<path>\KEYBOARD.SYS
	COMPARE_STRINGS 	S_KEYBOARD, S_US
	.IF < c > and						;AN000; if keyboard not US (will be handled in autoexec)
	.IF < N_KYBD_VAL eq E_KYBD_VAL_YES > near		;AN000; if keyboard is valid
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,S_STR120_1,SC_KEYB_C
	   APPEND_STRING	SC_LINE, MC_LINE, S_US		;AN000;    append keyboard id = US
	   APPEND_STRING	SC_LINE, MC_LINE, SC_COMMAS	;AN000;    append comma
	   APPEND_STRING	SC_LINE, MC_LINE,S_DOS_PATH	;AN000;    append install path
	   APPEND_STRING	SC_LINE,MC_LINE,SC_KEYBOARD_SYS ;AN000;    append KEYBOARD.SYS
	   WRITE_LINE		SC_LINE 			;AN000;    write KEYB command
	.ENDIF
								;
	;;;S_STR120_1 = INSTALL=<path>\ 			;
	;;;write INSTALL=<path>\SHARE <parameter>		;
	.IF < F_SHARE eq E_SHARE_YES >				;AN000; if SHARE support required
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,S_STR120_1,SC_SHARE
	   APPEND_STRING	SC_LINE, MC_LINE, S_SHARE
	   WRITE_LINE		SC_LINE 			;AN000;    write SHARE command
	.ENDIF
								;
	;;;S_STR120_1 = INSTALL=<path>\ 			;
	;;;write INSTALL=<path>\FASTOPEN <parameter>		;
	.IF < F_FASTOPEN eq E_FASTOPEN_YES >			;AN000; if FASTOPEN support required
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,S_STR120_1,SC_FASTOPEN
	   APPEND_STRING	SC_LINE, MC_LINE, S_FASTOPEN
	   WRITE_LINE		SC_LINE 			;AN000;    write FASTOPEN command
	.ENDIF
								;
	;;;S_STR120_1 = INSTALL=<path>\ 			;
	;;;write INSTALL=<path>\NLSFUNC <path>\COUNTRY.SYS	;
	.IF < F_CPSW eq E_CPSW_YES >				;AN000; if code page switching support required
	.THEN
	   MERGE_STRING 	SC_LINE,MC_LINE,S_STR120_1,SC_NLSFUNC
	   APPEND_STRING	SC_LINE,MC_LINE,S_DOS_PATH
	   APPEND_STRING	SC_LINE, MC_LINE,SC_COUNTRY_SYS
	   WRITE_LINE		SC_LINE 			;AN000;    write NLSFUNC command
	.ENDIF
								;
	RET
CREATE_CONFIG_SYS	ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Create DOSSHELL.BAT file
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CREATE_SHELL_BAT     PROC
	;;;write SHELL <parameter>
	.IF < I_DEST_DRIVE eq E_DEST_DRIVE_C >			;AN000; If install fixed disk
	   WRITE_LINE		SC_DRIVE_C
	   COPY_STRING		SC_LINE, MC_LINE, SC_CD
	   APPEND_STRING	SC_LINE, MC_LINE, S_INSTALL_PATH
	   WRITE_LINE		SC_LINE 			;AN000; write CD path command
	.ENDIF
								;
	WRITE_LINE	     SC_SHELLC_1
	MERGE_STRING	     SC_LINE,MC_LINE,SC_AT_SIGN,SC_BREAK      ;AN092;SEH break=off
	APPEND_STRING	     SC_LINE,MC_LINE,S_OFF		;AN092;SEH
	WRITE_LINE	     SC_LINE				;AN092;SEH
	MERGE_STRING	     SC_LINE,MC_LINE,SC_SHELLC,S_SHELL
	WRITE_LINE	     SC_LINE				;AN000;DT    write SHELL command
	WRITE_LINE	     SC_SHELLC_2
								;
	;;;restore BREAK=<parameter>				;
	.IF < S_BREAK gt 0 >					;AN000;JW if field length > zero
	   MERGE_STRING 	SC_LINE,MC_LINE,SC_AT_SIGN,SC_BREAK
	   APPEND_STRING	SC_LINE,MC_LINE,S_BREAK
	   WRITE_LINE		SC_LINE 			;AN000;JW    write BREAK command
	.ENDIF
								;
								;
	RET
CREATE_SHELL_BAT     ENDP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

SELECT	 ENDS
	 END
