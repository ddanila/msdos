

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;
;	SEL_FILE.INC :	Copyright 1988 Microsoft
;
;	DATE:	 August 8/87
;
;	COMMENT: Module contains variables used by SELECT.
;
;
;	Files found on INSTALL diskette
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
								;
	PUBLIC	COPY_SEL_EGA,E_SEL_EGA
COPY_SEL_EGA	LABEL	BYTE
	DB	'EGA.CPI     '
E_SEL_EGA	EQU ( $ - COPY_SEL_EGA ) / 12
								;
	PUBLIC	COPY_SEL_LCD,E_SEL_LCD
COPY_SEL_LCD	LABEL	BYTE
	DB	'LCD.CPI     '
E_SEL_LCD	EQU ( $ - COPY_SEL_LCD ) / 12
								;
	PUBLIC	COPY_SEL_SHEL,E_SEL_SHEL
COPY_SEL_SHEL	LABEL	BYTE
	DB	'COMMAND.COM '
E_SEL_SHEL	EQU ( $ - COPY_SEL_SHEL) / 12
								;
	PUBLIC	COPY_INST_1200_1440,E_INST_1200_1440
COPY_INST_1200_1440	LABEL	BYTE				;AN000; this will copy files for 1.44M diskettes
								;
	DB	'ANSI.SYS    '
	DB	'COMMAND.COM '
	DB	'COUNTRY.SYS '
	DB	'DISKCOPY.COM'
	DB	'DISPLAY.SYS '
	DB	'DRIVER.SYS  '
	DB	'EGA.CPI     '
	DB	'FORMAT.COM  '
	DB	'GRAFTABL.COM'
	DB	'GRAPHICS.COM'
	DB	'GRAPHICS.PRO'
	DB	'KEYB.COM    '
	DB	'KEYBOARD.SYS'
	DB	'LCD.CPI     '
	DB	'MODE.COM    '
	DB	'NLSFUNC.EXE '
	DB	'PRINT.COM   '
	DB	'PRINTER.SYS '
	DB	'RAMDRIVE.SYS'
	DB	'4201.CPI    '
	DB	'5202.CPI    '
	DB	'4208.CPI    '
	DB	'REPLACE.EXE '
	DB	'SHARE.EXE   '
	DB	'SYS.COM     '
								;
E_INST_1200_1440 EQU	( $ - COPY_INST_1200_1440 ) / 12 	;AN000; end of list for 1.44M diskettes
								;
								;
		PUBLIC	HIDE_SEL,E_HIDE_SEL
HIDE_SEL	DB	'AUTOEXEC.BAT',?,?
		DB	'CONFIG.SYS  ',?,?
		DB	'SELECT.PRT  ',?,?
		DB	'SELECT.EXE  ',?,?
		DB	'SELECT.DAT  ',?,?
		DB	'SELECT.HLP  ',?,?
E_HIDE_SEL	EQU	($ - HIDE_SEL) / 14
								;
		PUBLIC	HIDE_STARTUP,E_HIDE_STARTUP
HIDE_STARTUP	DB	'AUTOEXEC.BAT',?,?
		DB	'CONFIG.SYS  ',?,?
		DB	'SELECT.COM  ',?,?
		DB	'SELECT.HLP  ',?,?
		DB	'SELECT.PRT  ',?,?
E_HIDE_STARTUP	EQU	($ - HIDE_STARTUP) / 14
								;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Files found on OPERATE diskette
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
								;
	PUBLIC	COPY_OPER_1200_1440,E_OPER_1200_1440
COPY_OPER_1200_1440	LABEL	BYTE				;AN000; this will copy files to 1.2M $ 1.44M diskettes
								;
	DB	'APPEND.EXE  '
	DB	'ASSIGN.COM  '
	DB	'ATTRIB.EXE  '
	DB	'BACKUP.COM  '
	DB	'CHKDSK.COM  '
	DB	'COMP.COM    '
	DB	'DEBUG.COM   '
	DB	'DISKCOMP.COM'
	DB	'EDLIN.COM   '
	DB	'EXE2BIN.EXE '
	DB	'FC.EXE      '
	DB	'FILESYS.EXE '
	DB	'FIND.EXE    '
	DB	'GWBASIC.EXE '
	DB	'IFSFUNC.EXE '
	DB	'JOIN.EXE    '
	DB	'LABEL.COM   '
	DB	'LINK.EXE    '
	DB	'MEM.EXE     '
	DB	'MODE.COM    '
	DB	'MORE.COM    '
	DB	'RECOVER.COM '
	DB	'RESTORE.COM '
	DB	'SORT.EXE    '
	DB	'SUBST.EXE   '
	DB	'TREE.COM    '
	DB	'XCOPY.EXE   '
