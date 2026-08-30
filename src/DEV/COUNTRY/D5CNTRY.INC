; DOS 5 country records derived from the retail COUNTRY.SYS tables.
br_info label word
	db	0FFh,43h,54h,59h,49h,4Eh,46h,4Fh,26h,00h,37h,00h,52h,03h,01h,00h
	db	43h,72h,24h,00h,00h,2Eh,00h,2Ch,00h,2Fh,00h,3Ah,00h,00h,02h,01h
	db	00h,00h,00h,00h,3Bh,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
;
yu_info label word
	db	0FFh,43h,54h,59h,49h,4Eh,46h,4Fh,26h,00h,26h,00h,54h,03h,02h,00h
	db	44h,69h,6Eh,00h,00h,2Eh,00h,2Ch,00h,2Dh,00h,3Ah,00h,02h,02h,01h
	db	00h,00h,00h,00h,2Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
;
cz_info label word
	db	0FFh,43h,54h,59h,49h,4Eh,46h,4Fh,26h,00h,2Ah,00h,54h,03h,02h,00h
	db	4Bh,9Fh,73h,00h,00h,2Eh,00h,2Ch,00h,2Dh,00h,3Ah,00h,02h,02h,01h
	db	00h,00h,00h,00h,2Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
;
pl_info label word
	db	0FFh,43h,54h,59h,49h,4Eh,46h,4Fh,26h,00h,30h,00h,54h,03h,02h,00h
	db	5Ah,88h,00h,00h,00h,2Eh,00h,2Ch,00h,2Dh,00h,3Ah,00h,00h,02h,01h
	db	00h,00h,00h,00h,2Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
;
hu_info label word
	db	0FFh,43h,54h,59h,49h,4Eh,46h,4Fh,26h,00h,24h,00h,54h,03h,02h,00h
	db	46h,74h,00h,00h,00h,20h,00h,2Ch,00h,2Dh,00h,3Ah,00h,00h,02h,01h
	db	00h,00h,00h,00h,2Ch,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
;
br437_collate label word
	db	0FFh,43h,4Fh,4Ch,4Ch,41h,54h,45h,00h,01h,00h,01h,02h,03h,04h,05h
	db	06h,07h,08h,09h,0Ah,0Bh,0Ch,0Dh,0Eh,0Fh,10h,11h,12h,13h,14h,15h
	db	16h,17h,18h,19h,1Ah,1Bh,1Ch,1Dh,1Eh,1Fh,20h,21h,22h,23h,24h,25h
	db	26h,27h,28h,29h,2Ah,2Bh,2Ch,2Dh,2Eh,2Fh,30h,31h,32h,33h,34h,35h
	db	36h,37h,38h,39h,3Ah,3Bh,3Ch,3Dh,3Eh,3Fh,40h,41h,42h,43h,44h,45h
	db	46h,47h,48h,49h,4Ah,4Bh,4Ch,4Dh,4Eh,4Fh,50h,51h,52h,53h,54h,55h
	db	56h,57h,58h,59h,5Ah,5Bh,5Ch,5Dh,5Eh,5Fh,60h,41h,42h,43h,44h,45h
	db	46h,47h,48h,49h,4Ah,4Bh,4Ch,4Dh,4Eh,4Fh,50h,51h,52h,53h,54h,55h
	db	56h,57h,58h,59h,5Ah,7Bh,7Ch,7Dh,7Eh,7Fh,43h,55h,45h,41h,41h,41h
	db	41h,43h,45h,45h,45h,49h,49h,49h,41h,41h,45h,41h,41h,4Fh,4Fh,4Fh
	db	55h,55h,59h,4Fh,55h,24h,24h,24h,24h,24h,41h,49h,4Fh,55h,4Eh,4Eh
	db	0A6h,0A7h,3Fh,0A9h,0AAh,0ABh,0ACh,21h,22h,22h,0B0h,0B1h,0B2h,0B3h,0B4h,0B5h
	db	0B6h,0B7h,0B8h,0B9h,0BAh,0BBh,0BCh,0BDh,0BEh,0BFh,0C0h,0C1h,0C2h,0C3h,0C4h,0C5h
	db	0C6h,0C7h,0C8h,0C9h,0CAh,0CBh,0CCh,0CDh,0CEh,0CFh,0D0h,0D1h,0D2h,0D3h,0D4h,0D5h
	db	0D6h,0D7h,0D8h,0D9h,0DAh,0DBh,0DCh,0DDh,0DEh,0DFh,0E0h,53h,0E2h,0E3h,0E4h,0E5h
	db	0E6h,0E7h,0E8h,0E9h,0EAh,0EBh,0ECh,0EDh,0EEh,0EFh,0F0h,0F1h,0F2h,0F3h,0F4h,0F5h
	db	0F6h,0F7h,0F8h,0F9h,0FAh,0FBh,0FCh,0FDh,0FEh,0FFh,0FFh
