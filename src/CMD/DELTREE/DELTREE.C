#include <dos.h>
#include <io.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ALL_ATTR (_A_RDONLY | _A_HIDDEN | _A_SYSTEM | _A_SUBDIR | _A_ARCH)

static int force_yes;

static int remove_dir(const char *path)
{
    union REGS inregs, outregs;
    struct SREGS segregs;
    const char far *far_path = (const char far *)path;
    segread(&segregs);
    inregs.h.ah = 0x3a;
    inregs.x.dx = FP_OFF(far_path);
    segregs.ds = FP_SEG(far_path);
    intdosx(&inregs, &outregs, &segregs);
    return outregs.x.cflag ? 1 : 0;
}

static void usage(void)
{
    puts("Deletes a directory and all files and subdirectories in it.");
    puts("DELTREE [/Y] [drive:]path [[drive:]path ...]");
}

static int confirm(const char *path)
{
    int c;
    if (force_yes)
        return 1;
    printf("Delete %s and all its subdirectories? [yn] ", path);
    fflush(stdout);
    do c = getchar(); while (c == '\r' || c == '\n');
    puts("");
    return c == 'y' || c == 'Y';
}

static int delete_one(const char *path)
{
    struct find_t find;
    char scan[132], child[132];
    unsigned attr;
    int errors = 0;

    if (_dos_getfileattr(path, &attr)) {
        fprintf(stderr, "DELTREE: cannot find %s.\n", path);
        return 1;
    }
    _dos_setfileattr(path, 0);
    if (!(attr & _A_SUBDIR)) {
        if (remove(path)) {
            fprintf(stderr, "DELTREE: cannot delete %s.\n", path);
            return 1;
        }
        return 0;
    }
    if (strlen(path) + 5 >= sizeof(scan)) {
        fputs("DELTREE: path is too long.\n", stderr);
        return 1;
    }
    strcpy(scan, path);
    if (scan[strlen(scan) - 1] != '\\' && scan[strlen(scan) - 1] != '/')
        strcat(scan, "\\");
    strcat(scan, "*.*");
    if (!_dos_findfirst(scan, ALL_ATTR, &find)) {
        do {
            if (!strcmp(find.name, ".") || !strcmp(find.name, ".."))
                continue;
            strcpy(child, path);
            if (child[strlen(child) - 1] != '\\' && child[strlen(child) - 1] != '/')
                strcat(child, "\\");
            strcat(child, find.name);
            errors |= delete_one(child);
        } while (!_dos_findnext(&find));
    }
    _dos_setfileattr(path, 0);
    if (remove_dir(path)) {
        fprintf(stderr, "DELTREE: cannot remove %s.\n", path);
        errors = 1;
    }
    return errors;
}

static int delete_spec(const char *spec)
{
    struct find_t find;
    char prefix[132], path[132];
    const char *slash;
    int errors = 0, found = 0;

    if (!strchr(spec, '*') && !strchr(spec, '?'))
        return confirm(spec) ? delete_one(spec) : 0;
    slash = strrchr(spec, '\\');
    if (!slash)
        slash = strrchr(spec, '/');
    if (slash) {
        unsigned length = slash - spec + 1;
        if (length >= sizeof(prefix))
            return 1;
        memcpy(prefix, spec, length);
        prefix[length] = 0;
    } else {
        prefix[0] = 0;
    }
    if (!_dos_findfirst(spec, ALL_ATTR, &find)) {
        do {
            if (!strcmp(find.name, ".") || !strcmp(find.name, ".."))
                continue;
            strcpy(path, prefix);
            strcat(path, find.name);
            found = 1;
            if (confirm(path))
                errors |= delete_one(path);
        } while (!_dos_findnext(&find));
    }
    if (!found) {
        fprintf(stderr, "DELTREE: cannot find %s.\n", spec);
        return 1;
    }
    return errors;
}

int main(int argc, char **argv)
{
    int i, operands = 0, errors = 0;
    for (i = 1; i < argc; ++i) {
        if (!stricmp(argv[i],"/?")) {
            usage();
            return 0;
        }
        if (!stricmp(argv[i],"/Y")) {
            force_yes = 1;
            continue;
        }
        if (argv[i][0] == '/') {
            fputs("DELTREE: invalid switch.\n", stderr);
            return 1;
        }
        ++operands;
        errors |= delete_spec(argv[i]);
    }
    if (!operands) {
        usage();
        return 1;
    }
    return errors ? 1 : 0;
}