E_OPER_1200_1440 EQU	( $ - COPY_OPER_1200_1440 ) / 12


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Files found on MS-SHELL diskette
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
								;
	PUBLIC	COPY_SHELL_1200_1440,E_SHELL_1200_1440
COPY_SHELL_1200_1440	LABEL	BYTE				;AN000; this will copy files to 1.2M $ 1.44M diskettes
								;
	DB	'SHELL.CLR   '
	DB	'SHELL.HLP   '
	DB	'SHELL.MEU   '
	DB	'SHELLB.COM  '
	DB	'SHELLC.EXE  '
	DB	'DOSUTIL.MEU '
E_SHELL_1200_1440 EQU	( $ - COPY_SHELL_1200_1440 ) / 12
								;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;	Files which will be unique on ship/install diskettes
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		PUBLIC	S_DOS_SHEL_DISK
S_DOS_SHEL_DISK DW	M_DOS_SHEL_DISK
P_DOS_SHEL_DISK DB	'SHELLC.EXE '
M_DOS_SHEL_DISK EQU	$ - P_DOS_SHEL_DISK - 1
								;
		PUBLIC	S_DOS_SEL_360
S_DOS_SEL_360	DW	M_DOS_SEL_360
P_DOS_SEL_360	DB	'SELECT.EXE '
M_DOS_SEL_360	EQU	$ - P_DOS_SEL_360 - 1
								;GHG
		PUBLIC	S_DOS_UTIL1_DISK
S_DOS_UTIL1_DISK DW	 M_DOS_UTIL1_DISK
P_DOS_UTIL1_DISK DB	 'ATTRIB.EXE '
M_DOS_UTIL1_DISK EQU	 $ - P_DOS_UTIL1_DISK - 1
								;GHG
		PUBLIC	S_DOS_UTIL2_DISK
S_DOS_UTIL2_DISK DW	 M_DOS_UTIL2_DISK
P_DOS_UTIL2_DISK DB	 'GWBASIC.EXE '
M_DOS_UTIL2_DISK EQU	 $ - P_DOS_UTIL2_DISK - 1
								;GHG
		PUBLIC	S_DOS_UTIL3_DISK
S_DOS_UTIL3_DISK DW	 M_DOS_UTIL3_DISK
P_DOS_UTIL3_DISK DB	 'DRIVER.SYS '
M_DOS_UTIL3_DISK EQU	 $ - P_DOS_UTIL3_DISK - 1

		PUBLIC	S_DOS_COM_360
S_DOS_COM_360	DW	M_DOS_COM_360
P_DOS_COM_360	DB	'SELECT.COM '
M_DOS_COM_360	EQU	$ - P_DOS_COM_360 - 1
								;GHG
		PUBLIC	E_FILE_ATTR
E_FILE_ATTR	EQU	00H					;AN000; attribute not important
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		PUBLIC	S_COMMAND_COM
S_COMMAND_COM	DW	M_COMMAND_COM
P_COMMAND_COM	DB	'C:\COMMAND.COM '
M_COMMAND_COM	EQU	$ - P_COMMAND_COM - 1
								;
		PUBLIC	S_SELECT_TMP
S_SELECT_TMP	DW	M_SELECT_TMP
P_SELECT_TMP	DB	'SELECT.TMP '
M_SELECT_TMP	EQU	$ - P_SELECT_TMP - 1			;AN000; space for ASCII-Z conversion
								;
		PUBLIC	S_PRINT_FILE,M_PRINT_FILE
S_PRINT_FILE	DW	M_PRINT_FILE				;AN000;GHG  NAME OF THE SELECT PRINTER
P_PRINT_FILE	DB	'SELECT.PRT '                           ;AN000;GHG  PROFILE. - space for ASCII-Z conversion
M_PRINT_FILE	EQU	$-P_PRINT_FILE-1
								;
		PUBLIC	S_AUTO_NEW, S_CONFIG_NEW
