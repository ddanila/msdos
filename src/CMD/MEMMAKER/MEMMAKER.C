#include <ctype.h>
#include <conio.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SWAP_SWITCH "/SWAP:"
#define WINDOW_SWITCH "/W:"
#define SIZER_MAGIC 0x5a53
#define SIZER_LOAD_MAGIC 0x4c53
#define DRIVER_MAGIC 0x4453
#define MAX_MEASUREMENTS 64

struct size_record {
    unsigned magic;
    unsigned index;
    unsigned before;
    unsigned after;
};

struct options {
    int monochrome;
    int batch;
    int session;
    int final;
    int custom;
    unsigned high_drivers;
    unsigned high_tsrs;
    int no_token_ring;
    int undo;
    int swap_set;
    unsigned drive;
    unsigned reserve_one;
    unsigned reserve_two;
    int expanded_memory;
    int monochrome_region;
};

static unsigned char file_buffer[2048];
static unsigned measured_umb_k;
static unsigned measured_conventional_k;
static unsigned baseline_umb_k;
static unsigned baseline_conventional_k;
static unsigned config_umb_k;
static unsigned config_conventional_k;
static unsigned selected_high_drivers;
static unsigned selected_high_tsrs;
static unsigned eligible_high_drivers;
static unsigned eligible_high_tsrs;
static int windows_ini_found;
static int windows_version;
static unsigned measured_tsr_count;
static unsigned measured_tsr_paragraphs;
static unsigned measured_driver_count;
static unsigned measured_driver_paragraphs;
static unsigned optimized_tsr_count;
static unsigned optimized_tsr_paragraphs;
static char injected_point[16];
static unsigned tsr_sizes[MAX_MEASUREMENTS];
static unsigned tsr_load_sizes[MAX_MEASUREMENTS];
static unsigned char tsr_selected[MAX_MEASUREMENTS];
static unsigned char tsr_regions[MAX_MEASUREMENTS];
static unsigned umb_region_sizes[16];

#define WINDOWS_UNKNOWN 0
#define WINDOWS_30      30
#define WINDOWS_31      31

static int ask_yes_no(const char *prompt);

static unsigned umb_region_size(unsigned region)
{
    union REGS regs;
    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5809;
    regs.x.bx = region;
    regs.x.cx = 0x4d55;
    regs.x.si = 0x2142;
    regs.x.di = 0xa55a;
    intdos(&regs, &regs);
    return regs.x.cflag ? 0 : regs.x.ax;
}

static unsigned probe_largest_block(unsigned strategy, unsigned link_umbs)
{
    union REGS regs;
    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5801;
    regs.x.bx = strategy;
    intdos(&regs, &regs);
    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5803;
    regs.x.bx = link_umbs;
    intdos(&regs, &regs);
    memset(&regs, 0, sizeof(regs));
    regs.h.ah = 0x48;
    regs.x.bx = 0xffff;
    intdos(&regs, &regs);
    return regs.x.bx;
}

static void measure_memory(void)
{
    union REGS regs;
    unsigned saved_strategy;
    unsigned saved_link;
    unsigned paragraphs;

    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5800;
    intdos(&regs, &regs);
    saved_strategy = regs.x.ax;
    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5802;
    intdos(&regs, &regs);
    saved_link = regs.x.ax;

    paragraphs = probe_largest_block(0x40, 1); /* high memory only */
    measured_umb_k = paragraphs / 64;
    paragraphs = probe_largest_block(0, 0);    /* conventional only */
    measured_conventional_k = paragraphs / 64;

    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5801;
    regs.x.bx = saved_strategy;
    intdos(&regs, &regs);
    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5803;
    regs.x.bx = saved_link;
    intdos(&regs, &regs);
}

static int injected_failure(const char *point)
{
    return injected_point[0] && !stricmp(injected_point, point);
}

static int switch_is(const char *left, const char *right)
{
    while (*left && *right) {
        if (toupper((unsigned char)*left) !=
            toupper((unsigned char)*right))
            return 0;
        ++left;
        ++right;
    }
    return !*left && !*right;
}

static int starts_with(const char *line, const char *prefix)
{
    while (*line == ' ' || *line == '\t' || *line == '@')
        ++line;
    while (*prefix) {
        if (toupper((unsigned char)*line) != *prefix)
            return 0;
        ++line;
        ++prefix;
    }
    return 1;
}

static unsigned far_word(const unsigned char far *p)
{
    return p[0] | ((unsigned)p[1] << 8);
}

static void driver_name(const char *line, char name[9])
{
    const char *start = strchr(line, '=');
    const char *base;
    unsigned length = 0;
    memset(name, ' ', 8);
    name[8] = 0;
    if (!start)
        return;
    ++start;
    while (*start == ' ' || *start == '\t')
        ++start;
    base = start;
    while (*start && *start != ' ' && *start != '\t' &&
           *start != '\r' && *start != '\n') {
        if (*start == '\\' || *start == '/' || *start == ':')
            base = start + 1;
        ++start;
    }
    while (base < start && *base != '.' && length < 8)
        name[length++] = (char)toupper((unsigned char)*base++);
}

