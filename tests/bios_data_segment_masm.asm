; Compile both ownership choices without enabling the unfinished high body.
.8086
.model tiny
.code
org 0
include MSBSEG.INC
BIOS_PUSH_DATA_SEG
pop es
retf
BIOS_SERVICE_LOW_SEGMENT dw 1234h
end
