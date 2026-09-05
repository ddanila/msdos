.8086
option oldstructs
.model tiny
.code
org 0
BREAK macro args:VARARG
endm
include SYSVAR.INC
include DPB.INC
include CURDIR.INC
include SF.INC
include DEVSYM.INC
include BUFFER.INC
dw SYSI_DPB,SYSI_SFT,SYSI_CDS,SYSI_NUMIO,SYSI_NCDS,SYSI_DEV
dw DPB_NEXT_DPB,DPB_DRIVER_ADDR,DPB_SECTOR_SIZE
dw curdir_devptr,curdirLen
dw SFLink,SFCount,SFTable,SIZE sf_entry,sf_ref_count,sf_devptr,sf_name
dw SDEVNEXT,SDEVATT,SDEVNAME
dw SYSI_CON
dw SYSI_BUF,HASH_PTR,HASH_COUNT,BUFFER_BUCKET,SIZE BUFFER_HASH_ENTRY,BUF_NEXT
end