static int devmark_size(const char name[9], unsigned *paragraphs)
{
    union REGS regs;
    struct SREGS segregs;
    const unsigned char far *lists;
    unsigned arena_segment;
    unsigned arenas = 0;
    unsigned saved_link;
    int found = 0;
    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5802;
    intdos(&regs, &regs);
    saved_link = regs.x.ax;
    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5803;
    regs.x.bx = 1;
    intdos(&regs, &regs);
    memset(&regs, 0, sizeof(regs));
    memset(&segregs, 0, sizeof(segregs));
    regs.h.ah = 0x52;
    intdosx(&regs, &regs, &segregs);
    lists = (const unsigned char far *)MK_FP(segregs.es, regs.x.bx);
    arena_segment = far_word(lists - 2);
    while (arena_segment && arena_segment < 0xffff && arenas++ < 512) {
        const unsigned char far *arena =
            (const unsigned char far *)MK_FP(arena_segment, 0);
        unsigned size = far_word(arena + 3);
        if (far_word(arena + 1) == 8) {
            unsigned cursor = arena_segment + 1;
            unsigned limit = cursor + size;
            unsigned entries = 0;
            while (cursor < limit && entries++ < 256) {
                const unsigned char far *mark =
                    (const unsigned char far *)MK_FP(cursor, 0);
                unsigned mark_size = far_word(mark + 3);
                unsigned i;
                if (mark[0] == 'D') {
                    for (i = 0; i < 8; ++i)
                        if ((char)toupper(mark[8 + i]) != name[i])
                            break;
                    if (i == 8) {
                        *paragraphs = mark_size;
                        found = 1;
                        break;
                    }
                }
                if (!mark_size || cursor + mark_size + 1 <= cursor)
                    break;
                cursor += mark_size + 1;
            }
        }
        if (found)
            break;
        if (arena[0] == 'Z' || !size || arena_segment + size + 1 <= arena_segment)
            break;
        arena_segment += size + 1;
    }
    memset(&regs, 0, sizeof(regs));
    regs.x.ax = 0x5803;
    regs.x.bx = saved_link;
    intdos(&regs, &regs);
    return found;
}

static int record_driver_sizes(const char *config, const char *sizes_path)
{
    char line[256];
    char name[9];
    unsigned index = 0;
    FILE *input = fopen(config, "r");
    FILE *output;
    if (!input)
        return 1;
    output = fopen(sizes_path, "ab");
    if (!output) {
        fclose(input);
        return 1;
    }
    while (fgets(line, sizeof(line), input)) {
        const char *body = line;
        struct size_record record;
        unsigned paragraphs;
        while (*body == ' ' || *body == '\t')
            ++body;
        if (!starts_with(body, "DEVICEHIGH="))
            continue;
        driver_name(body, name);
        if (index < MAX_MEASUREMENTS && devmark_size(name, &paragraphs)) {
            record.magic = DRIVER_MAGIC;
            record.index = index;
            record.before = paragraphs;
            record.after = 0;
            if (fwrite(&record, sizeof(record), 1, output) != 1) {
                fclose(input);
                fclose(output);
                return 1;
            }
        }
        ++index;
    }
    fclose(input);
    return fclose(output) != 0;
}

static int contains_name(const char *line, const char *name)
{
    size_t length = strlen(name);
    while (*line) {
        if (!strnicmp(line, name, length))
            return 1;
        ++line;
    }
    return 0;
}

static void usage(void)
{
    puts("Optimizes conventional memory by loading drivers and TSRs high.");
    puts("Syntax: MEMMAKER [/B] [/BATCH|/CUSTOM] [/SESSION] [/FINAL] [/SWAP:drive]");
    puts("                [/T] [/UNDO] [/W:size1,size2]");
}

static int parse_number(const char **text, unsigned *value)
{
    unsigned long number = 0;
    const char *p = *text;
    if (!isdigit((unsigned char)*p))
        return 1;
    while (isdigit((unsigned char)*p)) {
        number = number * 10UL + (unsigned)(*p++ - '0');
        if (number > 65535UL)
            return 1;
    }
    *text = p;
    *value = (unsigned)number;
    return 0;
}

static int parse_options(int argc, char **argv, struct options *options)
{
    int index;
    memset(options, 0, sizeof(*options));
    options->high_drivers = 1;
    options->high_tsrs = 1;
    options->expanded_memory = 1;
    for (index = 1; index < argc; ++index) {
        char *argument = argv[index];
        char *name;
        while (*argument && isspace((unsigned char)*argument))
            ++argument;
        if (!argument[0])
            continue;
        if (argument[0] != '/' && argument[0] != '-') {
            fprintf(stderr, "Invalid parameter - %s\n", argument);
            return 1;
        }
        name = argument + 1;
        if (switch_is(name, "?")) {
            usage();
            exit(0);
        } else if (switch_is(name, "B")) options->monochrome = 1;
        else if (switch_is(name, "BATCH")) options->batch = 1;
        else if (switch_is(name, "SESSION")) options->session = 1;
        else if (switch_is(name, "FINAL")) options->final = 1;
        else if (switch_is(name, "CUSTOM")) options->custom = 1;
        else if (switch_is(name, "T")) options->no_token_ring = 1;
        else if (switch_is(name, "UNDO")) options->undo = 1;
        else if (!strnicmp(name, SWAP_SWITCH + 1, 5) && isalpha(name[5]) &&
                 !name[6]) {
            options->drive = toupper((unsigned char)name[5]) - 'A';
            options->swap_set = 1;
        } else if (!strnicmp(name, WINDOW_SWITCH + 1, 2)) {
            const char *value = name + 2;
            if (parse_number(&value, &options->reserve_one) ||
                *value++ != ',' ||
                parse_number(&value, &options->reserve_two) || *value) {
                fputs("Invalid /W reserve sizes.\n", stderr);
                return 1;
            }
        } else {
            fprintf(stderr, "Invalid switch - %s\n", argument);
            return 1;
        }
    }
    if (options->undo && (options->batch || options->session || options->final)) {
        fputs("/UNDO cannot be combined with /BATCH, /SESSION, or /FINAL.\n", stderr);
        return 1;
    }
    if (options->batch && options->custom) {
        fputs("/BATCH and /CUSTOM cannot be combined.\n", stderr);
        return 1;
    }
    return 0;
}

static void make_path(char *path, unsigned drive, const char *name)
{
    path[0] = (char)('A' + drive);
    path[1] = ':';
    path[2] = '\\';
    strcpy(path + 3, name);
}

