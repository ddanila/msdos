	public	Daycnt_to_day	;J.K. 4/30/86 for real time clock support
Daycnt_to_day	proc	near	;J.K. 4/30/86 for real time clock support
;Entry: [DAYCNT] = number of days since 1-1-80
;Return: CH - centry in BCD, CL - year in BCD, DH - month in BCD, DL - day in BCD

	push	bp			;preserve caller's frame register
	IFDEF BIOS_CLOCK_HIGH
	mov	bp, ds:[daycnt]		; caller retains the low BIOS data owner
	ELSE
	mov	bp, daycnt		;keep the working count in a register
	ENDIF
	mov	cx, 5013h		;CL = century 19, CH = year 80
	cmp	bp, (365*20+(20/4)) ;# of days from 1-1-1980 to 1-1-2000
	jb	years
century20:				;20th century
	mov	cx, 0014h		;CL = century 20, CH = year 0
	sub	bp, (365*20+(20/4)) ;adjust daycnt
years:
	xor	dx, dx
	xchg	ax, bp			;old AX is dead; BP is replaced below
	mov	bx, (366+365*3) 	;# of days in a Leap year block
	div	bx			;AX = # of leap block, DX = daycnt
	xchg	bp, dx			;save daycnt left; prior BP is dead
	inc	bp			;make the remainder one-based
;	or	ah, ah			;ax should be less than 256
;	jz	OK1
;	 jmp	 Erroroccur
;OK1:
	mov	bl,4
	mul	bl			;AX = # of years. Less than 100 years!
	add	ch, al			;So, ah = 0. Adjust year accordingly.
	xor	bx, bx			;BL = month, BH = leap-day adjustment
	cmp	bp, 366			;the daycnt here is the remainder of the leap year block.
	jbe	Leapyear		;So, it should within 366+355+355+355 days.
	inc	ch			;First if daycnt <= 366, then leap year
	sub	bp, 366			;else daycnt--, base_year++;
					;And the next three years are regular years.
Regularyear:
	cmp	bp, 365			;for(i=1; i>3 or daycnt <=365;i++)
	jbe	YearDone		;{if (daycnt > 365)
	inc	ch			;  { daycnt -= 365
	sub	bp, 365			;  }
	jmp	regularyear		;normalized remainder bounds the loop
;	 jmp	 Erroroccur		 ;cannot come to here
Leapyear:
	mov	bh, 2			;mark February as the leap month
Yeardone:
	xor	dx,dx
	xchg	ax, bp			;working count is no longer needed
	mov	si, offset month_tab
Months:
	inc	bl			;
	mov	dl, byte ptr ds:[si]	;compare daycnt for each month until fits
	cmp	bl, bh
	jne	Month_length_ready
	inc	dl			;apply the leap day only to February
Month_length_ready:
	cmp	ax, dx			;dh=0.
	jbe	Month_done
	inc	si			;next month
	sub	ax, dx			;adjust daycnt
	jmp	Months			;normalized day count guarantees a match
;	 jmp	 Erroroccur
Month_done:
	mov	dl, bl
	mov	dh, ch			;now, al=day, dl=month,dh=year,cl=century
	IFDEF BIOS_CLOCK_HIGH
	mov	si, OFFSET Bin_to_bcd
	ELSE
	mov	si, BinToBCD
	ENDIF
	call	si
	xchg	dl, al			;dl = bcd day, al = month
	call	si
	xchg	dh, al			;dh = bcd month, al = year
	call	si
	xchg	cl, al			;cl = bcd year, al = century
	call	si
	mov	ch, al			;ch = bcd century
	pop	bp
	ret
Daycnt_to_day	endp

	public	EndDaycntToDay
EndDaycntToDay label	byte

	public	Bin_to_bcd
Bin_to_bcd	proc	near		;J.K. 4/30/86 for real time clock support
;Convert a binary input in AL (less than 63h or 99 decimal)
;into a bcd value in AL.  AH destroyed.
	aam			;AH = tens, AL = units
	db	0D5h, 10h	;AAD 16: AL = tens * 16 + units
	ret
Bin_to_bcd	endp

	Public	EndCMOSClockset 	;End of supporting routines for CMOS clock setting.
EndCMOSClockset label byte
;
