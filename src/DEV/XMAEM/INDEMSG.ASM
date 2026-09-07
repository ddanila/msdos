PAGE	60,132
TITLE	INDEMSG - 80386 XMA Emulator - Messages

COMMENT #
* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
*									      *
* MODULE NAME	  : INDEMSG						      *
*									      *
*		     5669-196 (C) COPYRIGHT 1988 Microsoft Corp.	      *
*									      *
* DESCRIPTIVE NAME: 80386 XMA Emulator messages -- U.S. 		      *
*									      *
* STATUS (LEVEL)  : Version (0) Level (1.10)				      *
*									      *
* FUNCTION	  : Declare the U.S. messages for the 80386 XMA Emulator      *
*									      *
* MODULE TYPE	  : ASM 						      *
*									      *
* REGISTER USAGE  : N/A 						      *
*									      *
* RESTRICTIONS	  : None						      *
*									      *
* DEPENDENCIES	  : None						      *
*									      *
* ENTRY POINT	  : None						      *
*									      *
* LINKAGE	  : The messages are made PUBLIC so that the initialization   *
*		    module, INDEINI, can access them.			      *
*									      *
* INPUT PARMS	  : None						      *
*									      *
* RETURN PARMS	  : None						      *
*									      *
* OTHER EFFECTS   : None						      *
*									      *
* EXIT NORMAL	  : None						      *
*									      *
* EXIT ERROR	  : None						      *
*									      *
* EXTERNAL								      *
* REFERENCES	  : None						      *
*									      *
* SUB-ROUTINES	  : None						      *
*									      *
* MACROS	  : None						      *
*									      *
* CONTROL BLOCKS  : None						      *
*									      *
* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
#

SUBTTL	   Messages							;   D0A
PAGE									;   D0A
									;   D0A
PROG	   SEGMENT PARA PUBLIC	'PROG'                                  ;   D0A
									;   D0A
	   ASSUME  CS:PROG						;   D0A
	   ASSUME  SS:NOTHING						;   D0A
	   ASSUME  DS:PROG						;   D0A
	   ASSUME  ES:NOTHING						;   D0A
									;   D0A
INDEMSG    LABEL   NEAR 						;   D0A
									;   D0A
;---------------------------------------------------------------------------P2A;
; Declare messages that the emulator will display on the screen.  These     P2A;
; messages are declared with line lengths of 80 bytes to allow for World    P2A;
; Trade translation.  The messages are made public so that other modules    P2A;
; can access them.							    P2A;
; Note that the messages are declared 80 bytes long to facilitate world trade translation.	       P2A;
;---------------------------------------------------------------------------P2A;
									;   P2A
	   PUBLIC  WELCOME						;   P2A
	   PUBLIC  GOODLOAD						;   P2A
	   PUBLIC  NO_80386						;   P2A
	   PUBLIC  WAS_INST						;   P2A
	   Public  Small_Parm
	   Public  No_Mem
									;   P2A
CR	   EQU	   13	     ; ASCII for a carriage return		;  @P2A
LF	   EQU	   10	     ; ASCII for a line feed			;  @P2A
									;   P2A
INCLUDE    xmaem.cl1

PROG	   ENDS 							;   D0A
	   END								;   D0A