static int detect_windows_version(const char *directory)
{
    char path[128];
    char window[5] = { 0, 0, 0, 0, 0 };
    size_t length = strlen(directory);
    size_t count, index;
    int saw_30 = 0;
    FILE *file;
    if (length > 118)
        return WINDOWS_UNKNOWN;
    strcpy(path, directory);
    if (length && path[length - 1] != '\\' && path[length - 1] != '/')
        path[length++] = '\\';
    strcpy(path + length, "WIN.COM");
    file = fopen(path, "rb");
    if (!file)
        return WINDOWS_UNKNOWN;
    while ((count = fread(file_buffer, 1, sizeof(file_buffer), file)) != 0) {
        for (index = 0; index < count; ++index) {
            window[0] = window[1];
            window[1] = window[2];
            window[2] = window[3];
            window[3] = (char)file_buffer[index];
            if (!memcmp(window, "3.10", 4) ||
                !memcmp(window + 1, "3.1", 3)) {
                fclose(file);
                return WINDOWS_31;
            }
            if (!memcmp(window, "3.00", 4) ||
                !memcmp(window + 1, "3.0", 3))
                saw_30 = 1;
        }
    }
    fclose(file);
    return saw_30 ? WINDOWS_30 : WINDOWS_UNKNOWN;
}

static int windows_paths(char *system_ini, char *system_backup)
{
    const char *directory = getenv("WINDIR");
    size_t length;
    FILE *file;
    if (!directory || !*directory)
        return 0;
    windows_version = detect_windows_version(directory);
    length = strlen(directory);
    if (length > 110)
        return 0;
    strcpy(system_ini, directory);
    if (system_ini[length - 1] != '\\' && system_ini[length - 1] != '/')
        system_ini[length++] = '\\';
    strcpy(system_ini + length, "SYSTEM.INI");
    file = fopen(system_ini, "rb");
    if (!file)
        return 0;
    fclose(file);
    strcpy(system_backup, directory);
    length = strlen(system_backup);
    if (system_backup[length - 1] != '\\' && system_backup[length - 1] != '/')
        system_backup[length++] = '\\';
    strcpy(system_backup + length, "SYSTEM.UMB");
    return 1;
}

static int copy_file(const char *source, const char *target)
{
    size_t count;
    FILE *input = fopen(source, "rb");
    FILE *output;
    if (!input)
        return 1;
    output = fopen(target, "wb");
    if (!output) {
        fclose(input);
        return 1;
    }
    while ((count = fread(file_buffer, 1, sizeof(file_buffer), input)) != 0)
        if (fwrite(file_buffer, 1, count, output) != count) {
            fclose(input);
            fclose(output);
            return 1;
        }
    if (ferror(input) || fclose(output)) {
        fclose(input);
        return 1;
    }
    fclose(input);
    return 0;
}

static int ini_section_is(const char *line, const char *name)
{
    const char *end;
    size_t length;
    while (*line == ' ' || *line == '\t')
        ++line;
    if (*line++ != '[')
        return 0;
    end = strchr(line, ']');
    if (!end)
        return 0;
    length = (size_t)(end - line);
    return strlen(name) == length && !strnicmp(line, name, length);
}

static int ini_key_is(const char *line, const char *name)
{
    size_t length = strlen(name);
    while (*line == ' ' || *line == '\t')
        ++line;
    if (strnicmp(line, name, length))
        return 0;
    line += length;
    while (*line == ' ' || *line == '\t')
        ++line;
    return *line == '=';
}

static void write_windows_30_settings(FILE *output, int *rom, int *exclude,
                                      int *include, int *dual, int *noemm,
                                      const struct options *options)
{
    if (!*rom) {
        fputs("SYSTEMROMBREAKPOINT=FALSE\n", output);
        *rom = 1;
    }
    if (!*exclude) {
        fputs("EMMEXCLUDE=A000-FFFF\n", output);
        *exclude = 1;
    }
    if (options->monochrome_region && !*include) {
        fputs("EMMINCLUDE=B000-B7FF\n", output);
        *include = 1;
    }
    if (options->monochrome_region && !*dual) {
        fputs("DUALDISPLAY=TRUE\n", output);
        *dual = 1;
    }
    if (!options->expanded_memory && !*noemm) {
        fputs("NOEMMDRIVER=TRUE\n", output);
        *noemm = 1;
    }
}

static int transform_system_ini(const char *source, const char *temporary,
                                const struct options *options)
{
    FILE *input = fopen(source, "r");
    FILE *output;
    char line[256];
    int in_386enh = 0;
    int found_386enh = 0;
    int wrote_rom = 0;
    int wrote_exclude = 0;
    int wrote_include = 0;
    int wrote_dual = 0;
    int wrote_noemm = 0;
    if (!input)
        return 1;
    output = fopen(temporary, "w");
    if (!output) {
        fclose(input);
        return 1;
    }
    while (fgets(line, sizeof(line), input)) {
        if (!strchr(line, '\n') && !feof(input)) {
            fclose(input);
            fclose(output);
            remove(temporary);
            return 1;
        }
        if (line[0] == '[' || line[0] == ' ' || line[0] == '\t') {
            int is_386enh = ini_section_is(line, "386Enh");
            if (in_386enh && !is_386enh && strchr(line, '['))
                write_windows_30_settings(output, &wrote_rom, &wrote_exclude,
                                          &wrote_include, &wrote_dual,
                                          &wrote_noemm, options);
            if (strchr(line, '['))
                in_386enh = is_386enh;
            if (is_386enh)
                found_386enh = 1;
        }
        if (in_386enh && ini_key_is(line, "SYSTEMROMBREAKPOINT")) {
            if (!wrote_rom) {
                fputs("SYSTEMROMBREAKPOINT=FALSE\n", output);
                wrote_rom = 1;
            }
        } else if (in_386enh && ini_key_is(line, "EMMEXCLUDE")) {
            if (!wrote_exclude) {
                fputs("EMMEXCLUDE=A000-FFFF\n", output);
                wrote_exclude = 1;
            }
        } else if (in_386enh && ini_key_is(line, "EMMINCLUDE")) {
            fputs(line, output);
            if (contains_name(line, "B000-B7FF"))
                wrote_include = 1;
        } else if (in_386enh && ini_key_is(line, "DUALDISPLAY")) {
            if (options->monochrome_region && !wrote_dual) {
                fputs("DUALDISPLAY=TRUE\n", output);
                wrote_dual = 1;
            }
        } else if (in_386enh && ini_key_is(line, "NOEMMDRIVER")) {
            if (!options->expanded_memory && !wrote_noemm) {
                fputs("NOEMMDRIVER=TRUE\n", output);
                wrote_noemm = 1;
            }
        } else {
            fputs(line, output);
        }
    }
    if (in_386enh)
        write_windows_30_settings(output, &wrote_rom, &wrote_exclude,
                                  &wrote_include, &wrote_dual,
                                  &wrote_noemm, options);
    else if (!found_386enh) {
        fputs("[386Enh]\n", output);
        write_windows_30_settings(output, &wrote_rom, &wrote_exclude,
                                  &wrote_include, &wrote_dual,
                                  &wrote_noemm, options);
    }
    fclose(input);
    if (fclose(output)) {
        remove(temporary);
        return 1;
    }
    return 0;
}

