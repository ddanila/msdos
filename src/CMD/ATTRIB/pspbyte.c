/* OW-compat module for ATTRIB (option b: OW cstart is the entry). */
#include <dos.h>
extern unsigned _psp;          /* OW: PSP segment, set by cstart */

unsigned char getpspbyte(unsigned off)
{
    return *(unsigned char __far *)MK_FP(_psp, off);
}
void putpspbyte(unsigned off, unsigned char val)
{
    *(unsigned char __far *)MK_FP(_psp, off) = val;
}

/* cstart calls main(); reconstruct the DOS command tail (PSP:0x80) on the
   stack -- as the old XCMAIN startup did -- and hand it to inmain(). A stack
   buffer (vs static BSS) avoids being clobbered by the utility's globals. */
extern int inmain(char *line);
int main(void)
{
    char cmdtail[130];
    unsigned n = getpspbyte(0x80), i;
    if (n > 128) n = 128;
    for (i = 0; i < n; i++) cmdtail[i] = getpspbyte(0x81 + i);
    cmdtail[n] = '\0';
    inmain(cmdtail);
    return 0;
}
