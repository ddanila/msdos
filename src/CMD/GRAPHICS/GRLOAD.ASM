	PAGE	,132
	TITLE	DOS - GRAPHICS Command  -	Profile Load Modules
;; DOS - GRAPHICS Command
;; (C) Copyright 1988 Microsoft
;; File Name:  GRLOAD.ASM
;; ----------
;; Description:
;; ------------
;;   This file contains the modules used to load the
;;   GRAPHICS profile into resident memory.
;;   ************* The EGA Dynamic Save Area will be built (by
;;   **  NOTE	** CHAIN_INTERRUPTS in file GRINST.ASM) over top of these
;;   ************* modules to avoid having to relocate this save just before
;;   terminating.  This is safe since the maximum memory used is
;;   288 bytes and the profile loading modules are MUCH larger than
;;   this.  So GRLOAD.ASM MUST be linked before GRINST.ASM and after
;;   GRPRINT.ASM.
;; Documentation Reference:
;; ------------------------
;;	 PLACID Functional Specifications
;;	 OASIS High Level Design
;;	 OASIS GRAPHICS I1 Overview
;; Procedures Contained in This File:
;; ----------------------------------
;;	 LOAD_PROFILE - Main module for profile loading
;; Include Files Required:
;; -----------------------
;;	 ?????????? - Externals for profile loading modules
;; External Procedure References:
;; ------------------------------
;;	 None
;; Linkage Instructions:
;; ---------------------
;;	 Refer to GRAPHICS.ASM
CODE	SEGMENT PUBLIC 'CODE' BYTE     ;;
	INCLUDE STRUC.INC	       ;;
	INCLUDE GRINST.EXT	       ;; Bring in external declarations
				       ;;  for transient command processing
	INCLUDE GRSHAR.STR	       ;;
	INCLUDE GRPARSE.EXT	       ;;
	INCLUDE GRLOAD2.EXT	       ;;
	INCLUDE GRLOAD3.EXT	       ;;
	INCLUDE GRMSG.EQU	       ;;
;; Public Symbols
   PUBLIC  LOAD_PROFILE
   PUBLIC  GROW_SHARED_DATA
   PUBLIC  BLOCK_START
   PUBLIC  BLOCK_END
   PUBLIC  FIRST_BLOCK
   PUBLIC  MAX_BLOCK_END
   PUBLIC  GROUPS_DONE
   PUBLIC  STMTS_DONE
   PUBLIC  STMTS_DONE
   PUBLIC  PTD_FOUND
   PUBLIC  BUILD_STATE
   PUBLIC  STMT_ERROR
   PUBLIC  FILE_ERROR
   PUBLIC  PARSE_ERROR
   PUBLIC  END_OF_FILE
   PUBLIC  MEM_OVERFLOW
   PUBLIC  STMT_BUFFER
   PUBLIC  CUR_STMT
   PUBLIC  PREV_STMT
   PUBLIC  PRT_BOX_ERROR
	ASSUME	CS:CODE,DS:CODE        ;;