static int replace_file(const char *temporary, const char *target)
{
    remove(target);
    return rename(temporary, target) != 0;
}

static int line_is_tsr(const char *line)
{
    static const char *names[] = {
        "APPEND", "DOSKEY", "FASTOPEN", "KEYB", "MODE", "MOUSE",
        "MSCDEX", "NLSFUNC", "PRINT", "SHARE", "SMARTDRV", 0
    };
    char command[16];
    unsigned length = 0;
    unsigned index;
    while (*line == ' ' || *line == '\t' || *line == '@')
        ++line;
    while (*line && *line != ' ' && *line != '\t' && *line != '.' &&
           length + 1 < sizeof(command))
        command[length++] = (char)toupper((unsigned char)*line++);
    command[length] = 0;
    for (index = 0; names[index]; ++index)
        if (!strcmp(command, names[index]))
            return 1;
    return 0;
}

static int line_is_high_driver(const char *line)
{
    /* Keep this list conservative until the measurement pass can prove an
       arbitrary driver's upper-memory behavior across a reboot. */
    static const char *names[] = { "DRIVER.SYS", 0 };
    unsigned index;
    for (index = 0; names[index]; ++index)
        if (contains_name(line, names[index]))
            return 1;
    return 0;
}

static int inspect_config(FILE *input, int *has_himem, int *has_emm)
{
    char line[256];
    *has_himem = *has_emm = 0;
    while (fgets(line, sizeof(line), input)) {
        if (contains_name(line, "HIMEM.SYS"))
            *has_himem = 1;
        if (contains_name(line, "EMM386.EXE"))
            *has_emm = 1;
        if (!strchr(line, '\n') && !feof(input))
            return 1;
    }
    rewind(input);
    return 0;
}

#define CONFIG_OTHER      0
#define CONFIG_HIMEM      1
#define CONFIG_EMM386     2
#define CONFIG_BUFFERS    3
#define CONFIG_FILES      4
#define CONFIG_DOS        5
#define CONFIG_LASTDRIVE  6
#define CONFIG_FCBS       7

static int config_line_class(const char *line)
{
    const char *body = line;
    while (*body == ' ' || *body == '\t')
        ++body;
    if ((starts_with(body, "DEVICE=") ||
         starts_with(body, "DEVICEHIGH=")) &&
        contains_name(body, "HIMEM.SYS"))
        return CONFIG_HIMEM;
    if ((starts_with(body, "DEVICE=") ||
         starts_with(body, "DEVICEHIGH=")) &&
        contains_name(body, "EMM386.EXE"))
        return CONFIG_EMM386;
    if (starts_with(body, "BUFFERS=") || starts_with(body, "BUFFERSHIGH="))
        return CONFIG_BUFFERS;
    if (starts_with(body, "FILES="))
        return CONFIG_FILES;
    if (starts_with(body, "DOS="))
        return CONFIG_DOS;
    if (starts_with(body, "LASTDRIVE="))
        return CONFIG_LASTDRIVE;
    if (starts_with(body, "FCBS="))
        return CONFIG_FCBS;
    return CONFIG_OTHER;
}

static int copy_config_class(FILE *input, FILE *output, int wanted)
{
    char line[256];
    while (fgets(line, sizeof(line), input)) {
        if (!strchr(line, '\n') && !feof(input))
            return 1;
        if (config_line_class(line) == wanted)
            fputs(line, output);
    }
    rewind(input);
    return 0;
}

static char *find_text(char *text, const char *needle)
{
    size_t length = strlen(needle);
    while (*text) {
        if (!strnicmp(text, needle, length))
            return text;
        ++text;
    }
    return 0;
}

static int copy_config_emm386(FILE *input, FILE *output,
                              const struct options *options)
{
    char line[256];
    while (fgets(line, sizeof(line), input)) {
        char *name, *tail, *p;
        char token[64];
        int has_mono = 0;
        if (!strchr(line, '\n') && !feof(input))
            return 1;
        if (config_line_class(line) != CONFIG_EMM386)
            continue;
        name = find_text(line, "EMM386.EXE");
        if (!name)
            return 1;
        tail = name + strlen("EMM386.EXE");
        *tail = 0;
        fputs(line, output);
        p = tail + 1;
        while (*p) {
            unsigned length = 0;
            while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n')
                ++p;
            if (!*p)
                break;
            while (*p && *p != ' ' && *p != '\t' && *p != '\r' &&
                   *p != '\n' && length + 1 < sizeof(token))
                token[length++] = *p++;
            token[length] = 0;
            while (*p && *p != ' ' && *p != '\t' && *p != '\r' &&
                   *p != '\n')
                ++p;
            if (stricmp(token, "RAM") && stricmp(token, "NOEMS")) {
                if (!stricmp(token, "I=B000-B7FF"))
                    has_mono = 1;
                if (stricmp(token, "I=B000-B7FF") ||
                    options->monochrome_region)
                    fprintf(output, " %s", token);
            }
        }
        fprintf(output, " %s", options->expanded_memory ? "RAM" : "NOEMS");
        if (options->monochrome_region && !has_mono)
            fputs(" I=B000-B7FF", output);
        fputc('\n', output);
    }
    rewind(input);
    return 0;
}