S_AUTO_NEW	DW	M_AUTO_NEW
P_AUTO_NEW	DB	'AUTOEXEC.400 '                         ;AN003;GHG Temporary
M_AUTO_NEW	EQU	$ - P_AUTO_NEW - 1			;AN003;GHG AUTOEXEC.BAT
								;
S_CONFIG_NEW	DW	M_CONFIG_NEW
P_CONFIG_NEW	DB	'CONFIG.400 '                           ;AN003;GHG Temporary
M_CONFIG_NEW	EQU	$ - P_CONFIG_NEW - 1			;AN003;GHG CONFIG
								;
		PUBLIC	S_OS2_CONFIG_C, S_OS2_AUTO_C		;AN065;SEH
S_OS2_CONFIG_C	DW	M_OS2_CONFIG_C				;AN065;SEH rename OS2's config.sys
P_OS2_CONFIG_C	DB	'C:\CONFIG.OS2 '                        ;AN065;SEH
M_OS2_CONFIG_C	EQU	$ - P_OS2_CONFIG_C - 1			;AN065;SEH
								;
S_OS2_AUTO_C	DW	M_OS2_AUTO_C				;AN065;SEH rename OS2's autoexec.bat
P_OS2_AUTO_C	DB	'C:\AUTOEXEC.OS2 '                      ;AN065;SEH
M_OS2_AUTO_C	EQU	$ - P_OS2_AUTO_C - 1			;AN065;SEH
								;
		PUBLIC	S_SHELL_NEW
S_SHELL_NEW	DW	M_SHELL_NEW
P_SHELL_NEW	DB	'DOSSHELL.BAT '                         ;AC019;SEH ;AN000;DT space for ASCII-Z conversion
M_SHELL_NEW	EQU	$ - P_SHELL_NEW - 1
								;
		PUBLIC	S_SHELL_NEW_B
S_SHELL_NEW_B	DW	M_SHELL_NEW_B
P_SHELL_NEW_B	DB	'B:\DOSSHELL.BAT '                      ;AC019;SEH ;AN000;DT space for ASCII-Z conversion
M_SHELL_NEW_B	EQU	$ - P_SHELL_NEW_B - 1
								;
		PUBLIC	S_AUTO_NEW_B, S_CONFIG_NEW_B
S_AUTO_NEW_B	DW	M_AUTO_NEW_B
P_AUTO_NEW_B	DB	'B:\AUTOEXEC.BAT '                      ;AN000; space for ASCII-Z conversion
M_AUTO_NEW_B	EQU	$ - P_AUTO_NEW_B - 1
								;
S_CONFIG_NEW_B	DW	M_CONFIG_NEW_B
P_CONFIG_NEW_B	DB	'B:\CONFIG.SYS '                        ;AN000; space for ASCII-Z conversion
M_CONFIG_NEW_B	EQU	$ - P_CONFIG_NEW_B - 1
								;
		PUBLIC	S_AUTO_REN, S_CONFIG_REN
S_AUTO_REN	DW	M_AUTO_REN
P_AUTO_REN	DB	'C:\AUTOEXEC.400 '
M_AUTO_REN	EQU	$ - P_AUTO_REN - 1
								;
S_CONFIG_REN	DW	M_CONFIG_REN
P_CONFIG_REN	DB	'C:\CONFIG.400 '
M_CONFIG_REN	EQU	$ - P_CONFIG_REN - 1
								;
		PUBLIC	S_AUTO_C, S_CONFIG_C
S_AUTO_C	DW	M_AUTO_C
P_AUTO_C	DB	'C:\AUTOEXEC.BAT '                      ;AN000; space for ASCII-Z conversion
M_AUTO_C	EQU	$ - P_AUTO_C - 1
								;
S_CONFIG_C	DW	M_CONFIG_C
P_CONFIG_C	DB	'C:\CONFIG.SYS '                        ;AN000; space for ASCII-Z conversion
M_CONFIG_C	EQU	$ - P_CONFIG_C - 1
								;
		PUBLIC	S_AUTO_NEW_C, S_CONFIG_NEW_C
S_AUTO_NEW_C	DW	M_AUTO_NEW_C
P_AUTO_NEW_C	DB	'C:AUTOEXEC.BAT '                       ;AN000; space for ASCII-Z conversion
M_AUTO_NEW_C	EQU	$ - P_AUTO_NEW_C - 1
								;
