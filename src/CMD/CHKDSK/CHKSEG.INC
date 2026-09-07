PSP	segment public	para 'DUMMY'
PSP	ends
data	segment public para 'DATA'
data	ends
CONST	SEGMENT PUBLIC para 'DATA'
CONST	ENDS
code	segment public para 'CODE'
code	ends
cstack	 segment para stack 'STACK'
cstack	 ends
lastseg segment public para 'LAST'
lastseg ends			 ;this is a pointer to the end of the pgm     ;A;an000;bgbN000;bgb
DG	GROUP	data,const,code,CSTACK,lastseg
assume	cs:dg,ds:dg,ss:dg,es:dg