static int transform_config(unsigned drive, const struct options *options,
                            const char *program,
                            const char *source, const char *temporary)
{
    FILE *input = fopen(source, "r");
    FILE *output;
    char line[256];
    int has_himem;
    int has_emm;
    if (!input)
        return 1;
    if (inspect_config(input, &has_himem, &has_emm)) {
        fclose(input);
        return 1;
    }
    output = fopen(temporary, "w");
    if (!output) {
        fclose(input);
        return 1;
    }
    if (!has_himem)
        fprintf(output, "DEVICE=%c:\\HIMEM.SYS /TESTMEM:ON\n", 'A' + drive);
    else if (copy_config_class(input, output, CONFIG_HIMEM))
        goto fail;
    if (!has_emm)
        fprintf(output, "DEVICE=%c:\\EMM386.EXE %s M5%s\n", 'A' + drive,
                options->expanded_memory ? "RAM" : "NOEMS",
                options->monochrome_region ? " I=B000-B7FF" : "");
    else if (copy_config_emm386(input, output, options))
        goto fail;
    if (copy_config_class(input, output, CONFIG_BUFFERS) ||
        copy_config_class(input, output, CONFIG_FILES))
        goto fail;
    fputs("DOS=HIGH,UMB\n", output);
    if (copy_config_class(input, output, CONFIG_LASTDRIVE) ||
        copy_config_class(input, output, CONFIG_FCBS))
        goto fail;
    while (fgets(line, sizeof(line), input)) {
        const char *body = line;
        while (*body == ' ' || *body == '\t')
            ++body;
        if (config_line_class(body) != CONFIG_OTHER)
            continue;
        if (starts_with(body, "DEVICE=") && line_is_high_driver(body) &&
            !contains_name(body, "HIMEM.SYS") &&
            !contains_name(body, "EMM386.EXE")) {
            int place_high = options->high_drivers;
            ++eligible_high_drivers;
            if (options->custom) {
                printf("Driver candidate: %s", strchr(body, '=') + 1);
                place_high = ask_yes_no("Load this driver into upper memory (Y/N)? ");
            }
            if (place_high) {
                ++selected_high_drivers;
                fputs("DEVICEHIGH=", output);
                fputs(strchr(body, '=') + 1, output);
            } else {
                fputs(line, output);
            }
        } else if (starts_with(body, "INSTALL=")) {
            fputs("INSTALLHIGH=", output);
            fputs(strchr(body, '=') + 1, output);
        } else {
            fputs(line, output);
        }
    }
    if (strchr(program, ':') || strchr(program, '\\') || strchr(program, '/'))
        fprintf(output, "INSTALL=%s /SESSION /SWAP:%c /W:%u,%u\n",
                program, 'A' + drive,
                options->reserve_one, options->reserve_two);
    else
        fprintf(output,
                "INSTALL=%c:\\MEMMAKER.EXE /SESSION /SWAP:%c /W:%u,%u\n",
                'A' + drive, 'A' + drive,
                options->reserve_one, options->reserve_two);
    fclose(input);
    if (fclose(output))
        return 1;
    return 0;
fail:
    fclose(input);
    fclose(output);
    remove(temporary);
    return 1;
}

static int transform_autoexec(unsigned drive, const struct options *options,
                              const char *program, const char *source,
                              const char *temporary)
{
    FILE *input = fopen(source, "r");
    FILE *output;
    char line[256];
    if (!input)
        return 1;
    output = fopen(temporary, "w");
    if (!output) {
        fclose(input);
        return 1;
    }
    while (fgets(line, sizeof(line), input)) {
        if (starts_with(line, "MEMMAKER ") || starts_with(line, "MEMMAKER\n"))
            continue;
        if (!starts_with(line, "LH ") && !starts_with(line, "LOADHIGH ") &&
            line_is_tsr(line)) {
            int place_high = options->high_tsrs;
            ++eligible_high_tsrs;
            if (options->custom) {
                printf("TSR candidate: %s", line);
                place_high = ask_yes_no("Load this TSR into upper memory (Y/N)? ");
            }
            if (place_high) {
                ++selected_high_tsrs;
                fprintf(output, "%c:\\SIZER.EXE /M:%u /SWAP:%c ",
                        'A' + drive, eligible_high_tsrs, 'A' + drive);
            }
        }
        fputs(line, output);
    }
    if (strchr(program, ':') || strchr(program, '\\') || strchr(program, '/'))
        fprintf(output, "%s /FINAL /SWAP:%c /W:%u,%u\n",
                program, 'A' + drive,
                options->reserve_one, options->reserve_two);
    else
        fprintf(output, "%c:\\MEMMAKER.EXE /FINAL /SWAP:%c /W:%u,%u\n",
                'A' + drive, 'A' + drive,
                options->reserve_one, options->reserve_two);
    fclose(input);
    if (fclose(output))
        return 1;
    return 0;
}