S_CONFIG_NEW_C	DW	M_CONFIG_NEW_C
P_CONFIG_NEW_C	DB	'C:CONFIG.SYS '                         ;AN000; space for ASCII-Z conversion
M_CONFIG_NEW_C	EQU	$ - P_CONFIG_NEW_C - 1
								;
		PUBLIC	S_AUTO_REBOOT
S_AUTO_REBOOT	DW	M_AUTO_REBOOT
P_AUTO_REBOOT	DB	'AUTOEXEC.BAT '
M_AUTO_REBOOT	EQU	$ - P_AUTO_REBOOT - 1
								;
		PUBLIC	S_AUTO_MENU
S_AUTO_MENU	DW	M_AUTO_MENU
P_AUTO_MENU	DB	'MENU'
M_AUTO_MENU	EQU	$ - P_AUTO_MENU
								;
		PUBLIC	S_AUTO_FDISK
S_AUTO_FDISK	DW	M_AUTO_FDISK
P_AUTO_FDISK	DB	'FDISK'
M_AUTO_FDISK	EQU	$ - P_AUTO_FDISK
								;
		PUBLIC	S_CONFIG_AUTO, E_FILES
S_CONFIG_AUTO	DB	'CONFIG.400  '
		DB	'AUTOEXEC.400'
E_FILES 	EQU	($ - S_CONFIG_AUTO) / 12
								;
		PUBLIC	S_SHELL2, SH_FILES
S_SHELL2	DB	'DOSSHELL.BAT'                          ;AC019;SEH
SH_FILES	EQU	($ - S_SHELL2) / 12
								;
		PUBLIC	S_KEYB
S_KEYB		DW	M_KEYB
P_KEYB		DB	'KEYB.COM '                             ;AN000; KEYB command - space at end for ASCII-Z
M_KEYB		EQU	$ - P_KEYB - 1
								;
		PUBLIC	S_FDISK
S_FDISK 	DW	M_FDISK
P_FDISK 	DB	'FDISK.EXE '                            ;AC042;SEH ;AN000; FDISK command - space at end for ASCII-Z
M_FDISK 	EQU	$ - P_FDISK - 1
								;
		PUBLIC	S_DISKCOPY
S_DISKCOPY	DW	M_DISKCOPY
P_DISKCOPY	DB	'DISKCOPY.COM '                         ;AN000; DISKCOPY command - space at end for ASCII-Z
M_DISKCOPY	EQU	$ - P_DISKCOPY - 1
								;
		PUBLIC	S_DISKCOPY_PARM
S_DISKCOPY_PARM DW	M_DISKCOPY_PARM
P_DISKCOPY_PARM DB	' A: A:'
M_DISKCOPY_PARM EQU	$ - P_DISKCOPY_PARM
								;
		PUBLIC	SC_1, SC_2
SC_1		DW	MC_1					;AN000; disk number 1
PC_1		DB	'1 '
MC_1		EQU	$ - PC_1
SC_2		DW	MC_2					;AN000; disk number 2
PC_2		DB	'2 '
MC_2		EQU	$ - PC_2
								;
		PUBLIC	SC_PRI,SC_EXT,SC_LOG
SC_PRI		DW	MC_PRI					;AN000; DOS parameter for FDSIK command
PC_PRI		DB	' /PRI:'
MC_PRI		EQU	$ - PC_PRI
SC_EXT		DW	MC_EXT
PC_EXT		DB	' /EXT:'
MC_EXT		EQU	$ - PC_EXT
SC_LOG		DW	MC_LOG
PC_LOG		DB	' /LOG:'
MC_LOG		EQU	$ - PC_LOG
								;
		PUBLIC	S_FORMAT
S_FORMAT	DW	M_FORMAT
P_FORMAT	DB	'FORMAT.COM '                           ;AN000; FORMAT command - space at end for ASCII-Z
M_FORMAT	EQU	$ - P_FORMAT - 1
								;
		PUBLIC	S_DRIVE_C
S_DRIVE_C	DW	M_DRIVE_C
P_DRIVE_C	DB	'C:'
M_DRIVE_C	EQU	$ - P_DRIVE_C
								;
		PUBLIC	S_FORMAT_B
S_FORMAT_B	DW	M_FORMAT_B
P_FORMAT_B	DB	'B: /S /V:DOS400 /SELECT '
M_FORMAT_B	EQU	$ - P_FORMAT_B
								;
		PUBLIC	S_FORMAT_A
