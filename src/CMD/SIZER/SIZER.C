#include <ctype.h>
#include <dos.h>
#include <errno.h>
#include <process.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SIZER_MAGIC 0x5a53
#define SIZER_LOAD_MAGIC 0x4c53
#define EXEC_OVERHEAD_PARAGRAPHS 64

struct size_record {
    unsigned magic;
    unsigned index;
    unsigned before;
    unsigned after;
};

static unsigned word_at(const unsigned char *data)
{
    return (unsigned)data[0] | ((unsigned)data[1] << 8);
}

static FILE *open_program(const char *name, char *path)
{
    const char *base;
    const char *slash;
    FILE *file;
    char found[128];
    unsigned attempt;

    strncpy(path, name, 123);
    path[123] = 0;
    base = path;
    slash = strrchr(path, '\\');
    if (slash)
        base = slash + 1;
    slash = strrchr(base, '/');
    if (slash)
        base = slash + 1;
    for (attempt = 0; attempt < 3; ++attempt) {
        if (attempt) {
            if (strchr(base, '.'))
                break;
            strcat(path, attempt == 1 ? ".COM" : ".EXE");
        }
        file = fopen(path, "rb");
        if (file)
            return file;
        found[0] = 0;
        _searchenv(path, "PATH", found);
        if (found[0]) {
            strcpy(path, found);
            file = fopen(path, "rb");
            if (file)
                return file;
        }
        if (attempt)
            path[strlen(path) - 4] = 0;
    }
    return NULL;
}

static unsigned executable_paragraphs(const char *name)
{
    unsigned char header[28];
    char path[128];
    FILE *file;
    long length;
    unsigned long bytes;
    unsigned long paragraphs;
    unsigned image;
    unsigned stack;

    file = open_program(name, path);
    if (!file)
        return 0;
    if (fread(header, 1, sizeof(header), file) != sizeof(header) ||
        fseek(file, 0L, SEEK_END) || (length = ftell(file)) < 0) {
        fclose(file);
        return 0;
    }
    fclose(file);
    bytes = (unsigned long)length;
    if (header[0] != 'M' || header[1] != 'Z') {
        /* DOS gives COM programs all available memory before they can resize
         * themselves, so they cannot be safely pinned to a finite region. */
        paragraphs = 65535UL;
    } else {
        unsigned last = word_at(header + 2);
        unsigned pages = word_at(header + 4);
        unsigned header_paragraphs = word_at(header + 8);
        unsigned minalloc = word_at(header + 10);
        unsigned maxalloc = word_at(header + 12);
        unsigned ss = word_at(header + 14);
        unsigned sp = word_at(header + 16);
        unsigned long mz_bytes = pages ? (unsigned long)(pages - 1U) * 512UL +
                                 (last ? last : 512U) : bytes;
        if (mz_bytes > bytes)
            mz_bytes = bytes;
        if (mz_bytes < (unsigned long)header_paragraphs * 16UL)
            return 0;
        if (maxalloc == 0xffffU)
            return 65535U;
        image = (unsigned)((mz_bytes - (unsigned long)header_paragraphs * 16UL +
                            15UL) / 16UL);
        stack = ss + (sp + 15U) / 16U;
        if (image + minalloc < stack)
            minalloc = stack - image;
        paragraphs = (unsigned long)image + minalloc + 16UL +
                     EXEC_OVERHEAD_PARAGRAPHS;
    }
    return paragraphs > 65535UL ? 65535U : (unsigned)paragraphs;
}

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
    struct size_record load_record;
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
    load_record.magic = SIZER_LOAD_MAGIC;
    load_record.index = index;
    load_record.before = executable_paragraphs(argv[3]);
    load_record.after = 0;
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
    if (fwrite(&record, sizeof(record), 1, file) != 1 ||
        fwrite(&load_record, sizeof(load_record), 1, file) != 1 || fclose(file)) {
        fputs("SIZER cannot record the resident-memory measurement.\n", stderr);
        return 1;
    }
    return result;
}
