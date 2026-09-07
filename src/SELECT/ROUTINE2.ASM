;***************************************************************************
; Subroutines which are called by the macros in MACROS.INC.
; File: ROUTINE2.ASM
; Latest Change Date: August 04, 1987
;
; This is a stand alone module and is meant to be linked with the calling
; program.
;
;***************************************************************************
.ALPHA
;**********************************************************************
DATA	SEGMENT BYTE PUBLIC 'DATA'

PATH_STRING		DW	  0
STRING_SIZE		DW	  0
PATH_PTR		DW	  0
PATH_SIZE		DW	  0
MAX_CHAR		DW	  0
CHAR_COUNT		DW	  0


SEARCH_FLAG		DB	  0

    PERIOD		EQU	  00000001B
    SLASH_FOUND 	EQU	  00000010B


    RESET_PERIOD	EQU	  11111110B
    RESET_SLASH_FOUND	EQU	  11111101B

INVALID_STRING		DB	  '"/\[]:|<>+=;, '
			END_INVALID_STRING  EQU  $
SIZE_INVALID_STR	EQU	  END_INVALID_STRING - INVALID_STRING

ZEROED_CHAR		DB	  0
			DB	  0

SEP_POSITION		DW	  0
NUM_PATHS		DW	  0


ERR_INVALID_DRV 	EQU	  1
ERR_NO_DRIVE		EQU	  2
ERR_DRIVE		EQU	  3
ERR_LEADING_SLASH	EQU	  4
ERR_NO_SLASH		EQU	  5
ERR_LAST_SLASH		EQU	  6
ERR_INVALID_CHAR	EQU	  7

OLD_ATTRIB		DW	  0
NEW_ATTRIB		DW	  0
WAY			DW	  0



PUBLIC	      CHK_W_PROTECT_FLAG
PUBLIC	      W_PROTECT_FLAG

W_P_FILENAME_A		DB	  'A:\',12 DUP(0), 0
W_P_FILENAME_B		DB	  'B:\',12 DUP(0), 0
CHK_W_PROTECT_FLAG	DB	  0
W_PROTECT_FLAG		DB	  0
DRIVE_FLAG		DB	  ?


NUM_FILES		DW	  0
LIST_TYPE		DW	  0
STR_PTR 		DW	  0
FILE_PTR		DW	  0



DATA	       ENDS				 ;AN000; DATA
;**********************************************************************
						 ;
	.XLIST
	INCLUDE STRUC.INC
	INCLUDE MACROS.INC
	INCLUDE VARSTRUC.INC
	INCLUDE EXT.INC
	INCLUDE MAC_EQU.INC
	EXTRN	EXIT_DOS:FAR
	EXTRN	POS_ZERO:FAR
	EXTRN	HOOK_INT_24:FAR
	EXTRN	RESTORE_INT_24:FAR
	EXTRN	GGET_STATUS:FAR
	.LIST
						 ;
						 ;
;**********************************************************************
CODE_FAR    SEGMENT PARA PUBLIC 'CODE'           ;AN000; Segment for far routine
	ASSUME	CS:CODE_FAR,DS:DATA
						 ;
;********************************************************************************
; CHECK_DOS_PATH_ROUTINE: Check to see if the sepecified path for the DOS
;	      SET PATH command is valid.
;
; INPUT:
;    SI = Points to an ASCII-N string containing the path to check.  There sould
;	  be an extra byte following the string to facilitate changing the string
;	  into an ASCII-Z string.
;
; OUTPUT:
;    If CY = 0, the path is valid.
;    If CY = 1, The path is NOT valid:
;
;********************************************************************************
PUBLIC	 CHECK_DOS_PATH_ROUTINE
CHECK_DOS_PATH_ROUTINE	PROC FAR
						 ;
    MOV  PATH_PTR, SI				 ;AN000; Get the pointer from the path
    MOV  AX, [SI]				 ;AN000; Get the lenth of the path string
    .IF < AX EQ 0 >				 ;AN000; If the length is zero then return that
	 JMP  NO_ERROR_DOS_PATH 		 ;AN000;    the path is valid.
    .ENDIF
    MOV  PATH_SIZE, AX				 ;AN000; Save the size of the string
    ADD  SI, 2					 ;AN000; Adjust path pointer for length word
						 ;
    .REPEAT					 ;AN000; Check all the path names in the string
	 MOV  AL, ';'                            ;AN000; separator between filenames
	 MOV  CX, PATH_PTR			 ;AN000; Get the pointer to the path
	 ADD  CX, 2				 ;AN000; Point to the start of the string
	 ADD  CX, PATH_SIZE			 ;AN000; Add the size of the path
	 SUB  CX, SI				 ;AN000; Subtract current pointer - Get length of string remaining
	 CALL ISOLATE_NEXT_PATH 		 ;AN000; Make the next path name into an ASCII-Z string
	 PUSH SEP_POSITION			 ;AN000; Save the position of the path seperator
	 PUSH WORD PTR ZEROED_CHAR		 ;AN000; Save the character that was made into a zero
	 MOV  CX, SEP_POSITION
	 SUB  CX, SI				 ;AN000; Get the length of the string
	 MOV  AX, 0101H
	 CALL FAR PTR CHECK_VALID_PATH		 ;AN000; Check if it is a valid filename
	 POP  WORD PTR ZEROED_CHAR
	 POP  SEP_POSITION
	 CALL RESTORE_SEPARATOR 		 ;AN000; Restore the character between the path names
	 .IF < C >				 ;AN000; Was the file name not valid?
	      JMP  ERROR_DOS_PATH		 ;AN000; Exit the subroutine
	 .ENDIF
	 MOV  SI, DI				 ;AN000; Get the pointer to the next path name
    .UNTIL < ZERO SI >				 ;AN000; If zero, all path names have been examined.
NO_ERROR_DOS_PATH:
    CLC
    JMP  EXIT_DOS_PATH
ERROR_DOS_PATH:
    STC
EXIT_DOS_PATH:
    RET
						 ;
CHECK_DOS_PATH_ROUTINE	ENDP
						 ;
						 ;
