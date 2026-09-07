;:util COMP                 ;utility name
;:class 1                   ;DOS extended errors:
;:class 2                   ;parse errors:
;:class A                   ;system messages
;:use 1 COMMON1             ;"Incorrect DOS version"
;:use 2 EXTEND8             ;"Insufficient memory"
;:use 3 PARSE10             ;"Invalid parameter"
;:def 4 "10 Mismatches - ending compare",CR,LF
;:use 5 EXTEND15            ;"Invalid drive specification"
;:def 6 "Compare error at OFFSET %1",CR,LF
;:def 7 "File 1 = %1",CR,LF
;:def 8 "File 2 = %1",CR,LF
;:def 9 "Eof mark not found",CR,LF
;:def 10 "Files compare ok",CR,LF
;:use 11 EXTEND2            ;"File not found"
;:use 12 COMMON25           ;"Invalid path"
;:use 13 EXTEND32           ;"Sharing violation"
;:use 14 EXTEND4            ;"Too many open files"
;:def 15 CR,LF,CR,LF,"Enter primary file name",CR,LF
;:def 16 CR,LF,CR,LF,"Enter 2nd file name or drive id",CR,LF
;:def 17 "Files are different sizes",CR,LF
;:def 18 "Compare more files? (Y/N)",CR,LF
;:def 19 "%1 and %2",CR,LF
;:def 20 CR,LF
;:use 21 EXTEND5            ;"Access Denied"
;:use 22 EXTEND37           ;"Code page mismatch"
;:DEF 23 "Files compare ok",CR,LF
;:end
; = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
            IF1
                %OUT    COMPONENT=COMP, MODULE=COMPMS.INC...
            ENDIF
;               $SALUT (0,13,18,22)
; = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
            HEADER <MESSAGE DESCRIPTORS FOR SPECIFIC MESSAGES>
;           THE NEXT GROUP ARE ADDITIONAL CLASS "A" MESSAGES
;           SPECIFICALLY DEFINED FOR THE COMP UTILITY
; = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = =
; THIS IS SUBLIST FOR  MSGNUM_EXTERR (A CLASS 1 MESSAGE)
SUBLIST_EXTERR SUBLIST <,,FILL_OFF,FILL_SEG,PC_ID_0,SF_BITS<SF_LEFT,,SF_ASCIIZ,SF_CHAR>,MAX_0,MIN_1>
            PUBLIC SUBLIST_EXTERR
;           "Insufficient memory"
MSGNUM_MEM  MSG_DESC <2>
            PUBLIC MSGNUM_MEM
;           "invalid parameter"
MSGNUM_PARA MSG_DESC <3>
            PUBLIC MSGNUM_PARA
;           "10 Mismatches - ending compare",CR,LF
MSGNUM_TENMSG MSG_DESC <4>
            PUBLIC MSGNUM_TENMSG
;           "Invalid drive specification",CR,LF
MSGNUM_BADDRV MSG_DESC <5,STDOUT>
            PUBLIC MSGNUM_BADDRV
;           "Compare error at OFFSET %1",CR,LF
MSGNUM_BAD  MSG_DESC <6,,SUBLIST_6,ONE_SUBS>
SUBLIST_6   SUBLIST <,,FILL_OFF,FILL_SEG,PC_ID_1,SF_BITS<SF_LEFT,,SF_DWORD,SF_UN_BH>,MAX_0,MIN_1>
;           NOTE: ERROR NUMBER IS DWORD
            PUBLIC MSGNUM_BAD,SUBLIST_6
;           "File 1 = %1",CR,LF
MSGNUM_ADR  MSG_DESC <7,,SUBLIST_7,ONE_SUBS>
SUBLIST_7   SUBLIST <,,FILL_OFF,FILL_SEG,PC_ID_1,SF_BITS<SF_LEFT,,SF_BYTE,SF_UN_BH>,MAX_0,MIN_1>
            PUBLIC MSGNUM_ADR,SUBLIST_7
;           "File 2 = %1",CR,LF
MSGNUM_BDR  MSG_DESC <8,,SUBLIST_8,ONE_SUBS>
SUBLIST_8   SUBLIST <,,FILL_OFF,FILL_SEG,PC_ID_1,SF_BITS<SF_LEFT,,SF_BYTE,SF_UN_BH>,MAX_0,MIN_1>
            PUBLIC MSGNUM_BDR,SUBLIST_8
;           "Eof mark not found",CR,LF
MSGNUM_EOR  MSG_DESC <9>
            PUBLIC MSGNUM_EOR
;           "Files compare ok",CR,LF
MSGNUM_DONE MSG_DESC <10>
            PUBLIC MSGNUM_DONE