S_FORMAT_A	DW	M_FORMAT_A
P_FORMAT_A	DB	'A: /S /V:DOS400 /SELECT '
M_FORMAT_A	EQU	$ - P_FORMAT_A
								;
		PUBLIC	S_REPLACE
S_REPLACE	DW	M_REPLACE
P_REPLACE	DB	'REPLACE.EXE '                          ;AN000; space at end for ASCIII-Z string
M_REPLACE	EQU	$ - P_REPLACE - 1
								;
		PUBLIC	S_REPLACE_PAR1
S_REPLACE_PAR1	DW	M_REPLACE_PAR1
P_REPLACE_PAR1	DB	'A:*.* C:\ /S /R '
M_REPLACE_PAR1	EQU	$ - P_REPLACE_PAR1
								;
		PUBLIC	S_SLASH_R
S_SLASH_R	DW	M_SLASH_R
P_SLASH_R	DB	' /R'
M_SLASH_R	EQU	$ - P_SLASH_R
								;
		PUBLIC	S_A_STARS
S_A_STARS	DW	M_A_STARS
P_A_STARS	DB	'A:*.* '
M_A_STARS	EQU	$ - P_A_STARS
								;
		PUBLIC	S_SLASH_A
S_SLASH_A	DW	M_SLASH_A
P_SLASH_A	DB	' /A'
M_SLASH_A	EQU	$ - P_SLASH_A
								;
		PUBLIC	S_SLASH_S
S_SLASH_S	DW	M_SLASH_S
P_SLASH_S	DB	' /S'
M_SLASH_S	EQU	$ - P_SLASH_S
								;
		PUBLIC	S_SLASH_Q
S_SLASH_Q	DW	M_SLASH_Q
P_SLASH_Q	DB	' /Q'
M_SLASH_Q	EQU	$ - P_SLASH_Q
								;
		PUBLIC	S_COLON
S_COLON 	DW	M_COLON
P_COLON 	DB	':'
M_COLON 	EQU	$ - P_COLON
								;
		PUBLIC	S_SYS_C
S_SYS_C 	DW	M_SYS_C
P_SYS_C 	DB	'SYS.COM '                              ;AN000; space dor ASCII-Z conversion
M_SYS_C 	EQU	$ - P_SYS_C - 1
								;
		PUBLIC	S_VOL_SEL
S_VOL_SEL	DW	M_VOL_SEL
P_VOL_SEL	DB	' /V:DOS400 /SELECT '
M_VOL_SEL	EQU	$ - P_VOL_SEL
								;
		PUBLIC	S_PREP_EGA
S_PREP_EGA	DW	M_PREP_EGA
P_PREP_EGA	DB	'CON CP PREP=((850) EGA.CPI)'
M_PREP_EGA	EQU	$ - P_PREP_EGA
								;
		PUBLIC	S_PREP_LCD
S_PREP_LCD	DW	M_PREP_LCD
P_PREP_LCD	DB	'CON CP PREP=((850) LCD.CPI)'
M_PREP_LCD	EQU	$ - P_PREP_LCD
								;
		PUBLIC	S_CP_SEL
S_CP_SEL	DW	M_CP_SEL
P_CP_SEL	DB	'CON CP SEL=850'
M_CP_SEL	EQU	$ - P_CP_SEL
								;
		PUBLIC	S_MODE
S_MODE		DW	M_MODE
P_MODE		DB	'MODE.COM '                             ;AN000; Space at end of ASCII-Z conversion
M_MODE		EQU	$ - P_MODE-1
								;
		PUBLIC	S_SLASH
S_SLASH 	DW	M_SLASH
P_SLASH 	DB	'\'
M_SLASH 	EQU	$ - P_SLASH
		PUBLIC	S_DSKCPY_TO_B
S_DSKCPY_TO_B DW      M_DSKCPY_TO_B
P_DSKCPY_TO_B DB      ' A: B:'
M_DSKCPY_TO_B EQU     $ - P_DSKCPY_TO_B
								;
		PUBLIC	S_SELCOM_NEW_B
S_SELCOM_NEW_B	DW	M_SELCOM_NEW_B
P_SELCOM_NEW_B	DB	'B:\SELECT.COM '                        ;AN004;DT space for ASCII-Z conversion
M_SELCOM_NEW_B	EQU	$ - P_SELCOM_NEW_B - 1
		PUBLIC	S_SELHLP_NEW_B
