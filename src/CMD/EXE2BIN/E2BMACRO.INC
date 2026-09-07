






;
;******************************************************************************
; Message Macro Definitions
;******************************************************************************
;

      EXTRN Display_Interface:near


;-----------------------------------------------------------------------------

MESSAGE macro   Message_Name                    ;
                                                ;
        mov     dx,offset Message_Name          ;
        call    Display_Interface               ;
                                                ;
        endm                                    ;


;
;*****************************************************************************
; General Macro's
;*****************************************************************************
;

Procedure       macro   Proc_Name

Public  Proc_Name
Proc_Name    proc

        endm
;-----------------------------------------------------------------------------

DOS_Call        macro   Function

        mov     ah,Function
        int     21h

        endm
;-----------------------------------------------------------------------------

Parse_Message macro


        push    ds
        mov     dx,SEG parse_ptr
        mov     ds,dx
        ASSUME  DS:DATA
        ASSUME  ES:DATA
        mov     word ptr Parse_Error_Msg,ax
        mov     dx,offset Parse_Error_Msg       ;
        call    Display_Interface               ;
        pop     ds
        endm                                    ;

;-----------------------------------------------------------------------------

Extend_Message macro                            ;

                                                ;
        push    ds
        mov     dx,SEG parse_ptr
        mov     ds,dx
        ASSUME  DS:DATA
        ASSUME  ES:DATA
        mov     word ptr Extend_Error_Msg,ax     ;
        mov     dx,offset Extend_Error_Msg       ;
        call    Display_Interface               ;
        pop     ds
        endm                                    ;

;-----------------------------------------------------------------------------

