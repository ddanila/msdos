/* return the system variables in sysVars */

#include "sysvar.h"
#include <dos.h>
#include "jointype.h"

GetVars(pSVars)
struct sysVarsType *pSVars ;
{
        struct sysVarsType far *vptr ;
        int i ;

        union REGS ir ;
        register union REGS *iregs = &ir ;      /* Used for DOS calls      */
        struct SREGS syssegs ;

        iregs->h.ah = GETVARS ;                 /* Function 0x52           */
        intdosx(iregs, iregs, &syssegs) ;
#ifdef __WATCOMC__
        vptr = (struct sysVarsType far *) MK_FP(syssegs.es, iregs->x.bx) ;
#else
        *(long *)(&vptr) = (((long)syssegs.es) << 16)+(iregs->x.bx & 0xffffL) ;
#endif

        for (i=0 ; i < sizeof(*pSVars) ; i++)
                *((char *)pSVars+i) = *((char far *)vptr+i) ;

}




PutVars(pSVars)
struct sysVarsType *pSVars ;
{
        struct sysVarsType far *vptr ;
        int i ;

        union REGS ir ;
        register union REGS *iregs = &ir ;      /* Used for DOS calls      */
        struct SREGS syssegs ;

        iregs->h.ah = GETVARS ;                 /* Function 0x52           */
        intdosx(iregs, iregs, &syssegs) ;
#ifdef __WATCOMC__
        vptr = (struct sysVarsType far *) MK_FP(syssegs.es, iregs->x.bx) ;
#else
        *(long *)(&vptr) = (((long)syssegs.es) << 16)+(iregs->x.bx & 0xffffL) ;
#endif

        for (i=0 ; i < sizeof(*pSVars) ; i++)
                *((char far *)vptr+i) = *((char *)pSVars+i) ;

}