;; Profile Load Variables
NO	      EQU   0		       ;;
YES	      EQU   1		       ;;
;; Module Name:
;;   LOAD_PROFILE
;; Input Parameters:
;;   DS,ES,SS - points to our transient segment
;; Output Parameters:
;;   Temporary Shared Data Area
;;   Carry flag set if errors in profile.
;; Data Structures Referenced:
;;   Shared Data Area
;;   Profile Load Variables
;; Description:
;;   Build the profile information in the Temporary Shared Data Area.
;;   The information will be built for the printer type parsed off
;;   the command line.	ALL Printer Type Descriptions will be
;;   parsed to issue error messages and determine the maximum
;;   amount of resident memory required for initial load.
;;   The Shared Data Area begins with a fixed length section
;;   and then has several variable length sections.  PROFILE_BUILD_PTR
;;   is used to build the variable length sections by serving
;;   as a running pointer to the sections as they are built.
;; Register Usage:
;;   BP - points to beginning of Temp Shared Data
;; Called By:
;;   GRAPHICS_INSTALL
;; External Calls:
;;   PARSE_PRINTER, PARSE_DISPLAYMODE, PARSE_SETUP, PARSE_RESTORE
;;   PARSE_PRINTBOX, PARSE_GRAPHICS, PARSE_COLORSELECT,
;;   PARSE_COLORPRINT, GET_STATEMENT
;;   SYSPARSE
;; Logic:
;;   IF profile path not specified  THEN
;;	PROFILE_PATH := "GRAPHICS.PRO"  /* Current directory */
;;	Open profile using PROFILE_PATH
;;	IF error during open THEN
;;	   PROFILE_PATH := ARG(V0) with "GRAPHICS.COM" replaced
;;	     by "GRAPHICS.PRO"
;;	   Open profile using PROFILE_PATH
;;	   IF error during open THEN
;;	      Issue "Cannot find profile" msg
;;	      Set carry flag
;;	      RETURN
;;	   ENDIF
;;	ENDIF
;;   ELSE
;;	Open profile using specified path
;;	IF error during open THEN
;;	   Issue "Cannot find profile" msg
;;	   Set carry flag
;;	   RETURN
;;	ENDIF
;;   ENDIF
;;   /* don't start building until we find our printer type*/
;;   PARSE_MODE := NOBUILD
;;   MAX_BUILD_PTR := 0
;;   CALL GROW_SHARED_DATA(PROFILE-BUILD_PTR,size of FIXED PART
;;     of Shared Data Area)
;;   WHILE (not end of file) AND (no I/O error) DO
;;	CALL GET_STATEMENT
;;	IF I/O error THEN
;;	   Issue error message
;;	ELSE
;;	   CALL SYSPARSE to parse the statement verb
;;	   IF verb found THEN
;;	      IF invalid verb THEN
;;		 Issue error message
;;		 PARSE_MODE := ERROR
;;	      ELSE
;;		 CASE statement verb
;;		    PRINTER:
;;		       CALL PARSE_PRINTER
;;		    DISPLAYMODE:
;;		       CALL PARSE_DISPLAYMODE
;;		    PRINTBOX:
;;		       CALL PARSE_PRINTBOX
;;		    SETUP:
;;		       CALL PARSE_SETUP
;;		    RESTORE:
;;		       CALL PARSE_RESTORE
;;		    GRAPHICS:
;;		       CALL PARSE_GRAPHICS
;;		    COLORPRINT:
;;		       CALL PARSE_COLORPRINT
;;		    COLORSELECT:
;;		       CALL PARSE_COLORSELECT
;;		 ENDCASE
;;		 IF error on statement THEN
;;		    IF OVERFLOW bit set in RETURN_CODE THEN
;;		       Issue "Insufficient memory" message
;;		       RETURN to caller
;;		    ELSE
;;		       IF MISSING bit set in RETURN_CODE THEN
;;			  Issue "required statement missing" message
;;		       ENDIF
;;		       IF INVALID bit set in RETURN_CODE THEN
;;			  Issue "statement invalid" message
;;		       ENDIF
;;		       IF SEQUENCE bit set in RETURN_CODE THEN
;;			  Issue "out of sequence" message
;;		       ENDIF
;;		       display the statement in error
;;		    ENDIF
;;		    PARSE_MODE := ERROR
;;		 ENDIF
;;	      ENDIF
;;	   ENDIF
;;	ENDIF
;;   ENDWHILE
;;   /* Check length of last PTD */
;;   IF PROFILE_BUILD_PTR > MAX_BUILD_PTR THEN
;;	MAX_BUILD_PTR := PROFILE_BUILD_PTR
;;   ENDIF
;;   /* Make sure all required statements were in previous */
;;   /* Printer Type Description */
;;   /* Must have completed PRINTER, DISPLAYMODE, PRINTBOX and */
;;   /* GRAPHICS statements */
;;   IF PRT+DISP+BOX+GR bits not all set in STMTS_DONE THEN
;;	Issue "required statement missing" message
;;	Display "END OF FILE."
;;   ENDIF
;;   IF errors during build THEN
;;	set carry flag
;;   ELSE
;;	SD_TOTAL_SIZE := MAX_BUILD_PTR - TEMP_SHARED_DATA_PTR
;;   ENDIF
;;   RETURN
FILE_NOT_FOUND	EQU  2		       ;; DOS Int21H error codes
PATH_NOT_FOUND	EQU  3		       ;;
SUBLIST     LABEL  BYTE 	       ;; Message substituion list for stmt #
	    DB	11		       ;; sublist size
	    DB	0		       ;;
	    DW	STMT_NUM	       ;; \ Dword pointer to item