;
cp852_collate label word
	db	0FFh,43h,4Fh,4Ch,4Ch,41h,54h,45h,00h,01h,00h,01h,02h,03h,04h,05h
	db	06h,07h,08h,09h,0Ah,0Bh,0Ch,0Dh,0Eh,0Fh,10h,11h,12h,13h,14h,15h
	db	16h,17h,18h,19h,1Ah,1Bh,1Ch,1Dh,1Eh,1Fh,6Eh,6Fh,70h,71h,72h,73h
	db	74h,75h,76h,77h,78h,79h,7Ah,7Bh,7Ch,7Dh,64h,65h,66h,67h,68h,69h
	db	6Ah,6Bh,6Ch,6Dh,7Eh,7Fh,80h,81h,82h,83h,84h,21h,27h,28h,2Ch,2Fh
	db	34h,35h,36h,37h,3Ah,3Bh,3Ch,40h,41h,44h,49h,4Ah,4Bh,4Eh,53h,56h
	db	5Bh,5Ch,5Dh,5Eh,60h,85h,86h,87h,88h,89h,8Ah,21h,27h,28h,2Ch,2Fh
	db	34h,35h,36h,37h,3Ah,3Bh,3Ch,40h,41h,44h,49h,4Ah,4Bh,4Eh,53h,56h
	db	5Bh,5Ch,5Dh,5Eh,60h,8Bh,8Ch,8Dh,8Eh,20h,2Bh,59h,30h,26h,23h,58h
	db	29h,2Bh,3Fh,33h,48h,48h,39h,62h,23h,29h,30h,3Dh,3Dh,46h,47h,3Eh
	db	3Eh,52h,52h,47h,59h,54h,54h,3Fh,8Fh,2Ah,22h,38h,45h,57h,24h,24h
	db	61h,61h,32h,32h,90h,62h,2Ah,51h,91h,92h,97h,98h,99h,9Ah,9Bh,22h
	db	26h,31h,51h,9Ch,9Dh,9Eh,9Fh,63h,63h,0A0h,0A1h,0A2h,0A3h,0A4h,0A5h,0A6h
	db	25h,25h,0A7h,0A8h,0A9h,0AAh,0ABh,0ACh,0ADh,93h,2Dh,2Dh,2Eh,33h,2Eh,42h
	db	38h,39h,31h,0AEh,0AFh,0B0h,0B1h,55h,58h,0B2h,45h,4Fh,46h,43h,43h,42h
	db	50h,50h,4Ch,57h,4Ch,5Ah,5Fh,5Fh,55h,0B4h,94h,0B5h,0B6h,0B7h,0B8h,95h
	db	96h,0B9h,0BAh,0BBh,0BCh,5Ah,4Dh,4Dh,0B3h,0FFh,0FFh