PUBLIC	 CHECK_VALID_PATH
;********************************************************************************
; CHECK_VALID_PATH: Check to see if the sepecified path is valid.
;
; INPUT:
;    SI = Points to an ASCII-Z string containing the path to check.  There sould
;	  be an extra byte following the string to facilitate changing the string
;	  into an ASCII-Z string.
;
;   CX = The size of the string containing the path.  The zero byte at the end
;	 of the string is NOT included in the length.
;
;    AL = 0: Drive letter cannot be specified.
;	= 1: Drive letter is optional and can be specified.
;	= 2: Drive letter must be specified.
;
;    AH = 0: First non-drive character cannot be a backslash ('\')
;	= 1: First non-drive character may be a backslash ('\')
;	= 2: First non-drive character must be a backslash ('\')
;
; OUTPUT:
;    If CY = 0, the path is valid.
;    If CY = 1, The path is NOT valid:
;	  AX = 1, The drive specified is invalid.
;	     = 2, There was no drive specified.
;	     = 3, There was a drive specified.
;	     = 4, There was a leading backslash
;	     = 5, The leading backslash was NOT present.
;	     = 6, There was a trailing backslash.
;
;********************************************************************************
CHECK_VALID_PATH   PROC FAR
						 ;
    PUSH DI
    MOV  STRING_SIZE, CX			 ;AN000; Save the size of the string
    MOV  PATH_STRING, SI			 ;AN000; Save the pointer to the string
    CALL CHECK_VALID_DRIVE			 ;AN000; See if there is a valid drive
    .IF < C >					 ;AN000; Is the drive specified invalid?
	 MOV  AX, ERR_INVALID_DRV		 ;AN000; Return this error code
	 JMP  EXIT_CHK_DRV			 ;AN000; Exit the subroutine
    .ENDIF
    .IF < BX EQ 0 >				 ;AN000; No drive sepecified?
	 .IF < AL EQ 2 >			 ;AN000; Must the drive be specified?
	      MOV  AX, ERR_NO_DRIVE		 ;AN000; Return this error code
	      JMP  EXIT_CHK_DRV 		 ;AN000; Exit the subroutine
	 .ENDIF
    .ELSE					 ;AN000; Otherwise, the drive WAS specified.
	 .IF < AL EQ 0 >			 ;AN000; The drive cannot be specified
	      MOV  AX, ERR_DRIVE		 ;AN000; Return this error code
	      JMP  EXIT_CHK_DRV 		 ;AN000; Exit the subroutine
	 .ENDIF
	 ADD  SI, 2				 ;AN000; Push pointer past the drive
    .ENDIF
    .IF < <BYTE PTR [SI]> EQ '\' >               ;AN000; Is the next byte a backslash?
	 .IF < AH EQ 0 >			 ;AN000; Is one permitted?
	      MOV  AX, ERR_LEADING_SLASH	 ;AN000; No! Return this error code
	      JMP  EXIT_CHK_DRV 		 ;AN000; Exit the subroutine
	 .ELSE					 ;AN000; Otherwise, one allowed.
	      INC  SI				 ;AN000; Push pointer past \
	 .ENDIF
    .ELSE					 ;AN000; Otherwise, byte not a backslash
	 .IF < AH EQ 2 >			 ;AN000; Was one required?
	      MOV  AX, ERR_NO_SLASH		 ;AN000; If so, return this error code
	      JMP  EXIT_CHK_DRV 		 ;AN000; Exit from this subroutine
	 .ENDIF
    .ENDIF
						 ;
    MOV  NUM_PATHS, 0
    .REPEAT					 ;AN000; Check all the path names in the string
	 MOV  AL, '\'                            ;AN000; Separator between filenames
	 MOV  CX, PATH_STRING
	 ADD  CX, STRING_SIZE
	 SUB  CX, SI
	 .IF < NUM_PATHS EQ 0 > AND		 ;AN000; If this is the first path checked...and
	 .IF < CX EQ 0 >			 ;AN000; If the length of the path is zero...
	      JMP  EXIT_NO_ERROR		 ;AN000; Exit with no error
	 .ENDIF
	 CALL ISOLATE_NEXT_PATH 		 ;AN000; Make the next path name into an ASCII-Z string
	 CALL CHECK_VALID_FILENAME		 ;AN000; Check if it is a valid filename
	 CALL RESTORE_SEPARATOR 		 ;AN000; Restore the character between the path names
	 .IF < C >				 ;AN000; Was the file name not valid?
	      .IF < NUM_PATHS EQ 0 >
		   .LEAVE
	      .ELSE
		   MOV	AX, ERR_INVALID_CHAR	 ;AN000; If not, return this error code
		   JMP	EXIT_CHK_DRV		 ;AN000; Exit the subroutine
	      .ENDIF
	 .ENDIF
	 MOV  SI, DI				 ;AN000; Get the pointer to the next path name
    .UNTIL < ZERO SI >				 ;AN000; If zero, all path names have been examined.
						 ;
    MOV  SI, PATH_STRING			 ;AN000; Get the pointer to the whole string
    ADD  SI, STRING_SIZE			 ;AN000; Add the string length
    DEC  SI					 ;AN000; Point to the last character in the string
    .IF < <BYTE PTR [SI]> EQ '\'>                ;AN000; Is the last character a \ ?
	 MOV  AX, ERR_LAST_SLASH		 ;AN000; If so, return this error code
	 JMP  EXIT_CHK_DRV			 ;AN000; Exit from the subroutine
    .ENDIF
EXIT_NO_ERROR:
    CLC 					 ;AN000; Indicate there were no errors
    JMP  EXIT_CHECK_PATH
						 ;
EXIT_CHK_DRV:
    STC 					 ;AN000; Indicate that there were errors
EXIT_CHECK_PATH:
    POP  DI
    RET
						 ;
						 ;
CHECK_VALID_PATH   ENDP
;********************************************************************************
; CHECK_VALID_DRIVE: Check to see if there is a drive specified on the path and
;	       if there is, is it valid.
;
; INPUT:
;    SI - Points to a string containing the path to search.
;
; OUTPUT:
;    If CY = 1, the drive is specified and is invalid
;    If CY = 0, The drive might be specified and is valid
;	  BX = 0: The drive is NOT specified.
;	     = 1: The drive IS specified.
;
;
;********************************************************************************
CHECK_VALID_DRIVE  PROC NEAR
						 ;
    PUSH AX					 ;AN000; Push all registers used
    .IF < <BYTE PTR [SI+1]> EQ ':' >             ;AN000; Is the second character in the string a ':'
	 MOV  AL, [SI]				 ;AN000; If so, get the first character
	 .IF < AL AE 'A' > AND                   ;AN000; Is it a capital letter?
	 .IF < AL BE 'Z' >
	      CLC				 ;AN000; If so, drive valid.
	      MOV  BX, 1			 ;AN000; Indicate the drive exists
	 .ELSEIF < AL AE 'a' > AND               ;AN000; Else, is the drive a lowercase letter?
	 .IF < AL BE 'z' >
	      CLC				 ;AN000; If so, the drive is valid
	      MOV  BX, 1			 ;AN000; Indicate that the drive exists
	 .ELSE					 ;AN000; Otherwise...
	      STC				 ;AN000; The drive is not valid
	 .ENDIF
    .ELSE
	 CLC					 ;AN000; Indicate there were no errors
	 MOV  BX, 0				 ;AN000; The drive does not exist
    .ENDIF
    POP  AX
						 ;
    RET
						 ;
CHECK_VALID_DRIVE  ENDP
;********************************************************************************
; CHECK_VALID_FILENAME: Check to see if a filename is valid.
;
; INPUT:
;    SI - Points to an ASCII-Z string containing the filename to examine.
;
; OUTPUT:
;    If CY = 1, The filename is NOT valid.
;    If CY = 0, the filename IS valid.
;
;
;********************************************************************************
CHECK_VALID_FILENAME	PROC NEAR
						 ;
    INC  NUM_PATHS
    AND  SEARCH_FLAG, RESET_PERIOD		 ;AN000; Indicate no periods have been found yet
    MOV  MAX_CHAR, 8				 ;AN000; Up to 8 characters can be specified
    MOV  CHAR_COUNT, 0				 ;AN000; Number of character so far
    MOV  AL, [SI]				 ;AN000; Get the first character in the string
    .WHILE < AL NE 0 >				 ;AN000; Repeat untill we reach the string's end
	 INC  CHAR_COUNT			 ;AN000; Increment number of characters in path
	 MOV  BX, CHAR_COUNT
	 .IF < BX A MAX_CHAR > AND
	 .IF < AL NE '.' >
	      JMP  INVALID_CHAR
	 .ENDIF
	 .IF < AL B 20 >			 ;AN000; Is the character's code less than 20?
	      JMP  INVALID_CHAR 		 ;AN000; If so, it's invalid
	 .ELSE					 ;AN000; Otherwise...
	      CALL VALID_CHAR			 ;AN000; See if it's invalid
	      .IF < C > 			 ;AN000; If so,
		   JMP	INVALID_CHAR		 ;AN000; Exit the subroutine
	      .ENDIF
	 .ENDIF
	 .IF < AL EQ '.' >                       ;AN000; Is the character a period?
	      .IF < BIT SEARCH_FLAG AND PERIOD > ;AN000; Is this the first one?
		   JMP	INVALID_CHAR		 ;AN000; If not, filename is invalid.
	      .ELSE				 ;AN000; Otherwise...
		   OR	SEARCH_FLAG, PERIOD	 ;AN000; Indicate that ONE has been found
		   .IF < CHAR_COUNT EQ 1 >	 ;AN000; Were there any characters before the period
			JMP  INVALID_CHAR	 ;AN000; If not, this is an invalid path
		   .ENDIF
		   MOV	MAX_CHAR, 3		 ;AN000; Allow three characters after the period
		   MOV	CHAR_COUNT, 0		 ;AN000; No characters yet
	      .ENDIF
	 .ENDIF
	 INC  SI				 ;AN000; Point to next character
	 MOV  AL, [SI]				 ;AN000; Get that character
    .ENDWHILE
    .IF < CHAR_COUNT EQ 0 > AND
    .IF < MAX_CHAR   EQ 8 >
	 DEC  NUM_PATHS
	 JMP  INVALID_CHAR
    .ENDIF
    CLC 					 ;AN000; Indicate the name is valid
    JMP  CK_V_FILENAME				 ;AN000; Exit.
						 ;
INVALID_CHAR:					 ;AN000; Indicate that the name is not valid
    STC
CK_V_FILENAME:
    RET
						 ;
CHECK_VALID_FILENAME	ENDP
;********************************************************************************
; VALID_CHAR: Determine if a character is valid for a filename.
;
; INPUT:
;    AL = The character to check.
;
; OUTPUT:
;    If CY = 1, the character is not valid.
;    If CY = 0, the character IS valid.
;
;********************************************************************************
VALID_CHAR    PROC NEAR
						 ;
    PUSH CX					 ;AN000; Save the registers used.
    PUSH DI
    PUSH ES
						 ;
    MOV  DI, OFFSET INVALID_STRING		 ;AN000; Get the address of string containing invalid characters
    PUSH DS					 ;AN000; Save the data segment
    POP  ES					 ;AN000; Make ES=DS
    MOV  CX, SIZE_INVALID_STR			 ;AN000; Get the size of the string
    CLD 					 ;AN000; Scan forward
    REPNZ     SCASB				 ;AN000; See if this character is in the invalid string
    .IF < Z >					 ;AN000; If so,
	 STC					 ;AN000; Indicate the character is invalid
    .ELSE					 ;AN000; Otherwise...
	 CLC					 ;AN000; Indicate the character is valid
    .ENDIF
    POP  CX					 ;AN000; Restore the registers
    POP  DI
    POP  ES
    RET
						 ;
VALID_CHAR    ENDP
;********************************************************************************
; ISOLATE_NEXT_PATH: Search the filename for a '\'.  If found, it is replaced
;	  by a zero making the string into an ASCII-Z string.
;
; INPUT:
;    SI - Points to the first character in the path string
;    AL - Contains the character to search for
;    CX - Contains the length of the string
;
; OUTPUT:
;    DI - Points to the character following the next '\'
;    If this character is the last path element, DI = 0.
;
;    ZEROED_CHAR is loaded with the character which is made into a zero.
;
;********************************************************************************
ISOLATE_NEXT_PATH  PROC NEAR
						 ;
    PUSH AX					 ;AN000; Save registers used.
    PUSH BX
    PUSH CX
    PUSH SI
						 ;
    PUSH ES					 ;AN000; Make ES = DS
    PUSH DS
    POP  ES
    MOV  DI, SI 				 ;AN000; Copy the string pointer
						 ; CX holds the length of string after the pointer DI
						 ; AL holds the character to search for
    CLD 					 ;AN000; Search in the forward direction
    REPNZ     SCASB				 ;AN000; Search...
    JNZ  END_FOUND				 ;AN000; If NZ, we reached the string's end
    MOV  ZEROED_CHAR, AL			 ;AN000; Character overwritten with zero
    MOV  SEP_POSITION, DI			 ;AN000; Save the position of overwritten char
    DEC  SEP_POSITION
    MOV  BYTE PTR [DI-1], 0			 ;AN000; Make the character a zero
    CMP  CX,0					 ;AN031; SEH  User may have entered semicolon as last char, so check
    JE	 END_FOUND2				 ;AN031; SEH	   if it is last char instead of just a separator
    JMP  EXIT_ISOLATE				 ;AN000; Exit the subroutine
END_FOUND:
    MOV  AL, [DI]				 ;AN000; Get the last character
    MOV  ZEROED_CHAR, AL			 ;AN000; Save it.
    MOV  SEP_POSITION, DI			 ;AN000; Save its position
    MOV  BYTE PTR [DI], 0			 ;AN000; Make into a zero
END_FOUND2:					 ;AN031; SEH  Handle case of semicolon as last character in path
    MOV  DI, 0					 ;AN000; Indicate the string is finished
EXIT_ISOLATE:
    POP  ES					 ;AN000; Restore the registers.
    POP  SI
    POP  CX
    POP  BX
    POP  AX
						 ;
    RET
						 ;
ISOLATE_NEXT_PATH  ENDP
;********************************************************************************
; RESTORE_SEPARATOR: Restore the character which separates the characters in
;	  a path.
;
; INPUT:
;    SEP_POSITION - Contain the address of the location to restore the separator.
;    ZEROED_CHAR  - Contains the character to be restored.
;
; OUTPUT:
;    None.
;
;********************************************************************************
RESTORE_SEPARATOR  PROC NEAR
						 ;
    PUSH AX					 ;AN000; Save registers used
    PUSH SI
    MOV  SI, SEP_POSITION			 ;AN000; Get the position of the character
    MOV  AL, ZEROED_CHAR			 ;AN000; Get the character
    MOV  [SI], AL				 ;AN000; Save character in this position
    POP  SI					 ;AN000; Restore the registers
    POP  AX
    RET
						 ;
RESTORE_SEPARATOR  ENDP
;********************************************************************************
; CHANGE_ATTRIBUTE_ROUTINE:  Change the attributes on a group of files.
;
; INPUT:
;    SI = The address of a list of files to change the attributes of.
;    AX = 0: Attach a new attribute to the file.
;    AX = 1: Restore the original attribute to the files.
;    BX = The number of files in the list.
;
; OUTPUT:
;    If CY = 1, there were error encountered.
;    If CY = 0, there were no errors.
;
;********************************************************************************
PUBLIC	 CHANGE_ATTRIBUTE_ROUTINE
CHANGE_ATTRIBUTE_ROUTINE     PROC FAR
						 ;
    CALL HOOK_INT_24
						 ;
    MOV  WAY, AX				 ;AN000; Save flag indicating whether we are setting or restoring the attrb.
    MOV  NEW_ATTRIB, 02h			 ;AN000; Set new attribute to hidden.
    MOV  DI, 0					 ;AN000; Count of files processed
    .WHILE < DI B BX >
	 .IF < WAY EQ 0 >			 ;AN000; Setting the attribute?
	      MOV  WORD PTR [SI+12],0		 ;AN000; Make filename into a ASCII-Z string
	      MOV  DX, SI			 ;AN000; Load address of filename into DX
	      MOV  AX, 4300H			 ;AN000; Get the file's current attribute
	      DOSCALL
	      .IF < C > 			 ;AN000; Was there an error?
		   JMP	CHMOD_ERROR		 ;AN000; If so, exit the subroutine
	      .ENDIF
	      MOV  OLD_ATTRIB, CX		 ;AN000; Save the attribute
	      MOV  CX, NEW_ATTRIB		 ;AN000; Get the new attribute
	 .ELSE					 ;AN000; Otherwise, we are restoring the attribute
	      MOV  CX, [SI+12]			 ;AN000; Get the old attribute
	      MOV  OLD_ATTRIB, CX		 ;AN000; Save.
	      MOV  WORD PTR [SI+12], 0		 ;AN000; Make filename into an ASCII-Z string
	 .ENDIF
	 MOV  DX, SI				 ;AN000; Pointer to the filename
	 MOV  AX, 4301H 			 ;AN000; DOS function for setting the attribute
	 DOSCALL				 ;AN000; Set it.
	 .IF < C >				 ;AN000; Was there an error?
	      JMP  CHMOD_ERROR			 ;AN000; If so, exit the subroutine
	 .ENDIF
	 MOV  CX, OLD_ATTRIB			 ;AN000; Get the old attribute
	 MOV  [SI+12], CX			 ;AN000; Save in the table
	 ADD  SI, 14				 ;AN000; Point to the next filename
	 INC  DI				 ;AN000; Increment count of files processed
    .ENDWHILE
    CLC 					 ;AN000; Indicate there were no errors
    RET
						 ;
CHMOD_ERROR:
    STC 					 ;AN000; Indicate there were errors
						 ;
    CALL RESTORE_INT_24
						 ;
    RET
						 ;
CHANGE_ATTRIBUTE_ROUTINE     ENDP
;****************************************************************************
;
;   COMPARE_ROUTINE:  Compare two strings.
;
;   INPUT:
;	SI = The address of the first string. (ASCII-N string)
;	DI = The address of the second string. (ASCII-N string)
;
;   OUTPUT:
;	If CY = 1, the strings do no compare.
;	If CY = 0, the strings are the same.
;
;   OPERATION:
;
;****************************************************************************
PUBLIC	 COMPARE_ROUTINE
COMPARE_ROUTINE    PROC FAR
						 ;
    PUSH ES					 ;AN000; Make ES = DS
    PUSH DS
    POP  ES
						 ;
    MOV  CX, [SI]				 ;AN000; Get the length of the first string
    .IF < [DI] NE CX >				 ;AN000; Are the lengths of the strings the same?
	 JMP  DO_NOT_COMPARE			 ;AN000; If not, the strings are not the same
    .ENDIF
    ADD  SI, 2					 ;AN000; Move points past the length words
    ADD  DI, 2
    CLD 					 ;AN000; Compare in the forward direction
    REPZ CMPSB					 ;AN000; Compare the strings
    JNZ  DO_NOT_COMPARE 			 ;AN000; If the zero flag cleared, strings are not the same
    CLC 					 ;AN000; Indicate the strings do compare
    JMP  EXIT_COMPARE
DO_NOT_COMPARE:
    STC 					 ;AN000; Indicate the strings do no compare
EXIT_COMPARE:
    POP  ES
    RET
						 ;
COMPARE_ROUTINE    ENDP
;****************************************************************************
;
;   REMOVE_END_BLANKS: Removes the trailing blanks from a string.
;
;   INPUT:
;	ES:DI Points to the last character in the string.
;
;   OUTPUT:
;	ES:DI Points to the new end of the string after the blanks have been
;	      removed.
;
;   OPERATION:
;
;****************************************************************************
PUBLIC	 REMOVE_END_BLANKS
REMOVE_END_BLANKS  PROC FAR
						 ;
    MOV  CX, 0FFFFH
    MOV  AL, ' '
    STD
    REPZ SCASB
    .IF < NZ >
	 INC  DI
    .ENDIF
    RET
						 ;
REMOVE_END_BLANKS  ENDP
						 ;
;****************************************************************************
;
;   CHECK_WRITE_ROUTINE  Determine if the diskette in drive A is write
;		       protected.
;
;   INPUT:
;	CX = 0 - drive A
;	   = 1 - drive B
;
;   OUTPUT:
;	If CY = 1, The disk IS write protected.
;	If CY = 0, The disk is NOT write protected.
;
;   OPERATION:
;
;****************************************************************************
PUBLIC	 CHECK_WRITE_ROUTINE
CHECK_WRITE_ROUTINE	PROC FAR
						 ;
    MOV  DRIVE_FLAG,CL
						 ;
    CALL HOOK_INT_24
						 ;
    MOV  CHK_W_PROTECT_FLAG, TRUE		 ;AN000; Indicate to INT 24H handler we are looking for error
    MOV  W_PROTECT_FLAG, FALSE			 ;AN000; Error has not occured yet.
						 ;
    MOV  W_P_FILENAME_A+3, 0			 ;AN000; Make drive string into ASCII-Z string
    MOV  W_P_FILENAME_B+3, 0			 ;AN000; Make drive string into ASCII-Z string	  JW
    .IF < DRIVE_FLAG eq DRIVE_A >
       MOV  DX, OFFSET W_P_FILENAME_A		 ;AN000; Get address of the string
    .ELSE
       MOV  DX, OFFSET W_P_FILENAME_B		 ;AN000; Get address of the string JW
    .ENDIF
    MOV  CX, 0					 ;AN000; Attribute to give the file
    MOV  INT_24_ERROR, FALSE
    MOV  AH, 5AH				 ;AN000; DOS Fn. call to create a unique file
    DOSCALL					 ;AN000; Create the file
    .IF < C >					 ;AN000; Was there an error?
	 .IF < W_PROTECT_FLAG EQ TRUE > 	 ;AN000; If the INT 24H handler was call...
	      JMP  WRITE_PROTECTED		 ;AN000; The disk is write protected.
	 .ELSE					 ;AN000; Otherwise...
	      JMP  CHECK_ERROR			 ;AN000; There was some other disk error
	 .ENDIF
    .ELSE
	.IF < W_PROTECT_FLAG EQ TRUE >		 ;AN000; If the INT 24H handler was call...
	     JMP  WRITE_PROTECTED		 ;AN000; The disk is write protected.
	.ENDIF
    .ENDIF					 ;AN000; There were no errors...
    CLOSE_FILE	   AX				 ;AN000; Close the created file
    .IF < DRIVE_FLAG eq DRIVE_A >
       MOV  DX, OFFSET W_P_FILENAME_A		 ;AN000; Get address of the string
    .ELSE
       MOV  DX, OFFSET W_P_FILENAME_B		 ;AN000; Get address of the string JW
    .ENDIF
    MOV  AH, 41H				 ;AN000; DOS Fn. for erasing a file
    DOSCALL					 ;AN000; Erase the file
    MOV  AX, 0					 ;AN000; Indicate the file is NOT write protected
    CLC 					 ;AN000; Indicate there were no errors
    JMP  CHECK_EXIT				 ;AN000; Exit the routine

WRITE_PROTECTED:
    MOV  AX, 1					 ;AN000; Indicate the file IS write protected
    CLC 					 ;AN000; Indicate there were no errors
    JMP  CHECK_EXIT

CHECK_ERROR:
    MOV  AX, 0					 ;AN000; Indicate the file is NOT write protected
    STC 					 ;AN000; Indicate that there WERE errors

CHECK_EXIT:
    CALL RESTORE_INT_24 			 ;AN000; Restore the original INT 24H handler
    MOV  CHK_W_PROTECT_FLAG, FALSE		 ;AN000; We are no longer expecting a write protect error
    RET

CHECK_WRITE_ROUTINE	ENDP
;****************************************************************************
;
;   MATCH_FILES_ROUTINE  Determine is a list of file exist on a drive.
;
;   INPUT:
;	DI = Address of the ASCII-N string containing the drive and path to
;	     search for the files.
;	SI = The address of the list of file.  If AX = 2, the first two bytes
;	      in the list are ignored.
;	AX = The type of list to use.
;	   = 1: Use a list with only 12 bytes between the filenames.
;	   = 2: Use a list with only 14 bytes between the filenames.
;	CX = The number of files in the list.
;
;   OUTPUT:
;	If CY = 1, There was an error access the disk.
;	If CY = 0, There were no errors.
;	      AX = 1: All the files are on the disk.
;	      AX = 0: All the files are NOT on the disk.
;
;   OPERATION:
;
;****************************************************************************
PUBLIC	 MATCH_FILES_ROUTINE
MATCH_FILES_ROUTINE	PROC FAR
						 ;
						 ;
    PUSH ES					 ;AN000; Make ES = DS
    PUSH DS
    POP  ES
						 ;
    MOV  NUM_FILES, CX				 ;AN000; Save the number of files
    MOV  LIST_TYPE, AX				 ;AN000; Save the type of the list
						 ;
    MOV  CX, [DI]				 ;AN000; Get the length of the string
    ADD  DI, 2					 ;AN000; Point SI to the start of the string
    MOV  DX, DI 				 ;AN000; Copy the address of the string
    ADD  DI, CX 				 ;AN000; Point to the end of the string
    .IF < LIST_TYPE EQ 2 >			 ;AN000; If this list is a 14 byte list...
	 ADD  SI, 2				 ;AN000; Bypass the first two bytes in the list
    .ENDIF
    MOV  STR_PTR, DI				 ;AN000; Save the pointer to the path string
    MOV  FILE_PTR, SI				 ;AN000; Save the pointer to the file list
    MOV  BX, 0					 ;AN000; Initialize the count of files checked
						 ;
    .WHILE < BX B NUM_FILES >			 ;AN000; Perform NUM_FILES interations
	 CLD
	 MOV  CX, 12				 ;AN000; Move 12 bytes for the filename
	 REP  MOVSB				 ;AN000; Move the filename after the path string
	 MOV  BYTE PTR [DI], 0			 ;AN000; Make string into an ASCII-Z string
	 MOV  AH, 4EH				 ;AN000; DOS Fn. for find a file
	 MOV  CX, 0				 ;AN000; Attribute used for search
	 DOSCALL				 ;AN000; Get the matching filename
	 .IF < C >				 ;AN000; Was there an error?
	      .IF < AX EQ 18 >			 ;AN000; If error no = 18, then file not found
		   JMP	FILE_NOT_FOUND		 ;AN000; Return to the user
	      .ELSE				 ;AN000; Otherwise
		   JMP	MATCH_ERROR		 ;AN000; There was some other type of disk error
	      .ENDIF				 ;AN000; Exit the subroutine
	 .ENDIF
	 MOV  DI, STR_PTR			 ;AN000; Get the pointer to the string
	 MOV  SI, FILE_PTR			 ;AN000; Get the pointer to the file list
	 .IF < LIST_TYPE EQ 1 > 		 ;AN000; Check list type for incrementing the file pointer
	      ADD  SI, 12			 ;AN000; 12 bytes between files for list type 1
	 .ELSE
	      ADD  SI, 14			 ;AN000; 14 bytes between files for list type 2
	 .ENDIF
	 MOV  FILE_PTR, SI			 ;AN000; Save the new file name pointer
	 INC  BX				 ;AN000; Increment the count of files searched for
    .ENDWHILE
    CLC 					 ;AN000; Indicate there were no errors
    MOV  AX, 1					 ;AN000; Indicate that all the files were found
    JMP  EXIT_MATCH
FILE_NOT_FOUND:
    CLC 					 ;AN000; Indicate that there were no errors
    MOV  AX, 0					 ;AN000; But, all the files were not found
    JMP  EXIT_MATCH
MATCH_ERROR:
    STC 					 ;AN000; Indicate that there were errors
EXIT_MATCH:
    POP  ES
    RET
						 ;
MATCH_FILES_ROUTINE	ENDP
;************************************************************************
;
;   CLOSE_FILE_ROUTINE: Close File
;
;   INPUT:
;      BX = The file handle of the file to close.
;
;   OUTPUT:
;	     CY = 0, AX = undefined,  successful
;	     CY = 1, AX = error code
;
;   OPERATION:
;
;   THIS MACROS CLOSES THE FILE WITH THE GIVEN FILE HANDLE.
;   IT MAKES USE OF INT 21 (AH=3EH).
;   IF AN ERROR OCCURS, THE CARRY FLAG IS SET, AND THE ERROR CODE
;   IS RETURNED IN AX.
;
;**************************************************************************
PUBLIC	 CLOSE_FILE_ROUTINE
CLOSE_FILE_ROUTINE PROC FAR
						 ;
						 ;
    CALL HOOK_INT_24				 ;AN000; Hook in the critical error handler
    MOV  INT_24_ERROR, FALSE			 ;AN000; Indicate no critical error have occured yet
    MOV  AH, 3EH				 ;AN000; DOS Fn. for closing a file
    DOSCALL					 ;AN000; Close the file
    CALL RESTORE_INT_24 			 ;AN000; Restore the old critical error handler
    RET
						 ;
CLOSE_FILE_ROUTINE ENDP
;**************************************************************
;
;   CREATE_FILE: Create new File
;
;   INPUT:
;	 DI = The address of the filename in ASCII-N format
;	 CX = The attribute to give the file
;
;   OUTPUT:
;	 If CY = 0: There were no errors.
;	      AX - The file handle of the created file.
;	 If CY = 1: There were file errors.  AX contains the error code.
;
;   OPERATION:
;
;   CREATE_FILE CREATES A FILE WITH THE GIVEN NAME USING INT 21H (AH=5BH)
;   IF AN ERROR OCCURS, THE CARRY FLAG IS SET, AND THE ERROR CODE
;   IS RETURNED IN AX.
;
;**************************************************************************
PUBLIC	 CREATE_FILE_ROUTINE
CREATE_FILE_ROUTINE	PROC FAR
						 ;
    CALL HOOK_INT_24
    CALL POS_ZERO
    MOV  DX, DI
    ADD  DX, 2
    MOV  INT_24_ERROR, FALSE
    MOV  AH,5BH
    DOSCALL
    CALL RESTORE_INT_24
    RET
						 ;
CREATE_FILE_ROUTINE	ENDP
;****************************************************************************
;
;   ERASE_FILE_ROUTINE: Routine to erase a file.
;
;   INPUT:
;	 DI - The address of an ASCII-N string containing the name of the file
;	      to erase.
;
;   OUTPUT:
;	 If CY = 0, there were no error encountered.
;	 If CY = 1, there were errors.	AX contains the DOS error code.
;
;   OPERATION:
;
;   ERASE_FILE ERASES THE FILE USING INT 21H (AH=41H).
;   IF AN ERROR OCCURS, THE CARRY FLAG IS SET, AND THE ERROR CODE
;   IS RETURNED IN AX.
;
;****************************************************************************
PUBLIC	 ERASE_FILE_ROUTINE
ERASE_FILE_ROUTINE PROC FAR

    CALL HOOK_INT_24
    CALL POS_ZERO
    MOV  INT_24_ERROR, FALSE
    MOV  DX, DI
    ADD  DX, 2
    MOV  AH,41H
    DOSCALL
    CALL RESTORE_INT_24
    RET

ERASE_FILE_ROUTINE ENDP
;****************************************************************************
;
;   CHMOD_FILE_ROUTINE: Change file attributes to read/write
;
;   SYNTAX:  CHMOD_FILE_ROUTINE
;
;   INPUT:   DI = POINTER TO ASCII-N STRING - FILE NAME
;
;   OUTPUT:  None.
;
;   OPERATION:
;      The CHMOD dos call is executed (43H) to change the file's attributes
;      to read/write.
;
;****************************************************************************
PUBLIC CHMOD_FILE_ROUTINE
CHMOD_FILE_ROUTINE PROC FAR

	CALL HOOK_INT_24
	CALL POS_ZERO
	MOV  INT_24_ERROR, FALSE
	MOV  DX, DI
	ADD  DX, 2
	MOV  AH,043H
	MOV  AL,01
	XOR  CX,CX
	DOSCALL
	CALL RESTORE_INT_24
	RET

CHMOD_FILE_ROUTINE ENDP
;************************************************************************
;   FIND_FILE: Find File
;
;   INPUT:
;	 DI - The address of an ASCII-N string contian the name of the file
;	      to find.
;	 CX - The attribute to be used in the search.
;
;   OUTPUT:
;	 If CY = 1, there were errors encountered. AX contians the DOS error
;		    code.
;	 If CY = 0, there were no errors.
;
;   OPERATION:
;
;   FINDFILE FINDS THE FIRST FILENAME SPECIFIED USING INT 21 (AH=4EH).
;   AND LOADS INFORMATION INTO THE CURRENT DTA.
;   NOTE : THE DEFAULT DTA IS AT 80H IN THE PSP.
;   IF AN ERROR OCCURS, THE CARRY FLAG IS SET, AND THE ERROR CODE
;   IS RETURNED IN AX.
;
;************************************************************************
PUBLIC	 FIND_FILE_ROUTINE
FIND_FILE_ROUTINE  PROC FAR
						 ;
    CALL HOOK_INT_24
    CALL POS_ZERO
    MOV  DX, DI
    ADD  DX, 2
    MOV  INT_24_ERROR, FALSE
						 ; CX Contains the attribute to be used in the search
    MOV  AH,4EH
    DOSCALL
    CALL  RESTORE_INT_24
    RET

FIND_FILE_ROUTINE  ENDP
;**************************************************************************
;
;   OPEN_FILE_ROUTINE - Open File
;
;   INPUT:
;	 DI - The address of an ASCII-N string containing the name of the
;	      file to open.
;	 AL - The mode to open the file with ( 0 = read, 1 = write,
;	      2 = read/write)
;
;   OUTPUT:
;	 If CY = 1, there were errors encountered.  AX contains the DOS error
;		    code.
;	 If CY = 0, there were no errors.  AX contains the file handle.
;
;   OPERATION:
;
;   THIS MACRO OPENS A FILE FOR READ/WRITE OPERATIONS.
;   IT MAKES USE OF INT 21 (AH=3DH).
;   IF AN ERROR OCCURS, THE CARRY FLAG IS SET, AND THE ERROR CODE
;   IS RETURNED IN AX.
;
;**************************************************************************
PUBLIC	 OPEN_FILE_ROUTINE
OPEN_FILE_ROUTINE  PROC FAR
						 ;
    CALL HOOK_INT_24
    CALL POS_ZERO
    MOV  INT_24_ERROR, FALSE
    MOV  DX, DI
    ADD  DX, 2
						 ; AL contains the mode for opening the file.
    MOV  AH,3DH
    DOSCALL
    CALL RESTORE_INT_24
    RET

OPEN_FILE_ROUTINE  ENDP
;**************************************************************************
;
;   RENAME_FILE_ROUTINE - Rename File
;
;   INPUT:
;	 SI - The address of an ASCII-N string containing the file to rename
;	      current file name.
;	 DI - The address of an ASCII-N string containing the new name for the
;	      file.
;
;   OUTPUT:
;	 If CY = 1, there were errors encountered.  AX contains the DOS error
;		   error code.
;	 If CY = 0, there were no errors.
;
;
;   OPERATION:
;
;   THIS MACRO RENAMES A FILE GIVEN 2 NAMES.
;   IT MAKES USE OF INT 21 (AH=56H).
;   IF AN ERROR OCCURS, THE CARRY FLAG IS SET, AND THE ERROR CODE
;   IS RETURNED IN AX.
;
;**************************************************************************
PUBLIC	 RENAME_FILE_ROUTINE
RENAME_FILE_ROUTINE	PROC FAR

    CALL HOOK_INT_24
    PUSH ES
    PUSH DS
    POP  ES
    PUSH DI
    ; SI Contains the address of the string containing the old filename.
    MOV  DI, SI
    CALL POS_ZERO
    MOV  DX, DI
    ADD  DX, 2

    POP  DI
    ; DI contains the address of the string containing the new filename.
    CALL POS_ZERO
    ADD  DI, 2

    MOV  INT_24_ERROR, FALSE
    MOV  AH,56H
    DOSCALL
    POP  ES
    CALL  RESTORE_INT_24
    RET

RENAME_FILE_ROUTINE	ENDP
;**************************************************************************
;
;   READ_FILE_ROUTINE: Transfer the specified number of bytes from a file into a
;	buffer location.
;
;   INPUT:
;	BX - The handle of the file to read.
;	DX - The address of where to store the data
;	CX - The number of characters to read
;
;   OUTPUT:
;	CY = 0, Read success.  AX - number of bytes read
;	CY = 1, Read error. AX contains the error code.
;
;   OPERATION:
;
;   THIS MACRO READS TO AN ALREADY OPENED FILE.
;   IT MAKES USE OF INT 21 (AH=3FH).
;   AX WILL RETURN THE NUMBER BYTES ACTUALLY WRITTEN.
;
;************************************************************************
PUBLIC	 READ_FILE_ROUTINE
READ_FILE_ROUTINE  PROC FAR
						 ;
    CALL HOOK_INT_24
    MOV  INT_24_ERROR, FALSE
						 ; BX - The file handle
						 ; CX - The number of bytes to read
						 ; DX - The address of the buffer to store the data
    MOV  AH,3FH
    DOSCALL
    CALL RESTORE_INT_24
    RET

READ_FILE_ROUTINE  ENDP
;**************************************************************************
;
;   WRITE_FILE_ROUTINE: Transfer the specified number of bytes from a buffer into a
;	specified file.
;
;   INPUT:
;	BX - The handle of the file to write to.
;	DX - The address of where the data is stored.
;	CX - The number of characters to write.
;
;   OUTPUT:
;	CY = 0, Write success.	AX - number of bytes written.
;	CY = 1, Write error. AX contains the error code.
;
;   OPERATION:
;
;   THIS MACRO WRITES TO AN ALREADY OPENED FILE.
;   IT MAKES USE OF INT 21 (AH=3DH).
;   AX WILL RETURN THE NUMBER BYTES ACTUALLY WRITTEN.
;
;************************************************************************
PUBLIC	 WRITE_FILE_ROUTINE
WRITE_FILE_ROUTINE PROC FAR
						 ;
    CALL HOOK_INT_24
    MOV  INT_24_ERROR, FALSE
						 ; BX - The file handle
						 ; CX - The number of bytes to read
						 ; DX - The address of the buffer to store the data
    MOV  AH,40H
    DOSCALL
    CALL RESTORE_INT_24
    RET

WRITE_FILE_ROUTINE ENDP
;***************************************************************************
;
;   CHECK_DISK:  Check is the specified fixed disk is present.	If disk is
;	present, return disk partition status.
;
;   INPUT:
;	AX = 1: First fixed disk.
;	   = 2: Second fixed disk.
;
;   OUTPUT:
;	CX = 0: Disk not present.
;	   = 1: Disk present - No DOS or EDOS partitions
;	   = 2: Disk present - DOS or EDOS partitions exist
;	BX = 01H: Primary DOS partition exists
;	   = 02H: Extended DOS partitions exists
;	   = 04H: Logical drives exist
;	   = 08H: Free space exists in EDOS partition
;	   = 10H: Free space exists on disk
;			      More than one status bit can be set
;	DX = 0: There is no free space in EDOS partition and the
;		disk.
;	   = 1: There is free space in the EDOS partition.
;	   = 2: There is no EDOS partition, but there is free
;			  disk space.
;	DI = Buffer for fixed disk status information.
;
;   OPERATION:	A call is performed to the FDISK utility (GET_DISK_STATUS)
;	to get the status of the specified fixed disk drive.  The returned
;	status information is checked and the memory variables are set as
;	specified above.
;
;***************************************************************************
PUBLIC	 CHECK_DISK_ROUTINE
CHECK_DISK_ROUTINE PROC FAR
						 ;
    PUSH ES					 ;AN000; Make ES = DS
    PUSH DS
    POP  ES
    PUSH DI
    ADD  DI, 2
    CALL GGET_STATUS
    POP  DI
    MOV  [DI+1], CL				 ;AN000; Store the number of table entries
    .IF < ZERO AX >
	 .IF < BIT BX AND M_DOS_EDOS_PART >
	      MOV  CX, PRESENT_WITH_PART
	 .ELSE
	      MOV  CX, PRESENT_WITHOUT_PART
	 .ENDIF
    .ELSE
	 MOV  CX, NOT_PRESENT
    .ENDIF
    MOV  DX, NO_EDOS_SPACE			 ;AN000; Initialize
    .IF < BIT BX AND M_EDOS_EXISTS >		 ;AN000; Does the extended DOS partition exist?
	 .IF < BIT BX AND M_EDOS_SPACE >	 ;AN000; Yes! Is there free space in it?
	      MOV  DX, FREE_EDOS_SPACE		 ;AN000; Indicate that there is free space
	 .ELSEIF < BIT BX NAND M_FREE_SPACE >	 ;AN000; Is there no free space on the disk?
	      MOV  DX, NO_EDOS_SPACE		 ;AN000; Indicate there is no free space in EDOS or on the disk.
	 .ENDIF
    .ELSEIF < BIT BX AND M_FREE_SPACE >		 ;AN000; No! There is no EDOS partition
	 MOV  DX, NO_EDOS_BUT_SPACE		 ;AN000; But there is free space on the disk
    .ENDIF
    POP  ES
    RET
						 ;
CHECK_DISK_ROUTINE ENDP
;************************************************************************;;
;
;   CHECK_VALID_MEDIA:	Check if the diskettes attached will support
;	installation of SELECT.  Also, check if install destination will
;	be selected by user or determined by SELECT.
;
;   SYNTAX:  CHECK_VALID_MEDIA	var_disk_a, var_disk_b, var_tot, var_disk,
;				var_def, var_index, var_option
;
;   INPUT:
;	var_disk_a  =  diskette A presence and type
;	var_disk_b  =  diskette B presence and type
;	var_tot     =  total number of dikettes
;	var_disk    =  0: first fixed disk is not present
;		    >  0: first fixed disk is present
;
;   OUTPUT:
;	CY = 0: Success variables are returned as defined below.
;	CY = 1: Error - invalid media
;	var_def   =  0 use default destination drive
;		  =  1 default destination drive not applicable
;	var_index =  1 default destination is drive C
;		  =  2 default destination is drive B
;	var_option = 1 possible drive B or C
;		   = 2 possible drive A or C
;		   = 3 possible drive A or B or C
;		   = 4 possible drive A or B
;
;   OPERATION:	The diskette drive types are checked for valid media type.
;	If the diskette media types are valid, a check is made to determine if
;	install destination will be user selected or will be determined by
;	SELECT.  The following checks are made.
;
;	 - if one diskette, return valid media and default destination is A
;
;	 - If two diskettes only, return valid and:
;	       if A = B, default = B
;	       if A <> B, default = A
;	       if A and B are mixed 720 and 1.44, destination option is A or B
;
;	 - If one diskette and a fixed disk only, return valid media and
;	   destination option is drive A or C.
;
;	 - If two diskettes and a fixed disk, return valid media and:
;	       if A = B, destination option is B or C
;	       if A <> B, destination option is A or C
;	       if A and B are mixed 720 and 1.44, destination option is
;		 A or B or C
;
;************************************************************************;;
PUBLIC	 CHECK_VALID_MEDIA_ROUTINE
CHECK_VALID_MEDIA_ROUTINE    PROC FAR


    VAR_DISK_A	   EQU	     AL
    VAR_DISK_B	   EQU	     BL
    VAR_DEF	   EQU	     CL
    VAR_INDEX	   EQU	     DX
    VAR_DISK	   EQU	     SI
    VAR_OPTION	   EQU	     DI

    .IF < VAR_DISK_A NE E_DISKETTE_INV >	 ;AN111; Is disk A present
	 .IF <VAR_DISK_B NE E_DISKETTE_INV>	 ;AN111; Is disk B present
	      .IF < VAR_DISK GT 0 >		 ;AN111; Hard disk is present?
		   MOV	  VAR_DEF, DO_NOT_USE_DEFAULT ;AN111; Yes! Destination drive is undefined
		   MOV VAR_OPTION,E_OPTION_B_C	 ;AN111; options will be B or C
		   MOV	  VAR_INDEX,DEF_DEST_C	 ;AN073; SEH highlight option C
		   CLC				 ;AN111; Indicate valid media
	      .ELSE
		   MOV	VAR_DEF, USE_DEFAULT	 ;AN111; Yes! Use the default destination = B
		   MOV	VAR_INDEX, DEF_DEST_B	 ;AN111; Drive B is that default
		   CLC				 ;AN111; Indicate valid media
	      .ENDIF
	 .ELSE
	      .IF < VAR_DISK GT 0 >		 ;AN111; Hard disk is present?
		   MOV	  VAR_DEF, DO_NOT_USE_DEFAULT ;AN111; Yes! Destination drive is undefined
		   MOV	  VAR_OPTION, E_OPTION_A_C ;AN111; options are A or C
		   MOV	  VAR_INDEX,DEF_DEST_C	 ;AN073; SEH highlight option C
		   CLC				 ;AN111; Indicate valid media
	      .ELSE
		   MOV	  VAR_DEF, USE_DEFAULT	 ;AN111; no, Use the default destination
		   MOV	  VAR_INDEX, DEF_DEST_A  ;AN111; Drive A is that default
		   CLC				 ;AN111; Indicate valid media
	      .ENDIF
	 .ENDIF
    .ELSE
	 STC					 ;AN111; Indicate invalid media
    .ENDIF
    RET

CHECK_VALID_MEDIA_ROUTINE    ENDP
;************************************************************************;;
;
;   SCAN_DISK_TABLE:  Scan the specified disk status table from the
;	specified index item for specified field and return status information.
;
;   INPUT:
;	CX = 1: First fixed disk
;	   = 2: Second fixed disk
;	AX = Index of the information to return
;
;   OUTPUT:
;	AX = 0: Success - Index into table is valid
;	   = 1: Error - Index invalid or end of table
;	N_NAME_PART   = Partition name.
;	N_SIZE_PART   = Partition size.
;	N_STATUS_PART = Partition status
;	P_DRIVE_PART  = Drive letter assigned.
;	P_LEVEL1_PART  = Version number (1st part).   For DOS 4.00 1st part = blank
;	P_LEVEL2_PART  = Version number (2nd part).   For DOS 4.00 2nd part = 4
;	P_LEVEL3_PART  = Version number (3rd part).   For DOS 4.00 3rd part = .
;	P_LEVEL4_PART  = Version number (4th part).   For DOS 4.00 4th part = 0
;
;   OPERATION:
;      Starts scanning the disk table from the point indicated by var_index
;      for either the name, status or type.  The table is scanned until either
;      the desired entry is found, or the end of the table is reached.	If
;      the end of the table is reached before a matching entry is found, then
;      var_ret returns 1, else if an entry is found, it returns 0.
;      If found, var_index will also return the index of the entry.
;
;      Note:  The index of the first entry in the table is 1.
;
;************************************************************************;;
PUBLIC	 SCAN_DISK_TABLE_ROUTINE
SCAN_DISK_TABLE_ROUTINE PROC FAR

    MOV  BX, 0
    .IF < CX EQ TABLE_ONE >
	 MOV  SI, OFFSET DISK_1_START		 ;AN000; Get the address of the first table
	 MOV  BL, DISK_1_VAL_ITEM		 ;AN000; Number of entries in the first table
    .ELSE
	 MOV  SI, OFFSET DISK_2_START		 ;AN000; Get the address of the second table
	 MOV  BL, DISK_2_VAL_ITEM		 ;AN000; Number of entries in the second table
    .ENDIF
    .IF < AX BE BX >
						 ; AX contains the index
	 DEC  AX				 ;AN000; Make the first index a 0
	 MOV  DX, TYPE DISK_STATUS		 ;AN000; Number of bytes in the structure
	 MUL  DX				 ;AN000; Calculate the offset into the table
	 ADD  SI, AX				 ;AN000; Add to the address of the table
	 COPY_BYTE	 N_NAME_PART,	[SI].N_PART_NAME   ;AN000; Copy the table entries
	 COPY_WORD	 N_SIZE_PART,	[SI].N_PART_SIZE
	 COPY_BYTE	 N_STATUS_PART, [SI].N_PART_STATUS
	 COPY_BYTE	 P_DRIVE_PART,	[SI].P_PART_DRIVE
	 COPY_BYTE	 N_TYPE_PART,	[SI].N_PART_TYPE
	 COPY_BYTE	 N_LEVEL1_PART, [SI].N_PART_LEVEL1 ;AN065;SEH 1st part of version number   For DOS 4.00 1st part = blank
	 COPY_BYTE	 N_LEVEL2_PART, [SI].N_PART_LEVEL2 ;AN065;SEH 2nd part of version number   For DOS 4.00 2nd part = 4
	 COPY_BYTE	 N_LEVEL3_PART, [SI].N_PART_LEVEL3 ;AN065;SEH 2nd part of version number   For DOS 4.00 3rd part = .
	 COPY_BYTE	 N_LEVEL4_PART, [SI].N_PART_LEVEL4 ;AN065;SEH 2nd part of version number   For DOS 4.00 4th part = 0
	 MOV  AX, DATA_VALID
    .ELSE
	 MOV  AX, DATA_INVALID
    .ENDIF
    RET

SCAN_DISK_TABLE_ROUTINE ENDP
;************************************************************************;;
;
;   UPDATE_DISK_TABLE:	Update the specifed disk status table for the
;	specified index item.
;
;   INPUT:
;	CX = 1: First fixed disk
;	   = 2: Second fixed disk
;	AX = Index into table
;
;   OUTPUT:
;	AX = 0: Success - Index into table is valid
;	   = 1: Error	- Index into table is not valid
;	partition name	 = N_NAME_PART
;	partition size	 = N_SIZE_PART
;	partition status = N_STATUS_PART
;	partition type	 = N_TYPE_PART
;	drive letter	 = P_DRIVE_PART
;
;   OPERATION:	If the index into the disk table is valid, the disk table
;	is updated for the specifed index.  Disk status information is obtained
;	from pre-defined locations as specified above.
;
;************************************************************************;;
PUBLIC	 UPDATE_DISK_TABLE_ROUTINE
UPDATE_DISK_TABLE_ROUTINE    PROC FAR

    MOV  BH, 0
    .IF < CX EQ TABLE_ONE >
	 MOV  SI, OFFSET DISK_1_START		 ;AN000; Get the address of the first table
	 MOV  BL, DISK_1_VAL_ITEM		 ;AN000; Number of entries in the first table
    .ELSE
	 MOV  SI, OFFSET DISK_2_START		 ;AN000; Get the address of the second table
	 MOV  BL, DISK_2_VAL_ITEM		 ;AN000; Number of entries in the second table
    .ENDIF
						 ; AX contains the index.
    DEC  AX					 ;AN000; Make the first index a 0
    MOV  DX, TYPE DISK_STATUS			 ;AN000; Number of bytes in the structure
    MUL  DX					 ;AN000; Calculate the offset into the table
    ADD  SI, AX 				 ;AN000; Add to the address of the table
    .IF < VAR_INDEX BE BX >
	 COPY_BYTE	[SI].N_PART_NAME,   N_NAME_PART
	 COPY_WORD	[SI].N_PART_SIZE,   N_SIZE_PART
	 COPY_BYTE	[SI].N_PART_STATUS, N_STATUS_PART
	 COPY_BYTE	[SI].P_PART_DRIVE,  P_DRIVE_PART
	 COPY_BYTE	[SI].N_PART_TYPE,   N_TYPE_PART
	 MOV	 AX, DATA_VALID 		 ;AN000; No error.
    .ELSE
	 MOV	 AX, DATA_INVALID		 ;AN000; Indicate an error
    .ENDIF
    RET
						 ;
UPDATE_DISK_TABLE_ROUTINE    ENDP
						 ;
CODE_FAR ENDS
						 ;
END