SUBLIST_SEG DW	?		       ;; /
	    DB	1		       ;; Substitution #
;; Flag format	a0sstttt	       ;;
	    DB	00100001B	       ;; Unsigned binary word - left align
;;;;	    DB	00000000B	       ;; charcater
	    DB	0		       ;; max field width
	    DB	1		       ;; min width width
	    DB	' '                    ;; pad characeter
STMT_NUM    DW	0		       ;;
FILE_ERROR  DB	0		       ;; Error opening or reading PROFILE
PARSE_ERROR DB	0		       ;; Syntax errors in PROFILE
END_OF_FILE	DB  0		       ;; 1 if end of file
MEM_OVERFLOW  DB  0		       ;; 1 if insufficient memory
STMT_ERROR  DB	0		       ;; Error flag for individual stmt errors
MISSING     EQU 1		       ;; Required statement missing
INVALID     EQU 2		       ;; Invalid statement format
SEQUENCE    EQU 4		       ;; Statement out of sequence
DEFAULT_PATH	  DB "GRAPHICS.PRO",0  ;;
BUFFER	    DB	64 DUP("$")            ;;
HANDLE	    DW	0		       ;; Profile handle
BUILD_STATE DB	0		       ;; 1 if we are currently building
				       ;;  data.  0 means syntax checking
				       ;;   only
				       ;; Keep track of whether this PTD
				       ;;  matches the type requested
PTD_FOUND   DB	0		       ;; Values are NO (0), YES (1) and
PROCESSED   EQU 2		       ;;  PROCESSED (2)
VERB	    DB	0		       ;; PTR into VERB_JMP_TAB
VERB_JMP_TAB  LABEL WORD	       ;;
	DW  OFFSET PARSE_PRINTER       ;;
	DW  OFFSET PARSE_DISPLAYMODE   ;;
	DW  OFFSET PARSE_PRINTBOX      ;;
	DW  OFFSET PARSE_SETUP	       ;;
	DW  OFFSET PARSE_RESTORE       ;;
	DW  OFFSET PARSE_GRAPHICS      ;;
	DW  OFFSET PARSE_COLORPRINT    ;;
	DW  OFFSET PARSE_COLORSELECT   ;;
	DW  OFFSET PARSE_DARKADJUST    ;;
STMTS_DONE   DW  0		       ;;
GROUPS_DONE  DW  0		       ;;
PREV_STMT    DW  0		       ;;
CUR_STMT     DW  0		       ;;
PRT	EQU  1			       ;; Bit masks for STMTS_DONE and
DISP	EQU  2			       ;;  GROUPS_DONE.  There is one
BOX	EQU  4			       ;;   bit for each statement except
GR	EQU  8			       ;;    DARKADJUST
SET	EQU  10H		       ;;
REST	EQU  20H		       ;;
COLS	EQU  40H		       ;;
COLP	EQU  80H		       ;;
DARK	EQU  100H		       ;;
BLOCK_START  DW  ?		       ;; Extents of the variable size block
BLOCK_END    DW  ?		       ;;  currently being built
				       ;; These are relative to the
				       ;;  start of the Shared Data Area
				       ;;   so the area can be relocated
MAX_BLOCK_END	DW  0		       ;; End of largest PTD contained
				       ;;  in profile
FIRST_BLOCK  DW  ?		       ;; Pointer to first variable block
				       ;;  (end of fixed part)
