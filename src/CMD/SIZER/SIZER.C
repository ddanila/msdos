#include <ctype.h>
#include <dos.h>
#include <errno.h>
#include <process.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SIZER_MAGIC 0x5a53

struct size_record {
    unsigned magic;
    unsigned index;
    unsigned before;
    unsigned after;
};

static unsigned largest_conventional(void)
{
    union REGS regs;
    unsigned strategy, linked, paragraphs;
    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5800;
    intdos(&regs, &regs);
    strategy = regs.x.ax;
    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5802;
    intdos(&regs, &regs);
    linked = regs.x.ax;
    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5801;
    regs.x.bx = 0;
    intdos(&regs, &regs);
    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5803;
    regs.x.bx = 0;
    intdos(&regs, &regs);
    memset(&regs, 0, sizeof(regs));
    regs.h.ah = 0x48;
    regs.x.bx = 0xffff;
    intdos(&regs, &regs);
    paragraphs = regs.x.bx;
    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5801;
    regs.x.bx = strategy;
    intdos(&regs, &regs);
    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5803;
    regs.x.bx = linked;
    intdos(&regs, &regs);
    return paragraphs;
}

static int number(const char *text, unsigned *value)
{
    unsigned long result = 0;
    if (!*text)
        return 1;
    while (*text) {
        if (*text < '0' || *text > '9')
            return 1;
        result = result * 10UL + (unsigned)(*text++ - '0');
        if (result > 65535UL)
            return 1;
    }
    *value = (unsigned)result;
    return 0;
}

int main(int argc, char **argv)
{
    struct size_record record;
    unsigned drive = 2;
    unsigned index;
    char path[24];
    FILE *file;
    int result;
    if (argc < 4 || strnicmp(argv[1], "/M:", 3) ||
        number(argv[1] + 3, &index) || strnicmp(argv[2], "/SWAP:", 6) ||
        !argv[2][6] || argv[2][7]) {
        fputs("SIZER is used internally by MemMaker.\n", stderr);
        return 1;
    }
    drive = (unsigned)(toupper((unsigned char)argv[2][6]) - 'A');
    if (drive >= 26)
        return 1;
    record.magic = SIZER_MAGIC;
    record.index = index;
    record.before = largest_conventional();
    result = spawnvp(P_WAIT, argv[3], (const char * const *)(argv + 3));
    if (result == -1) {
        fprintf(stderr, "SIZER cannot run %s (error %d).\n", argv[3], errno);
        return 1;
    }
    record.after = largest_conventional();
    sprintf(path, "%c:\\MEMMAKER.SIZ", 'A' + drive);
    file = fopen(path, "ab");
    if (!file) {
        fputs("SIZER cannot record the resident-memory measurement.\n", stderr);
        return 1;
    }
    if (fwrite(&record, sizeof(record), 1, file) != 1 || fclose(file)) {
        fputs("SIZER cannot record the resident-memory measurement.\n", stderr);
        return 1;
    }
    return result;
}
