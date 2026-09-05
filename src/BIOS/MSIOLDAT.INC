; Mutable IOCTL state and ROM/DMA-facing format descriptors must remain low.
; Keep code dispatch tables in MSIOCTL.INC, not in this allocation.
INCLUDE MSIOLIM.INC
PUBLIC BIOS_IOCTL_LOW_START, BIOS_IOCTL_LOW_END
PUBLIC SECTORSPERTRACK, TRACKTABLE, MEDIATYPE
PUBLIC MEDIA_SET_FOR_FORMAT, Had_Format_Error, TEMPDPT
BIOS_IOCTL_LOW_START LABEL BYTE
SECTORSPERTRACK DW	36
TRACKTABLE	DB	0,0,1,2
		DB	0,0,2,2
		DB	0,0,3,2
		DB	0,0,4,2
		DB	0,0,5,2
		DB	0,0,6,2
		DB	0,0,7,2
		DB	0,0,8,2
		DB	0,0,9,2
		DB	0,0,10,2
		DB	0,0,11,2
		DB	0,0,12,2
		DB	0,0,13,2
		DB	0,0,14,2
		DB	0,0,15,2
		db	0,0,16,2
		db	0,0,17,2
		db	0,0,18,2
		db	0,0,19,2
		db	0,0,20,2
		db	0,0,21,2
		db	0,0,22,2
		db	0,0,23,2
		db	0,0,24,2
		db	0,0,25,2
		db	0,0,26,2
		db	0,0,27,2
		db	0,0,28,2
		db	0,0,29,2
		db	0,0,30,2
		db	0,0,31,2
		db	0,0,32,2
		db	0,0,33,2
		db	0,0,34,2
		db	0,0,35,2
		db	0,0,36,2
		DB	4*MAX_SECTORS_CURR_SUP - ($ - TRACKTABLE) DUP (0)

; Current format-media selection and retry state.
MEDIATYPE	DB	0

MEDIA_SET_FOR_FORMAT	DB	0	; 1 IF WE HAVE DONE AN INT 13 SET MEDIA
					; TYPE FOR FORMAT CALL
Had_Format_Error	db	0	; 1 if the previous format operation
					; failed. - J.K. 7/8/86
; Saved disk parameter table pointer, restored after formatting.
TEMPDPT DD -1
BIOS_IOCTL_LOW_END LABEL BYTE
