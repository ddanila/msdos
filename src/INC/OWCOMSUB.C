/*
 * Open-source replacements for the COMSUBS.LIB routines used by the
 * migrated Open Watcom utilities.  String searches skip complete DBCS
 * characters so a trail byte is never mistaken for an ASCII delimiter.
 */

#include <dos.h>

static int dbcs_lead(c)
unsigned char c;
{
    union REGS inregs, outregs;
    struct SREGS segregs;
    unsigned char far *ranges;

    segread(&segregs);
    inregs.x.ax = 0x6300;
    intdosx(&inregs, &outregs, &segregs);
    ranges = (unsigned char far *)MK_FP(segregs.ds, outregs.x.si);
    while (ranges[0] || ranges[1]) {
        if (c >= ranges[0] && c <= ranges[1])
            return 1;
        ranges += 2;
    }
    return 0;
}

int com_toupper(c)
unsigned char c;
{
    union REGS inregs, outregs;

    inregs.x.ax = 0x6520;
    inregs.h.dl = c;
    intdos(&inregs, &outregs);
    return outregs.h.dl;
}

/* COMSUBS maps DOS return codes directly to extended-error message IDs. */
unsigned rctomid(return_code)
unsigned return_code;
{
    return return_code;
}

char *com_strchr(string, target)
unsigned char *string;
unsigned char target;
{
    unsigned char *scan = string;

    while (*scan) {
        if (dbcs_lead(*scan) && scan[1]) {
            scan += 2;
            continue;
        }
        if (*scan == target)
            return (char *)scan;
        scan++;
    }
    return target == 0 ? (char *)scan : 0;
}

unsigned char *com_strrchr(string, target)
unsigned char *string;
unsigned char target;
{
    unsigned char *last = 0;
    unsigned char *scan = string;

    while (*scan) {
        if (dbcs_lead(*scan) && scan[1]) {
            scan += 2;
            continue;
        }
        if (*scan == target)
            last = scan;
        scan++;
    }
    return target == 0 ? scan : last;
}

unsigned char *com_substr(string, pattern)
unsigned char *string;
unsigned char *pattern;
{
    unsigned char *scan = string;
    unsigned char *left;
    unsigned char *right;

    if (!*pattern)
        return string;
    while (*scan) {
        if (dbcs_lead(*scan) && scan[1]) {
            scan += 2;
            continue;
        }
        left = scan;
        right = pattern;
        while (*right && *left == *right) {
            left++;
            right++;
        }
        if (!*right)
            return scan;
        scan++;
    }
    return 0;
}
