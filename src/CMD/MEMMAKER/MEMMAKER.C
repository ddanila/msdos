#include <ctype.h>
#include <conio.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SWAP_SWITCH "/SWAP:"
#define WINDOW_SWITCH "/W:"

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

static int ask_yes_no(const char *prompt);

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

    paragraphs = probe_largest_block(0x80, 1); /* high memory only */
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
#ifdef MEMMAKER_TEST_FAULTS
    const char *selected = getenv("MEMMAKER_FAULT");
    return selected && !stricmp(selected, point);
#else
    (void)point;
    return 0;
#endif
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

static int windows_paths(char *system_ini, char *system_backup)
{
    const char *directory = getenv("WINDIR");
    size_t length;
    FILE *file;
    if (!directory || !*directory)
        return 0;
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
    if (!has_emm)
        fprintf(output, "DEVICE=%c:\\EMM386.EXE RAM M5\n", 'A' + drive);
    fputs("DOS=HIGH,UMB\n", output);
    while (fgets(line, sizeof(line), input)) {
        const char *body = line;
        while (*body == ' ' || *body == '\t')
            ++body;
        if (starts_with(body, "DOS="))
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
                fputs("LH ", output);
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
            windows_ini_found ? "examined and backed up" : "not found");
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
                "TSRs selected for upper memory: %u of %u\n",
                selected_high_drivers, eligible_high_drivers,
                selected_high_tsrs, eligible_high_tsrs);
    }
    return fclose(file) != 0;
}

static int restore_files(unsigned drive, const struct options *options)
{
    char config[32], autoexec[32], config_backup[32], auto_backup[32];
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
    write_status(drive, options, "The previous memory configuration was restored.");
    puts("The previous startup files were restored.");
    return 0;
}

static int finish_session(unsigned drive, const struct options *options)
{
    char config[32], temporary[32], memory[32], line[256];
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
    FILE *input;
    FILE *output;
    FILE *measure;
    make_path(autoexec, drive, "AUTOEXEC.BAT");
    make_path(temporary, drive, "AUTOEXEC.MMT");
    make_path(memory, drive, "MEMMAKER.MEM");
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
    input = fopen(autoexec, "r");
    output = fopen(temporary, "w");
    if (!input || !output) {
        if (input) fclose(input);
        if (output) fclose(output);
        return 1;
    }
    while (fgets(line, sizeof(line), input))
        if (!(contains_name(line, "MEMMAKER.EXE") && contains_name(line, "/FINAL")))
            fputs(line, output);
    fclose(input);
    if (fclose(output) || replace_file(temporary, autoexec))
        return 1;
    measure_memory();
    if (write_status(drive, options,
            "Memory optimization completed after measured reboot passes."))
        return 1;
    remove(memory);
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
    char system_ini[128], system_backup[128];
    union REGS regs;
    int answer;
    make_path(config, drive, "CONFIG.SYS");
    make_path(autoexec, drive, "AUTOEXEC.BAT");
    make_path(config_backup, drive, "CONFIG.MM");
    make_path(auto_backup, drive, "AUTOEXEC.MM");
    make_path(config_temp, drive, "CONFIG.MMT");
    make_path(auto_temp, drive, "AUTOEXEC.MMT");
    make_path(status, drive, "MEMMAKER.STS");
    windows_ini_found = windows_paths(system_ini, system_backup);
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
    if (copy_file(config, config_backup) || copy_file(autoexec, auto_backup) ||
        (windows_ini_found && copy_file(system_ini, system_backup)) ||
        transform_config(drive, options, program, config, config_temp) ||
        transform_autoexec(drive, options, program, autoexec, auto_temp)) {
        remove(config_temp);
        remove(auto_temp);
        fputs("MemMaker could not prepare the startup files.\n", stderr);
        return 1;
    }
    measure_memory();
    if (write_baseline(drive, options) ||
        replace_file(config_temp, config) ||
        injected_failure("CONFIG") ||
        replace_file(auto_temp, autoexec) ||
        injected_failure("AUTOEXEC") ||
        write_status(drive, options,
            "Startup files optimized; beginning the reboot pass.") ||
        injected_failure("STATUS")) {
        copy_file(config_backup, config);
        copy_file(auto_backup, autoexec);
        if (windows_ini_found)
            copy_file(system_backup, system_ini);
        remove(config_temp);
        remove(auto_temp);
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
