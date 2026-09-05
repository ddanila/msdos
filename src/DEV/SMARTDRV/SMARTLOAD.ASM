	TITLE	SMARTDRV embedded driver loader

memS	EQU	1
?PLM	=	0
?WIN	=	0

include cmacros.inc

extrn	INT13DEV:byte
extrn	SMART_STRATEGY:far
extrn	SMART_INTERRUPT:far

sBegin	CODE

assumes CS, CODE
assumes DS, DATA

; Initialize the driver image linked into this executable and append its
; character-device header to DOS's live device chain.
cProc InstallEmbedded, <PUBLIC>, <si,di,es>

cBegin
	; Initialization expands the driver's conventional track buffer beyond
	; the linked image. Reserve its entire 64 KiB segment before it writes
	; cache metadata there; the C runtime has already shrunk our DOS block.
	mov	ah,51h
	int	21h
	mov	es,bx
	mov	bx,SEG INT13DEV
	mov	ax,es
	sub	bx,ax
	add	bx,1000h
	mov	ah,4ah
	int	21h
	jc	install_failed
	push	cs
	pop	es
	mov	word ptr cs:InitPacket+20,cs
	mov	bx,OFFSET InitPacket
	push	ds
	mov	ax,SEG INT13DEV
	mov	ds,ax
	call	SMART_STRATEGY
	call	SMART_INTERRUPT
	pop	ds
	test	word ptr cs:InitPacket+3,8000h
	jnz	short install_failed
	push	es
	mov	ax,SEG INT13DEV
	mov	es,ax
	mov	di,OFFSET INT13DEV
	cmp	word ptr es:[di+4],0
	pop	es
	je	short install_failed

	mov	ah,52h
	int	21h
	lea	di,[bx+34]
install_find_tail:
	cmp	word ptr es:[di],0ffffh
	je	short install_link_header
	les	di,es:[di]
	jmp	short install_find_tail
install_link_header:
	mov	ax,OFFSET INT13DEV
	mov	es:[di],ax
	mov	ax,SEG INT13DEV
	mov	es:[di+2],ax
	xor	ax,ax
	jmp	short install_done
install_failed:
	mov	ax,-1
install_done:
cEnd

; Keep the PSP, loaded image, and active stack after first installation.
cProc KeepResident, <PUBLIC>, <>

ParmW ExitCode

cBegin
	mov	ah,51h
	int	21h
	mov	ax,ss
	sub	ax,bx
	mov	dx,sp
	add	dx,15
	mov	cl,4
	shr	dx,cl
	add	dx,ax
	inc	dx
	; The INIT break address includes the dynamically sized track buffer
	; and cache metadata. Keeping only the C stack frees live driver storage.
	mov	ax,word ptr cs:InitPacket+14
	mov	cx,ax
	and	cx,15
	shr	ax,1
	shr	ax,1
	shr	ax,1
	shr	ax,1
	jcxz	resident_break_aligned
	inc	ax
resident_break_aligned:
	add	ax,word ptr cs:InitPacket+16
	sub	ax,bx
	cmp	dx,ax
	jae	resident_size_ready
	mov	dx,ax
resident_size_ready:
	mov	ax,ExitCode
	mov	ah,31h
	int	21h
cEnd

InitPacket db 23,0,0
	   dw 0
	   db 8 dup(0)
	   db 0
	   dd 0
	   dd InitCommand
	   db 0
InitCommand db 'SMARTDRV.EXE',13

sEnd	CODE

	end
