; Russian country records. Formats and collation: English DOS 6.22.
; Independent expectations: locales/ru/dos622-reference.json.
; CP866 uppercase is explicitly derived from its split alphabet ranges.

ru866_data label word
	dw CDATAITEMS
	ctrydat <CDATASIZE,SETCOUNTRYINFO,,ru866_info>
	ctrydat <CDATASIZE,SETCOLLATE,,ru866_collate>
	ctrydat <CDATASIZE,SETUCASE,,ru866_ucase>
	ctrydat <CDATASIZE,SETUCASEFILE,,ru866_ucase>
	ctrydat <CDATASIZE,SETFILELIST,,us_flist>
	ctrydat <CDATASIZE,SETDBCS,,us_dbcs>

ru866_info label word
	ctable <>
	dw CID_RU,866,DATE_DMY
	db 0E0h,'.',0,0,0
	db ' ',0,'.',0,'.',0,':',0
	db 3,2,HR24 ; symbol follows amount with a space, two decimal digits
	dd 0
	db ';',0
	dw 5 dup (0)

ru866_collate label word
	ctable <,'COLLATE',256>
	db 0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh
	db 0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh,0FEh
	db 001h,008h,010h,01Eh,019h,01Fh,01Ch,00Fh,011h,012h,01Ah,020h,005h,004h,00Bh,00Ah
	db 026h,027h,028h,029h,02Ah,02Bh,02Ch,02Dh,02Eh,02Fh,007h,006h,021h,022h,023h,009h
	db 018h,031h,033h,035h,037h,039h,03Bh,03Dh,03Fh,041h,043h,045h,047h,049h,04Bh,04Dh
	db 04Fh,051h,053h,055h,057h,059h,05Bh,05Dh,05Fh,061h,063h,013h,01Bh,014h,00Dh,002h
	db 00Ch,030h,032h,034h,036h,038h,03Ah,03Ch,03Eh,040h,042h,044h,046h,048h,04Ah,04Ch
	db 04Eh,050h,052h,054h,056h,058h,05Ah,05Ch,05Eh,060h,062h,015h,024h,016h,00Eh,0ACh
	db 065h,067h,069h,06Bh,06Dh,06Fh,073h,075h,077h,079h,07Bh,07Dh,07Fh,081h,083h,085h
	db 087h,089h,08Bh,08Dh,08Fh,091h,093h,095h,097h,099h,09Bh,09Dh,09Fh,0A1h,0A3h,0A5h
	db 064h,066h,068h,06Ah,06Ch,06Eh,072h,074h,076h,078h,07Ah,07Ch,07Eh,080h,082h,084h
	db 0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h
	db 0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h
	db 0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h
	db 086h,088h,08Ah,08Ch,08Eh,090h,092h,094h,096h,098h,09Ah,09Ch,09Eh,0A0h,0A2h,0A4h
	db 071h,070h,0A7h,0A6h,0A9h,0A8h,0ABh,0AAh,025h,025h,025h,0ADh,01Dh,019h,0F0h,0FFh

ru866_ucase label word
	ctable <,'UCASE  ',128>
; 80-9F capitals: identity. A0-AF lowercase: subtract 20h.
ru_byte = 080h
	rept 32
	 db ru_byte
ru_byte = ru_byte+1
	endm
ru_byte = 080h
	rept 16
	 db ru_byte
ru_byte = ru_byte+1
	endm
; B0-DF pseudographics: identity. E0-EF lowercase: subtract 50h.
ru_byte = 0B0h
	rept 48
	 db ru_byte
ru_byte = ru_byte+1
	endm
ru_byte = 090h
	rept 16
	 db ru_byte
ru_byte = ru_byte+1
	endm
; Yo/yo, Ukrainian Ie, Yi and Byelorussian short U; symbols unchanged.
	db 0F0h,0F0h,0F2h,0F2h,0F4h,0F4h,0F6h,0F6h
	db 0F8h,0F9h,0FAh,0FBh,0FCh,0FDh,0FEh,0FFh

ru437_data label word
	dw CDATAITEMS
	ctrydat <CDATASIZE,SETCOUNTRYINFO,,ru437_info>
	ctrydat <CDATASIZE,SETCOLLATE,,ru437_collate>
	ctrydat <CDATASIZE,SETUCASE,,ru437_ucase>
	ctrydat <CDATASIZE,SETUCASEFILE,,ru437_ucase>
	ctrydat <CDATASIZE,SETFILELIST,,us_flist>
	ctrydat <CDATASIZE,SETDBCS,,us_dbcs>

ru437_info label word
	ctable <>
	dw CID_RU,437,DATE_DMY
	db 'r','.',0,0,0
	db ' ',0,'.',0,'.',0,':',0
	db 3,2,HR24 ; symbol follows amount with a space, two decimal digits
	dd 0
	db ';',0
	dw 5 dup (0)

