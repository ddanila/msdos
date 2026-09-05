; Assemble the shared production-candidate gate with the BIOS toolchain too.
.8086
LOW_GATE SEGMENT BYTE PUBLIC 'CODE'
ASSUME CS:LOW_GATE
include HIGHROM.INC
LOW_GATE ENDS
END
