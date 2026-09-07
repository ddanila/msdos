


.seq
stack       segment  Stack  'STACK' ; represents STACK
stack       ends

cseg_main   segment   Public 'CODE'; represents MAIN
cseg_main   ends

cseg_open   segment   Public 'CODE'; represents  FASTOPEN
cseg_open   ends

cseg_seek   segment   Public 'CODE'; represents FASTSEEK
cseg_seek   ends

cseg_init   segment  Public 'CODE' ; represents INIT
cseg_init   ends

GMAIN      GROUP cseg_main
GOPEN      GROUP cseg_open
GSEEK      GROUP cseg_seek
GINIT      GROUP cseg_init