PRT_BOX_ERROR  DB  0		       ;;
LOAD_PROFILE  PROC NEAR 	       ;;
  PUSH	CS			       ;;
  POP	SUBLIST_SEG		       ;; setup segment for message sublist
  CALL OPEN_FILE		       ;;
 .IF <FILE_ERROR EQ YES>	       ;; Check for error during open
     STC			       ;;
     RET			       ;;
 .ENDIF 			       ;;
  MOV  BP,TEMP_SHARED_DATA_PTR	       ;; BP points to START of Shared Data
  MOV  AX,SIZE SHARED_DATA_AREA_STR    ;; size of fixed part of Shared Data
  MOV  BLOCK_END,0		       ;; Initialize BLOCK_START,BLOCK_END
  MOV  [BP].DARKADJUST_VALUE,0	       ;; Init some values in the fixed
  MOV  [BP].NUM_PRT_COLOR,0	       ;;  area
  MOV  [BP].COLORPRINT_PTR,-1	       ;;
  MOV  [BP].NUM_PRT_BANDS,0	       ;;
  MOV  [BP].COLORSELECT_PTR,-1	       ;;
  MOV  [BP].PRINTER_TYPE,BLACK_WHITE   ;;
  CALL GROW_SHARED_DATA 	       ;;  to the first byte after the
				       ;;   fixed part of Shared Data
     MOV  AX,BLOCK_END		       ;; Variable size data will be built
     MOV  BLOCK_START,AX	       ;;  starting at BLOCK_START
     MOV  FIRST_BLOCK,AX	       ;; Save start of variable data
     MOV  SI,BUFFER_PTR 	       ;; Set up SI for GET_BYTE
     CALL GET_BYTE		       ;; Get first byte from file
     MOV  NEXT_BYTE,AL		       ;;  and store it
     MOV  BUFFER_PTR,SI 	       ;; Save SI for next GET_BYTE
    .WHILE <END_OF_FILE EQ NO> AND     ;; Keep parsing until end of file or
    .WHILE <FILE_ERROR EQ NO>	       ;;  file error occurs
       MOV STMT_ERROR,0 	       ;; Clear parse error flags
       CALL GET_STATEMENT	       ;; Get next profile statement
       INC  STMT_NUM		       ;;
      .IF NC			       ;; Carry flag set if get unsuccessful
	  CALL PARSE_VERB	       ;; Index into verb jump table returned
				       ;;  in BX
	 .IF <AX EQ 0> THEN	       ;; AX=0 if there is a recognized
	    MOV  AX,CUR_STMT	       ;;
	    MOV  PREV_STMT,AX	       ;; Save last statement verb
	    CALL VERB_JMP_TAB[BX]      ;;  statement to parse
	 .ELSEIF <AX NE -1> THEN       ;;
	    OR	 STMT_ERROR,INVALID    ;;
	    MOV  PARSE_ERROR,YES       ;;
	    MOV  BUILD_STATE,NO        ;;
	 .ENDIF 		       ;;
	 .IF <STMT_ERROR NE 0>	       ;; An error was detected
	    CALL SHOW_PARSE_ERROR      ;;
	    MOV PARSE_ERROR,YES        ;;
	    MOV STMT_ERROR,0	       ;;
	 .ENDIF 		       ;;
      .ENDIF			       ;;
    .ENDWHILE			       ;;
 .IF <BIT STMTS_DONE  AND PRT>	       ;; Must have at least one PRINTER
     CALL TERMINATE_DISPLAYMODE        ;; Terminate the last PRINTER and
     CALL TERMINATE_PRINTER	       ;;  DISPLAYMODE sections
 .ELSE				       ;;
     OR  STMT_ERROR,MISSING	       ;;
 .ENDIF 			       ;;
 .IF <STMT_ERROR NE 0>		       ;;
     CALL  SHOW_PARSE_ERROR	       ;; Issue Profile syntax messages
 .ENDIF 			       ;;
  MOV  AX,3E00H 		       ;; Close the file
  MOV  BX,HANDLE		       ;;
  INT  21H			       ;;
 .IF <PARSE_ERROR EQ YES>	       ;;
      MOV  AX,SYNTAX_ERRORS	       ;; Issue "Syntax errors found in
      MOV  CX,0 		       ;;  profile" message.
      CALL DISP_ERROR		       ;;
 .ENDIF 			       ;;
 .IF <PTD_FOUND EQ NO>		       ;; Did we find the requested printer
      MOV  AX,INVALID_PRT	       ;;  type?  If not issue error
      MOV  CX,0 		       ;;  message.
      CALL DISP_ERROR		       ;;
      MOV  PARSE_ERROR,YES	       ;;
 .ENDIF 			       ;;
 .IF <PARSE_ERROR EQ YES> OR	       ;;
 .IF <PRT_BOX_ERROR EQ YES> OR	       ;;
 .IF <FILE_ERROR EQ YES>	       ;; Set carry flag if profile load
     STC			       ;;  was unsuccessful
 .ELSE				       ;;
    .IF <MEM_OVERFLOW EQ YES>	       ;; Everthing else was OK BUT we ran
	.IF <INSTALLED EQ YES>	       ;;  out of memory!!!
	    MOV   AX,NB_FREE_BYTES     ;;
	   .IF <AX LT RESIDENT_SHARED_DATA_SIZE>
	       MOV   AX,NO_MEMORY      ;; We ran out of physical memory!
	   .ELSE		       ;;
	       MOV   AX,UNABLE_RELOAD  ;; Allocated shared data is too small
	   .ENDIF		       ;;
	.ELSE			       ;;
	    MOV   AX,NO_MEMORY	       ;; We ran out of physical memory
	.ENDIF			       ;;
	 MOV   CX,0		       ;;
	 CALL  DISP_ERROR	       ;;
	 STC			       ;; Indicate unsuccessful
    .ELSE			       ;;
	 MOV  AX,MAX_BLOCK_END	       ;; Extent of largest PRINTER section
	 MOV  [BP].SD_TOTAL_SIZE,AX    ;;  we parsed.
	 CLC			       ;; SUCCESSFUL LOAD!!!!
    .ENDIF			       ;;
 .ENDIF 			       ;;
  RET				       ;;
