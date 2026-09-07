CTY_DEF 	STRUC
COUNTRY_CODE	DW	0		;AN000; Country Code
KEYBOARD_VALID	DB	0		;AN000; =0 Keyboard code is not valid
					;	=1 Keyboard code is valid
KEYBOARD_CODE	DB	'  '            ;AN000; Keyboard Code
PRI_CODEPAGE	DW	0		;AN000; Primary Code Page
SEC_CODEPAGE	DW	0		;AN000; Secondary Code Page
NUM_DESIGNATES	DW	0		;AN000; number of designates
CPSW_STAT	DW	0		;AN000; code page switching recommendation for country
RESERVED_1	DW	0		;AN000; reserved byte
CTY_DEF 	ENDS

KYB_DEF 	STRUC
KEYB_CODE	DB	'  '            ;AN000; Keyboard code
KEYB_ALT_VALID	DB	0		;AN000; =0 No alternate Keyboard code
					;	=1 Alternate Keyboard code present
KYB_DEF 	ENDS

ALT_KYB_DEF	STRUC
ALT_KYB 	DB	'  '            ;AN000; keyboard codes which have alternate keyboards
ALT_KYB_PTR	DW	0		;AN000; pointer to list of alternate keyboards
ALT_KYB_IDENT	DB	0		;AN000; keyboard code identifier
ALT_KYB_DEF	ENDS

FR_STRUC	STRUC			;AN000; Alternate French Keyboard
FR_KYB		DB	'   '
FR_STRUC	ENDS

IT_STRUC	STRUC			;AN000; Alternate Italian Keyboard
IT_KYB		DB	'   '
IT_STRUC	ENDS

UK_STRUC	STRUC			;AN000; Alternate UK English Keyboard
UK_KYB		DB	'   '
UK_STRUC	ENDS

DISK_STATUS	STRUC
N_PART_NAME	DB	0		;AN000; Partition name
N_PART_SIZE	DW	0		;AN000; size of above partition in MBytes
N_PART_STATUS	DB	0		;AN000; Partition status
P_PART_DRIVE	DB	?		;AN000; drive letter assigned to the partition (ASCII)
N_PART_TYPE	DB	0
N_PART_LEVEL1	DB	0		;AN065; SEH version number (1st part) for DOS 4.00 1st part = blank
N_PART_LEVEL2	DB	0		;AN065; SEH version number (2nd part) for DOS 4.00 2nd part = 4
N_PART_LEVEL3	DB	0		;AN065; SEH version number (3rd part) for DOS 4.00 3rd part = .
N_PART_LEVEL4	DB	0		;AN065; SEH version number (4th part) for DOS 4.00 4th part = 0
DISK_STATUS	ENDS

PRINTER_DEF	STRUC
PRINTER_INDEX	DW	0		;AN000; index into SELECT.PRT
PRINTER_TYPE	DB	0		;AN000; printer type serial/parallel
PRINTER_DATA_VALID DB	0
MODE_PARMS	DW	0
		DB	40 DUP(?)
CODE_DRIVER	DW	0
		DB	22 DUP(?)
CODE_PREPARE	DW	0
		DB	12 DUP(?)
GRAPHICS_PARMS	DW	0
		DB	20 DUP(?)
PORT_NUMBER	DW	0
REDIRECTION_PORT DW	0
PRINTER_TAB_NUM DW	0		;AN000; indicates 1st, 2nd, 3rd, etc. printer selected
PRINTER_DEF	ENDS

