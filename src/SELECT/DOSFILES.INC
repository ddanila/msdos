ALLOCATE_START	   DW	     0
					;
DEST		   DB	     0
FILE_NUM	   DW	     0
NUMBER_OF_FILES    DW	     0
TABLE_OFFSET	   DW	     0
PATH_OFFSET	   DW	     0
NOT_FOUND_FLAG	   DB	     0
SP_SAVE 	   DW	     0
					;
EVERYTHING	   DB	     'B:*.*',0
					;
DOS_FILE_PTR	   DW	     0
BUFFER_START	   DW	     0
					;
B_TARGET	   DB	     'B:\',0
LENGTH_B_TARGET    EQU	     $-B_TARGET
					;
A_TARGET	   DB	     'A:\',0
LENGTH_A_TARGET    EQU	     $-A_TARGET