LOAD_PROFILE  ENDP		       ;;
;; Module Name:
;;   SHOW_PARSE_ERROR
CARRAIGE_RET   EQU  13		       ;;
LINE_FEED      EQU  10		       ;;
SHOW_PARSE_ERROR   PROC 	       ;;
  MOV  ERROR_DEVICE,STDOUT	       ;; profile syntax messages to STDOUT
 .IF <BIT STMT_ERROR AND MISSING>
    PUSH SI		    ;;
    MOV  AX,MISSING_STMT    ;;
    MOV  CX,1		    ;;
    MOV  SI,OFFSET SUBLIST  ;;
    CALL DISP_ERROR	    ;;
    POP  SI		    ;;
 .ENDIF 		    ;;
 .IF <BIT STMT_ERROR AND INVALID>
    PUSH SI		    ;;
    MOV  AX,INVALID_STMT    ;;
    MOV  CX,1
    MOV  SI,OFFSET SUBLIST  ;;
    CALL DISP_ERROR	    ;;
    POP  SI		    ;;
 .ENDIF 		    ;;
 .IF <BIT STMT_ERROR AND SEQUENCE>
    PUSH SI		    ;;
    MOV  AX,OUT_SEQ_STMT    ;;
    MOV  CX,1
    MOV  SI,OFFSET SUBLIST  ;;
    CALL DISP_ERROR	    ;;
    POP  SI		    ;;
 .ENDIF 		    ;;
  MOV  DI,STMT_END_INDEX  ;;
  MOV  STMT_BUFFER[DI],'$'           ;; For display
  MOV  AH,9			     ;;
  MOV  DX,OFFSET STMT_BUFFER
  INT  21H			     ;;
  MOV  DL,CARRIAGE_RET		     ;;
  MOV  AH,2			     ;;
  INT  21H			     ;;
  MOV  DL,LINE_FEED		     ;;
  MOV  AH,2			     ;;
  INT  21H			     ;;
  MOV  ERROR_DEVICE,STDERR	       ;; reset to STDERR
  RET				       ;;
