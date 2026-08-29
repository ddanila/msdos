;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; *** MACROS **** MACROS **** MACROS ****
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
IF1                                     ;
        %OUT .               -MACROS  .INC-
ENDIF                                   ;
                                        ;
JUMP    MACRO   LBL                     ;
.XCREF                                  ;
        JMP     LBL                     ; JWasm selects the valid displacement.
.CREF                                   ;
        ENDM                            ;
.XCREF JUMP                             ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; *** MACROS **** MACROS **** MACROS ****
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