S_SELHLP_NEW_B	DW	M_SELHLP_NEW_B
P_SELHLP_NEW_B	DB	'B:\SELECT.HLP '                        ;AN004;DT space for ASCII-Z conversion
M_SELHLP_NEW_B	EQU	$ - P_SELHLP_NEW_B - 1
		PUBLIC	S_SELPRT_NEW_B
S_SELPRT_NEW_B	DW	M_SELPRT_NEW_B
P_SELPRT_NEW_B	DB	'B:\SELECT.PRT '                        ;AN004;DT space for ASCII-Z conversion
M_SELPRT_NEW_B	EQU	$ - P_SELPRT_NEW_B - 1
								;
		PUBLIC	S_SELEXE_NEW_B
S_SELEXE_NEW_B	DW	M_SELEXE_NEW_B
P_SELEXE_NEW_B	DB	'B:\SELECT.EXE '                        ;AN004;DT space for ASCII-Z conversion
M_SELEXE_NEW_B	EQU	$ - P_SELEXE_NEW_B - 1
								;
		PUBLIC	S_SELDAT_NEW_B
S_SELDAT_NEW_B	DW	M_SELDAT_NEW_B
P_SELDAT_NEW_B	DB	'B:\SELECT.DAT '                        ;AN004;DT space for ASCII-Z conversion
M_SELDAT_NEW_B	EQU	$ - P_SELDAT_NEW_B - 1
								;
		PUBLIC	S_SELDAT_C				;AN004;DT  Used to erase from C: after 360KB install
S_SELDAT_C	DW	M_SELDAT_C
P_SELDAT_C	DB	'\SELECT.DAT '                          ;AN004;DT space for ASCII-Z conversion
M_SELDAT_C	EQU	$ - P_SELDAT_C - 1
								;
		PUBLIC	S_SELCOM_C
S_SELCOM_C	DW	M_SELCOM_C
P_SELCOM_C	DB	'\SELECT.COM '                          ;AN004;DT space for ASCII-Z conversion
M_SELCOM_C	EQU	$ - P_SELCOM_C - 1
								;
		PUBLIC	S_SELHLP_C
S_SELHLP_C	DW	M_SELHLP_C
P_SELHLP_C	DB	'\SELECT.HLP '                          ;AN004;DT space for ASCII-Z conversion
M_SELHLP_C	EQU	$ - P_SELHLP_C - 1
								;
		PUBLIC	S_SELPRT_C
S_SELPRT_C	DW	M_SELPRT_C
P_SELPRT_C	DB	'\SELECT.PRT '                          ;AN004;DT space for ASCII-Z conversion
M_SELPRT_C	EQU	$ - P_SELPRT_C - 1
								;
		PUBLIC	S_SELEXE_C
S_SELEXE_C	DW	M_SELEXE_C
P_SELEXE_C	DB	'\SELECT.EXE '                          ;AN004;DT space for ASCII-Z conversion
M_SELEXE_C	EQU	$ - P_SELEXE_C - 1
								;
		PUBLIC	S_AUTOEX_C
S_AUTOEX_C	DW	M_AUTOEX_C
P_AUTOEX_C	DB	'\AUTOEXEC.BAT '                        ;AN004;DT space for ASCII-Z conversion
M_AUTOEX_C	EQU	$ - P_AUTOEX_C - 1
								;
		PUBLIC	S_CONSYS_C
S_CONSYS_C	DW	M_CONSYS_C
P_CONSYS_C	DB	'\CONFIG.SYS '                          ;AN004;DT space for ASCII-Z conversion
M_CONSYS_C	EQU	$ - P_CONSYS_C - 1
								;
		PUBLIC	S_VDISK_B
S_VDISK_B	DW	M_VDISK_B
P_VDISK_B	DB	'B:\RAMDRIVE.SYS '                      ;AN006;JW space for ASCII-Z conversion
M_VDISK_B	EQU	$ - P_VDISK_B - 1
								;
		PUBLIC	S_ANSI_B
S_ANSI_B	DW	M_ANSI_B
P_ANSI_B	DB	'B:\ANSI.SYS '                          ;AN006;JW space for ASCII-Z conversion
M_ANSI_B	EQU	$ - P_ANSI_B - 1
								;
		PUBLIC	S_APPEND_B