SHOW_PARSE_ERROR   ENDP 	       ;;
;; Module Name:
;;   OPEN_FILE
OPEN_FILE     PROC NEAR 	       ;;
 .IF <PROFILE_PATH NE 0>	       ;; If a path was specified then
     MOV  DX,OFFSET PROFILE_PATH       ;;  try and open it
     MOV  AX,3D00H		       ;;
     INT  21H			       ;; Open it
    .IF C			       ;; Open error if carry flag set
       .IF <AX EQ FILE_NOT_FOUND> OR   ;; Check for error other than
       .IF <AX EQ PATH_NOT_FOUND>      ;;  file not found
	   MOV	 AX,PROFILE_NOT_FOUND  ;;
	   MOV	 CX,0		       ;;
	   CALL  DISP_ERROR	       ;; Issue "File not found" common msg
	   MOV	 FILE_ERROR,YES        ;;
       .ELSE			       ;;
	   CALL  FILE_ERROR_PROC       ;; Issue "Open error"
       .ENDIF			       ;;
    .ELSE			       ;;
	MOV  HANDLE,AX		       ;;
    .ENDIF			       ;; File opened OK
 .ELSE				       ;; No path parameter
     MOV  DX,OFFSET DEFAULT_PATH       ;; Try and open "GRAPHICS.PRO"
     MOV  AX,3D00H		       ;;
     INT  21H			       ;; Open it
    .IF C			       ;; Open error if carry flag set
       .IF <AX EQ FILE_NOT_FOUND> OR   ;; Check for file not found error
       .IF <AX EQ PATH_NOT_FOUND>      ;;
	   CALL COPY_ARGV0	       ;;
	   MOV	DX,OFFSET PROFILE_PATH ;; Try and open "GRAPHICS.PRO" in
	   MOV	AX,3D00H	       ;;  ARGV0 directory
	   INT	21H		       ;;
	  .IF C 		       ;; Issue "File not found" common msg
	     .IF <AX EQ FILE_NOT_FOUND> OR
	     .IF <AX EQ PATH_NOT_FOUND>
		 MOV   AX,PROFILE_NOT_FOUND  ;;
		 MOV   CX,0		     ;;
		 CALL  DISP_ERROR	     ;; Issue "File not found"common MSG
		 MOV   FILE_ERROR,YES	     ;;
	     .ELSE		       ;;
		 CALL  FILE_ERROR_PROC ;; Issue "Open error"
	     .ENDIF		       ;;
	  .ELSE 		       ;;
	      MOV  HANDLE,AX	       ;;
	  .ENDIF		       ;; File opened OK
       .ELSE			       ;;
	   CALL  FILE_ERROR_PROC       ;; Issue "Open error"
       .ENDIF			       ;;
    .ELSE			       ;;
	MOV  HANDLE,AX		       ;;
    .ENDIF			       ;;
 .ENDIF 			       ;;
  RET				       ;;
OPEN_FILE     ENDP		       ;;
;; Module Name:
;;   COPY_ARGV0
COPY_ARGV0  PROC		       ;;
  PUSH	 ES			       ;;
  PUSH	 DI			       ;;
  PUSH	 SI			       ;;
  MOV	 DI,2CH 		       ;; Locate environment string
  MOV	 ES,[DI]		       ;;
  XOR	 SI,SI			       ;;
  .WHILE <<WORD PTR ES:[SI]> NE 0>     ;;
     INC   SI			       ;;
  .ENDWHILE			       ;;
  ADD	 SI,4			       ;;
  LEA	 DI,PROFILE_PATH	       ;; Move string to work area
  .REPEAT			       ;;
     MOV    AL,ES:[SI]		       ;;
     MOV    [DI],AL		       ;;
     INC    SI			       ;;
     INC    DI			       ;;
  .UNTIL <<BYTE PTR ES:[SI]> EQ 0>     ;;
  MOV	 BYTE PTR [DI],0	       ;;
  MOV	 BYTE PTR [DI]-3,"P"           ;; Change COM to PRO
  MOV	 BYTE PTR [DI]-2,"R"           ;;
  MOV	 BYTE PTR [DI]-1,"O"           ;;
  POP	    SI			       ;;
  POP	    DI			       ;;
  POP	    ES			       ;;
  RET				       ;;
COPY_ARGV0  ENDP		       ;;
;; Module Name:
;;   FILE_ERROR_PROC
FILE_ERROR_PROC  PROC		       ;;
  MOV	AX,FILE_ERRORS		       ;;
  MOV	CX,0			       ;;
  CALL	DISP_ERROR		       ;;
  MOV	FILE_ERROR,YES		       ;;
  RET				       ;;
