	PAGE	,132			;
	TITLE	COMPPAR.SAL - LOOK AT COMMAND LINE PARMS
;****************** START OF SPECIFICATIONS *****************************
; MODULE NAME: COMPPAR.SAL
;
; DESCRIPTIVE NAME: Handle the definition of the DOS command line parameters
;		    and the interface to the DOS system PARSER.
;
;FUNCTION: The static data areas are prescribed by the DOS system PARSER
;	   to define the several parameters presented to COMP.	These
;	   data areas are passed to the PARSER, and its responses checked
;	   to determine the nature of the user's specifications.  Any errors
;	   found in the user's parameters are defined in messages back
;	   to the user.
;
; ENTRY POINT: PARSER, near
;
; INPUT: (DOS COMMAND LINE PARAMETERS)
;
;	[d:][path] COMP [d:][path][filenam1[.ext]] [d:][path][filenam2[.ext]]
;
;	 Where
;	 [d:][path] before COMP to specify the drive and path that
;		    contains the COMP command file.
;
;	 [d:][path][filenam1[.ext]] -  to specify the FIRST (or primary)
;		    file or group of files to be compared
;
;	 [d:][path][filenam2[.ext]]  - to specify the SECOND file or group
;		    of files to be compared with the corresponding file
;		    from the FIRST group
;
;	 Global filename characters are allowed in both filenames,
;	 and will cause all of the files matching the first filename
;	 to be compared with the corresponding files from the second
;	 filename.  Thus, entering COMP A:*.ASM B:*.BAK will cause
;	 each file from drive A:  that has an extension of .ASM to be
;	 compared with a file of the same name (but with an extension
;	 of .BAK) from drive B:.
;
;	 If you enter only a drive specification, COMP will assume
;	 all files in the current directory of the specified drive.
;	 If you enter a path without a filename, COMP assumes all
;	 files in the specified directory.  Thus, COMP A:\LEVEL1
;	 B:\LEVEL2 will compare all files in directory A:\LEVEL1 with
;	 the files of the same names in directory B:\LEVEL2.
;
;	 If no parameters are entered with the COMP command, you will
;	 be prompted for both.	If the second parm is omitted, COMP
;	 will prompt for it.  If you simply press ENTER when prompted
;	 for the second filename, COMP assumes *.* (all files
;	 matching the primary filename), and will use the current
;	 directory of the default drive.
;
;	 If no file matches the primary filename, COMP will prompt
;	 again for both parameters.
;
;
;	Upon entry to PARSER in this module,
;	"CURRENT_PARM" = offset to start of parm text in command string
;	"ORDINAL" = initialized to zero
;	PSP+81H = text of DOS command line parms string
;
; EXIT-NORMAL: If a Code Page number was specified
;		  BX = Offset to language table to be loaded
;		  DX = Integer value of Code Page specified
;	       If /STATUS (or /STA) was specified
;		  BX = 0
;	       If Question mark was specified
;		  BX=-1
;
; EXIT-ERROR: If there was any problem with the parms,
;	      the question mark is assumed, and the appropriate
;	      PARSE error message is displayed.
;	      The Errorlevel code of "EXPAR" (3), meaning: "PARM ERROR",
;	      set in "EXITFL", is requested to be returned to the user.
;
; INTERNAL REFERENCES:
;    ROUTINES:
;	PARSE_ERROR:NEAR Display the appropriate Parse error message.
;
;    DATA AREAS:
;	The several parameter control blocks, defined by the System
;	PARSER interface, defining the COMP parameters.
;
; EXTERNAL REFERENCES:
;    ROUTINES:
;	SENDMSG:NEAR	Uses Msg Descriptor to drive message handler.
;	SYSPARSE:NEAR	System Command Line Common Parser.
;
;    DATA AREAS:
;	EXITFL:BYTE	Errorlevel return code.
;	MSGNUM_PARSE:WORD Message descriptor for all parse errors.
;
; COPYRIGHT: The following notice is found in the OBJ code generated from
;	     the "COMPSM.SAL" module:
;
;	     "The DOS COMP Utility"
;	     "Version 4.0  (C) Copyright 1988 Microsoft"
;	     "Licensed Material - Property of Microsoft"
;
;****************** END OF SPECIFICATIONS *****************************
	IF1
	    %OUT    COMPONENT=COMP, MODULE=COMPPAR.SAL...
	ENDIF
