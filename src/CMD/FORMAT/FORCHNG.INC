.xlist
; Disable Ctrl-Break while writing the FAT, directory, and system files.
; Slow AT head resets make bad-sector verification appear hung; keep its
; progress indication. SELECT supplies prompts through INT 2Fh/AX=ADC1h
; and uses exit codes 6 (drive not ready) and 7 (write protected).
.list