static int write_status(unsigned drive, const struct options *options,
                        const char *message)
{
    char path[32];
    char system_ini[128], system_backup[128];
    FILE *file;
    windows_ini_found = windows_paths(system_ini, system_backup);
    make_path(path, drive, "MEMMAKER.STS");
    file = fopen(path, "w");
    if (!file)
        return 1;
    fprintf(file, "%s\nWindows UMB reserve: %u,%u\nToken-ring probe: %s\n",
            message, options->reserve_one, options->reserve_two,
            options->no_token_ring ? "disabled" : "enabled");
    fprintf(file, "Windows SYSTEM.INI: %s\n",
            !windows_ini_found ? "not found" :
            windows_version == WINDOWS_30 ? "Windows 3.0 settings applied and backed up" :
            windows_version == WINDOWS_31 ? "Windows 3.1 detected; unchanged" :
            "version unknown; unchanged");
    if (measured_umb_k || measured_conventional_k) {
        unsigned reserve = options->reserve_one + options->reserve_two;
        unsigned usable = measured_umb_k > reserve ? measured_umb_k - reserve : 0;
        fprintf(file,
                "Measured largest UMB: %uK\n"
                "Measured largest conventional block: %uK\n"
                "Measured UMB after /W reserve: %uK\n",
                measured_umb_k, measured_conventional_k, usable);
        fprintf(file,
                "Baseline largest UMB: %uK\n"
                "Baseline largest conventional block: %uK\n"
                "Post-CONFIG largest UMB: %uK\n"
                "Post-CONFIG largest conventional block: %uK\n"
                "Measured conventional-memory gain: %dK\n",
                baseline_umb_k, baseline_conventional_k,
                config_umb_k, config_conventional_k,
                (int)measured_conventional_k - (int)baseline_conventional_k);
        fprintf(file,
                "Drivers selected for upper memory: %u of %u\n"
                "Drivers measured from CONFIG: %u, %u paragraphs resident\n"
                "TSRs selected for upper memory: %u of %u\n"
                "TSRs measured by SIZER: %u, %u paragraphs resident\n"
                "TSRs placed high by measured optimizer: %u, %u paragraphs\n",
                selected_high_drivers, eligible_high_drivers,
                measured_driver_count, measured_driver_paragraphs,
                selected_high_tsrs, eligible_high_tsrs,
                measured_tsr_count, measured_tsr_paragraphs,
                optimized_tsr_count, optimized_tsr_paragraphs);
    }
    return fclose(file) != 0;
}

static int restore_files(unsigned drive, const struct options *options)
{
    char config[32], autoexec[32], config_backup[32], auto_backup[32];
    char handoff[32];
    char system_ini[128], system_backup[128];
    make_path(config, drive, "CONFIG.SYS");
    make_path(autoexec, drive, "AUTOEXEC.BAT");
    make_path(config_backup, drive, "CONFIG.MM");
    make_path(auto_backup, drive, "AUTOEXEC.MM");
    if (copy_file(config_backup, config) || copy_file(auto_backup, autoexec)) {
        fputs("MemMaker cannot restore its startup-file backups.\n", stderr);
        return 1;
    }
    if (windows_paths(system_ini, system_backup)) {
        FILE *backup = fopen(system_backup, "rb");
        if (backup) {
            fclose(backup);
            if (copy_file(system_backup, system_ini)) {
                fputs("MemMaker cannot restore SYSTEM.INI.\n", stderr);
                return 1;
            }
            windows_ini_found = 1;
        }
    }
    make_path(handoff, drive, "MEMMAKER.MEM");
    remove(handoff);
    make_path(handoff, drive, "MEMMAKER.SIZ");
    remove(handoff);
    write_status(drive, options, "The previous memory configuration was restored.");
    puts("The previous startup files were restored.");
    return 0;
}

static int finish_session(unsigned drive, const struct options *options)
{
    char config[32], temporary[32], memory[32], sizes[32], line[256];
    FILE *input;
    FILE *output;
    make_path(config, drive, "CONFIG.SYS");
    make_path(temporary, drive, "CONFIG.MMT");
    input = fopen(config, "r");
    output = fopen(temporary, "w");
    if (!input || !output) {
        if (input) fclose(input);
        if (output) fclose(output);
        return 1;
    }
    while (fgets(line, sizeof(line), input))
        if (!(starts_with(line, "INSTALL=") &&
              contains_name(line, "MEMMAKER.EXE")))
            fputs(line, output);
    fclose(input);
    if (fclose(output) || replace_file(temporary, config))
        return 1;
    make_path(sizes, drive, "MEMMAKER.SIZ");
    if (record_driver_sizes(config, sizes))
        return 1;
    measure_memory();
    make_path(memory, drive, "MEMMAKER.MEM");
    output = fopen(memory, "ab");
    if (!output)
        return 1;
    if (fwrite(&measured_umb_k, sizeof(measured_umb_k), 1, output) != 1 ||
        fwrite(&measured_conventional_k, sizeof(measured_conventional_k), 1, output) != 1 ||
        fclose(output))
        return 1;
    puts("MemMaker completed the post-CONFIG measurement pass.");
    return 0;
}

static int write_baseline(unsigned drive, const struct options *options)
{
    char path[32];
    FILE *file;
    make_path(path, drive, "MEMMAKER.MEM");
    file = fopen(path, "wb");
    if (!file)
        return 1;
    if (fwrite(&measured_umb_k, sizeof(measured_umb_k), 1, file) != 1 ||
        fwrite(&measured_conventional_k, sizeof(measured_conventional_k), 1, file) != 1 ||
        fwrite(&selected_high_drivers, sizeof(selected_high_drivers), 1, file) != 1 ||
        fwrite(&eligible_high_drivers, sizeof(eligible_high_drivers), 1, file) != 1 ||
        fwrite(&selected_high_tsrs, sizeof(selected_high_tsrs), 1, file) != 1 ||
        fwrite(&eligible_high_tsrs, sizeof(eligible_high_tsrs), 1, file) != 1) {
        fclose(file);
        return 1;
    }
    return fclose(file) != 0;
}