S_APPEND_B	DW	M_APPEND_B
P_APPEND_B	DB	'B:\APPEND.EXE '                        ;AN006;JW space for ASCII-Z conversion
M_APPEND_B	EQU	$ - P_APPEND_B - 1
								;
		PUBLIC	S_GRAFTABL_B
S_GRAFTABL_B	DW	M_GRAFTABL_B
P_GRAFTABL_B	DB	'B:\GRAFTABL.COM '                      ;AN006;JW space for ASCII-Z conversion
M_GRAFTABL_B	EQU	$ - P_GRAFTABL_B - 1
								;
		PUBLIC	S_GRAPHICS_B
S_GRAPHICS_B	DW	M_GRAPHICS_B
P_GRAPHICS_B	DB	'B:\GRAPHICS.COM '                      ;AN006;JW space for ASCII-Z conversion
M_GRAPHICS_B	EQU	$ - P_GRAPHICS_B - 1
								;
		PUBLIC	S_GRAPHPRO_B
S_GRAPHPRO_B	DW	M_GRAPHPRO_B
P_GRAPHPRO_B	DB	'B:\GRAPHICS.PRO '                      ;AN006;JW space for ASCII-Z conversion
M_GRAPHPRO_B	EQU	$ - P_GRAPHPRO_B - 1
								;
		PUBLIC	S_RECOVER_B
S_RECOVER_B	DW	M_RECOVER_B
P_RECOVER_B	DB	'B:\RECOVER.COM '                       ;AN007;JW space for ASCII-Z conversion
M_RECOVER_B	EQU	$ - P_RECOVER_B - 1
								;
		PUBLIC	S_FASTOPEN_B
S_FASTOPEN_B	DW	M_FASTOPEN_B
P_FASTOPEN_B	DB	'B:\FASTOPEN.EXE '                      ;AN007;JW space for ASCII-Z conversion
M_FASTOPEN_B	EQU	$ - P_FASTOPEN_B - 1
								;
		PUBLIC	S_VDISK_C
S_VDISK_C	DW	M_VDISK_C
P_VDISK_C	DB	'\RAMDRIVE.SYS '                        ;AN006;JW space for ASCII-Z conversion
M_VDISK_C	EQU	$ - P_VDISK_C - 1
								;
		PUBLIC	S_ANSI_C
S_ANSI_C	DW	M_ANSI_C
P_ANSI_C	DB	'\ANSI.SYS '                            ;AN006;JW space for ASCII-Z conversion
M_ANSI_C	EQU	$ - P_ANSI_C - 1
								;
		PUBLIC	S_APPEND_C
S_APPEND_C	DW	M_APPEND_C
P_APPEND_C	DB	'\APPEND.EXE '                          ;AN006;JW space for ASCII-Z conversion
M_APPEND_C	EQU	$ - P_APPEND_C - 1
								;
		PUBLIC	S_GRAFTABL_C
S_GRAFTABL_C	DW	M_GRAFTABL_C
P_GRAFTABL_C	DB	'\GRAFTABL.COM '                        ;AN006;JW space for ASCII-Z conversion
M_GRAFTABL_C	EQU	$ - P_GRAFTABL_C - 1
								;
		PUBLIC	S_GRAPHICS_C
S_GRAPHICS_C	DW	M_GRAPHICS_C
P_GRAPHICS_C	DB	'\GRAPHICS.COM '                        ;AN006;JW space for ASCII-Z conversion
M_GRAPHICS_C	EQU	$ - P_GRAPHICS_C - 1
								;
		PUBLIC	S_GRAPHPRO_C
S_GRAPHPRO_C	DW	M_GRAPHPRO_C
P_GRAPHPRO_C	DB	'\GRAPHICS.PRO '                        ;AN006;JW space for ASCII-Z conversion
M_GRAPHPRO_C	EQU	$ - P_GRAPHPRO_C - 1
								;
		PUBLIC	S_RECOVER_C
S_RECOVER_C	DW	M_RECOVER_C
P_RECOVER_C	DB	'\RECOVER.COM '                         ;AN007;JW space for ASCII-Z conversion
M_RECOVER_C	EQU	$ - P_RECOVER_C - 1
								;
		PUBLIC	S_FASTOPEN_C
S_FASTOPEN_C	DW	M_FASTOPEN_C
P_FASTOPEN_C	DB	'\FASTOPEN.EXE '                        ;AN007;JW space for ASCII-Z conversion
M_FASTOPEN_C	EQU	$ - P_FASTOPEN_C - 1
								;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