;
br850_collate label word
	db	0FFh,43h,4Fh,4Ch,4Ch,41h,54h,45h,00h,01h,00h,01h,02h,03h,04h,05h
	db	06h,07h,08h,09h,0Ah,0Bh,0Ch,0Dh,0Eh,0Fh,10h,11h,12h,13h,14h,15h
	db	16h,17h,18h,19h,1Ah,1Bh,1Ch,1Dh,1Eh,1Fh,20h,21h,22h,23h,24h,25h
	db	26h,27h,28h,29h,2Ah,2Bh,2Ch,2Dh,2Eh,2Fh,30h,31h,32h,33h,34h,35h
	db	36h,37h,38h,39h,3Ah,3Bh,3Ch,3Dh,3Eh,3Fh,40h,41h,42h,43h,44h,45h
	db	46h,47h,48h,49h,4Ah,4Bh,4Ch,4Dh,4Eh,4Fh,50h,51h,52h,53h,54h,55h
	db	56h,57h,58h,59h,5Ah,5Bh,5Ch,5Dh,5Eh,5Fh,60h,41h,42h,43h,44h,45h
	db	46h,47h,48h,49h,4Ah,4Bh,4Ch,4Dh,4Eh,4Fh,50h,51h,52h,53h,54h,55h
	db	56h,57h,58h,59h,5Ah,7Bh,7Ch,7Dh,7Eh,7Fh,43h,55h,45h,41h,41h,41h
	db	41h,43h,45h,45h,45h,49h,49h,49h,41h,41h,45h,41h,41h,4Fh,4Fh,4Fh
	db	55h,55h,59h,4Fh,55h,4Fh,24h,4Fh,9Eh,24h,41h,49h,4Fh,55h,4Eh,4Eh
	db	0A6h,0A7h,3Fh,0A9h,0AAh,0ABh,0ACh,21h,22h,22h,0B0h,0B1h,0B2h,0B3h,0B4h,41h
	db	41h,41h,0B8h,0B9h,0BAh,0BBh,0BCh,24h,24h,0BFh,0C0h,0C1h,0C2h,0C3h,0C4h,0C5h
	db	41h,41h,0C8h,0C9h,0CAh,0CBh,0CCh,0CDh,0CEh,24h,44h,44h,45h,45h,45h,49h
	db	49h,49h,49h,0D9h,0DAh,0DBh,0DCh,0DDh,49h,0DFh,4Fh,53h,4Fh,4Fh,4Fh,4Fh
	db	0E6h,0E8h,0E8h,55h,55h,55h,59h,59h,0EEh,0EFh,0F0h,0F1h,0F2h,0F3h,0F4h,0F5h
	db	0F6h,0F7h,0F8h,0F9h,0FAh,0FBh,0FCh,0FDh,0FEh,0FFh,0FFh
;
br437_ucase label word
	db	0FFh,55h,43h,41h,53h,45h,20h,20h,80h,00h,80h,9Ah,45h,41h,8Eh,41h
	db	8Fh,80h,45h,45h,45h,49h,49h,49h,8Eh,8Fh,90h,92h,92h,4Fh,99h,4Fh
	db	55h,55h,59h,99h,9Ah,9Bh,9Ch,9Dh,9Eh,9Fh,41h,49h,4Fh,55h,0A5h,0A5h
	db	0A6h,0A7h,0A8h,0A9h,0AAh,0ABh,0ACh,0ADh,0AEh,0AFh,0B0h,0B1h,0B2h,0B3h,0B4h,0B5h
	db	0B6h,0B7h,0B8h,0B9h,0BAh,0BBh,0BCh,0BDh,0BEh,0BFh,0C0h,0C1h,0C2h,0C3h,0C4h,0C5h
	db	0C6h,0C7h,0C8h,0C9h,0CAh,0CBh,0CCh,0CDh,0CEh,0CFh,0D0h,0D1h,0D2h,0D3h,0D4h,0D5h
	db	0D6h,0D7h,0D8h,0D9h,0DAh,0DBh,0DCh,0DDh,0DEh,0DFh,0E0h,0E1h,0E2h,0E3h,0E4h,0E5h
	db	0E6h,0E7h,0E8h,0E9h,0EAh,0EBh,0ECh,0EDh,0EEh,0EFh,0F0h,0F1h,0F2h,0F3h,0F4h,0F5h
	db	0F6h,0F7h,0F8h,0F9h,0FAh,0FBh,0FCh,0FDh,0FEh,0FFh
;
cp852_ucase label word
	db	0FFh,55h,43h,41h,53h,45h,20h,20h,80h,00h,80h,9Ah,90h,0B6h,8Eh,0DEh
	db	8Fh,80h,9Dh,0D3h,8Ah,8Ah,0D7h,8Dh,8Eh,8Fh,90h,91h,91h,0E2h,99h,95h
	db	95h,97h,97h,99h,9Ah,9Bh,9Bh,9Dh,9Eh,0ACh,0B5h,0D6h,0E0h,0E9h,0A4h,0A4h
	db	0A6h,0A6h,0A8h,0A8h,0AAh,8Dh,0ACh,0B8h,0AEh,0AFh,0B0h,0B1h,0B2h,0B3h,0B4h,0B5h
	db	0B6h,0B7h,0B8h,0B9h,0BAh,0BBh,0BCh,0BDh,0BDh,0BFh,0C0h,0C1h,0C2h,0C3h,0C4h,0C5h
	db	0C6h,0C6h,0C8h,0C9h,0CAh,0CBh,0CCh,0CDh,0CEh,0CFh,0D1h,0D1h,0D2h,0D3h,0D2h,0D5h
	db	0D6h,0D7h,0B7h,0D9h,0DAh,0DBh,0DCh,0DDh,0DEh,0DFh,0E0h,0E1h,0E2h,0E3h,0E3h,0D5h
	db	0E6h,0E6h,0E8h,0E9h,0E8h,0EBh,0EDh,0EDh,0DDh,0EFh,0F0h,0F1h,0F2h,0F3h,0F4h,0F5h
	db	0F6h,0F7h,0F8h,0F9h,0FAh,0EBh,0FCh,0FCh,0FEh,0FFh
