#include <ctype.h>
#include <dos.h>
#include <io.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ALL_ATTR (_A_RDONLY | _A_HIDDEN | _A_SYSTEM | _A_SUBDIR | _A_ARCH)
#define PATH_SIZE 132

static int overwrite = -1;

static void usage(void)
{
    puts("Moves files and renames files and directories.");
    puts("MOVE [/Y | /-Y] source [source ...] target");
}

static int dos_mkdir(const char *path)
{
    union REGS inregs, outregs;
    struct SREGS segregs;
    const char far *p = (const char far *)path;
    segread(&segregs);
    inregs.h.ah = 0x39;
    inregs.x.dx = FP_OFF(p);
    segregs.ds = FP_SEG(p);
    intdosx(&inregs, &outregs, &segregs);
    return outregs.x.cflag ? 1 : 0;
}

static int dos_rmdir(const char *path)
{
    union REGS inregs, outregs;
    struct SREGS segregs;
    const char far *p = (const char far *)path;
    segread(&segregs);
    inregs.h.ah = 0x3a;
    inregs.x.dx = FP_OFF(p);
    segregs.ds = FP_SEG(p);
    intdosx(&inregs, &outregs, &segregs);
    return outregs.x.cflag ? 1 : 0;
}

static const char *base_name(const char *path)
{
    const char *a = strrchr(path, '\\');
    const char *b = strrchr(path, '/');
    const char *p = a > b ? a : b;
    if (!p && path[0] && path[1] == ':')
        p = path + 1;
    return p ? p + 1 : path;
}

static int join_path(char *out, const char *dir, const char *name)
{
    unsigned length = strlen(dir);
    if (length + strlen(name) + 2 > PATH_SIZE)
        return 1;
    strcpy(out, dir);
    if (length && out[length - 1] != '\\' && out[length - 1] != '/')
        strcat(out, "\\");
    strcat(out, name);
    return 0;
}

static unsigned path_drive(const char *path)
{
    unsigned drive;
    if (path[0] && path[1] == ':')
        return toupper((unsigned char)path[0]) - 'A' + 1;
    _dos_getdrive(&drive);
    return drive;
}

static int ask_overwrite(const char *path)
{
    int c;
    if (overwrite >= 0)
        return overwrite;
    printf("Overwrite %s? (Yes/No/All): ", path);
    fflush(stdout);
    do c = getchar(); while (c == '\r' || c == '\n');
    puts("");
    if (c == 'a' || c == 'A') {
        overwrite = 1;
        return 1;
    }
    return c == 'y' || c == 'Y';
}

static int remove_existing(const char *path, unsigned attr)
{
    if (!ask_overwrite(path))
        return 2;
    _dos_setfileattr(path, 0);
    if (attr & _A_SUBDIR)
        return dos_rmdir(path);
    return remove(path);
}

static int copy_file(const char *source, const char *target, unsigned attr)
{
    FILE *in, *out;
    char buffer[8192];
    size_t count;
    unsigned target_attr;

    if (!_dos_getfileattr(target, &target_attr)) {
        int removed = remove_existing(target, target_attr);
        if (removed)
            return removed == 2 ? 0 : 1;
    }
    in = fopen(source, "rb");
    if (!in)
        return 1;
    out = fopen(target, "wb");
    if (!out) {
        fclose(in);
        return 1;
    }
    while ((count = fread(buffer, 1, sizeof(buffer), in)) != 0)
        if (fwrite(buffer, 1, count, out) != count)
            break;
    if (ferror(in) || ferror(out) || fclose(out)) {
        fclose(in);
        remove(target);
        return 1;
    }
    fclose(in);
    _dos_setfileattr(target, attr & ~_A_SUBDIR);
    _dos_setfileattr(source, 0);
    if (remove(source))
        return 1;
    return 0;
}

static int move_path(const char *source, const char *target);

static int copy_directory(const char *source, const char *target, unsigned attr)
{
    struct find_t find;
    char scan[PATH_SIZE], from[PATH_SIZE], to[PATH_SIZE];
    unsigned target_attr;
    int errors = 0;

    if (!_dos_getfileattr(target, &target_attr)) {
        if (!(target_attr & _A_SUBDIR))
            return 1;
    } else if (dos_mkdir(target)) {
        return 1;
    }
    if (join_path(scan, source, "*.*"))
        return 1;
    if (!_dos_findfirst(scan, ALL_ATTR, &find)) {
        do {
            if (!strcmp(find.name, ".") || !strcmp(find.name, ".."))
                continue;
            if (join_path(from, source, find.name) || join_path(to, target, find.name)) {
                errors = 1;
                continue;
            }
            errors |= move_path(from, to);
        } while (!_dos_findnext(&find));
    }
    if (!errors) {
        _dos_setfileattr(source, 0);
        if (dos_rmdir(source))
            errors = 1;
        else
            _dos_setfileattr(target, attr & ~_A_SUBDIR);
    }
    return errors;
}

