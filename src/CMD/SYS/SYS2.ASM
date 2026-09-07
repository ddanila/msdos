	TITLE	SYS-2-	Program
	include version.inc
	INCLUDE SYSHDR.INC

	page	80,132
	BREAK	<SYS2 - Program Organization>
;******************+ START OF PSEUDOCODE +**************************************
; Ä Ä Ä Ä Ä Ä Ä Ä¿	ÚÄÄÄÄÄÄÄÄÄ¿
; Read_Directory ÃÄÄÄÄÄÄ´Find_DPB ³
; Ä Ä Ä Ä Ä Ä Ä ÄÙ	ÀÄÄÄÄÄÄÄÄÄÙ
; Ä Ä Ä Ä Ä Ä Ä Ä Ä ÄÄ¿
; Verify_File_LocationÃÄ¿
; Ä Ä Ä Ä Ä Ä Ä Ä Ä ÄÄÙ ³
; ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
; ³ ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿   ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿  Ú Ä Ä Ä Ä Ä Ä ¿
; ÃÄ´Move_DIR_EntryÃÄÄÂ´Find_Empty_Entry ÃÄÄ´Direct_Access³
; ³ ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ  ³ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ  À Ä Ä Ä Ä Ä Ä Ù
; ³		      ³ÚÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
; ³		      À´Direct_Access³
; ³		       ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
; ³  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
; ³ ÚÄÄÄÄÄÄÄÄÄÄÄÄ¿     ÚÄÄÄÄÄÄÄÄÄÄÄ¿	    ÚÄÄÄÄÄÄÄ¿
; ÀÄ´Free_ClusterÃÄÄÄÄÂ´Is_It_EmptyÃÄÄÄÄÄÄÄÄ´Unpack ³
;   ÀÄÄÄÄÄÄÄÄÄÄÄÄÙ    ³ÀÄÄÄÄÄÄÄÄÄÄÄÙ	    ÀÄÄÄÄÄÄÄÙ
;		      ³ÚÄÄÄÄÄÄÄÄÄÄ¿	    Ú Ä Ä Ä ¿
;		      Ã´Search_FATÃÄÄÄÄÄÄÄÄÂ´Unpack ³
;		      ³ÀÄÄÄÄÄÄÄÄÄÄÙ	   ³À Ä Ä Ä Ù
;		      ³ 		   ³ÚÄÄÄÄÄÄ¿
;		      ³ 		   Ã´Pack  ³
;		      ³ 		   ³ÀÄÄÄÄÄÄÙ
;		      ³ 		   ³ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿  Ú Ä Ä Ä ¿
;		      ³ 		   Ã´Find_Empty_Cluster³ÄÄ´Unpack ³
;		      ³ 		   ³ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ  À Ä Ä Ä Ù
;		      ³ 		   ³ÚÄÄÄÄÄÄÄÄÄ¿ 	  Ú Ä Ä Ä Ä Ä Ä ¿
;		      ³ 		   Ã´Xfer_DataÃÄÄÄÄÄÄÄÄÄÄÄ´Direct_Access³
;		      ³ 		   ³ÀÄÄÄÄÄÄÄÄÄÙ 	  À Ä Ä Ä Ä Ä Ä Ù
;		      ³ 		   ³Ú Ä Ä Ä Ä Ä Ä ¿
;	ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÙ 		   À´Direct_Access³
;	³				    À Ä Ä Ä Ä Ä Ä Ù
;	³ÚÄÄÄÄÄÄÄÄÄÄ¿	 ÚÄÄÄÄÄÄÄÄÄÄÄ¿	    Ú Ä Ä Ä ¿
;	À´Search_DIRÃÄÄÄÄ´Search_LoopÃÄÄÄÄÄÂ´Unpack ³
;	 ÀÄÄÄÄÄÄÄÄÄÄÙ	 ÀÄÄÄÄÄÄÄÄÄÄÄÙ	   ³À Ä Ä Ä Ù
;					   ³ÚÄÄÄÄÄÄ¿
;					   Ã´Pack  ³				     Direct_Access
;					   ³ÀÄÄÄÄÄÄÙ
;					   ³ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿  Ú Ä Ä Ä ¿
;					   Ã´Find_Empty_Cluster³ÄÄ´Unpack ³
;					   ³ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ  À Ä Ä Ä Ù
;					   ³ÚÄÄÄÄÄÄÄÄÄÄÄÄ¿  Ú Ä Ä Ä ¿
;					   Ã´Sub_DIR_Loop³ÄÄ´Unpack ³
;					   ³ÀÄÄÄÄÄÄÄÄÄÄÄÄÙ  À Ä Ä Ä Ù
;					   ³ÚÄÄÄÄÄÄÄÄÄ¿ 	  Ú Ä Ä Ä Ä Ä Ä ¿
;					   Ã´Xfer_DataÃÄÄÄÄÄÄÄÄÄÄÄ´Direct_Access³
;					   ³ÀÄÄÄÄÄÄÄÄÄÙ 	  À Ä Ä Ä Ä Ä Ä Ù
;					   ³Ú Ä Ä Ä Ä Ä Ä ¿
;					   À´Direct_Access³
;					    À Ä Ä Ä Ä Ä Ä Ù
;
;******************+ END OF PSEUDOCODE +*****************************************
	BREAK	<SYS2 - Data space>

	DATA	SEGMENT PARA PUBLIC

	extrn	TargDrvNum:BYTE, TargSpec:WORD, bio_owns_it:BYTE, DOS_VER:BYTE
	extrn	packet_sectors:WORD, packet_buffer:WORD, packet:WORD

	public	THIS_DPB, BUF, DIR_SECTOR, first_dir_sector


;			$SALUT (4,25,30,41)

first_dir_sector	dw   ?
current_dir_sector	dw   ?
last_dir_sector 	dw   ?
entries_per_sector	db   ?
current_entry		db   3
source_ptr		dw   ?
ibmbio_status		db   ?
ibmdos_status		db   ?
FAT_sectors		dw   FAT_sect_size ; initailize it to 12 sectors
FAT_changed		db   0		; FAT must be written - its packed
FAT_2			db   0		; if non zero, [packet] points at FAT 2
cluster_count		dw   ?		; number of clusters that must be free
last_cluster		dw   0		; cluster pointing to [current_cluster]
current_cluster 	dw   2		; start at cluster 2
next_cluster		dw   0		; cluster [current_cluster] points at
empty_cluster		dw   0		; newly aquired cluster
cluster_low		dw   0
cluster_high		dw   clusters_loaded

l_sector_offset 	dw   ?		; this is the value required to convert
					;  a sector from a cluster # to a
					;  logical sector # for INT 25 & 26

DIR_cluster		dw   0		; Sub DIR cluster being processed
					;  = 0 - not processing s Sub DIR
					;  = 1 - starting to process
					;	 (set by Search_Loop)
					;  = n - Sub DIR cluster now being
					;	 processed. (set by Xfer_Data)
present_cluster 	dw   ?		; current cluster for DIR search
sector_offset		dw   ?		; current sector in present_cluster
entry_number		db   ?		; DIR entry in current sector
FRAME_ptr		dw   ?
dir_sector_low		dw   ?
dir_sector_hi		dw   ?
DIR_offset		dw   ?
sector_count		db   1

FRAME			STRUC

p_cluster		dw   ?		; current cluster for DIR search
s_offset		dw   ?		; current sector in present_cluster
e_number		db   ?		; DIR entry in current sector

FRAME			ENDS

BIGFAT			DB   0		;0=12 bit FAT, NZ=16bit FAT
EOFVAL			DW   0FF8H	;0FF8 for 12 bit FAT,0FFF8 for 16 bit
BADVAL			DW   0FF7H	;0FF7 for 12 bit FAT,0FFF7 for 16 bit

THIS_DPB		DD   ?		;Pointer to drive DPB
CSIZE			DW   ?		;Sectors per cluster
SSIZE			DW   ?		;bytes per sector
DSIZE			DW   ?		;# alloc units on disk
FSIZE			DW   ?		;# sectors in 1 FAT
first_FAT		DW   ?		; first cluster of first FAT
num_of_FATS		db   ?		; number of FATS
MCLUS			DW   ?		;DSIZE + 1
;
; The following is used as the source/destination for a name trans
;
ENTRY_BUF		DB   size dir_entry DUP (?)
DIR_BUF 		DB   ( 34 * size frame) DUP (?) ; space for DIR frames - see Search_DIR
DIR_SECTOR		DB   512 DUP (?) ; space for 1 DIR sector

BUF			LABEL BYTE	; beginning of area for file reads

			DATA ENDS

;  $SALUT (4,4,9,41)

   CODE SEGMENT PARA PUBLIC

   ASSUME cs:CODE, ds:nothing, es:nothing

   BREAK <SYS - Find_DPB >
;******************* START OF SPECIFICATIONS ***********************************
;Routine name:	Find_DPB
;*******************************************************************************
;
;Description:	Find_DPB gets the pointer to the Target DPB and initializes all
;		local valiables required by Move_DIR_Entry and Free_Cluster.
;
;NOTE:		This routine contains code that is specific for DOS 3.3.  It
;		must be removed for subsequent releases.  In and before
;		DOS 3.3 the DPB was one byte smaller.  The field dpb_FAT_size
;		was changed from a byte to a word in DOS 4.00.
;
;
;Entry: 	Called by Verify_File_Location
;
;Called Procedures:
;
;		INT 21 - 32h
;
;Input: 	al = Drive number
;
;Output:	All local variables initalized
;		DS:BX = pointer to DPB
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START Find_DPB
;
;	get DPB pointer (INT 21 - 32h)
;	initalize first_dir_sector
;	initalize current_dir_sector
;	initalize current_cluster (0 for root)
;	calculate # of clusters required by IBMBIO
;	initalize [cluster_count]
;	calculate # of dir sectors
;	initalize [dir_sectors]
;	initalize [current_entry] to #3
;	allocate memory for FAT + 32 DIR frames
;	allocate memory for data sectors
;
;	ret
;
;	END Find_DPB
;
;******************-  END  OF PSEUDOCODE -**************************************


   PUBLIC Find_DPB

   Find_DPB PROC NEAR

   MOV	AH,GET_DPB			;Get the DPB
   INT	21H

   mov	ax,(disk_reset shl 8)		; reset the disk to protect all INT 26's
   INT	21h				;   that follow


					; initalize current_entry to #3

   ASSUME ds:nothing,ES:DGROUP

   MOV	WORD PTR [THIS_DPB+2],DS	;
   push es				;
   pop	ds				;

   ASSUME DS:DGROUP

   mov	WORD PTR [THIS_DPB],bx		;
   lds	bx,[THIS_DPB]			;

   ASSUME ds:nothing

   mov	ax,[bx.dpb_sector_size] 	;
   mov	[SSIZE],ax			;Sector size in bytes

   xor	ax,ax				;
   mov	al,[bx.dpb_cluster_mask]	;
   inc	al				;
   mov	[CSIZE],ax			;Sectros per cluster

   mov	ax,[BX.dpb_first_FAT]		;First sector of FAT
   mov	[first_FAT],ax			;

   mov	al,[BX.dpb_FAT_count]		;Number of FATs
   mov	[num_of_FATS],al		;

   mov	ax,[bx.dpb_max_cluster] 	;
   mov	[MCLUS],ax			;Bound for FAT searching

   cmp	ax,4096-10			;Big or little FAT?
