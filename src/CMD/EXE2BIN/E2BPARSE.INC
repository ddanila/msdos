


data    segment public 'DATA'



;
;***************************************************************************
; Equates
;***************************************************************************
;

;Match Flags

Numeric_Value           equ     8000h           ;
Signed_Numeric_Value    equ     4000h           ;
Simple_String           equ     2000h           ;
Date_String             equ     1000h           ;
Time_String             equ     0800h           ;
Complex_List            equ     0400h           ;
Filespec                equ     0200h           ;
Drive_Only              equ     0100h           ;
Quoted_String           equ     0080h           ;
Ignore_Colon            equ     0010h           ;
Repeats_Allowed         equ     0002h           ;
Optional                equ     0001h           ;

;Function_Flags

File_Table_Capitalize   equ     1               ;

;Result buffer type returned
rb_Number               equ     1
rb_List_Index           equ     2
rb_String               equ     3
rb_Complex              equ     4
rb_Filespec             equ     5
rb_Drive                equ     6
rb_Date                 equ     7
rb_Time                 equ     8
rb_Quoted_String        equ     9


;Extra delimeters and EOL

Delimiters_Only         equ     1               ;
EOL_Or_Delimiters       equ     2               ;

Semi_Colon              equ     ";"             ;
Tab                     equ     09h             ;
Colon1                  equ     ":"             ;
NUL                     equ     "0"

;Parse Errors

No_Error                equ     0               ;
Too_Many_Operands       equ     1               ;
Operand_Missing         equ     2               ;
Not_In_Switch_List      equ     3               ;
Not_In_Keyword_List     equ     4               ;
Out_Of_Range            equ     6               ;
Not_In_Value_List       equ     7               ;
Not_In_String_List      equ     8               ;
Syntax_Error            equ     9               ;
End_Of_Parse            equ     -1              ;

;Other

None                    equ     0               ;
No_Error                equ     0               ;
Switch_Found            equ     0FFFFh          ;
Range_Ok                equ     1               ;
Command_Line_Parms      equ     81h             ;

;
;*****************************************************************************
; Parse Structures
;*****************************************************************************
;

Control          struc

Match_Flags     dw      ?
Function_Flags  dw      ?
Result          dw      ?
Values          dw      ?
Num_Keywords    db      ?
Keyword         db      ?

Control         ends

File_Name_Return        struc                   ;

Drive_Type      db      0                       ;
Drive_Item_Tag  db      0                       ;
Synonym         dw      0                       ;
String_Value_ptr db     0                       ;File Name

File_Name_Return     ends                       ;


;
;**************************************************************************
; Parse tables
;**************************************************************************
;

Command_Line_Table label byte                      ;

        dw      Command_Control                 ;Point to next level
        db      Delimiters_Only                 ;
        db      1                               ;
        db      Semi_Colon                      ;


;
;**************************************************************************
; Define Positionals, Switches and Keywords
;**************************************************************************
;

Command_Control label byte                      ;

        db      1,2                             ;File names Positional (1 required)
        dw      Positional_Control1             ;Pointer to control table
        dw      Positional_Control2             ;Pointer to control table
        db      None                            ;no switches
        db      None                            ;No Keywords (maxk)

;
;**************************************************************************
;Control Tables
;**************************************************************************
;

Positional_Control1 label byte                  ;

        dw      Filespec                        ;Match_Flag
        dw      File_Table_Capitalize           ;No function flags
        dw      File_Name_Buffer1               ;Where it will be returned
        dw      No_Value                        ;No value ranges defined
        db      None                            ;No defined switches/keywords

Positional_Control2 label byte                  ;

        dw      Filespec+Optional               ;Match_Flag

        dw      File_Table_Capitalize           ;No function flags
        dw      File_Name_Buffer2               ;Where it will be returned
        dw      No_Value                        ;No value ranges defined
        db      None                            ;No defined switches/keywords

No_Value        label   byte                    ;
        db      0                               ;

;
;************************************************************************
; PARSE Return Buffers
;************************************************************************
;
File_name_Buffer1   label  byte                 ;

rb_type1       db      0                        ;type returned
rb_item_tag1   db      0                        ;matched item tag
rb_synonym1    dw      0                        ;found synonyms
rb_string1_off dw      0                        ;Offset of string
rb_string1_seg dw      0                        ;Offset of string

File_name_Buffer2   label  byte                 ;

rb_type2       db      0                        ;type returned
rb_item_tag2   db      0                        ;matched item tag
rb_synonym2    dw      0                        ;found synonyms
rb_string2_off dw      0                        ;Offset of string
rb_string2_seg dw      0                        ;Offset of string

data    ends