static int move_path(const char *source, const char *target)
{
    unsigned source_attr, target_attr;
    char actual[PATH_SIZE];

    if (_dos_getfileattr(source, &source_attr))
        return 1;
    strcpy(actual, target);
    if (!_dos_getfileattr(target, &target_attr) && (target_attr & _A_SUBDIR)) {
        if (join_path(actual, target, base_name(source)))
            return 1;
    }
    if (path_drive(source) == path_drive(actual)) {
        if (!_dos_getfileattr(actual, &target_attr)) {
            int removed = remove_existing(actual, target_attr);
            if (removed)
                return removed == 2 ? 0 : 1;
        }
        _dos_setfileattr(source, source_attr & ~_A_RDONLY);
        if (!rename(source, actual)) {
            _dos_setfileattr(actual, source_attr);
            return 0;
        }
        _dos_setfileattr(source, source_attr);
    }
    if (source_attr & _A_SUBDIR)
        return copy_directory(source, actual, source_attr);
    return copy_file(source, actual, source_attr);
}

static int move_spec(const char *spec, const char *target, int many)
{
    struct find_t find;
    char prefix[PATH_SIZE], source[PATH_SIZE];
    const char *slash;
    unsigned target_attr, length;
    int found = 0, errors = 0;

    if (!strchr(spec, '*') && !strchr(spec, '?'))
        return move_path(spec, target);
    if (_dos_getfileattr(target, &target_attr) || !(target_attr & _A_SUBDIR)) {
        fputs("MOVE: wildcard or multiple sources require a directory target.\n", stderr);
        return 1;
    }
    slash = strrchr(spec, '\\');
    if (!slash)
        slash = strrchr(spec, '/');
    length = slash ? (unsigned)(slash - spec + 1) : 0;
    memcpy(prefix, spec, length);
    prefix[length] = 0;
    if (!_dos_findfirst(spec, ALL_ATTR, &find)) {
        do {
            if (!strcmp(find.name, ".") || !strcmp(find.name, ".."))
                continue;
            strcpy(source, prefix);
            strcat(source, find.name);
            found = 1;
            errors |= move_path(source, target);
        } while (!_dos_findnext(&find));
    }
    if (!found)
        errors = 1;
    (void)many;
    return errors;
}

static void apply_copycmd(void)
{
    const char *value = getenv("COPYCMD");
    if (!value)
        return;
    if (strstr(value, "/-Y") || strstr(value, "/-y"))
        overwrite = -1;
    else if (strstr(value, "/Y") || strstr(value, "/y"))
        overwrite = 1;
}

int main(int argc, char **argv)
{
    char *operands[64];
    int count = 0, i, errors = 0;
    unsigned attr;

    apply_copycmd();
    for (i = 1; i < argc; ++i) {
        if (!stricmp(argv[i],"/?")) {
            usage();
            return 0;
        }
        if (!stricmp(argv[i],"/Y")) {
            overwrite = 1;
            continue;
        }
        if (!stricmp(argv[i],"/-Y")) {
            overwrite = -1;
            continue;
        }
        if (argv[i][0] == '/') {
            fputs("MOVE: invalid switch.\n", stderr);
            return 1;
        }
        if (count == 64) {
            fputs("MOVE: too many files.\n", stderr);
            return 1;
        }
        operands[count++] = argv[i];
    }
    if (count < 2) {
        usage();
        return 1;
    }
    if (count > 2 && (_dos_getfileattr(operands[count - 1], &attr) ||
                      !(attr & _A_SUBDIR))) {
        fputs("MOVE: multiple sources require a directory target.\n", stderr);
        return 1;
    }
    for (i = 0; i < count - 1; ++i) {
        if (move_spec(operands[i], operands[count - 1], count > 2)) {
            fprintf(stderr, "MOVE: cannot move %s.\n", operands[i]);
            errors = 1;
        }
    }
    return errors;
}
