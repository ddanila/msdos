; Test-only SYSINIT fixture. Seed immediately before publication, after DOS
; allocation calls, so a later pathname call cannot mask a missed cache fixup.
; Cases: first entry, last entry, one-past-array, same offset in another segment.
CdsCacheArmed DB 0
CdsCacheOffset DW 0
CdsCacheSegment DW 0
CdsCacheSeed PROC NEAR
        cli                     ; outer helper restores the original flags
        les di,cs:[DosInfo]
        xor bx,bx
        mov ax,cs:[CdsLowStart]
        inc ax
        IF BIOS_CDS_CACHE_CASE EQ 2
        mov bx,cs:[CdsBytes]
        sub bx,size curdir_list
        ENDIF
        IF BIOS_CDS_CACHE_CASE EQ 3
        mov bx,cs:[CdsBytes]
        ENDIF
        IF BIOS_CDS_CACHE_CASE EQ 4
        inc ax
        ENDIF
        mov cs:[CdsCacheOffset],bx
        mov cs:[CdsCacheSegment],ax
        mov word ptr es:[CDS_THISCDS],bx
        mov word ptr es:[CDS_THISCDS+2],ax
        mov cs:[CdsCacheArmed],1
        ret
CdsCacheSeed ENDP

CdsCacheCheck PROC NEAR
        cmp cs:[CdsCacheArmed],0
        je CdsCacheReturn
        les di,cs:[DosInfo]
        mov bx,cs:[CdsCacheOffset]
        mov ax,cs:[CdsCacheSegment]
        IF BIOS_CDS_CACHE_CASE LE 2
        ; Derive the expected owner from the published public root, not from
        ; CdsUpper or the code branch whose cache write is under test.
        mov ax,word ptr es:[di.SYSI_CDS+2]
        ENDIF
        mov si,OFFSET CdsCachePass
        cmp word ptr es:[CDS_THISCDS],bx
        jne CdsCacheBad
        cmp word ptr es:[CDS_THISCDS+2],ax
        je CdsCacheEmit
CdsCacheBad:
        mov si,OFFSET CdsCacheFail
CdsCacheEmit:
        ; MACRO2.ASM uses offset -1 as NULL ThisCDS. Remove the injected
        ; cache before normal boot continues, including out-of-range cases.
        mov word ptr es:[CDS_THISCDS],0ffffh
        mov cs:[CdsCacheArmed],0
        push cs
        pop ds
        cld
CdsCacheCharacter:
        lodsb
        or al,al
        jz CdsCacheReturn
        out 0e9h,al
        jmp short CdsCacheCharacter
CdsCacheReturn:
        ret
CdsCacheCheck ENDP
CdsCachePass DB 'CDS_CACHE_PASS',10,0
CdsCacheFail DB 'CDS_CACHE_FAIL',10,0