;
br850_ucase label word
	db	0FFh,55h,43h,41h,53h,45h,20h,20h,80h,00h,80h,9Ah,90h,0B6h,8Eh,0B7h
	db	8Fh,80h,0D2h,0D3h,0D4h,0D8h,0D7h,0DEh,8Eh,8Fh,90h,92h,92h,0E2h,99h,0E3h
	db	0EAh,0EBh,98h,99h,9Ah,9Dh,9Ch,9Dh,9Eh,9Fh,0B5h,0D6h,0E0h,0E9h,0A5h,0A5h
	db	0A6h,0A7h,0A8h,0A9h,0AAh,0ABh,0ACh,0ADh,0AEh,0AFh,0B0h,0B1h,0B2h,0B3h,0B4h,0B5h
	db	0B6h,0B7h,0B8h,0B9h,0BAh,0BBh,0BCh,0BDh,0BEh,0BFh,0C0h,0C1h,0C2h,0C3h,0C4h,0C5h
	db	0C7h,0C7h,0C8h,0C9h,0CAh,0CBh,0CCh,0CDh,0CEh,0CFh,0D1h,0D1h,0D2h,0D3h,0D4h,0D5h
	db	0D6h,0D7h,0D8h,0D9h,0DAh,0DBh,0DCh,0DDh,0DEh,0DFh,0E0h,0E1h,0E2h,0E3h,0E5h,0E5h
	db	0E6h,0E8h,0E8h,0E9h,0EAh,0EBh,0EDh,0EDh,0EEh,0EFh,0F0h,0F1h,0F2h,0F3h,0F4h,0F5h
	db	0F6h,0F7h,0F8h,0F9h,0FAh,0FBh,0FCh,0FDh,0FEh,0FFh
;
cp852_ucfile label word
	db	0FFh,46h,55h,43h,41h,53h,45h,20h,80h,00h,80h,9Ah,90h,0B6h,8Eh,0DEh
	db	8Fh,80h,9Dh,0D3h,8Ah,8Ah,0D7h,8Dh,8Eh,8Fh,90h,91h,91h,0E2h,99h,95h
	db	95h,97h,97h,99h,9Ah,9Bh,9Bh,9Dh,9Eh,0ACh,0B5h,0D6h,0E0h,0E9h,0A4h,0A4h
	db	0A6h,0A6h,0A8h,0A8h,0AAh,8Dh,0ACh,0B8h,0AEh,0AFh,0B0h,0B1h,0B2h,0B3h,0B4h,0B5h
	db	0B6h,0B7h,0B8h,0B9h,0BAh,0BBh,0BCh,0BDh,0BDh,0BFh,0C0h,0C1h,0C2h,0C3h,0C4h,0C5h
	db	0C6h,0C6h,0C8h,0C9h,0CAh,0CBh,0CCh,0CDh,0CEh,0CFh,0D1h,0D1h,0D2h,0D3h,0D2h,0D5h
	db	0D6h,0D7h,0B7h,0D9h,0DAh,0DBh,0DCh,0DDh,0DEh,0DFh,0E0h,0E1h,0E2h,0E3h,0E3h,0D5h
	db	0E6h,0E6h,0E8h,0E9h,0E8h,0EBh,0EDh,0EDh,0DDh,0EFh,0F0h,0F1h,0F2h,0F3h,0F4h,0F5h
	db	0F6h,0F7h,0F8h,0F9h,0FAh,0EBh,0FCh,0FCh,0FEh,0FFh
;