;  $if	ae				;
   JNAE $$IF1
       inc  [BIGFAT]			;
       mov  [EOFVAL],0FFF8h		;
       mov  [BADVAL],0FFF7h		;
;  $endif				;
$$IF1:
   dec	ax				;
   mov	[DSIZE],ax			;Total data clusters on disk

					;--------------------------------------
					; calculate # of dir sectors and
					;    initalize last_dir_sector
					;--------------------------------------
   mov	ax,[bx.dpb_root_entries]	; max # of entries in the root
   mov	cx,size dir_entry		; size of each entry
   mul	cx				; size of root directory in bytes
					; in AX:DX
   mov	cx,[SSIZE]			; # of bytes per sector
   div	cx				; = # of root directory sectors
   cmp	dx,0				; any remainder ?
;  $if	nz				;
   JZ $$IF3
       inc  ax				;
;  $endif				;
$$IF3:
   mov	[first_dir_sector],ax		; save for last directory sector calc.

   mov	ax,[bx.dpb_FAT_size]		;Sectors for one fat
   cmp	DOS_VER,0			; running on current version?

;  $if	ne				; BANG! - we'er running on DOS 3.3
   JE $$IF5
					;	  dpb_FAT_size is only a BYTE
					;	  so ajust it to a word
       xor  ah,ah
       dec  bx				; BACK UP the index into the DPB
       mov  WORD PTR [THIS_DPB],bx	;   save it for later (dpb_next_free)
					; Now  everything else lines up !
;  $endif
$$IF5:

   mov	[FSIZE],ax			;

   mov	ax,[SSIZE]			;
   mov	cx,SIZE dir_entry		;
   div	cx				;
   dec	ax				; first entry number is zero
   mov	[entries_per_sector],al 	;
   cmp	[BIGFAT],0			; is it a big fat ?

;  $if	e				; if not
   JNE $$IF7
       mov  ax,[FSIZE]			;
       mov  [FAT_sectors],ax		; bring it down to the actual size
;  $endif				;
$$IF7:
					;--------------------------------------
					; initalize first_dir_sector
					;	and current_dir_sector
					;--------------------------------------
   mov	ax,[bx.dpb_dir_sector]		; first dir sector
   mov	[current_dir_sector],ax 	; save it for later
   xchg [first_dir_sector],ax		; save it and recover # of dir sectors

   add	ax,[first_dir_sector]		; # of last directory sector
   mov	[l_sector_offset],ax		;
   dec	ax				;
   mov	[last_dir_sector],ax		; save it for later

   ret					;

   Find_DPB ENDP

   BREAK <SYS - Move_DIR_Entry >