FILE_ERROR_PROC  ENDP		       ;;
;; Module Name:
;;   GET_STATEMENT
;; Input Parameters:
;;   NONE
;; Output Parameters:
;;   PROFILE_LINE
;;   RETURN CODE : 0 - successfull read
;;		 : 1 - end of file
;;		 : 2 - error during read
;; Data Structures Referenced:
;; Description:
;;   Get a statement from the profile.
;;   The file read in 512 byte buffers and parsed into
;;   lines by the presence of a carriage return at the end of each line.
;; Called By:
;;   LOAD_PROFILE
;; External Calls:
;;   NONE
;; Logic:
;;   FOUND := FALSE
;;   RETURN_CODE := 0
;;   WHILE NOT FOUND DO
;;	IF end of buffer THEN
;;	   Read next profile record into buffer
;;	   IF successful read THEN
;;	      point to first byte in buffer
;;	   ELSE
;;	      IF end of file THEN
;;		 Close profile
;;		 RETURN_CODE := 1
;;		 FOUND := TRUE
;;	      ELSE
;;		 RETURN_CODE := 2
;;		 FOUND := TRUE
;;	      ENDIF
;;	   ENDIF
;;	ENDIF
;;	copy byte to PROFILE_LINE
;;	IF byte in buffer is a CR THEN
;;	   FOUND := TRUE
;;	ENDIF
;;   ENDWHILE
;;   RETURN
FOUND  DB   0			       ;;
CARRIAGE_RET	EQU 13		       ;;
LINE_FEED	EQU 10		       ;;
NEXT_BYTE	DB  0		       ;; Save area for byte just read
BUFFER_SIZE	EQU 512 	       ;;
FILE_BUFFER	DB  512 DUP(0)	       ;;
BUFFER_PTR	DW  512 	       ;;
BUFFER_END	DW  512 	       ;;
STMT_BUFFER	DB  255 DUP(0)	       ;;
		DB  ?		       ;; In case we have to insert a CR
		DB  ?		       ;;  and a LF
		DB  ?		       ;; Too put the "$" for displaying the
				       ;;  line.
STMT_END_INDEX	DW  ?		       ;;
MAX_STMT_LEN	EQU 255 	       ;;
CR_FOUND	DB  0		       ;; 1 if we found a line terminator
GET_STATEMENT PROC		       ;;
  MOV  FOUND,NO 		       ;;
  MOV  STMT_ERROR,0		       ;; Clear error flags
  XOR  DI,DI			       ;; Index for extracted statement
  MOV  SI,BUFFER_PTR		       ;; Init file buffer ptr
  MOV  AL,NEXT_BYTE		       ;; Restore current byte
  MOV  CR_FOUND,NO		       ;;
 .WHILE <FOUND EQ NO> AND	       ;; Keep parsing until we find a stmt
 .WHILE <FILE_ERROR EQ NO> AND	       ;;  or a file error occurs
 .WHILE <END_OF_FILE EQ NO>	       ;;   or we reach end of file
   .IF <CR_FOUND EQ YES>	       ;;
      .IF <AL EQ LINE_FEED>	       ;; Return the line feed as well
	 .IF <DI NA MAX_STMT_LEN>      ;; Truncate lines longer than MAX
	     MOV  STMT_BUFFER[DI],AL   ;;  MOVE TO statement buffer
	     INC  DI		       ;; Point to next byte in file buffr
	  .ELSE 		       ;;
	      OR   STMT_ERROR,INVALID  ;; Line has been truncated > ERROR
	      MOV  PARSE_ERROR,YES     ;;
	      MOV  BUILD_STATE,NO      ;;
	 .ENDIF 		       ;;
	  CALL GET_BYTE 	       ;; Get the first byte of next statement
      .ENDIF			       ;;
       MOV  FOUND,YES		       ;; Time to leave this WHILE
       MOV  NEXT_BYTE,AL	       ;; Save the byte we just read
   .ELSE			       ;;
      .IF <DI NA MAX_STMT_LEN>	       ;; Truncate lines longer than MAX
	  MOV  STMT_BUFFER[DI],AL      ;; move byte to statement buffer
	  INC  DI		       ;; Point to next byte in file buffer
      .ELSE			       ;;
	  OR   STMT_ERROR,INVALID      ;; Line has been truncated > ERROR
	  MOV  PARSE_ERROR,YES	       ;;
	  MOV  BUILD_STATE,NO	       ;;
      .ENDIF			       ;;
      .IF <AL EQ CARRIAGE_RET>	       ;; Found a line terminator
	  MOV  CR_FOUND,YES	       ;; Indicate carriage return found
      .ENDIF			       ;;  and go through once more to
       CALL GET_BYTE		       ;;   check for a line feed
   .ENDIF			       ;;
 .ENDWHILE			       ;;
 .IF <STMT_BUFFER[DI-1] NE CARRIAGE_RET> AND		 ;;
 .IF <STMT_BUFFER[DI-1] NE LINE_FEED>		      ;;
     MOV  STMT_BUFFER[DI],CARRIAGE_RET ;;
     MOV  STMT_BUFFER[DI+1],LINE_FEED  ;;
     INC  DI			       ;;
     INC  DI			       ;;
 .ENDIF 			       ;;
  MOV STMT_END_INDEX,DI 	       ;;
  MOV BUFFER_PTR,SI		       ;; Save buffer ptr for next time
 .IF <END_OF_FILE EQ YES>	       ;;
     .IF <DI EQ 0>		       ;; Clear carry if we read something
	STC			       ;;  and no file error occured otherwise
     .ELSE			       ;;   set carry indicating unsuccessful
	CLC			       ;;    get.
     .ENDIF			       ;;
 .ELSE				       ;;
     .IF <FILE_ERROR EQ YES>	       ;;
	 STC			       ;;
     .ELSE			       ;;
	 CLC			       ;;
     .ENDIF			       ;;
 .ENDIF 			       ;;
  RET				       ;;