static int finish_final(unsigned drive, const struct options *options)
{
    char autoexec[32], temporary[32], memory[32], line[256];
    char sizes_path[32];
    unsigned *sizes = tsr_sizes;
    unsigned *load_sizes = tsr_load_sizes;
    unsigned char *selected = tsr_selected;
    unsigned char *regions = tsr_regions;
    unsigned *region_sizes = umb_region_sizes;
    unsigned available;
    unsigned char *choice = NULL;
    FILE *input;
    FILE *output;
    FILE *measure;
    struct size_record record;
    memset(sizes, 0, sizeof(tsr_sizes));
    memset(load_sizes, 0, sizeof(tsr_load_sizes));
    memset(selected, 0, sizeof(tsr_selected));
    memset(regions, 0, sizeof(tsr_regions));
    memset(region_sizes, 0, sizeof(umb_region_sizes));
    make_path(autoexec, drive, "AUTOEXEC.BAT");
    make_path(temporary, drive, "AUTOEXEC.MMT");
    make_path(memory, drive, "MEMMAKER.MEM");
    make_path(sizes_path, drive, "MEMMAKER.SIZ");
    measure = fopen(memory, "rb");
    if (!measure)
        return 1;
    if (fread(&baseline_umb_k, sizeof(baseline_umb_k), 1, measure) != 1 ||
        fread(&baseline_conventional_k, sizeof(baseline_conventional_k), 1, measure) != 1 ||
        fread(&selected_high_drivers, sizeof(selected_high_drivers), 1, measure) != 1 ||
        fread(&eligible_high_drivers, sizeof(eligible_high_drivers), 1, measure) != 1 ||
        fread(&selected_high_tsrs, sizeof(selected_high_tsrs), 1, measure) != 1 ||
        fread(&eligible_high_tsrs, sizeof(eligible_high_tsrs), 1, measure) != 1 ||
        fread(&config_umb_k, sizeof(config_umb_k), 1, measure) != 1 ||
        fread(&config_conventional_k, sizeof(config_conventional_k), 1, measure) != 1) {
        fclose(measure);
        return 1;
    }
    fclose(measure);
    measure = fopen(sizes_path, "rb");
    if (measure) {
        while (fread(&record, sizeof(record), 1, measure) == 1) {
            if (record.magic == DRIVER_MAGIC && record.index < MAX_MEASUREMENTS) {
                ++measured_driver_count;
                measured_driver_paragraphs += record.before;
            } else if (record.magic == SIZER_MAGIC && record.index < MAX_MEASUREMENTS &&
                record.before >= record.after) {
                sizes[record.index] = record.before - record.after;
                ++measured_tsr_count;
                measured_tsr_paragraphs += sizes[record.index];
            } else if (record.magic == SIZER_LOAD_MAGIC &&
                       record.index < MAX_MEASUREMENTS) {
                load_sizes[record.index] = record.before;
            }
        }
        fclose(measure);
    }
    measure_memory();
    {
        unsigned region;
        available = 0;
        for (region = 1; region <= 16; ++region) {
            region_sizes[region - 1] = umb_region_size(region);
            available += region_sizes[region - 1];
        }
    }
    if (available > (options->reserve_one + options->reserve_two) * 64U)
        available -= (options->reserve_one + options->reserve_two) * 64U;
    else
        available = 0;
    if (available) {
        unsigned index;
        unsigned sum;
        choice = malloc(available + 1U);
        if (choice) {
            memset(choice, 0xff, available + 1U);
            choice[0] = 0;
            for (index = 1; index < MAX_MEASUREMENTS; ++index) {
                unsigned size = sizes[index];
                if (!size || size > available)
                    continue;
                sum = available;
                for (;;) {
                    if (choice[sum] == 0xffU &&
                        choice[sum - size] != 0xffU) {
                        choice[sum] = (unsigned char)index;
                    }
                    if (sum == size)
                        break;
                    --sum;
                }
            }
            for (sum = available; sum && choice[sum] == 0xffU; --sum)
                ;
            optimized_tsr_paragraphs = sum;
            while (sum) {
                index = choice[sum];
                if (!index)
                    break;
                selected[index] = 1;
                ++optimized_tsr_count;
                sum -= sizes[index];
            }
            /* A resident footprint determines long-term capacity, but the
             * selected region must first fit the larger EXEC-time image. */
            for (;;) {
                unsigned best_index = 0;
                unsigned best_load = 0;
                unsigned region;
                unsigned best_region = 0;
                unsigned best_capacity = 0xffffU;
                for (index = 1; index < MAX_MEASUREMENTS; ++index) {
                    if (selected[index] && !regions[index] &&
                        (!best_index || load_sizes[index] > best_load)) {
                        best_index = index;
                        best_load = load_sizes[index];
                    }
                }
                if (!best_index)
                    break;
                if (!best_load || best_load == 0xffffU) {
                    regions[best_index] = 0xffU;
                    continue;
                }
                for (region = 0; region < 16; ++region) {
                    if (region_sizes[region] >= best_load &&
                        region_sizes[region] < best_capacity) {
                        best_region = region + 1;
                        best_capacity = region_sizes[region];
                    }
                }
                if (!best_region) {
                    selected[best_index] = 0;
                    optimized_tsr_paragraphs -= sizes[best_index];
                    --optimized_tsr_count;
                    continue;
                }
                regions[best_index] = (unsigned char)best_region;
                region_sizes[best_region - 1] -= sizes[best_index];
            }
        }
        free(choice);
    }
    input = fopen(autoexec, "r");
    output = fopen(temporary, "w");
    if (!input || !output) {
        if (input) fclose(input);
        if (output) fclose(output);
        return 1;
    }
    while (fgets(line, sizeof(line), input)) {
        if (contains_name(line, "MEMMAKER.EXE") && contains_name(line, "/FINAL"))
            continue;
        if (contains_name(line, "SIZER.EXE") && contains_name(line, "/M:")) {
            char *marker = find_text(line, "/M:");
            char *swap = find_text(line, "/SWAP:");
            unsigned index = marker ? (unsigned)atoi(marker + 3) : 0;
            char *command = swap;
            if (command) {
                while (*command && *command != ' ' && *command != '\t')
                    ++command;
                while (*command == ' ' || *command == '\t')
                    ++command;
            }
            if (command && index < MAX_MEASUREMENTS) {
                if (selected[index]) {
                    if (regions[index] == 0xffU) {
                        fputs("LH ", output);
                    } else {
                        unsigned long minimum =
                            (unsigned long)load_sizes[index] * 16UL;
                        fprintf(output, "LH /L:%u,%lu ", regions[index], minimum);
                    }
                }
                fputs(command, output);
                continue;
            }
        }
        fputs(line, output);
    }
    fclose(input);
    if (fclose(output) || replace_file(temporary, autoexec))
        return 1;
    if (write_status(drive, options,
            "Memory optimization completed after measured reboot passes."))
        return 1;
    remove(memory);
    remove(sizes_path);
    puts("MemMaker measured memory optimization is complete.");
    return 0;
}