; =  =	=  =  =  =  =  =  =  =	=  =
HEADER	MACRO	TEXT			;
.XLIST					;
	SUBTTL	TEXT			;
.LIST					;
	PAGE				;
	ENDM				;
; =  =	=  =  =  =  =  =  =  =	=  =
;		      $SALUT (4,23,28,36)

		      INCLUDE COMPEQ.INC
;		      LOCAL EQUATES
MAX_PATH_LEN	      EQU  64	   ;MAX CHAR IN A PATH
EXPAR		      EQU  1	   ;RETURN TO DOS, INVALID DOS COMMAND LINE PARMS
ZERO_PARM_CT	      EQU  0	   ;ORDINAL VALUE BEFORE FIRST PARM FOUND
FIRST_PARM_CT	      EQU  1	   ;ORDINAL VALUE AFTER FIRST PARM FOUND
NUL		      EQU  0	   ;ASCIIZ STRING DELIMITER
; =  =	=  =  =  =  =  =  =  =	=  =
;		      EXIT CODES FROM SYSPARSE (WHEN CY=0)

SYSPRM_EX_OK	      EQU  0	   ; no error
SYSPRM_EX_MANY	      EQU  1	   ; too many operands
SYSPRM_EX_MISSING     EQU  2	   ; required operand missing
SYSPRM_EX_NOT_SWLIST  EQU  3	   ; not in switch list provided
SYSPRM_EX_NOT_KEYLIST EQU  4	   ; not in keyword list provided
SYSPRM_EX_RANGE       EQU  6	   ; out of range specified
SYSPRM_EX_VALUE       EQU  7	   ; not in value list provided
SYSPRM_EX_STRING      EQU  8	   ; not in string list provided
SYSPRM_EX_SYNTAX      EQU  9	   ; syntax error
SYSPRM_EX_EOL	      EQU  -1	   ; end of command line
; =  =	=  =  =  =  =  =  =  =	=  =
		      HEADER <STRUC - DEFINITIONS OF EXTERNAL CONTROL BLOCKS>
PSP		      STRUC
		      DB   80H DUP (?) ;SKIP OVER FIRST HALF OF PSP
PSP_PARMLEN	      DB   ?	   ;NUMBER OF BYTES IN DOS COMMAND LINE
PSP_COMMAND	      DB   127 DUP(?) ;TEXT OF DOS COMMAND LINE
PSP		      ENDS
; =  =	=  =  =  =  =  =  =  =	=  =
FILESPEC	      STRUC
FS_DRIVE_ID	      DB   ?	   ;DRIVE LETTER
FS_COLON	      DB   ":"	   ;COLON SEPARATOR
FS_SLASH1	      DB   "\"	   ;LEADING BACKSLASH,START AT ROOT
FS_PATH 	      DB   MAX_PATH_LEN DUP (0) ;TEXT OF PATH

;LOCATION OF REMAINING FIELDS DEPENDS ON LENGTH OF ACTUAL PATH
;POSITIONS SHOWN ARE FOR MAX PATH LENGTH ONLY

FS_SLASH2	      DB   0	   ;TRAILING BACKSLASH
FS_FNAME	      DB   8 DUP (0) ;FILENAME
FS_PER		      DB   0	   ;PERIOD END OF FILENAME
FS_EXT		      DB   3 DUP (0) ;FILENAME EXTENSION
FILESPEC	      ENDS
; =  =	=  =  =  =  =  =  =  =	=  =
		      HEADER <PARSING WORKAREAS>
;	     $SALUT (4,14,19,36)
CSEG	     SEGMENT PARA PUBLIC 'CODE'
	     ASSUME CS:CSEG,DS:CSEG,ES:CSEG,SS:CSEG

	     EXTRN SENDMSG:NEAR    ;USES MSG DESCRIPTOR TO DRIVE MESSAGE HANDLR
	     EXTRN SYSPARSE:NEAR   ;SYSTEM COMMAND LINE PARSER

	     EXTRN EXITFL:BYTE	   ;ERRORLEVEL RETURN CODE
	     EXTRN PATH1:BYTE	   ;FIRST POSITIONAL PARM
	     EXTRN PATH2:BYTE	   ;SECOND POSITIONAL PARM
	     EXTRN MSGNUM_PPARSE:WORD ;MESSAGE DESCRIPTOR FOR ALL PARSE ERRORS
	     EXTRN SUBLIST_24:WORD ;sublist for parse error messages