ru437_collate label word
	ctable <,'COLLATE',256>
	db 000h,001h,002h,003h,004h,005h,006h,007h,008h,009h,00Ah,00Bh,00Ch,00Dh,00Eh,00Fh
	db 010h,011h,012h,013h,014h,015h,016h,017h,018h,019h,01Ah,01Bh,01Ch,01Dh,01Eh,01Fh
	db 020h,021h,022h,023h,024h,025h,026h,027h,028h,029h,02Ah,02Bh,02Ch,02Dh,02Eh,02Fh
	db 030h,031h,032h,033h,034h,035h,036h,037h,038h,039h,03Ah,03Bh,03Ch,03Dh,03Eh,03Fh
	db 040h,041h,042h,043h,044h,045h,046h,047h,048h,049h,04Ah,04Bh,04Ch,04Dh,04Eh,04Fh
	db 050h,051h,052h,053h,054h,055h,056h,057h,058h,059h,05Ah,05Bh,05Ch,05Dh,05Eh,05Fh
	db 060h,041h,042h,043h,044h,045h,046h,047h,048h,049h,04Ah,04Bh,04Ch,04Dh,04Eh,04Fh
	db 050h,051h,052h,053h,054h,055h,056h,057h,058h,059h,05Ah,07Bh,07Ch,07Dh,07Eh,07Fh
	db 043h,055h,045h,041h,041h,041h,041h,043h,045h,045h,045h,049h,049h,049h,041h,041h
	db 045h,041h,041h,04Fh,04Fh,04Fh,055h,055h,059h,04Fh,055h,024h,024h,024h,024h,024h
	db 041h,049h,04Fh,055h,04Eh,04Eh,0A6h,0A7h,03Fh,0A9h,0AAh,0ABh,0ACh,021h,022h,022h
	db 0B0h,0B1h,0B2h,0B3h,0B4h,0B5h,0B6h,0B7h,0B8h,0B9h,0BAh,0BBh,0BCh,0BDh,0BEh,0BFh
	db 0C0h,0C1h,0C2h,0C3h,0C4h,0C5h,0C6h,0C7h,0C8h,0C9h,0CAh,0CBh,0CCh,0CDh,0CEh,0CFh
	db 0D0h,0D1h,0D2h,0D3h,0D4h,0D5h,0D6h,0D7h,0D8h,0D9h,0DAh,0DBh,0DCh,0DDh,0DEh,0DFh
	db 0E0h,053h,0E2h,0E3h,0E4h,0E5h,0E6h,0E7h,0E8h,0E9h,0EAh,0EBh,0ECh,0EDh,0EEh,0EFh
	db 0F0h,0F1h,0F2h,0F3h,0F4h,0F5h,0F6h,0F7h,0F8h,0F9h,0FAh,0FBh,0FCh,0FDh,0FEh,0FFh

ru437_ucase label word
	ctable <,'UCASE  ',128>
	db 080h,09Ah,045h,041h,08Eh,041h,08Fh,080h,045h,045h,045h,049h,049h,049h,08Eh,08Fh
	db 090h,092h,092h,04Fh,099h,04Fh,055h,055h,059h,099h,09Ah,09Bh,09Ch,09Dh,09Eh,09Fh
	db 041h,049h,04Fh,055h,0A5h,0A5h,0A6h,0A7h,0A8h,0A9h,0AAh,0ABh,0ACh,0ADh,0AEh,0AFh
	db 0B0h,0B1h,0B2h,0B3h,0B4h,0B5h,0B6h,0B7h,0B8h,0B9h,0BAh,0BBh,0BCh,0BDh,0BEh,0BFh
	db 0C0h,0C1h,0C2h,0C3h,0C4h,0C5h,0C6h,0C7h,0C8h,0C9h,0CAh,0CBh,0CCh,0CDh,0CEh,0CFh
	db 0D0h,0D1h,0D2h,0D3h,0D4h,0D5h,0D6h,0D7h,0D8h,0D9h,0DAh,0DBh,0DCh,0DDh,0DEh,0DFh
	db 0E0h,0E1h,0E2h,0E3h,0E4h,0E5h,0E6h,0E7h,0E8h,0E9h,0EAh,0EBh,0ECh,0EDh,0EEh,0EFh
	db 0F0h,0F1h,0F2h,0F3h,0F4h,0F5h,0F6h,0F7h,0F8h,0F9h,0FAh,0FBh,0FCh,0FDh,0FEh,0FFh

ru850_data label word
	dw CDATAITEMS
	ctrydat <CDATASIZE,SETCOUNTRYINFO,,ru850_info>
	ctrydat <CDATASIZE,SETCOLLATE,,ru850_collate>
	ctrydat <CDATASIZE,SETUCASE,,ru850_ucase>
	ctrydat <CDATASIZE,SETUCASEFILE,,ru850_ucase>
	ctrydat <CDATASIZE,SETFILELIST,,us_flist>
	ctrydat <CDATASIZE,SETDBCS,,us_dbcs>

