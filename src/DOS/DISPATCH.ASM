;
; Major dispatch code and table for MSDOS 2.X and above.
;
; The system calls are dispatched to in such a fashion as to have their entire
; register set passed to them except for CS:IP and SS:SP.  This reduces the
; need for retreiving information from the user's stack.
;
; There are also critical sections that need to be observed when running in a
; multitasking environment.  These sections are:
;
;   1	critDisk    any of the disk code that will twiddle the buffer cache
;   2	critDevice  all device drivers
;
;   4	critMem     memory allocation stuff
;   5	critNet     network critical section
;
; The system calls below are noted as to which of these critical sections they
; belong.  The critical sections are noted in the source files by the macros
; EnterCrit and LeaveCrit.
;

; critical section information for the system calls

;   System Call 		      Who takes care of the reentrancy
;   Abort			   0	(flushbuf) DOS_Close
;   Std_Con_Input		   1	DOS_Read
;   Std_Con_Output		   2	DOS_Write
;   Std_Aux_Input		   3	DOS_Read
;   Std_Aux_Output		   4	DOS_Write
;   Std_Printer_Output		   5	DOS_Write
;   Raw_Con_IO			   6	DOS_Read/DOS_Write
;   Raw_Con_Input		   7	DOS_Read
;   Std_Con_Input_No_Echo	   8	DOS_Read
;   Std_Con_String_Output	   9	DOS_Write
;   Std_Con_String_Input	   A	DOS_Read
;   Std_Con_Input_Status	   B	DOS_Read
;   Std_Con_Input_Flush 	   C	DOS_Read
;   Disk_Reset			   D	(FlushBuf, ScanPlace, SkipVisit)
;   Set_Default_Drive		   E	*none*
;   FCB_Open			   F	DOS_Open
;   FCB_Close			  10	DOS_Close
;   Dir_Search_First		  11	DOS_Search_First
;   Dir_Search_Next		  12	DOS_Search_Next
;   FCB_Delete			  13	DOS_Delete
;   FCB_Seq_Read		  14	DOS_Read/DOS_Write
;   FCB_Seq_Write		  15	DOS_Read/DOS_Write
;   FCB_Create			  16	DOS_Create
;   FCB_Rename			  17	DOS_rename
;   Get_Default_Drive		  19	*none*
;   Set_DMA			  1A	*none*
;   Get_Default_DPB		  1F	*none*
;   FCB_Random_Read		  21	DOS_Read/DOS_Write
;   FCB_Random_Write		  22	DOS_Read/DOS_Write
;   Get_FCB_File_Length 	  23	Get_file_info
;   Get_FCB_Position		  24	*none*
;   Set_Interrupt_Vector	  25	*none*
;   Create_Process_Data_Block	  26	*none*
;   FCB_Random_Read_Block	  27	DOS_Read/DOS_Write
;   FCB_Random_Write_Block	  28	DOS_Read/DOS_Write
;   Parse_File_Descriptor	  29	*none*
;   Get_Date			  2A	DEVIOCALL
;   Set_Date			  2B	DEVIOCALL
;   Get_Time			  2C	DEVIOCALL
;   Set_Time			  2D	DEVIOCALL
;   Set_Verify_On_Write 	  2E	*none*
;   Get_DMA			  2F	*none*
;   Get_Version 		  30	*none*
;   Keep_Process		  31	$abort...
;   Get_DPB			  32	*none*
;   Set_CTRL_C_Trapping 	  33	*none*
;   Get_InDOS_Flag		  34	*none*
;   Get_Interrupt_Vector	  35	*none*
;   Get_Drive_Freespace 	  36	Disk_Info
;   Char_Oper			  37	*none*
;   International		  38	*none*
;   MKDir			  39	DOS_MkDir
;   RMDir			  3A	DOS_RmDir
;   CHDir			  3B	DOS_ChDir
;   Creat			  3C	DOS_Create
;   Open			  3D	DOS_Open
;   Close			  3E	DOS_Close
;   Read			  3F	DOS_Read
;   Write			  40	DOS_Write
;   Unlink			  41	DOS_Delete
;   LSeek			  42	*none*
;   CHMod			  43	Get_file_info, Set_File_Attribute
;   IOCtl			  44	DEVIOCALL
;   XDup			  45	*none*
;   XDup2			  46	*none*
;   Current_Dir 		  47	$Current_Dir
;   Alloc			  48	$Alloc
;   Dealloc			  49	$Dealloc
;   Setblock			  4A	$SetBlock
;   Exec			  4B
;   Exit			  4C	$abort...
;   Wait			  4D	*none*
;   Find_First			  4E	DOS_Search_First
;   Find_Next			  4F	DOS_Search_Next
;   Set_Current_PDB		  50	*none*
;   Get_Current_PDB		  51	*none*
;   Get_In_Vars 		  52	*none*
;   SetDPB			  53	*none*
;   Get_Verify_On_Write 	  54	*none*
;   Dup_PDB			  55
;   Rename			  56	DOS_Rename
;   File_Times			  57	*none*
;   AllocOper			  58	*none*
;   GetExtendedError		  59	*none*
;   CreateTempFile		  5A	DOS_Create_New
;   CreateNewFile		  5B	DOS_Create_New
;   LockOper			  5C
;   ServerCall			  5D
;   UserOper			  5E
;   AssignOper			  5F
