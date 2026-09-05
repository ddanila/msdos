; Retained-low disk request entries. Command numbers index DSKTBL, not INT 21h.
; Expand BIOS_DEVICE_ENTRY to emit a low A20-restoring tail stub and its far
; target slot. No extra return frame may survive into the high service: it
; completes through MSBIO1's original nine-register device epilogue.
;
; Compilation does NOT change DSKTBL. The installer must bind every pointer,
; preserve the selected/purged command policy, and only then publish low stub
; offsets under an interrupt-disabled commit. Keep the original table on any
; failure; after reclaiming the low body, reverting pointers is not rollback.
BIOS_DEVICE_ENTRY 4,BIOS_DEVICE_READ,BIOS_HIGH_READ_ENTRY,DSK$READ
BIOS_DEVICE_ENTRY 8,BIOS_DEVICE_WRITE,BIOS_HIGH_WRITE_ENTRY,DSK$WRIT
BIOS_DEVICE_ENTRY 9,BIOS_DEVICE_VERIFY,BIOS_HIGH_VERIFY_ENTRY,DSK$WRITV
BIOS_DEVICE_ENTRY 15,BIOS_DEVICE_REMOVABLE,BIOS_HIGH_REMOVABLE_ENTRY,DSK$REM
BIOS_DEVICE_ENTRY 19,BIOS_DEVICE_IOCTL,BIOS_HIGH_IOCTL_ENTRY,GENERIC$IOCTL
BIOS_DEVICE_ENTRY 23,BIOS_DEVICE_GETOWNER,BIOS_HIGH_GETOWNER_ENTRY,IOCTL$GETOWN
BIOS_DEVICE_ENTRY 24,BIOS_DEVICE_SETOWNER,BIOS_HIGH_SETOWNER_ENTRY,IOCTL$SETOWN
