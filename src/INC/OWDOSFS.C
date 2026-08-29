/* cdecl DOS filesystem wrappers for legacy sources built with wcc -ecc. */

#include <dos.h>

int chdir(path)
const char *path;
{
    union REGS inregs, outregs;

    inregs.x.ax = 0x3b00;
    inregs.x.dx = (unsigned)path;
    intdos(&inregs, &outregs);
    return outregs.x.cflag ? -1 : 0;
}

int mkdir(path)
const char *path;
{
    union REGS inregs, outregs;

    inregs.x.ax = 0x3900;
    inregs.x.dx = (unsigned)path;
    intdos(&inregs, &outregs);
    return outregs.x.cflag ? -1 : 0;
}
