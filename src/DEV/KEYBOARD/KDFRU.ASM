; Russian JCUKEN, ID 441, CP866. Authored using the project KEYB macros.
; Translation facts are checked against locales/ru/dos622-reference.json.
; No retail keyboard resident code is embedded here.
; Features 1000h/2000h request Alt+Shift selection / initial Latin mode.
; Physical-input qualification is recorded in locales/ru.
INCLUDE KEYBSHAR.INC
INCLUDE POSTEQU.INC
INCLUDE KEYBMAC.INC

CODE SEGMENT PUBLIC 'CODE'
ASSUME CS:CODE,DS:CODE
DB 0FFh,'KEYB   ',8 DUP(0)
; Reserve the existing KEYBOARD.SYS capacities so KEYB can later load an
; existing layout into the same resident allocation (for example GR/437).
DW 1120,496,640
DW 0,1,1
DB 'RU'
DW OFFSET RU_ENTRY,0
DW 441,OFFSET RU_ENTRY,0
RU_ENTRY:
DB 'RU'
DW 441,OFFSET RU_LOGIC,0
DB 1,1
DW 866,OFFSET RU_PAGE,0

INCLUDE KDFRUTAB.INC
CODE ENDS
END
