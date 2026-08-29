/* error.c - return text of error corresponding to the most recent DOS error */

#include <errno.h>
#include <string.h>
#include "tools.h"

extern char UnKnown[];

char *error ()
{
    if (errno < 0)
	return UnKnown;
    return strerror(errno);
}