;******************* START OF SPECIFICATIONS ***********************************
;Routine name: Move_DIR_Entry
;*******************************************************************************
;
;Description:	Move_DIR_Entry will move the entry pointed to by the caller into
;		the first available location in the root, if one exists.
;
;Entry: 	Called by Verify_File_Location
;
;Called Procedures:
;
;		Find_Empty_Entry - find an available entry
;		Direct_Access	 - do an INT 25 & INT 26
;
;Input: 	first_dir_sector
;		current_dir_sector
;		last_dir_sector
;		current_entry
;		pointer set to source entry to be moved
;
;Output:	CF = 0 - DIR entry moved to first available entry
;		CF = 1 - Error, not able to free up entry
;
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START  Move_DIR_Entry
;
;	set dest = entry_buffer
;	save source pointer
;	copy input entry to buffer
;	if no error and
;	call Find_Empty_Entry to find hole in directory
;	if no error
;		set source to entry_buffer
;		set dest to hole pointer
;		copy buffer to enpty entry
;		if first_dir_sector != current_dir_sector
;		set up for write
;		call Direct_Access to write it out
;			if no error
;				set up for first_dir_sector
;				set up for read
;				call Direct_Access to read it in
;			endif
;		if no error
;			recover source pointer
;			null out entry being processed
;			set up for write
;			call Direct_Access to update the root
;		endif
;	endif
;
;	ret
;
;	END   Move_DIR_Entry
;
;******************-  END  OF PSEUDOCODE -**************************************


   PUBLIC Move_DIR_Entry

   Move_DIR_Entry PROC NEAR

   ASSUME DS:DGROUP			;  must ensure this is true xxxxxxxxxxxxxxxxx

					; source = source entry (#1 or #2) DS:SI
   lea	di,ENTRY_BUF			; dest	 = entry_buffer
   mov	[source_ptr],si 		; save source pointer
   mov	ax,size dir_entry		;
   mov	cx,ax				;
   rep	movsb				; copy directory entry into entry buffer
   lea	si,DIR_SECTOR			; start at beginning of directory
   mov	di,si				; save start for end calculation
   shl	ax,1				; set pointer for current entry to #3
   add	ax,si				;
   mov	si,ax				;
   add	di,[SSIZE]			; calculate end of directory
   call Find_Empty_Entry		; find hole in directory
;  $if	nc				; if no error and
   JC $$IF9
       mov  di,si			; dest	 = hole pointer
       lea  si,ENTRY_BUF		; source = entry_buffer
       mov  cx,size dir_entry		;
       rep  movsb			; copy buffer to DTA
       mov  ax,[first_dir_sector]	;
       cmp  ax,[current_dir_sector]	;
;      $if  ne				; if first_dir_sector != current_dir_sector
       JE $$IF10
	   mov	ah,-1			; set up for write
	   call Direct_Access		; write it out
;	   $if	nc			; if no error
	   JC $$IF11
	       mov  ax,[first_dir_sector] ; set up for first_dir_sector
	       mov  [current_dir_sector],ax ; update current_dir_sector
	       mov  [packet],ax 	;
	       xor  ah,ah		; set up for read
	       call Direct_Access	; read it in
;	   $endif			;
$$IF11:
;      $endif				;
$$IF10:
;      $if  nc				; if no error
       JC $$IF14
	   mov	si,[source_ptr] 	; recover source pointer
	   mov	BYTE PTR [si],deleted	; delete entry being processed
	   mov	BYTE PTR [si.dir_first],0 ; null out cluster #
	   cmp	si,offset DIR_SECTOR	;  are we at the first entry ?
;	   $if	e,and			; if so -
	   JNE $$IF15
	   cmp	BYTE PTR [si + size DIR_ENTRY],0 ; is second one a null entry?
;	   $if	e			; if so -
	   JNE $$IF15
	       mov  BYTE PTR [si + size DIR_ENTRY],deleted ; make it deleted
;	   $endif			;
$$IF15:
	   mov	ah,-1			; set up for write
	   call Direct_Access		; write it out
;      $endif				;
$$IF14:
;  $endif				;
$$IF9:

   ret					;

   Move_DIR_Entry ENDP

   BREAK <SYS - Find_Empty_Entry >
;******************* START OF SPECIFICATIONS ***********************************
;Routine name: Find_Empty_Entry
;*******************************************************************************
;
;Description:	Find_Empty_Entry scans all root directory sectors looking for
;		an empty entry.
;
; NOTE; 	It is assumed that each DIRectory entry is 32 bytes long
;
;Called Procedures:
;
;		Direct_Acces - do INT 25
;
;Input: 	current_dir_sector
;		last_dir_sector
;		first_dir_sector in DTA buffer
;		DS:SI set for first entry to check
;		DS:DI set to end of directory (sector)
;
;Output:	success 	pointer set to hole
;		CF = 0		current_entry updated
;				current_dir_sector updated
;
;		fail		message # set
;		CF = 1
;
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START  Find_Empty_Entry
;
;	search all available sectors
;		search for hole  (leaves pointer set to the hole)
;		leave if empty
;		leave if deleted
;		advace to next entry
;		exitif past end of sector
;			set carry
;		orelse
;		endloop
;			clear carry
;			save current_entry
;		endsrch
;	exitif hole found (no CF)
;		update current_entry
;	orelse
;		if not at end (current <= last)
;			set for read
;			call Direct_Access to read in next sector
;		else
;			load error message (no room for system files)
;			set error (CF)
;		endif
;	leave if error (CF)
;			update current_DIR_sector
;			update current_entry
;		endif
;	endloop
;	endsrch
;
;	ret
;
;	END  Find_Empty_Entry
;
;******************-  END  OF PSEUDOCODE -**************************************

   PUBLIC Find_Empty_Entry

   Find_Empty_Entry PROC NEAR

;  $search				; for sectors available
$$DO19:
;      $search				; for hole - this leaves pointer set at
$$DO20:
					; the hole
	   cmp	BYTE PTR [si],empty	; empty   ?
;      $leave e 			;
       JE $$EN20
	   cmp	BYTE PTR [si],deleted	; deleted ?
;      $leave e 			;
       JE $$EN20
	   add	ax,size dir_entry	; advace to next entry
	   mov	si,ax			;
	   cmp	ax,di			; past end of sector ?
;      $exitif ae			; at end
       JNAE $$IF20
	   stc				; set carry
;      $orelse				;
       JMP SHORT $$SR20
$$IF20:
;      $endloop 			;
       JMP SHORT $$DO20
$$EN20:
	   clc				; clear carry
;      $endsrch 			;
$$SR20:
;  $exitif nc				; hole is found
   JC $$IF19
;  $orelse				;
   JMP SHORT $$SR19
$$IF19:
       inc  [current_dir_sector]	; advance to next sector
       mov  ax,[current_dir_sector]	;
       cmp  ax,[last_dir_sector]	; past last_dir_sector ?
;  $leave a				; if at end (current <= last)
   JA $$EN19
       lea  si,DIR_SECTOR		; start at start of next sector
       mov  [packet],ax 		;
       xor  ah,ah			; set for read
       call Direct_Access		; read in next sector
;      $if  c				; if error
       JNC $$IF30
	   dec	[current_dir_sector]	; restore curren_dir_sector
;      $endif				;
$$IF30:
;  $leave c				; error
   JC $$EN19
       mov  ax,si			; reset pointer to start
;  $endloop a				; past last_dir_sector
   JNA $$DO19
$$EN19:
       mov  ax,(util shl 8) + no_room	; set message# and class
       stc				; ensure carry still set
;  $endsrch				;
$$SR19:

   ret					;

   Find_Empty_Entry ENDP



   BREAK <SYS - Direct_Access >
;******************* START OF SPECIFICATIONS ***********************************
;Routine name: Direct_Access
;*******************************************************************************
;
;Description:  Direct_Access
;
;Called Procedures:
;
;		INT 25
;		INT 26
;
;Input:       ah = 0  - read
;	      ah = -1 - write
;
;Output:      CF = 0 - Sectors moved
;	      CF = 1 - Message and class in AX
;
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START  Direct_Access
;
;	save registers
;	if read
;		INT 25
;	else
;		zero ah
;		INT 26
;	endif
;	save return flag
;	clear stack
;	if error
;	       set message# and class
;	endif
;	restore registers
;
;	ret
;
;	END  Direct_Access
;
;******************-  END  OF PSEUDOCODE -**************************************

   public Direct_Access

   Direct_Access PROC NEAR

   push si				; save registers
   push bp				; save registers
   cmp	DOS_VER,0			;

;  $if	e				;
   JNE $$IF35

       mov  cx,-1			; set up for INT
       mov  bx,offset packet		;

;  $else				;
   JMP SHORT $$EN35
$$IF35:
					; If running on DOS 3.3 the INT 25
					; interface is:
					;	al = drive number
					;	bx = buffer for read data
					;	cx = # of sectors
					;	dx = start sector
       mov  cx,word ptr [packet_sectors] ;
       mov  dx,[packet] 		; get starting dir sector
       mov  bx,PACKET_BUFFER[0] 	;

;  $endif				;
$$EN35:

   mov	al,TargDrvNum			; set up drive number
   dec	al				;
   cmp	ah,0				;
;  $if	e				; if read
   JNE $$IF38
       INT  25h 			; INT 25
;  $else				; else
   JMP SHORT $$EN38
$$IF38:
       xor  ah,ah			; zero ah
       INT  26h 			; INT 26
;  $endif				; endif
$$EN38:
;; ?					; save return flag
   pop	ax				; clear stack
   pop	bp				;
   pop	si				;

   ret					;

   Direct_Access ENDP

   BREAK <SYS - Free_Cluster >
;******************* START OF SPECIFICATIONS ***********************************
;Routine name:	Free_Cluster processor
;*******************************************************************************
;
;Description: IBMBIO MUST have at lease cluster 2 as its first cluster. This
;	      routine ensures that cluster 2 and any additional clusters (if
;	      needed) ARE available. If they are chained, their data is copied
;	      into the first available cluster, and the needed cluster is
;	      is replaced by this cluster in the FAT
;
;Entry:       Called by Verify_File_Location
;
;Called Procedures:
;
;	      Is_It_Empty - see if Cluster is empty
;	      Search_FAT  - scan FAT to see if the cluster is chained
;	      Search_DIR  - use FAT to walk directories looking for the cluster
;
;	NOTES: Check_FAT and Check_DIR will do the processing requred to move
;	       data out of the cluster and fix up the FAT and the Dir (if needed).
;
;Input:       All local DBP values initalized by Get_DPB
;
;Ouput:       CF = 0  -  Cluster available
;	      CF = 1  -  Cluster not available
;
;
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START  Free_Cluster
;
;	initialize [cluster_count]
;	do until all copies of FAT attempted
;		load FAT into memory (INT 25)
;	leave if successful
;	enddo
;	do until [cluster_count] = 0
;		call Is_It_Empty
;		if not found and
;		if no errors and
;		call Search_FAT
;		if not found and
;		if no errors
;			call Search_DIR
;		endif
;	leave if error
;	enddo
;
;	ret
;
;	END Free_Cluster
;
;******************-  END  OF PSEUDOCODE -**************************************

   public Free_Cluster

   Free_Cluster PROC NEAR

   mov	ax,IBMLOADSIZE			; calculate # of clusters reqd
   xor	cx,cx				;
   mov	di,cx				;
   dec	di				;
   mov	cx,[CSIZE]			;   by IBMLOAD (consecutive clusters
   div	cl				;   for IBMBIO)
   cmp	ah,0				;
;  $if	ne				;
   JE $$IF41
       inc  al				;
       xor  ah,ah			;
;  $endif				;
$$IF41:
   inc	ax				; will be decrimenter immediately upon
					;   entering complex do below
   mov	[cluster_count],ax		; save for later
   mov	ax,[FAT_sectors]		;only read needed sectors
   mov	[packet_sectors],ax		;
   mov	cl,[num_of_FATS]		;Number of FATs
   mov	ax,[first_FAT]			;First sector of FAT
   mov	[packet],ax			;
   mov	[packet_buffer],OFFSET BUF	; point to FAT buffer
   call Load_FAT			;
;  $if	nc				; no error so far.......
   JC $$IF43
;      $do  complex			;
       JMP SHORT $$SD44
$$DO44:
	   mov	[cluster_count],cx	;
	   call Is_It_Empty		;
;      $leave c 			;
       JC $$EN44
	   cmp	al,not_found		; ( -1 ?)
;	   $if	e			; if not found
	   JNE $$IF46
	       call Search_FAT		; scan FAT to see if cluster chained
;	   $else			;
	   JMP SHORT $$EN46
$$IF46:
	       clc			;
;	   $endif			;
$$EN46:
;      $leave c 			;
       JC $$EN44
	   cmp	al,not_found		; if still not found
;	   $if	e			;
	   JNE $$IF50
	       call Search_DIR		; scan DIR to see who starts with #2
;	   $else			;
	   JMP SHORT $$EN50
$$IF50:
	       clc			; ensure carry is still clear
;	   $endif			;
$$EN50:
;      $leave c 			;
       JC $$EN44
	   inc	[current_cluster]	;
;      $strtdo				;
$$SD44:
	   mov	cx,[cluster_count]	;
;      $enddo LOOP			;
       LOOP $$DO44
$$EN44:
;  $endif				;
$$IF43:
;  $if	c				;
   JNC $$IF57
       mov  ax,(util shl 8) + no_room	; error message - no room to sys
;  $endif				;
$$IF57:

   ret					;

   Free_Cluster ENDP

   public Load_FAT

   Load_FAT PROC NEAR

   lea	bx,[packet]			;

;  $search				;
$$DO59:
       xchg cx,di			;
       push cx				;
       push di				;
       push dx				;
       push bx				;
       xor  ah,ah			;
       mov  al,TargDrvNum		; set up drive number
       dec  al				;
       cmp  DOS_VER,0			; if DOS 3.3

;      $if  ne				; load registers for old style INT 25
       JE $$IF60
	   mov	bx,[packet_buffer]	;
	   mov	cx,[packet_sectors]	;
	   mov	dx,[packet]		;
;      $endif				;
$$IF60:

       push bp				;
       int  25h 			;Read in the FAT
       pop  ax				;Flags
       pop  bp				;
;  $exitif nc				; error - set up for next fat
   JC $$IF59
       add  sp,8			;Clean up stack
       mov  ax,1			;
;	mov [packet],ax ; reset to first FAT
;  $orelse				;
   JMP SHORT $$SR59
$$IF59:
       pop  bx				;
       pop  dx				;
       pop  cx				;
       pop  di				;
       add  [packet],dx 		; point to start of next FAT
       inc  [FAT_2]			;
;  $endloop LOOP			;Try next FAT
   LOOP $$DO59
       mov  ax,(util shl 8) + no_room	; set message# and class
;  $endsrch				;
$$SR59:

   ret

   Load_FAT ENDP


   BREAK <SYS - Is_It_Empty >
;******************* START OF SPECIFICATIONS ***********************************
;Routine name: Is_It_Empty
;*******************************************************************************
;
;Description: Is_It_Empty looks directly into the FAT to see if a specified
;	      cluster is allocated.
;
;Entry:       Called by Free_Cluster
;
;Called Procedures:
;
;	      Unpack - unpack a FAT cluster number (CF set on error)
;
;Input:       CX = cluster to check
;	      12 sectors of FAT in BUF
;
;Output:      CF = 0   AL = 0  - cluster 2 found empty
;		       AL =-1  - not found & no error
;	      CF = 1   - critical error
;
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START Is_It_Empty
;
;	set up for call to Unpack
;	set cluster # to [cluster_number]
;	call Unpack
;	if no error
;		if cluster is not empty
;			if bad cluster
;				set error flag
;			else
;				if cluster belongs to IBMBIO
;					if next cluster is not contiguous
;						 reset ownership flag
;					endif
;					set cluster empty (ax = 0)
;				else
;					save cluster number
;					set cluster used (ax = -1)
;				endif
;		else
;			set cluster empty (ax = 0)
;		endif
;	endif
;
;	ret
;
;	END Is_It_Empty
;
;******************-  END  OF PSEUDOCODE -**************************************

   public Is_It_Empty

   Is_It_Empty PROC NEAR

   mov	si,[current_cluster]		; set up for call to Unpack
   call Unpack				; to find the value
;  $if	nc				; if no error
   JC $$IF66
;      $if  nz				; cluster is not empty
       JZ $$IF67
	   mov	ax,di			;
	   cmp	al,bad_sector		;
;	   $if	e			;
	   JNE $$IF68
	       stc			;
;	   $else			;
	   JMP SHORT $$EN68
$$IF68:
	       cmp  [bio_owns_it],0	; is it owned by IBMBIO ?
;	       $if  ne			; if it is
	       JE $$IF70
		   dec	ax		;
		   cmp	ax,[current_cluster] ;
;		   $if	ne		;
		   JE $$IF71
		       dec  [bio_owns_it] ; its not the owner form here on
;		   $endif		;
$$IF71:
		   xor	ax,ax		;
		   clc			; its IBMBIO's anyway
;	       $else			;
	       JMP SHORT $$EN70
$$IF70:
		   mov	[next_cluster],di ;
		   xor	ax,ax		; reset fail flag
		   dec	ax		;  - its not empty
;	       $endif			;
$$EN70:
;	   $endif			;
$$EN68:
;      $else				; its empty !
       JMP SHORT $$EN67
$$IF67:
	   xor	ax,ax			; its empty - and no error
;      $endif				;
$$EN67:
;  $endif				;
$$IF66:

   ret					;

   Is_It_Empty ENDP

   BREAK <SYS - Search_FAT >
;******************* START OF SPECIFICATIONS ***********************************
;Routine name: Search_FAT
;*******************************************************************************
;
;Description: Search_FAT for a [cluster_number]. If it is listed in the FAT,
;	      then its chained into a file. The data in the [cluster_number] is
;	      then buffered, and copied into an empty cluster, and the FAT is
;	      updated
;
;Called Procedures:
;
;		Unpack		   - to find a FAT entry for a Cluster #
;		Pack		   - to set a FAT entry for a Cluster #
;		Find_Empty_Cluster - find an unused cluster
;		Xfer_Data	   - transfere data from one cluster to another
;		Direct_Access	   - absolute disk i/o
;
;Input: 	FAT in BUF
;		[cluster_number] of specified cluster
;
;Output:	CF = 0	- AX = 0 if cluster found
;			     = -1 if cluster not found
;		CF = 1 if critical error
;
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START Search_FAT
;
;	set cluster # to [cluster_number]
;	search till at end of FAT
;		call Unpack
;	exitif cluster found
;		save [last_cluster]
;		clear CF
;	orelse
;		advance to next cluster
;	endloop if past last cluster in fat
;		set CF
;	endsrch
;	if cluster found
;		call Find_Empty_Cluster
;	endif
;
;	if empty cluster available and
;
;	call Xfer_Data
;
;	if no errors
;
;	set taget cluster as one pointing to [cluster_number]
;	set value to that of empty cluster
;	call Pack to update FAT
;	set target cluster as [cluster_number]
;	set cluster value to empty
;	call Pack to update FAT
;	set destination to first sector of first FAT
;	set count to # of fat sectors
;	set up for write
;	do until all FATS written
;		call Direct_Access
;		advace to next FAT  (ignore errors)
;	enddo
;
;	endif
;
;	if no errors
;		update DPB first cluster and total empty clusters
;	endif
;
;	ret
;
;	END Search_FAT
;
;******************-  END  OF PSEUDOCODE -**************************************

   public Search_FAT

   Search_FAT PROC NEAR

   mov	si,[current_cluster]		; set cluster # to [cluster_number]
;  $search				; till at end of FAT
$$DO79:
       call Unpack			;
;  $leave c				; quit on an error
   JC $$EN79
       cmp  di,[current_cluster]	; is it [current_cluster] ?
;  $exitif e				; it is
   JNE $$IF79
       mov  [last_cluster],si		; save number for later
       xor  ax,ax			;
       clc				; clear error flag (found)
;  $orelse				;
   JMP SHORT $$SR79
$$IF79:
       inc  si				; advance to next cluster
       xor  ax,ax			;
       dec  ax				;
       cmp  si,[MCLUS]			; at the end ?
;  $endloop e				; if past last cluster
   JNE $$DO79
$$EN79:
       stc				;
;  $endsrch				;
$$SR79:
;  $if	nc				; if cluster found
   JC $$IF85
       call Find_Empty_Cluster		; to move data to
;  $endif				;
$$IF85:
;  $if	nc,and				; empty cluster available and
   JC $$IF87
   call Xfer_Data			; to move data to new cluster
;  $if	nc,and				; no errors
   JC $$IF87
   mov	si,[last_cluster]		; set target [last_cluster]
   mov	dx,[empty_cluster]		; set value to [empty_cluster]
   call Pack				; to update FAT
;  $if	nc,and				; no errors
   JC $$IF87
   mov	si,[empty_cluster]		; set target [empty_cluster]
   mov	dx,[next_cluster]		; set value to [next_cluster]
   call Pack				; to update FAT
;  $if	nc,and				; no errors
   JC $$IF87
   mov	si,[current_cluster]		; set target [current_cluster]
   xor	dx,dx				; set cluster value to empty
   call Pack				; to update FAT
;  $if	nc				; no errors
   JC $$IF87
       xor  ah,ah			;
       dec  ah				;
       call Direct_Access		; write it out - ignore errors
       mov  ax,[FSIZE]			;
       cmp  [FAT_2],0			;
;      $if  e				;
       JNE $$IF88
	   add	[packet],ax		;
	   inc	[FAT_2] 		; packet points to FAT #2
;      $else				;
       JMP SHORT $$EN88
$$IF88:
	   sub	[packet],ax		;
	   mov	[FAT_2],0		; reset - packet points to FAT #1
;      $endif				;
$$EN88:
       xor  ah,ah			;
       dec  ah				;
       call Direct_Access		; write it out - ignore errors
       mov  [FAT_changed],0		; FAT now cleared
       push es				; update DPB first cluster
       mov  bx,ds			;
       mov  es,bx			;
       lds  bx,[THIS_DPB]		;

       ASSUME ds:nothing,ES:DGROUP

       mov  [bx.dpb_next_free],2	;
       mov  ax,es			;
       mov  ds,ax			;
       pop  es				;
       xor  ax,ax			; signal success (ax = 0 , cf = 0)

       ASSUME DS:DGROUP, es:nothing

;  $endif				;
$$IF87:
;  $if	c				;
   JNC $$IF92
       cmp  ax,-1			;
;      $if  e				;
       JNE $$IF93
	   clc				; not a critical error - keep trying
;      $else				;
       JMP SHORT $$EN93
$$IF93:
	   stc				; major problem - critical error
;      $endif				;
$$EN93:
;  $endif				;
$$IF92:

   ret					;

   Search_FAT ENDP

   BREAK <SYS - Find_Empty_Cluster >
;******************* START OF SPECIFICATIONS ***********************************
;Routine name: Find_Empty_Cluster
;*******************************************************************************
;
;Description: Find_Empty_Cluster finds the first available empty cluster
;
;Called Procedures:
;
;		Unpack	- find next cluster number
;
;Input: 	none
;
;Output:	CF = 0 - empty cluster found (# in [empty_cluster])
;		CF = 1 - no empty clusters (ax = message)
;
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START Find_Empty_Cluster
;
;	search till at end of FAT
;		call Unpack
;	exitif cluster is empty (ZF)
;		save empty cluster number
;		clear CF
;	orelse
;		advance to next cluster
;	endloop if past last cluster
;		load ax message # - no room for sys files
;		set CF
;	endsrch
;
;	ret
;
;	END Find_Empty_Cluster
;
;******************-  END  OF PSEUDOCODE -**************************************

   public Find_Empty_Cluster

   Find_Empty_Cluster PROC NEAR

   mov	si,[current_cluster]		;
   mov	ax,[cluster_count]		;
   add	si,ax				; look past required space
;  $search				; till at end of FAT
$$DO97:
       call Unpack			; to convert # to value
;  $exitif z				; cluster is empty
   JNZ $$IF97
       mov  [empty_cluster],si		; save it for later
       clc				; clear error flag
;  $orelse				;
   JMP SHORT $$SR97
$$IF97:
       inc  si				; advance to next cluster
       cmp  si,[MCLUS]			; past the end ?
;  $endloop e				; if past last cluster
   JNE $$DO97
       stc				; set error flag
       mov  ax,(util shl 8) + no_room	; error message - no room to sys
;  $endsrch				;
$$SR97:

   ret					;

   Find_Empty_Cluster ENDP

   BREAK <SYS - Xfer_Data >
;******************* START OF SPECIFICATIONS ***********************************
;Routine name: Xfer_Data
;*******************************************************************************
;
;Description: Xfer_Data moves the data from [cluster_number] into the cluster
;	      number passed in ax.
;
;Called Procedures:
;
;		Direct_Access - do disk i/o
;
;Input: 	[current_cluster]
;		[empty_cluster]
;
;Output:	CF = 0	- data transfered
;		CF = 1	- error - message in AX
;
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START Xfer_Data
;
;	save active FAT starting sector
;	set source to first sector of [current_cluster]
;	set count to # of sectors per cluster
;	set up for read
;	call Direct_Access to read data
;	if no errors
;		set source to first sector of [empty_cluster]
;		set up for write
;		call Direct_Access to write data
;	endif
;	restore Fat starting sector
;	set count to FAT_sectors
;	set up for read
;	call Direct_Access to restore the FAT copy
;
;	endif
;
;	ret
;
;	END Xfer_Data
;
;******************-  END  OF PSEUDOCODE -**************************************

   public Xfer_Data

   Xfer_Data PROC NEAR

   push [packet]			; save active FAT starting sector
   push [packet+2]			;
   push [packet_sectors]		;
   mov	ax,[CSIZE]			;
   mov	[packet_sectors],ax		;
   mov	ax,[current_cluster]		; set source to [current_cluster]
   call cluster_2_sector		; convert Cluster to sector #
   mov	[packet],ax			; low sector word
   mov	[packet+2],dx			; high sector word
   xor	ah,ah				; set up for read
   call Direct_Access			; to read data
;  $if	nc				; no errors
   JC $$IF102
       mov  ax,[empty_cluster]		; set destination to [empty_cluster]
       cmp  [DIR_cluster],0		; have we just loaded a directory?
;      $if  ne				; if so -
       JE $$IF103
	   mov	[DIR_cluster],ax	; save the new cluster
	   lea	bx,BUF			;
	   mov	[bx.dir_first],ax	; update the '.' entry start cluster
;      $endif				;
$$IF103:
       call cluster_2_sector		; conver to logical sector
       mov  [packet],ax 		; low word
       mov  [packet+2],dx		; high word
       xor  ah,ah			; set up for write
       dec  ah				;
       call Direct_Access		; to write data
;  $endif				;
$$IF102:
   pop	[packet_sectors]		;
   pop	[packet+2]			; restore starting sector
   pop	[packet]			;
   xor	ah,ah				; set up for read
   call Direct_Access			; to restore the FAT copy

   ret					;

   Xfer_Data ENDP

   BREAK <SYS - cluster_2_sector >
;******************* START OF SPECIFICATIONS ***********************************
;Routine name: cluster_2_sector
;*******************************************************************************
;
;Description:  cluster_2_sector
;
;
;Called Procedures:
;
;		none
;
;Input: 	AX - cluster number
;
;Output:	AX - low word of sector
;		DX - high word of sector
;		CX - sectors per cluster
;
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START cluster_2_sector
;
;	ret
;
;	END cluster_2_sector
;
;******************-  END  OF PSEUDOCODE -**************************************

   public cluster_2_sector

   cluster_2_sector PROC NEAR

   dec	ax				;    of [current_cluster]
   dec	ax				;
   mov	cx,[CSIZE]			;
   mul	cx				;
   add	ax,[l_sector_offset]		;

   ret					;

   cluster_2_sector ENDP

   BREAK <SYS - Search_DIR >
;******************* START OF SPECIFICATIONS ***********************************
;Routine name: Search_DIR
;*******************************************************************************
;
;Description: Search_DIR walks the directory tree looking for the file that
;	      starts with [cluster_number]. If found, the data is moved to the
;	      first empty cluster (if available), and the directory entry is
;	      updated.
;
;	      This routine walks the DIR tree by creating a 'FRAME' for each
;	      Sub DIR it encounters. It saves all the data needed to continue
;	      the search once the Sub DIR has been checked.
;
;      FRAME   ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÂÄÄÄÄÄÄÄÄÄÄÄÄÄÂÄÄÄÄÄÄÄÄÄÄÄÄÄÄÂÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
;	       ³      present_cluster #     ³sector_offset ³ entry_number ³
;	       ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÁÄÄÄÄÄÄÄÄÄÄÄÄÄÁÄÄÄÄÄÄÄÄÄÄÄÄÄÄÁÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
;	  byte	       1	    2		    3		   4
;
;	      There is space in DIR_BUF for 32 frames (current DOS maximum
;	      level of nesting).
;
;Called Procedures:
;
;		Search_Loop   - scan the directory
;
;Input: 	[current_cluster] - # of cluster to be freed
;
;Output:	CF = 0	cluster now available
;		CF = 1	error - ax = message #
;
;
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START  Search_DIR
;
;	set up for first_dir_sector of root DIR
;	set up for read
;	call Direct_Access to read first root sector
;	if no error
;		set [current_sector]
;		set [sector_count] = #_dir_sectors
;		set [current_entry] = 1
;		set [sub_dir_level] = 0
;		do until cluster free (NC)
;			call Search_Loop
;			if SubDir
;				save [current_cluster] in frame
;				save [current_sector]in frame
;				save [current_entry] in frame
;				save [sector_count] in frame
;				incriment [sub_dir_level] (frame)
;				zero ax
;				set error flag (CF)
;			else
;				if end of DIR (CF + 00) and
;				if [dir_count] > 0
;					recover [current_cluster] from frame
;					recover [current_sector] from frame
;					recover [current_entry] from frame
;					recover [sector_count] from frame
;					decriment [sub_dir_level]
;					zero ax
;					set error flag (CF)
;				 else
;					load error message - no room to sys
;				 endif
;				 set error flag (CF) (ax = message)
;			endif
;		leave if error (ax > 0)
;		enddo
;	endif
;
;	ret
;
;	END  Search_DIR
;
;******************-  END  OF PSEUDOCODE -**************************************

   public Search_DIR

   Search_DIR PROC NEAR

   mov	ax,[first_dir_sector]		; set up for first_dir_sector of root
   mov	[packet],ax			;
   mov	[packet+2],0			; zero out high word
   mov	[packet_sectors],1		; only process 1 sector at a time
   mov	[packet_buffer],OFFSET DIR_SECTOR ;
   xor	ah,ah				; set up for read
   call Direct_Access			; to read first root sector
;  $if	nc,long 			; no error
   JNC $$XL1
   JMP $$IF106
$$XL1:
       xor  ax,ax			;
       mov  [present_cluster],ax	; set [present_cluster] = 0 (root)
       mov  [entry_number],al		; set [entry_number] = 0 (first)
       mov  ax,[first_dir_sector]	;
       mov  [sector_offset],ax		; set [sector_offset] = [first_dir_sec]
       lea  bx,DIR_BUF			; set [FRAME_ptr] = DIR_BUF
       mov  [FRAME_ptr],bx		;
;      $do				;  until cluster free (NC)
$$DO107:
	   call Search_Loop		;
;      $leave nc,long			; cluster found and moved
       JC $$XL2
       JMP $$EN107
$$XL2:
	   cmp	ax,0ffffh		;
;	   $if	e			; SubDir
	   JNE $$IF109

					; Search DIR returned with BX pointing
					;  to the current entry - now update
					;  current_cluster to this SubDIRs first
					;  cluster

	       mov  ax,[bx.dir_first]	; get starting cluster for where we
					;  want to go
	       mov  bx,[present_cluster] ; get [present_cluster] for frame
					;  (where we were)
	       mov  [present_cluster],ax ;  [present_cluster] for next pass
	       xchg ax,bx		; recover old [present_cluster]
	       mov  bx,[FRAME_ptr]	; get FRAME pointer
	       mov  [bx.p_cluster],ax	; save [present_cluster] in frame
	       mov  ax,[sector_offset]	; save [sector_offset]in frame
	       mov  [bx.s_offset],ax	;
	       mov  al,[entry_number]	; save [entry_number] in frame
	       mov  [bx.e_number],al	;
	       xor  ax,ax		; reset -
	       mov  [sector_offset],ax	;	  [sector_offset]
	       mov  [entry_number],al	;	  [entry_number]
	       add  bx,SIZE FRAME	; incriment FRAME pointer
	       lea  ax,DIR_SECTOR	;
	       cmp  ax,bx		;
;	       $if  a			;
	       JNA $$IF110
		   mov	[FRAME_ptr],bx	;
		   clc			; no error
;	       $else			;
	       JMP SHORT $$EN110
$$IF110:
		   stc			; set error flag (CF)
;	       $endif			;
$$EN110:
;	   $else long			;
	   JMP $$EN109
$$IF109:
	       cmp  ax,0		;
;	       $if  e,and,long		; end of DIR (CF + 00) and
	       JE $$XL3
	       JMP $$IF114
$$XL3:
next_level_down:			;
	       mov  bx,[FRAME_ptr]	; recover FRAME_ptr - but remember **
					;  it points to the next available
					;  frame - not the last one - so
	       sub  bx,SIZE FRAME	; move back!
	       lea  ax,DIR_BUF		;
	       cmp  ax,bx		;
;	       $if  be			; as long as there are still FRAMEs
	       JNBE $$IF114
		   mov	ax,[bx.p_cluster] ; get [present_cluster] from frame
		   mov	[present_cluster],ax ;
		   mov	ax,[bx.s_offset] ; recover [sector_offset] from frame
		   mov	[sector_offset],ax ;
		   mov	al,[bx.e_number] ; recover [entry_number] from frame
		   mov	[entry_number],al ;
		   mov	[FRAME_ptr],bx	;

					; Now set up at exactly same point
					;  as when SubDIR was entered -
					;  advance to next entry

		   inc	al		;
		   cmp	al,[entries_per_sector] ;
;		   $if	b		;
		   JNB $$IF115
		       inc  [entry_number] ;
		       clc		; no error
;		   $else		; we've left the sector
		   JMP SHORT $$EN115
$$IF115:
if not ibmcopyright
			xor	al, al
			mov [entry_number], al	; shall we start at, say, ENTRY ZERO?  Hmmmmm?
endif
		       mov  ax,[present_cluster] ;
		       cmp  ax,0	; in the root ?
;		       $if  ne		; no
		       JE $$IF117
			   mov	si,ax	;
			   mov	[cluster_high],1 ; force Upack to load FAT
			   mov	ax,[FAT_sectors] ; get the size right
			   mov	[packet_sectors],ax ;
			   mov	[packet_buffer],OFFSET BUF ;
			   call Unpack	; to get next cluster #
			   mov	[packet_buffer],OFFSET DIR_SECTOR ;
			   mov	[packet_sectors],1 ; set size back
			   mov	[cluster_high],1 ; ensure that FAT will be
					;	      re-loaded

			   mov	ax,di	; check if at end
			   cmp	al,end_cluster ;  at the end?
;			   $if	nz	; not at end of line
			   JZ $$IF118
			       mov  [present_cluster],di ; save it
			       clc	;
;			   $else	; we are at the end of a Sub DIR chain
			   JMP SHORT $$EN118
$$IF118:

					; the following is a best attempt fix
					; to a bad design problem ...... (how
					;  to get back a level.....???

; SEPT 21 - best solution is to check BEFORE putting the entry in the frame
;			       (not when taking it off !!! )

			       jmp  next_level_down ;

;			   $endif	;
$$EN118:
;		       $else		;  yes - in the root
		       JMP SHORT $$EN117
$$IF117:
			   mov	ax,[sector_offset] ;
			   inc	ax	;
			   cmp	ax,[l_sector_offset] ;
;			   $if	b	;
			   JNB $$IF122
			       inc  [sector_offset] ;
if not ibmcopyright
				clc	; no error, continue with loop
endif
;			   $else	; end of the line
			   JMP SHORT $$EN122
$$IF122:
			       stc	; we failed to find it
;			   $endif	;
$$EN122:
;		       $endif		;
$$EN117:
;		   $endif		;
$$EN115:
;	       $else			;
	       JMP SHORT $$EN114
$$IF114:
		   stc			; set error flag (CF)
;	       $endif			;
$$EN114:
;	   $endif			;
$$EN109:
;	   $if	c			; error
	   JNC $$IF130
	       mov  ax,(util shl 8) + no_room ; error message - no room to sys
;	   $endif			;
$$IF130:
;      $leave c 			; if error
       JC $$EN107
;      $enddo long			;
       JMP $$DO107
$$EN107:
;  $endif				;
$$IF106:

   ret					;

   Search_DIR ENDP

   BREAK <SYS - Search_Loop >
;******************* START OF SPECIFICATIONS ***********************************
;Routine name: Search_Loop
;*******************************************************************************
;
;Description: Search_Loop scans through all entries of all sectors of all
;	      clusters of a given Directory for a specified cluster
;
;Called Procedures:
;
;		Unpack		   - to find a FAT entry for a Cluster #
;		Pack		   - to set a FAT entry for a Cluster #
;		Find_Empty_Cluster - find an unused cluster
;		Xfer_Data	   - transfere data from one cluster to another
;		Direct_Access	   - absolute disk i/o
;
;Input:
;
;Output:	CF = 0	found and freed [cluster_number]
;		CF = 1 - ax = 0 		- at end of directory
;			 ax = (message + class) - error occured
;			 ax = -1		- SubDir found
;			 bx = pointer to current entry
;
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START  Search_Loop
;
;	search till at end of directory - all clusters checked
;		search till at end of sectors - in given cluster
;			search till at end of sector - all entries checked
;			exitif starting cluster = [cluster_number]
;				set up for FAT
;				call Find_Empty_Cluster
;				if no error and
;				call Xfer_Data
;				reset for DIR
;				if no error
;					update dir_first_clust
;					set up for write
;					call Direct_Access to write out the directory
;				endif
;			orelse
;			leave if entry is a subdirectory (ah = ffh)
;				advace to next entry
;				zero ax
;			endloop if past end of sector
;				set fail flag (CF)
;			endsrch
;		exit if [current_cluster] found (NC)
;		orelse
;		leave if subdirectory found (CF + FF)
;			if sectors left to read
;				set up to read
;				call Direct_Access to read sector
;			else
;				set error flag (CF)
;				zero ax (end of sectors)
;			endif
;		endloop if error
;		endsrch
;	leave if [current_cluster] found (NC)
;	leave if SubDir found (CF + FF)
;	leave if Error (CF + message)
;		get [current_cluster] #
;		call Unpack to get next cluster #
;	exitif no more clusters
;		zero ax (end of clusters)
;		set error flag (CF)
;	orelse
;		convert cluster # to logical sector #
;		update [current_sector]
;	endloop
;	endsrch
;
;	ret
;
;	END  Search_Loop
;
;******************-  END  OF PSEUDOCODE -**************************************

   public Search_Loop

   Search_Loop PROC NEAR

   mov	ax,[present_cluster]		; initailize for search
   cmp	ax,0				;
;  $if	ne				;
   JE $$IF135
       call cluster_2_sector		; convert it to a sector
       add  ax,[sector_offset]		;
;      $if  c				;
       JNC $$IF136
	   inc	dx			;
;      $endif				;
$$IF136:
;  $else				;
   JMP SHORT $$EN135
$$IF135:
       mov  ax,[sector_offset]		;[sector_offset] = current root sector
       xor  dx,dx			;
;  $endif				;
$$EN135:
   mov	[packet],ax			;
   mov	[packet+2],dx			;
   xor	ah,ah				;
   call Direct_Access			; to read the DIR
   mov	al,SIZE dir_entry		;
   mov	cl,[entry_number]		;
   mul	cl				;
   lea	bx,DIR_SECTOR			;
   add	bx,ax				; BX now points to the DIR entry
;  $search				; till at end of directory
$$DO140:
					;     - all clusters checked
;      $search				; till at end of sectors
$$DO141:
					;     - in given cluster
;	   $search			; till at end of sector
$$DO142:
					;     - all entries checked
	       cmp  BYTE PTR [bx],deleted ; make sure the entry is valid !!!
;	       $if  e			; if it is not -
	       JNE $$IF143
		   xor	ax,ax		;				       ;AN019:
		   mov	[bx.dir_first],ax ; zap the starting cluster
		   mov	[bx.dir_attr],al ;  zap the attribute
;	       $endif			;
$$IF143:
	       mov  ax,[bx.dir_first]	;
	       cmp  ax,[current_cluster] ;
;	   $exitif e,and,long		; starting cluster = [current_cluster]
	   JE $$XL4
	   JMP $$IF142
$$XL4:
	       cmp  BYTE PTR [bx],deleted ; make sure the entry is valid !!!
;	   $exitif ne,and,long		; and entry is not deleted
	   JNE $$XL5
	   JMP $$IF142
$$XL5:
	       cmp  BYTE PTR [bx],dot	;
;	   $exitif ne,long		; and entry is not a . or .. name
	   JNE $$XL6
	   JMP $$IF142
$$XL6:
	       test [bx.dir_attr],attr_directory ; is it a subdir ?
;	       $if  nz			;if entry is a subdirectory
	       JZ $$IF146
		   inc	[DIR_cluster]	; signal special processing
					;   Xfere_Data will use this later -
					;    0 = not a sub DIR
					;    1 = do Sub DIR processing and
					;	 update [DIR_cluster] to the
					;	 same value as [empty_cluster]
;	       $endif			;
$$IF146:
	       mov  ax,[packet] 	; save pointer to this DIR
	       mov  [dir_sector_low],ax ;
	       mov  ax,[packet+2]	;
	       mov  [dir_sector_hi],ax	;
	       mov  [source_ptr],bx	; save pointer
	       mov  [cluster_high],1	; force Upack to load FAT
	       mov  ax,[FAT_sectors]	; get the size right
	       mov  [packet_sectors],ax ;
	       mov  [packet],1		;
	       mov  [packet+2],0	;
	       mov  [packet_buffer],OFFSET BUF ;
	       call Find_Empty_Cluster	;
;	       $if  nc,and		; no errors so far
	       JC $$IF148
	       mov  si,[empty_cluster]	;
	       mov  dx,[next_cluster]	;
	       call PACK		;
;	       $if  nc,and		; no errors so far
	       JC $$IF148
	       mov  si,[current_cluster] ;
	       xor  dx,dx		; make it empty
	       call PACK		;
;	       $if  nc			; no errors so far
	       JC $$IF148
		   cmp	[bigfat],0	;
;		   $if	ne		;
		   JE $$IF149
		       mov  [cluster_high],1 ; ensure that FAT will be updated
		       call Unpack	;
;		   $else		; must manualy write out 12 bit FATS
		   JMP SHORT $$EN149
$$IF149:
		       xor  ah,ah	;
		       dec  ah		;
		       mov  [packet],1	; start with the first FAT
		       call Direct_Access ; write it out - ignore errors
		       mov  ax,[FSIZE]	;
		       add  [packet],ax ; advance to second FAT
		       xor  ah,ah	;
		       dec  ah		;
		       call Direct_Access ; write it out - ignore errors
;		   $endif		;
$$EN149:
;	       $endif			;
$$IF148:
;	       $if  nc,and		; no error and
	       JC $$IF153
	       call Xfer_Data		;
;	       $if  nc			; no error
	       JC $$IF153
		   mov	ax,[empty_cluster] ; update dir_first_clust
		   mov	bx,[source_ptr] ; recover pointer
		   mov	[bx.dir_first],ax ;
		   mov	[packet_sectors],1 ; set size back
		   mov	[packet_buffer],OFFSET DIR_SECTOR ;
		   mov	ax,[dir_sector_low] ; reset DIR sector
		   mov	[packet],ax	;
		   mov	ax,[dir_sector_hi] ;
		   mov	[packet+2],ax	;
		   xor	ah,ah		; set up for write
		   dec	ah		;
		   call Direct_Access	; to write out the directory
;		   $if	nc,and		;
		   JC $$IF154
		   cmp	[DIR_cluster],0 ; is a DIR being processed ?
;		   $if	ne		;
		   JE $$IF154
		       call Sub_DIR_Loop ; update any children
;		   $endif		;
$$IF154:
;		   $if	nc		; if no errors
		   JC $$IF156
		       mov  ax,[FAT_sectors] ;only read needed sectors
		       mov  [packet_sectors],ax ;
		       mov  [packet],1	;
		       mov  [packet_buffer],OFFSET BUF ; point to FAT buffer
		       mov  [cluster_high],clusters_loaded ;
		       mov  [cluster_low],0 ;
		       xor  cx,cx	;
		       mov  di,cx	;
		       dec  di		;
		       mov  cl,[num_of_FATS] ;
		       call Load_FAT	; restore FAT
		       push es		; update DPB first cluster
		       mov  bx,ds	;
		       mov  es,bx	;
		       lds  bx,[THIS_DPB] ;

		       ASSUME ds:nothing,ES:DGROUP

		       mov  [bx.dpb_next_free],2 ;
		       mov  ax,es	;
		       mov  ds,ax	;
		       pop  es		;

		       ASSUME DS:DGROUP, es:nothing

;		   $endif		;
$$IF156:
;	       $endif			;
$$IF153:
;	   $orelse			;
	   JMP SHORT $$SR142
$$IF142:
	       xor  ax,ax		; get ready in case -----
	       cmp  BYTE PTR [bx],0	; at the end of the dir?
;	   $leave e			;   then no point in continuing
	   JE $$EN142
	       dec  ax			; get ready in case we fail
	       test [bx.dir_attr],attr_directory ; is it a subdir ?
;	   $leave nz, and		;if entry is a subdirectory (ah = ffh)
	   JZ $$LL161
	       cmp  byte ptr [bx],dot	; but not a DOT
;	   $leave ne			;
	   JNE $$EN142
$$LL161:
	       xor  ax,ax		; zero ax
	       add  bx,SIZE dir_entry	; advace to next entry
	       inc  [entry_number]	;
	       cmp  bx,OFFSET BUF	; are we out of sector ?
;	   $endloop ae,long		;if past end of sector
	   JAE $$XL7
	   JMP $$DO142
$$XL7:
$$EN142:
	       stc			; set fail flag (CF)
;	   $endsrch			;
$$SR142:
;      $exitif nc			;[current_cluster] found (NC)
       JC $$IF141
;      $orelse				;
       JMP SHORT $$SR141
$$IF141:

					; we have  CF = 1 and could have:
					;		AX = 0 -
					;		AX = 1 to fffe
					;		AX = ffff
					;  so - leave if anything other than
					;	AX = 0 (out of stuff)

;      $leave c,and			; if not out of stuff
       JNC $$LL166
	   cmp	ax,0			;
	   stc				; restore carry flag!
;      $leave nz			;	------ leave !
       JNZ $$EN141
$$LL166:
	   mov	ax,[sector_offset]	;
	   inc	ax			;
	   cmp	[present_cluster],0	; are we in the root?
;	   $if	e			; if so -
	   JNE $$IF167
	       cmp  ax,[l_sector_offset] ;   use root sectors
;	   $else			;  else -
	   JMP SHORT $$EN167
$$IF167:
	       cmp  ax,[CSIZE]		;      use sectors per cluster
;	   $endif			;
$$EN167:
;	   $if	b			; sectors left to read
	   JNB $$IF170
	       add  [packet],1		; advance to the next sector
;	       $if  c			;
	       JNC $$IF171
		   inc	[packet+2]	; adjust high word if needed
;	       $endif			;
$$IF171:
	       xor  ah,ah		; set up to read
	       mov  [entry_number],ah	;
	       inc  [sector_offset]	;
	       call Direct_Access	; to read sector
	       lea  bx,DIR_SECTOR	; set index to start of sector
;	   $else			;
	   JMP SHORT $$EN170
$$IF170:
	       xor  ax,ax		; zero ax (end of sectors)
	       stc			; set error flag (CF)
;	   $endif			;
$$EN170:
;      $endloop c,long			; if error
       JC $$XL8
       JMP $$DO141
$$XL8:
$$EN141:
;      $endsrch 			;
$$SR141:
;  $leave nc				; if [current_cluster] found (NC)
   JNC $$EN140
;  $leave c,and 			;if SubDir found (CF + FF)
   JNC $$LL178
       cmp  ax,0			;
       stc				; set carry
;  $leave nz				; if Error (CF + messageor FFFFh)
   JNZ $$EN140
$$LL178:

					;--------------------------------------
					; CF = 1 and AX = 0 means - no critical
					;			     errors
					;			  -  no Sub DIR
					;			     found
					;  inner SEARCH is out of sectors
					;   - so advance to the next cluster
					;--------------------------------------
       mov  si,[present_cluster]	; get [present_cluster] #
       cmp  si,0			; end of the root ?
;      $if  nz				;
       JZ $$IF179
	   mov	[cluster_high],1	; force Upack to load FAT
	   mov	ax,FAT_sectors		; get the size right
	   mov	[packet_sectors],ax	;
	   mov	[packet_buffer],OFFSET BUF ;
	   call Unpack			; to get next cluster #
	   mov	[packet_sectors],1	; set size back
	   mov	[cluster_high],1	; ensure that FAT will be re-loaded
	   mov	[packet_buffer],OFFSET DIR_SECTOR ;
	   mov	ax,di			;
	   cmp	al,end_cluster		;
;      $endif				;
$$IF179:
;  $exitif z				; no more clusters
   JNZ $$IF140
       xor  ax,ax			; zero ax (end of clusters)
       stc				; set error flag (CF)
;  $orelse				;
   JMP SHORT $$SR140
$$IF140:
       mov  [present_cluster],di	;
       mov  ax,di			; set up for cluster_2_sector
       call cluster_2_sector		; convert cluster # to logical sector #
       mov  [packet],ax 		;
       mov  [packet+2],dx		;
       xor  ax,ax			;
       mov  [sector_offset],ax		; reset [sector_offset]
       mov  [entry_number],ah		; reset [entry_number]
       call Direct_Access		; to read sector
       lea  bx,DIR_SECTOR		; set pointer
;  $endloop c,long			; end loop if read fails
   JC $$XL9
   JMP $$DO140
$$XL9:
$$EN140:
;  $endsrch				;
$$SR140:

   ret					;

   Search_Loop ENDP

   BREAK <SYS - Sub_DIR_Loop >

;******************* START OF SPECIFICATIONS ***********************************
;Routine name: Sub_DIR_Loop
;*******************************************************************************
;
;Description: Sub_DIR_Loop scans through all entries of a subdirectory looking
;	      child subdirectories. If found, their parent [dir_first] entries
;	      (the .. entry) are updated to point to the correct cluster
;
;Called Procedures:
;
;		Unpack		   - to find a FAT entry for a Cluster #
;		Direct_Access	   - absolute disk i/o
;
;Input: 	[empty_cluster]   - new parent Sub DIR cluster #
;		[DIR_cluster]	  - current cluster of DIR being looped
;
;Output:	CF = 0	at end of directory
;		CF = 1	a read/write error occured
;
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START Sub_DIR _Loop
;
;	get DIR_cluster
;	call cluster_2_sector
;	update packet
;	set for read
;	reset entry pointer
;	reset sector count
;	call Direct_Access
;	if no error
;	      search till at end of directory - all clusters checked
;		    search till at end of sectors - in given cluster
;			  search till at end of sector - all entries checked
;			  leave if null entry
;				if entry is not deleted and
;				if this entry is a subdir and
;				if this is a true entry and
;				save current sector
;				save current entry
;				get start cluster
;				call cluster_2_sector
;				set for read
;				call Direct_Access
;				if no errors and
;				update pointer to parent
;				set for write
;				call Direct_Access
;				if no errors and
;				recover current sector
;				recover current entry
;				if no errors
;				     call Direct_Access
;				endif
;			  exitif error (CF)
;			  orelse
;				advance to next entry
;			  endloop if past end of sector
;				clear error flag
;			  endsrch
;		    leave if error
;			  advance to next sector (packet)
;			  incriment sector count
;		    exitif past end of cluster
;			  clear error flag
;		    orelse
;			  reset entry pointer
;			  set for read
;			  call Direct_Access
;		    endloop if error
;		    endsrch
;	      leave if error
;		    get DIR_cluster
;		    call UNPACK to find next Sub DIR cluster
;	      exitif at end of chain
;		    clear error flag
;	      orelse
;		    update DIR_cluster
;		    call cluster_2_sector
;		    update packet
;		    set for read
;		    call Direct_Access
;	      leave if error
;		    reset entry pointer
;		    reset sector count
;	      endloop
;	      endsrch
;	endif
;	reset Sub_DIR_cluster to 0
;
;	ret
;
;	END  Sub_DIR_Loop
;
;******************-  END  OF PSEUDOCODE -**************************************

   public Sub_DIR_Loop

   Sub_DIR_Loop PROC NEAR

   mov	ax,[DIR_cluster]		; get DIR_cluster
   call cluster_2_sector		; to convert to a logical sector
   mov	[packet],ax			; update packet
   mov	[packet+2],dx			;
   xor	ax,ax				; set for read
   call Direct_Access			; to read the first sector of the DIR
;  $if	nc,long 			; if no error
   JNC $$XL10
   JMP $$IF185
$$XL10:
       mov  [sector_count],1		; reset sector count
       lea  bx,DIR_SECTOR		; reset entry pointer
;      $search				; till at end of directory
$$DO186:
					;      - all clusters checked
;	   $search			; till at end of sectors
$$DO187:
					;      - in given cluster
;	       $search			; till at end of sector
$$DO188:
					;      - all entries checked
		   mov	[dir_offset],bx ; reset entry pointer
		   cmp	BYTE PTR [bx],0 ; null entry (00)?
;	       $leave z 		; if null entry
	       JZ $$EN188
		   cmp	BYTE PTR [bx],deleted ; deleted entry (E5)?
;		   $if	ne,and		; if entry is not deleted and
		   JE $$IF190
		   test [bx.dir_attr],attr_directory ; is it a subdir ?
;		   $if	nz,and		; if this entry is a subdir and
		   JZ $$IF190
		   cmp	BYTE PTR [bx],dot ; dot entry (2E)?
;		   $if	ne,and		; this is a true entry and
		   JE $$IF190
		   mov	ax,[packet]	; save current sector
		   mov	[dir_sector_low],ax ;
		   mov	ax,[packet+2]	;
		   mov	[dir_sector_hi],ax ;
		   mov	ax,[bx.dir_first] ; get start cluster
		   call cluster_2_sector ; convert to sector
		   mov	[packet],ax	; update packet
		   mov	[packet+2],dx	;
		   xor	ax,ax		; set for read
		   call Direct_Access	; to read it in
;		   $if	nc,and		; no errors and
		   JC $$IF190
		   mov	ax,[empty_cluster] ; update pointer to parent
		   lea	bx,DIR_SECTOR	;
		   mov	[bx + dir_first + size dir_entry],ax ;
		   xor	ax,ax		; set for write
		   dec	ax		;
		   call Direct_Access	; to write it back
;		   $if	nc,and		; if no errors and
		   JC $$IF190
		   mov	ax,[dir_sector_low] ;
		   mov	[packet],ax	; recover current sector
		   mov	ax,[dir_sector_hi] ;
		   mov	[packet+2],ax	;
;		   $if	nc		; if no errors
		   JC $$IF190
		       call Direct_Access ; to continue where we left off
;		   $endif		;
$$IF190:
;	       $exitif c		; quit if error (CF)
	       JNC $$IF188
;	       $orelse			;
	       JMP SHORT $$SR188
$$IF188:
		   mov	bx,[dir_offset] ; recover current entry
		   add	bx,SIZE dir_entry ; advance to next entry
		   cmp	bx,OFFSET BUF	;
;	       $endloop a		; if past end of sector
	       JNA $$DO188
$$EN188:
		   clc			; clear error flag
;	       $endsrch 		;
$$SR188:
;	   $leave c			; if error - quit
	   JC $$EN187
	       xor  ax,ax		;
	       mov  ax,[CSIZE]		; incriment sector count
	       inc  [sector_count]	;
	       cmp  [sector_count],al	;
;	   $exitif a			; past end of cluster
	   JNA $$IF187
	       clc			; clear error flag
	       mov  [sector_count],1	; reset sector count
;	   $orelse			;
	   JMP SHORT $$SR187
$$IF187:
	       xor  ax,ax		; set for read
	       add  WORD PTR [packet],1 ; advance to next sector (packet)
	       adc  [packet+2],ax	; look after carry
	       call Direct_Access	; to read in next sector
	       lea  bx,DIR_SECTOR	; reset entry pointer
;	   $endloop c,long		; if error - quit
	   JC $$XL11
	   JMP $$DO187
$$XL11:
$$EN187:
;	   $endsrch			;
$$SR187:
;      $leave c 			; if error - quit
       JC $$EN186
	   mov	si,[DIR_cluster]	; get DIR_cluster
	   push [packet_sectors]	; save current packet stuff
	   push [packet_buffer] 	;
	   mov	ax,[FAT_sectors]	; update packet to FAT
	   mov	[packet_sectors],ax	;
	   mov	[packet_buffer],OFFSET BUF ;
	   mov	[cluster_high],1	; force FAT to be reloaded - if needed
	   call UNPACK			; to find next Sub DIR cluster
	   pop	[packet_buffer] 	; recover packet to DIR
	   pop	[packet_sectors]	;
	   mov	ax,di			;
	   cmp	al,end_cluster		;
;      $exitif e			; at end of chain
       JNE $$IF186
	   clc				; clear error flag
;      $orelse				;
       JMP SHORT $$SR186
$$IF186:
	   mov	[DIR_cluster],ax	;
	   call cluster_2_sector	; to convert to sector
	   mov	[packet],ax		; update packet
	   mov	[packet+2],dx		;
	   xor	ax,ax			; set for read
	   call Direct_Access		; to read first sector of next cluster
;      $leave c 			; if error
       JC $$EN186
	   lea	bx,DIR_SECTOR		; reset entry pointer
	   mov	[sector_count],1	; reset sector count
;      $endloop long			;
       JMP $$DO186
$$EN186:
;      $endsrch 			;
$$SR186:
;  $endif				;
$$IF185:
   mov	[DIR_cluster],0 		; reset Sub_DIR_cluster to 0

   ret					;

   Sub_DIR_Loop ENDP

   BREAK <SYS - Unpack >
;******************* START OF SPECIFICATIONS ***********************************
;Routine name: Unpack
;*******************************************************************************
;
;Description: Read an entry in the FAT
;
;Called Procedures:
;
;		Check_FAT - to make sure right part of FAT is loaded (16 bit only)
;
;Input: 	Cluster number in SI
;
;Output:	Return contents in DI
;		xX destroyed
;		ZF set if cluster is free
;
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START Unpack
;
;	if 16 bit FAT
;		call Check_FAT
;		multiply # by 2
;		read value
;		check if empty
;	else
;		multiply # by 2
;		read value
;		if not word alligned
;			shift to allign
;		endif
;		mask off unused portion (set ZF if empty)
;	endif
;
;	ret
;
;	END Unpack
;
;******************-  END  OF PSEUDOCODE -**************************************

   public Unpack

   Unpack PROC NEAR

   lea	bx,BUF				;
   mov	di,si				;
   cmp	[BIGFAT],0			;
;  $if	nz				; if 16 bit FAT
   JZ $$IF208
       push si				;
       call Check_FAT			; make sure right part of FAT loaded
;      $if  nc				;
       JC $$IF209
	   mov	di,si			; Check_FAT ajusts si
	   shl	di,1			; Mult by 2
	   mov	di,WORD PTR [di+bx]	;
	   or	di,di			; Set zero
	   clc				;
;      $endif				;
$$IF209:
       pop  si				;
;  $else				; is 12 bit fat
   JMP SHORT $$EN208
$$IF208:
       shr  di,1			;
       add  di,si			; Mult by 1.5
       mov  di,WORD PTR [di+bx] 	;
       test si,1			;
;      $if  nz				; not allign on cluster
       JZ $$IF212
	   shr	di,1			;
	   shr	di,1			;
	   shr	di,1			;
	   shr	di,1			;
;      $endif				;
$$IF212:
       and  di,0FFFh			;
;  $endif				;
$$EN208:


   ret					;

   Unpack ENDP

   BREAK <SYS - Pack >
;******************* START OF SPECIFICATIONS ***********************************
;Routine name: Pack
;*******************************************************************************
;
;Description:	Change an entry in the FAT
;
;Called Procedures:
;
;		Check_FAT - to make sure right part of FAT is loaded (16 bit only)
;
;Input: 	si - cluster number to be packed
;		dx - data to be placed in cluster (si)
;
;Output:	bx,dx	destroyed
;
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START Pack
;
;	if 16 bit FAT
;		call Check_FAT
;		convert cluster # to offset
;		add offset of FAT
;		store value
;	else
;		convert cluster # to offset
;		add offset of FAT
;		recover current entry word
;		if not alligned on word boundary
;			shift to allign
;			mask off value to be replaced (byte)
;		else
;			mask off value to be replaced (word)
;		endif
;	combine new value and ballace
;	store the entry
;
;	ret
;
;	END Pack
;
;******************-  END  OF PSEUDOCODE -**************************************

   public Pack

   Pack PROC NEAR

   lea	bx,BUF				;
   push si				;
   mov	di,si				;
   cmp	[BIGFAT],0			;
;  $if	nz				; 16 bit FAT
   JZ $$IF215
       call Check_FAT			; make sure the part of the FAT we want
					;   is loaded & ajust offset to match
       shl  si,1			; convert cluster # to offset
       add  si,bx			; add offset of FAT
       mov  [si],dx			; store value
       mov  [FAT_changed],1		; the fat has been changed
;  $else				; its 12 bit FAT
   JMP SHORT $$EN215
$$IF215:
       shr  si,1			;
       add  si,bx			;
       add  si,di			;
       shr  di,1			;
       mov  di,[si]			;
;      $if  c				; no alligned
       JNC $$IF217
	   shl	dx,1			;
	   shl	dx,1			;
	   shl	dx,1			;
	   shl	dx,1			;
	   and	di,0Fh			;
;      $else				;
       JMP SHORT $$EN217
$$IF217:
	   and	di,0F000h		;
;      $endif				;
$$EN217:
       or   di,dx			;
       mov  [si],di			;
;  $endif				;
$$EN215:
   pop	si				;

   ret					;

   Pack ENDP

   BREAK <SYS - Check_FAT >
;******************* START OF SPECIFICATIONS ***********************************
;Routine name: Check_FAT
;*******************************************************************************
;
;Description:	Check that the protion of the FAT that is referenced in SI
;		is presently in memory.
;
;		Only 12 sectors of the FAT are kept in memory. If the requested
;		cluster does not fall within that range, 12 sectors of the FAT
;		are read into memory - the first cluster will contain the entry
;		of interest.
;
;Called Procedures:
;
;		none
;
;Input: 	si - cluster number to be checked
;		[FAT_changed] = 0 - no need to write out FAT before changing
;			      = x - must write before reading.
;
;
;Output:	appropriate block of FAT in BUF
;		si ajusted to match
;		NB: BX, DX preserved (for UNPACK)
;
;
;******************* END OF SPECIFICATIONS *************************************
;******************+ START OF PSEUDOCODE +**************************************
;
;	START Check_FAT
;
;
;	ret
;
;	END  Check_FAT
;
;******************-  END  OF PSEUDOCODE -**************************************

   public Check_FAT

   Check_FAT PROC  NEAR

   push bx
   cmp	si,[cluster_low]		;
;  $if	ae,and				;
   JNAE $$IF221
   cmp	si,[cluster_high]		;
;  $if	be				;
   JNBE $$IF221
       sub  si,[cluster_low]		;
;  $else				; the cluster is outside the range
   JMP SHORT $$EN221
$$IF221:
					;  of the part of the FAT presently loaded.
					; convert cluster # into sector + offset
					; by dividing the cluster # by # of entries
					; per sector IE: sector = 512 bytes
					;	     cluster entry = 2 bytes
					;	then # of entries/sector = 256

       cmp  [FAT_changed],0		;
;      $if  ne				;
       JE $$IF223
	   xor	ah,ah			;
	   dec	ah			;
	   call Direct_Access		; write it out - ignore errors
	   mov	ax,[FSIZE]		;
	   cmp	[FAT_2],0		;
;	   $if	e			;
	   JNE $$IF224
	       add  [packet],ax 	;
;	   $else			;
	   JMP SHORT $$EN224
$$IF224:
	       sub  [packet],ax 	;
	       mov  [FAT_2],0		; packet points to FAT #2
;	   $endif			;
$$EN224:
	   xor	ah,ah			;
	   dec	ah			;
	   call Direct_Access		; write it out - ignore errors
	   mov	[FAT_changed],0 	; FAT now cleared
;      $endif				;
$$IF223:
       mov  ax,si			;
       xor  cx,cx			;
       mov  cl,al			; this is a cheap and
       mov  al,ah			;  dirty divide by 256
       xor  ah,ah			;   ax = result
       push ax				; save starting sector
       mov  si,cx			;   cx = remainder
       inc  ax				; leave room for boot sector
       mov  [packet],ax 		;
       mov  [packet+2],0		;
       push dx				;
       call Direct_Access		;
;      $if  c				;
       JNC $$IF228
	   mov	ax,[FSIZE]		;
	   add	[packet],ax		;
	   mov	[FAT_2],1		; packet points to FAT #2
	   call Direct_Access		;
;      $endif				;
$$IF228:
       pop  dx				;
       pop  ax				; recover starting sector
;      $if  nc				;
       JC $$IF230
	   xchg al,ah			; convert sector back to cluster
	   mov	[cluster_low],ax	; new bottom of FAT
	   mov	[cluster_high],ax	;
	   add	[cluster_high],clusters_loaded ; new top of FAT
;      $endif				;
$$IF230:
;  $endif				;
$$EN221:
   pop	bx


   ret					;

   Check_FAT ENDP

   CODE ENDS

   END