; =  =	=  =  =  =  =  =  =  =	=  =

CURRENT_PARM DW   81H		   ;POINTER INTO COMMAND OF NEXT OPERAND
	     PUBLIC CURRENT_PARM

ORDINAL      DW   0		   ;ORDINAL NUMBER OF WHICH PARM TO PARSE
	     PUBLIC ORDINAL

PARM_COUNT   DW   00H		   ;CURRENT PARM COUNT (USED TO TRICK "PARSER"
	     PUBLIC PARM_COUNT	   ;INTO PARSING FILE NAMES ENTERED FROM THE
				   ;KEYBOARD INSTEAD OF COMMAND LINE
; =  =	=  =  =  =  =  =  =  =	=  =
	     HEADER <DOS COMMAND LINE PARSER CONTROL BLOCKS>

;INPUT PARAMETERS CONTROL BLOCK, POINTED TO BY ES:DI WHEN CALLING PARSER

	     PUBLIC PARMS	   ;LET LINK MAKE PARMS BLOCK ADDRESSABLE
PARMS	     LABEL BYTE 	   ;PARMS CONTROL BLOCK
	     DW   PARMSX	   ;POINTER TO PARMS EXTENSION
	     DB   0		   ; NUMBER OF STRINGS (0, 1, 2)
				   ; NEXT LIST WOULD BE EXTRA DELIM LIST
				   ;  (,& WHITESPACE ALWAYS)
				   ; NEXT LIST WOULD BE EXTRA END OF LINE LIST
				   ;  (CR,LF,0 ALWAYS)

;SYSTEM PARSER PARAMETER EXTENSION CONTROL BLOCK
PARMSX	     LABEL BYTE 	   ;PARMS EXTENSION CONTROL BLOCK
	     DB   0,2		   ; MIN, MAX POSITIONAL OPERANDS ALLOWED
	     DW   CONTROL_POS	   ; DESCRIPTION OF POSITIONAL 1
	     DW   CONTROL_POS	   ; DESCRIPTION OF POSITIONAL 2

	     DB   0		   ; MAX SWITCH OPERANDS ALLOWED

	     DB   0		   ; MAX KEYWORD OPERANDS ALLOWED
				   ; THERE IS NO CONTROL BLOCK
				   ;  DEFINING KEYWORDS

; = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
	     HEADER <POSITIONAL PARM DESCRIPTOR BLOCK>
;PARSER CONTROL BLOCK DEFINING THE ONLY POSITIONAL PARAMETER, OPTIONAL
;BOTH POSITIONAL PARAMETER ARE:
;	[d:][path][filename[.ext]]

	     PUBLIC CONTROL_POS    ;LET LINK MAKE THIS ADDRESSABLE
CONTROL_POS  LABEL BYTE 	   ;FIRST POSITIONAL DESCRIPTOR FOR FILESPEC,
				   ; OPTIONAL
	     DW   0201H 	   ; CONTROLS TYPE MATCHED
				   ; SELECTED BITS: "FILESPEC" AND "OPTIONAL"

				   ; 8000H=NUMERIC VALUE, (VALUE LIST WILL BE CHECKED)
				   ; 4000H=SIGNED NUMERIC VALUE (VALUE LIST WILL BE
				   ;   CHECKED)
				   ; 2000H=SIMPLE STRING(VALUE LIST WILL BE CHECKED)
				   ; 1000H=DATE STRING (VALUE LIST WON'T BE CHECKED)
				   ; 0800H=TIME STRING (VALUE LIST WON'T BE CHECKED)
				   ; 0400H=COMPLEX LIST (VALUE LIST WON'T BE CHECKED)
				   ; 0200H=FILE SPEC (VALUE LIST WON'T BE CHECKED)
				   ; 0100H=DRIVE ONLY (VALUE LIST WON'T BE CHECKED)
				   ; 0080H=QUOTED STRING (VALUE LIST WON'T BE CHECKED)
				   ; 0010H=IGNORE ":" AT END IN MATCH
				   ; 0002H=REPEATS ALLOWED
				   ; 0001H=OPTIONAL

	     DW   0001H 	   ;FUNCTION_FLAGS
				   ; 0001H=CAP RESULT BY FILE TABLE
				   ; 0002H=CAP RESULT BY CHAR TABLE
				   ; 0010H=REMOVE ":" AT END
	     DW   RESULT1	   ; RESULT BUFFER
	     DW   NOVALS	   ; VALUE LISTS
	     DB   0		   ; NUMBER OF KEYWORD/SWITCH SYNONYMS
				   ;   IN FOLLOWING LIST

; = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
;RESULTS CONTROL BLOCK FOR THE POSITIONAL PARAMETER
RESULT1      LABEL BYTE 	   ; BELOW FILLED IN FOR DEFAULTS
	     DB   5		   ; TYPE RETURNED: 0=RESERVED,
				   ;	   1=NUMBER, 2=LIST INDEX,
				   ;	   3=STRING, 4=COMPLEX,
				   ;	   5=FILESPEC, 6=DRIVE
				   ;	   7=DATE, 8=TIME
				   ;	   9=QUOTED STRING
RESULT_TAG   DB   0FFH		   ; MATCHED ITEM TAG
	     DW   0		   ;POINTER TO SYNONYM

RESULT_PTR1  DD   ?		   ; OFFSET OF STRING VALUE

; = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
;VALUE CONTROL BLOCK
NOVALS	     LABEL BYTE
	     DB   0		   ; NUMBER OF VALUE DEFINITIONS (0 - 3)

; =  =	=  =  =  =  =  =  =  =	=  =
	     HEADER <PARSER - ASK SYSPARM TO DECODE PARAMETERS>
;  $SALUT (4,4,9,36)
PARSER PROC NEAR
   PUBLIC PARSER

;INPUT: "CURRENT_PARM" = OFFSET TO NEXT PARM IN COMMAND STRING
;	"ORDINAL" = COUNT OF NEXT PARM TO PARSE
;	PSP+81H = TEXT OF DOS COMMAND LINE PARMS STRING

;OUTPUT: IF SPECIFIED, FIRST PARM GOES TO "PATH1".
;	 IF SPECIFIED, SECOND PARM GOES TO "PATH2".
;	 IF EITHER PARM MISSING, THEN "PATHn" STARTS WITH NUL CHAR.
;	 CARRY SET IF ERROR.
; =  =	=  =  =  =  =  =  =  =	=  =

;  $SEARCH COMPLEX		   ;LOOP THRU COMMAND LINE
   JMP SHORT $$SS1
$$DO1:
				   ;LOOKING AT RETURN CODE FROM SYSPARSE...
       AND  AX,AX		   ;AN008; ;WERE THERE ANY ERRORS?
;  $EXITIF NE			   ;HAD A PROBLEM
   JE $$IF1
       CALL PARSE_ERROR 	   ;DISPLAY REASON FOR ERROR
       MOV  AL,01h		   ;AN000; ;pass back errorlevel ret code
       mov  ah,4ch
       int  21h
;  $ORELSE			   ;SINCE NO PROBLEM, SO FAR
   JMP SHORT $$SR1
$$IF1:
       MOV  ORDINAL,CX		   ;SAVE UPDATED COUNT
       MOV  CURRENT_PARM,SI	   ;REMEMBER HOW FAR I GOT
       MOV  BX,DX		   ;SET DATA BASE REG TO POINT TO
				   ;RESULT BUFFER OF THIS OPERAND

       MOV  SI,WORD PTR RESULT_PTR1 ;GET WHERE STRING IS PUT
				   ;GUESS, THIS IS THE FIRST PARM
       MOV  DI,OFFSET PATH1	   ;GET WHERE STRING IS TO GO

				   ;IF PARSING FILENAME INPUTED FROM KEYBOARD
				   ;THEN PARM_COUNT MUST = ZERO_PARM_CT = 0
       CMP  CX,PARM_COUNT	   ;IS THIS THE FIRST PARM OR JUST A FILENAME IN BUFFER

;      $IF  NE			   ;NO, MUST BE THE SECOND PARM
       JE $$IF4
				   ;MADE A BAD GUESS, FIX IT
	   MOV	DI,OFFSET PATH2    ;CHANGE DEST TO WHERE SECOND STRING GOES
;      $ENDIF
$$IF4:

				   ;MOVE ASCIIZ STRING FROM DS:SI
				   ;WHERE COMMAND PARSE PUT IT
				   ;TO ES:DI WHERE COMP2 USES IT

;      $DO  COMPLEX
       JMP SHORT $$SD6
$$DO6:
	   STOSB		   ;PUT CHAR IN AL TO ES:DI
;      $STRTDO
$$SD6:
	   LODSB		   ;GET CHAR FROM DS:SI TO AL
	   CMP	AL,NUL		   ;IS THAT THE END OF STRING?
;      $ENDDO E 		   ;IF SO, QUIT
       JNE $$DO6

;  $STRTSRCH
$$SS1:
       LEA  DI,PARMS		   ;ES:DI = PARSE CONTROL DEFINITON
       MOV  SI,CURRENT_PARM	   ;DS:SI = COMMAND STRING, NEXT PARM
       XOR  DX,DX		   ;RESERVED, INIT TO ZERO
       MOV  CX,ORDINAL		   ;OPERAND ORDINAL, INITIALLY ZERO
       CALL SYSPARSE		   ;LOOK AT DOS PARMS
				   ;AX=EXIT CODE
				   ;BL=TERMINATED DELIMETER CODE
				   ;CX=NEW OPERAND ORDINAL
				   ;SI=SET TO PAST SCANNED OPERAND
				   ;DX=SELECTED RESULT BUFFER
       CMP  AX,SYSPRM_EX_EOL	   ;IS THAT THE END OF THE PARMS?
				   ;IF NOT, LOOP BACK AND FIND OUT
				   ;WHAT THAT PARM IS
;  $ENDLOOP E			   ;END OF LIST
   JNE $$DO1
       CLC			   ;RETURN FLAG FOR "NO ERROR"
;  $ENDSRCH			   ;FINISHED WITH DOS COMMAND LINE
$$SR1:
   RET				   ;RETURN TO CALLER
PARSER ENDP
; =  =	=  =  =  =  =  =  =  =	=  =
   HEADER <PARSE_ERROR - DISPLAY REASON FOR PARSE ERROR>
PARSE_ERROR PROC NEAR

;INPUT: "FIRST_TIME" - IF NON-ZERO, FORCE ERROR CODE TO "TOO MANY PARMS"
;	 AX - ERROR NUMBER RETURNED FROM PARSE.
;OUTPUT: APPROPRIATE ERROR MESSAGE IS DISPLAYED.
; =  =	=  =  =  =  =  =  =  =	=  =

   MOV	MSGNUM_PPARSE,AX	   ;PASS MESSAGE NUMBER TO DESCRIPTOR
   MOV	DX,OFFSET MSGNUM_PPARSE     ;PASS MESSAGE DESCRIPTOR
   MOV	BX,CURRENT_PARM
PE_BX:
   CMP	BX,SI			   ;are we past the point the parser stopped ?
   JAE	PE_BX_OK		   ;yes, we are done.
   CMP	BYTE PTR [BX],20H	   ;by-pass leading blanks
   JNE	PE_BX_OK
   INC	BX
   JMP	PE_BX
PE_BX_OK:
   MOV	SUBLIST_24.SUB_VALUE,BX
;
;make a ASCIIZ string out of parameter
;
PE_LOOP:
   CMP	BX,SI			   ;are we past the point the parser stopped ?
   JAE	PE_OK			   ;yes, we are done.
   CMP	BYTE PTR [BX],20H	   ;check for spaec or end of line
   JE	PE_OK
   INC	BX
   JMP	PE_LOOP
PE_OK:
   MOV	byte ptr [BX],00H	   ;end string with zero

   CALL SENDMSG 		   ;DISPLAY ERROR MESSAGE

   MOV	EXITFL,EXPAR		   ;ERRORLEVEL CODE TO "PARM ERROR"
   RET				   ;RETURN TO CALLER
PARSE_ERROR ENDP
; =  =	=  =  =  =  =  =  =  =	=  =
CSEG ENDS
   END
