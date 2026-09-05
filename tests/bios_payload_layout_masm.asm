.8086
option oldstructs
.model tiny
.code
org 0
include MSBDS.INC
dw DRIVENUM,FLAGS,TRACK,TIM_LO,TIM_HI,FNON_REMOVABLE,DRIVELET
end
