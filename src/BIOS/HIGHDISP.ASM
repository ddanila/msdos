; Isolated complete decoder for the coordinated development BIOS payload.
.8086
CODE segment public 'CODE'
CODE ends
BIOSHIGH segment byte public 'BIOSHIGH'
assume cs:BIOSHIGH
UNIT equ 1
CMD equ 2
MEDIA equ 13
TRANS equ 14
COUNT equ 18
START equ 20
START_L equ 26
START_H equ 28
extrn AUXNUM:byte, PTRSAV:dword, START_SEC_H:word, DSKTBL:word
extrn BIOS_DISPATCH_LOW_SEGMENT:word, BIOS_DISPATCH_ERROR_ENTRY:dword
extrn BIOS_DISPATCH_TABLE_SEGMENT:word, BIOS_DISPATCH_TABLE_DELTA:word
BIOS_DISPATCH_SEPARATE equ 1
BIOS_DISPATCH_TABLES_HIGH equ 1
public BIOS_DISPATCH_START, BIOS_DISPATCH_END
BIOS_DISPATCH_START label byte
include DISPATCH.INC
BIOS_DISPATCH_END label byte
BIOSHIGH ends
end