static int ask_yes_no(const char *prompt)
{
    int answer;
    fputs(prompt, stdout);
    fflush(stdout);
    do answer = toupper(getchar());
    while (answer == '\r' || answer == '\n' || answer == ' ');
    putchar('\n');
    return answer == 'Y';
}

static int optimize(unsigned drive, struct options *options,
                    const char *program)
{
    char config[32], autoexec[32], config_backup[32], auto_backup[32];
    char config_temp[32], auto_temp[32], status[32];
    char system_ini[128], system_backup[128], system_temp[128];
    union REGS regs;
    int answer;
    make_path(config, drive, "CONFIG.SYS");
    make_path(autoexec, drive, "AUTOEXEC.BAT");
    make_path(config_backup, drive, "CONFIG.MM");
    make_path(auto_backup, drive, "AUTOEXEC.MM");
    make_path(config_temp, drive, "CONFIG.MMT");
    make_path(auto_temp, drive, "AUTOEXEC.MMT");
    make_path(status, drive, "MEMMAKER.STS");
    {
        char sizes[32];
        make_path(sizes, drive, "MEMMAKER.SIZ");
        remove(sizes);
    }
    windows_ini_found = windows_paths(system_ini, system_backup);
    if (windows_ini_found && windows_version == WINDOWS_30) {
        char *separator;
        strcpy(system_temp, system_ini);
        separator = strrchr(system_temp, '\\');
        if (!separator)
            separator = strrchr(system_temp, '/');
        strcpy(separator + 1, "SYSTEM.MMT");
    }
    if (!options->batch) {
        if (!options->custom) {
            fputs("Use Express Setup to optimize memory (Y/N)? ", stdout);
            fflush(stdout);
            do answer = toupper(getchar());
            while (answer == '\r' || answer == '\n' || answer == ' ');
            putchar('\n');
            if (answer != 'Y')
                return 3;
        }
    }
    if (options->custom) {
        options->expanded_memory = ask_yes_no(
            "Do programs require expanded memory (Y/N)? ");
        options->monochrome_region = ask_yes_no(
            "Use monochrome region B000-B7FF for programs (Y/N)? ");
    }
    if (copy_file(config, config_backup) || copy_file(autoexec, auto_backup) ||
        (windows_ini_found && windows_version == WINDOWS_30 &&
         copy_file(system_ini, system_backup)) ||
        (windows_ini_found && windows_version == WINDOWS_30 &&
         transform_system_ini(system_ini, system_temp, options)) ||
        transform_config(drive, options, program, config, config_temp) ||
        transform_autoexec(drive, options, program, autoexec, auto_temp)) {
        remove(config_temp);
        remove(auto_temp);
        if (windows_ini_found && windows_version == WINDOWS_30)
            remove(system_temp);
        fputs("MemMaker could not prepare the startup files.\n", stderr);
        return 1;
    }
    measure_memory();
    if (write_baseline(drive, options) ||
        replace_file(config_temp, config) ||
        injected_failure("CONFIG") ||
        replace_file(auto_temp, autoexec) ||
        injected_failure("AUTOEXEC") ||
        (windows_ini_found && windows_version == WINDOWS_30 &&
         replace_file(system_temp, system_ini)) ||
        injected_failure("SYSTEM") ||
        write_status(drive, options,
            "Startup files optimized; beginning the reboot pass.") ||
        injected_failure("STATUS")) {
        copy_file(config_backup, config);
        copy_file(auto_backup, autoexec);
        if (windows_ini_found && windows_version == WINDOWS_30)
            copy_file(system_backup, system_ini);
        remove(config_temp);
        remove(auto_temp);
        if (windows_ini_found && windows_version == WINDOWS_30)
            remove(system_temp);
        remove(status);
        make_path(status, drive, "MEMMAKER.MEM");
        remove(status);
        fputs("MemMaker rolled back an incomplete startup-file update.\n", stderr);
        return 1;
    }
    remove(status);
    puts("MemMaker updated the startup files and is restarting the computer.");
    outp(0x64, 0xfe);
    memset(&regs, 0, sizeof(regs));
    int86(0x19, &regs, &regs);
    return 0;
}

int main(int argc, char **argv)
{
    struct options options;
    union REGS regs;
    unsigned drive;
    const char *fault = getenv("MEMMAKER_FAULT");
    if (fault) {
        strncpy(injected_point, fault, sizeof(injected_point) - 1U);
        injected_point[sizeof(injected_point) - 1U] = 0;
    }
    if (parse_options(argc, argv, &options)) {
        usage();
        return 1;
    }
    if (options.swap_set)
        drive = options.drive;
    else {
        memset(&regs, 0, sizeof(regs));
        regs.x.ax = 0x3305;
        intdos(&regs, &regs);
        drive = regs.h.dl ? regs.h.dl - 1U : 2U;
    }
    if (options.undo)
        return restore_files(drive, &options);
    if (options.session)
        return finish_session(drive, &options);
    if (options.final)
        return finish_final(drive, &options);
    return optimize(drive, &options, argv[0]);
}