;           "%1 - File not found",CR,LF
MSGNUM_FNF  MSG_DESC <11,,SUBLIST_11,ONE_SUBS>
SUBLIST_11  SUBLIST <,,FILL_OFF,FILL_SEG,PC_ID_0,SF_BITS<SF_LEFT,,SF_ASCIIZ,SF_CHAR>,MAX_0,MIN_1>
            PUBLIC MSGNUM_FNF,SUBLIST_11
;           "%1 - Invalid path",CR,LF
MSGNUM_BAD_PATH MSG_DESC <12,,SUBLIST_12,ONE_SUBS>
SUBLIST_12  SUBLIST <,,FILL_OFF,FILL_SEG,PC_ID_0,SF_BITS<SF_LEFT,,SF_ASCIIZ,SF_CHAR>,MAX_0,MIN_1>
            PUBLIC MSGNUM_BAD_PATH,SUBLIST_12
;           "%1 - File sharing conflict",CR,LF
MSGNUM_SHARE MSG_DESC <13,,SUBLIST_13,ONE_SUBS>
SUBLIST_13  SUBLIST <,,FILL_OFF,FILL_SEG,PC_ID_0,SF_BITS<SF_LEFT,,SF_ASCIIZ,SF_CHAR>,MAX_0,MIN_1>
            PUBLIC MSGNUM_SHARE,SUBLIST_13
;           "Too many files open",CR,LF
MSGNUM_TOO_MANY MSG_DESC <14>
            PUBLIC MSGNUM_TOO_MANY
;           CR,LF,CR,LF,"Enter primary file name",CR,LF
MSGNUM_PRINAM MSG_DESC <15,,,,(CLASS_A SHL 8) OR DOS_BUF_KEYB_INP>
            DW     ?             ;DEFINE EXTRA WORD FOR PTR TO INPUT BUFFER
                                 ;IT WILL BE ACCESSED AS A FIELD OF THE ABOVE STRUCT
            PUBLIC MSGNUM_PRINAM
;           CR,LF,CR,LF,"Enter 2nd file name or drive id",CR,LF
MSGNUM_SECNAM MSG_DESC <16,,,,(CLASS_A SHL 8) OR DOS_BUF_KEYB_INP>
            DW     ?             ;DEFINE EXTRA WORD FOR PTR TO INPUT BUFFER
                                 ;IT WILL BE ACCESSED AS A FIELD OF THE ABOVE STRUCT
            PUBLIC MSGNUM_SECNAM
;           "Files are different sizes",CR,LF
MSGNUM_BADSIZ MSG_DESC <17>
            PUBLIC MSGNUM_BADSIZ
;           "Compare more files (Y/N) ?",CR,LF
MSGNUM_NOTHER MSG_DESC <18,STDOUT,,,(CLASS_A SHL 8) OR 0C1H>                    ;AC210;;AD176;
            PUBLIC MSGNUM_NOTHER
;           "%1 and %2",CR,LF
MSGNUM_AND_MSG MSG_DESC <19,,SUBLIST_19A,TWO_SUBS>
SUBLIST_19A SUBLIST <,,FILL_OFF,FILL_SEG,PC_ID_1,SF_BITS<SF_LEFT,,SF_ASCIIZ,SF_CHAR>,MAX_0,MIN_1>
SUBLIST_19B SUBLIST <,,FILL_OFF,FILL_SEG,PC_ID_2,SF_BITS<SF_LEFT,,SF_ASCIIZ,SF_CHAR>,MAX_0,MIN_1>
            PUBLIC MSGNUM_AND_MSG,SUBLIST_19A,SUBLIST_19B
;           CR,LF
MSGNUM_CRLF MSG_DESC <20>
            PUBLIC MSGNUM_CRLF
;           "%1 - Access Denied",CR,LF
MSGNUM_ACCESSDENIED MSG_DESC <21,,SUBLIST_21,ONE_SUBS>
SUBLIST_21  SUBLIST <,,FILL_OFF,FILL_SEG,PC_ID_0,SF_BITS<SF_LEFT,,SF_ASCIIZ,SF_CHAR>,MAX_0,MIN_1>
            PUBLIC MSGNUM_ACCESSDENIED,SUBLIST_21
;           "Code page mismatch"
MSGNUM_CP_MISMATCH MSG_DESC <22>
            PUBLIC MSGNUM_CP_MISMATCH
;           "Files compare ok"
MSGNUM_OK   MSG_DESC <23>
            PUBLIC MSGNUM_OK
;
;
MSGNUM_PPARSE MSG_DESC <,STDERR,SUBLIST_24,ONE_SUBS,(CLASS_2 SHL 8)>
SUBLIST_24  SUBLIST <,,FILL_OFF,FILL_SEG,PC_ID_0,SF_BITS<SF_LEFT,,SF_ASCIIZ,SF_CHAR>,MAX_0,MIN_1>
            PUBLIC MSGNUM_PPARSE,SUBLIST_24

;end of COMPMS.INC