ru850_info label word
	ctable <>
	dw CID_RU,850,DATE_DMY
	db 'r','.',0,0,0
	db ' ',0,'.',0,'.',0,':',0
	db 3,2,HR24 ; symbol follows amount with a space, two decimal digits
	dd 0
	db ';',0
	dw 5 dup (0)

ru850_collate label word
	ctable <,'COLLATE',256>
	db 000h,001h,002h,003h,004h,005h,006h,007h,008h,009h,00Ah,00Bh,00Ch,00Dh,00Eh,00Fh
	db 010h,011h,012h,013h,014h,015h,016h,017h,018h,019h,01Ah,01Bh,01Ch,01Dh,01Eh,01Fh
	db 020h,021h,022h,023h,024h,025h,026h,027h,028h,029h,02Ah,02Bh,02Ch,02Dh,02Eh,02Fh
	db 030h,031h,032h,033h,034h,035h,036h,037h,038h,039h,03Ah,03Bh,03Ch,03Dh,03Eh,03Fh
	db 040h,041h,042h,043h,044h,045h,046h,047h,048h,049h,04Ah,04Bh,04Ch,04Dh,04Eh,04Fh
	db 050h,051h,052h,053h,054h,055h,056h,057h,058h,059h,05Ah,05Bh,05Ch,05Dh,05Eh,05Fh
	db 060h,041h,042h,043h,044h,045h,046h,047h,048h,049h,04Ah,04Bh,04Ch,04Dh,04Eh,04Fh
	db 050h,051h,052h,053h,054h,055h,056h,057h,058h,059h,05Ah,07Bh,07Ch,07Dh,07Eh,07Fh
	db 043h,055h,045h,041h,041h,041h,041h,043h,045h,045h,045h,049h,049h,049h,041h,041h
	db 045h,041h,041h,04Fh,04Fh,04Fh,055h,055h,059h,04Fh,055h,04Fh,024h,04Fh,09Eh,024h
	db 041h,049h,04Fh,055h,04Eh,04Eh,0A6h,0A7h,03Fh,0A9h,0AAh,0ABh,0ACh,021h,022h,022h
	db 0B0h,0B1h,0B2h,0B3h,0B4h,041h,041h,041h,0B8h,0B9h,0BAh,0BBh,0BCh,024h,024h,0BFh
	db 0C0h,0C1h,0C2h,0C3h,0C4h,0C5h,041h,041h,0C8h,0C9h,0CAh,0CBh,0CCh,0CDh,0CEh,024h
	db 044h,044h,045h,045h,045h,049h,049h,049h,049h,0D9h,0DAh,0DBh,0DCh,0DDh,049h,0DFh
	db 04Fh,053h,04Fh,04Fh,04Fh,04Fh,0E6h,0E8h,0E8h,055h,055h,055h,059h,059h,0EEh,0EFh
	db 0F0h,0F1h,0F2h,0F3h,0F4h,0F5h,0F6h,0F7h,0F8h,0F9h,0FAh,0FBh,0FCh,0FDh,0FEh,0FFh

ru850_ucase label word
	ctable <,'UCASE  ',128>
	db 043h,055h,045h,041h,041h,041h,041h,043h,045h,045h,045h,049h,049h,049h,041h,041h
	db 045h,092h,092h,04Fh,04Fh,04Fh,055h,055h,059h,04Fh,055h,04Fh,09Ch,04Fh,09Eh,09Fh
	db 041h,049h,04Fh,055h,0A5h,0A5h,0A6h,0A7h,0A8h,0A9h,0AAh,0ABh,0ACh,0ADh,0AEh,0AFh
	db 0B0h,0B1h,0B2h,0B3h,0B4h,041h,041h,041h,0B8h,0B9h,0BAh,0BBh,0BCh,0BDh,0BEh,0BFh
	db 0C0h,0C1h,0C2h,0C3h,0C4h,0C5h,041h,041h,0C8h,0C9h,0CAh,0CBh,0CCh,0CDh,0CEh,0CFh
	db 0D1h,0D1h,045h,045h,045h,049h,049h,049h,049h,0D9h,0DAh,0DBh,0DCh,0DDh,049h,0DFh
	db 04Fh,0E1h,04Fh,04Fh,04Fh,04Fh,0E6h,0E8h,0E8h,055h,055h,055h,059h,059h,0EEh,0EFh
	db 0F0h,0F1h,0F2h,0F3h,0F4h,0F5h,0F6h,0F7h,0F8h,0F9h,0FAh,0FBh,0FCh,0FDh,0FEh,0FFh