GET_STATEMENT ENDP		       ;;
;; Module Name:
;;   GET_BYTE
GET_BYTE      PROC		       ;;
 .IF <SI EQ BUFFER_END> 	       ;; If buffer empty do another read
     MOV  AH,3FH		       ;;
     MOV  DX,OFFSET FILE_BUFFER        ;;
     MOV  CX,BUFFER_SIZE	       ;;
     MOV  BX,HANDLE		       ;;
     INT  21H			       ;;
    .IF C			       ;; Carry set by DOS if file error
	CALL FILE_ERROR_PROC	       ;;
    .ELSE			       ;;
       .IF <AX EQ 0>		       ;; End of file if AX=0
	   MOV	END_OF_FILE,YES        ;;
	   MOV	AH,3EH		       ;; Close the file
	   MOV	BX,HANDLE	       ;;
	   INT	21H		       ;;
       .ELSE			       ;;
	   MOV BUFFER_END,AX	       ;; Number of bytes read
	   XOR SI,SI		       ;; Buffer pointer := 0
       .ENDIF			       ;;
    .ENDIF			       ;;
 .ENDIF 			       ;;
 .IF <FILE_ERROR EQ YES> OR	       ;;
 .IF <END_OF_FILE EQ YES>	       ;;
     STC			       ;; Unsuccessful get
 .ELSE				       ;;
    .IF <<FILE_BUFFER[SI]> EQ 1AH>	;; cHECK for EOF marker
	MOV END_OF_FILE,YES	       ;;
	STC			       ;;
    .ELSE			       ;;
	MOV  AL,FILE_BUFFER[SI] 	  ;; Return byte in AL
	INC  SI 			  ;;
	CLC				  ;; Successful get
    .ENDIF				  ;;
 .ENDIF 			       ;;
  RET				       ;;
GET_BYTE      ENDP		       ;;
;; Module Name:
;;   GROW_SHARED_DATA
GROW_SHARED_DATA  PROC		       ;;
  PUSH BX			       ;;
  ADD  BLOCK_END,AX		       ;; Grow the current block by AX
  MOV  BX,BLOCK_END		       ;;
 .IF <BX A NB_FREE_BYTES>	       ;; Check for overflow
     MOV  BUILD_STATE,NO	       ;; Stop building shared data
     MOV  MEM_OVERFLOW,YES	       ;;
 .ENDIF 			       ;;
  POP  BX			       ;;
  RET				       ;;
GROW_SHARED_DATA  ENDP		       ;;
CODE	ENDS			       ;;
	END
