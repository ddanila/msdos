; Development-only SYSINIT/provider negotiation in INIT's eight reserved bytes.
; Not a public DOS driver ABI. Both peers must opt in; version mismatch uses
; ordinary synchronous INIT. The callback expires before the loader links the
; driver or discards initialization storage. No relocation capability yet.
BP_MAGIC_OFF equ 5
BP_VERSION_OFF equ 7
BP_CALLBACK_OFF equ 9
BP_MAGIC equ 5042h
BP_VERSION equ 1
BP_ACTIVATE equ 1
BP_CANCEL equ 2
