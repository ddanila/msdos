#include <ctype.h>
#include <conio.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../RECOVERY/FATVOL.H"

#define BIT_BYTES 8192
#define MAX_DEPTH 64

#define POLICY_PROMPT 0
#define POLICY_FIX    1
#define POLICY_QUIT   2
#define POLICY_SKIP   3
#define POLICY_DELETE 4
#define POLICY_SAVE   5

#define CAT_OKAY       0
#define CAT_BAD_CHAIN  1
#define CAT_CROSSLINK  2
#define CAT_MISMATCH   3
#define CAT_BAD_CLUSTER 4
#define CAT_BAD_ENTRY  5
#define CAT_LOST       6

struct options {
    int all;
    int autofix;
    int check_only;
    int custom;
    int fragment;
    int mono;
    int no_save;
    int no_summary;
    int surface;
    int surface_explicit;
    int surface_prompt;
    int undo;
    int undo_prompt;
    int label_check;
    int lfn_check;
    unsigned surface_passes;
    unsigned save_log;
    unsigned char policies[7];
    unsigned drive_count;
    unsigned long drive_mask;
    int interactive;
    char fragment_spec[128];
};

struct scan_state {
    struct fat_volume volume;
    struct options options;
    unsigned long files;
    unsigned long directories;
    unsigned long bytes;
    unsigned long fragments;
    unsigned long lost_clusters;
    unsigned long bad_clusters;
    unsigned errors;
    unsigned repaired;
    unsigned unrepaired;
    unsigned next_chk;
    unsigned next_recovery_name;
    int repair_all;
    int aborted;
    int undo_decided;
    unsigned undo_drive;
    unsigned long undo_records;
    FILE *undo_file;
};

static unsigned char boot_sector[512];
static unsigned char directory_sector[512];
static unsigned char fat_buffer[1024];
static unsigned char compare_sector[512];
static unsigned char surface_sector[512];
static unsigned char journal_sector[512];
static unsigned char claimed[BIT_BYTES];
static unsigned char chain_seen[BIT_BYTES];
static unsigned char incoming[BIT_BYTES];
static long injected_surface_cluster = -1;
static int injected_surface_fired;
static int ui_mouse_available;
static int ui_mouse_latched;
static unsigned ui_mouse_x;
static unsigned ui_mouse_y;

#define UI_MOUSE_KEY 0x100

static void set_current_timestamp(unsigned char *entry);

static unsigned get_word(const unsigned char *p)
{
    return (unsigned)(p[0] | ((unsigned)p[1] << 8));
}

static unsigned long get_dword(const unsigned char *p)
{
    return (unsigned long)get_word(p) | ((unsigned long)get_word(p + 2) << 16);
}

static void put_word(unsigned char *p, unsigned value)
{
    p[0] = (unsigned char)value;
    p[1] = (unsigned char)(value >> 8);
}

static void put_dword(unsigned char *p, unsigned long value)
{
    put_word(p, (unsigned)value);
    put_word(p + 2, (unsigned)(value >> 16));
}

static int bit_get(const unsigned char *map, unsigned cluster)
{
    return map[cluster >> 3] & (1U << (cluster & 7));
}

static void bit_set(unsigned char *map, unsigned cluster)
{
    map[cluster >> 3] |= (unsigned char)(1U << (cluster & 7));
}

static void bit_clear(unsigned char *map, unsigned cluster)
{
    map[cluster >> 3] &= (unsigned char)~(1U << (cluster & 7));
}

static int equal_switch(const char *argument, const char *name)
{
    ++argument;
    while (*argument && *name) {
        if (toupper((unsigned char)*argument) != *name)
            return 0;
        ++argument;
        ++name;
    }
    return !*argument && !*name;
}

static void usage(void)
{
    puts("Checks and repairs FAT12 and FAT16 drives.");
    puts("Syntax: SCANDISK [drive: [drive: ...]] [/ALL] [/AUTOFIX] [/CHECKONLY]");
    puts("                [/CUSTOM] [/FRAGMENT] [/MONO] [/NOSAVE]");
    puts("                [/NOSUMMARY] [/SURFACE] [/UNDO]");
}

static int parse_options(int argc, char **argv, struct options *options)
{
    int index;
    unsigned exclusive = 0;
    memset(options, 0, sizeof(*options));
    for (index = 1; index < argc; ++index) {
        const char *argument = argv[index];
        if ((argument[0] == '/' || argument[0] == '-') && argument[1]) {
            if (equal_switch(argument, "?")) {
                usage();
                exit(0);
            } else if (equal_switch(argument, "ALL")) options->all = 1;
            else if (equal_switch(argument, "AUTOFIX")) options->autofix = 1;
            else if (equal_switch(argument, "CHECKONLY")) options->check_only = 1;
            else if (equal_switch(argument, "CUSTOM")) options->custom = 1;
            else if (equal_switch(argument, "FRAGMENT")) options->fragment = 1;
            else if (equal_switch(argument, "MONO")) options->mono = 1;
            else if (equal_switch(argument, "NOSAVE")) options->no_save = 1;
            else if (equal_switch(argument, "NOSUMMARY")) options->no_summary = 1;
            else if (equal_switch(argument, "SURFACE")) {
                options->surface = 1;
                options->surface_explicit = 1;
            }
            else if (equal_switch(argument, "UNDO")) options->undo = 1;
            else {
                fprintf(stderr, "Invalid switch - %s\n", argument);
                return 1;
            }
        } else if (isalpha((unsigned char)argument[0]) &&
                   argument[1] == ':' && argument[2] == 0 &&
                   !options->fragment) {
            unsigned drive = toupper((unsigned char)argument[0]) - 'A';
            if (options->drive_mask & (1UL << drive)) {
                fprintf(stderr, "Drive %c: was specified more than once.\n",
                        'A' + drive);
                return 1;
            }
            options->drive_mask |= 1UL << drive;
            ++options->drive_count;
        } else if (options->fragment && !options->fragment_spec[0] &&
                   strlen(argument) < sizeof(options->fragment_spec)) {
            strcpy(options->fragment_spec, argument);
        } else {
            fprintf(stderr, "Invalid drive or parameter - %s\n", argument);
            return 1;
        }
    }
    if (options->all && options->drive_count) {
        fputs("Specify either a drive or /ALL, not both.\n", stderr);
        return 1;
    }
    exclusive = (unsigned)options->autofix + (unsigned)options->check_only +
        (unsigned)options->custom;
    if (exclusive > 1) {
        fputs("/AUTOFIX, /CHECKONLY, and /CUSTOM cannot be combined.\n",
              stderr);
        return 1;
    }
    if (options->no_save && !options->autofix) {
        fputs("/NOSAVE can be used only with /AUTOFIX.\n", stderr);
        return 1;
    }
    if (options->fragment && !options->fragment_spec[0]) {
        fputs("/FRAGMENT requires a filename.\n", stderr);
        return 1;
    }
    if (options->fragment && (options->all || options->drive_count ||
                              options->autofix || options->check_only ||
                              options->custom || options->surface ||
                              options->no_save || options->undo)) {
        fputs("/FRAGMENT cannot be combined with drive-check options.\n",
              stderr);
        return 1;
    }
    if (options->undo && (options->all || options->drive_count > 1 ||
                          options->autofix || options->check_only ||
                          options->custom || options->fragment ||
                          options->surface || options->no_save ||
                          options->no_summary)) {
        fputs("/UNDO accepts only an optional undo drive and /MONO.\n",
              stderr);
        return 1;
    }
    return 0;
}

static char *trim(char *text)
{
    char *end;
    while (*text == ' ' || *text == '\t') ++text;
    end = text + strlen(text);
    while (end > text && (end[-1] == ' ' || end[-1] == '\t' ||
                          end[-1] == '\r' || end[-1] == '\n'))
        --end;
    *end = 0;
    return text;
}

static int ini_value(const char *value, const char *expected)
{
    return !stricmp(value, expected);
}

static unsigned char action_value(const char *value)
{
    if (ini_value(value, "FIX")) return POLICY_FIX;
    if (ini_value(value, "QUIT")) return POLICY_QUIT;
    if (ini_value(value, "SKIP")) return POLICY_SKIP;
    if (ini_value(value, "DELETE")) return POLICY_DELETE;
    if (ini_value(value, "SAVE")) return POLICY_SAVE;
    return POLICY_PROMPT;
}

static void load_custom_options(struct options *options, const char *program)
{
    FILE *file;
    char line[160];
    char path[160];
    int section = 0;
    options->surface_passes = 1;
    options->save_log = 1;
    options->undo_prompt = 1;
    options->lfn_check = 1;
    file = fopen("SCANDISK.INI", "r");
    if (!file && program && strlen(program) < sizeof(path)) {
        char *slash;
        strcpy(path, program);
        slash = strrchr(path, '\\');
        if (!slash) slash = strrchr(path, '/');
        if (slash) {
            strcpy(slash + 1, "SCANDISK.INI");
            file = fopen(path, "r");
        }
    }
    if (!file) return;
    while (fgets(line, sizeof(line), file)) {
        char *equal, *comment, *key, *value;
        comment = strchr(line, ';');
        if (comment) *comment = 0;
        key = trim(line);
        if (*key == '[') {
            section = !stricmp(key, "[ENVIRONMENT]") ? 1 :
                (!stricmp(key, "[CUSTOM]") ? 2 : 0);
            continue;
        }
        equal = strchr(key, '=');
        if (!equal) continue;
        *equal++ = 0;
        key = trim(key); value = trim(equal);
        if (section == 1) {
            if (!stricmp(key, "DISPLAY") && ini_value(value, "MONO"))
                options->mono = 1;
            else if (!stricmp(key, "NUMPASSES")) {
                unsigned long passes = strtoul(value, NULL, 10);
                if (passes >= 1 && passes <= 65535UL)
                    options->surface_passes = (unsigned)passes;
            } else if (!stricmp(key, "LABELCHECK"))
                options->label_check = ini_value(value, "ON");
            else if (!stricmp(key, "LFNCHECK"))
                options->lfn_check = !ini_value(value, "OFF");
        } else if (section == 2 && options->custom) {
            if (!stricmp(key, "DRIVESUMMARY") && ini_value(value, "OFF"))
                options->no_summary = 1;
            else if (!stricmp(key, "SURFACE")) {
                if (!options->surface_explicit) {
                    options->surface = ini_value(value, "ALWAYS");
                    options->surface_prompt = ini_value(value, "PROMPT");
                }
            } else if (!stricmp(key, "SAVELOG"))
                options->save_log = ini_value(value, "APPEND") ? 1 :
                    (ini_value(value, "OVERWRITE") ? 2 : 0);
            else if (!stricmp(key, "UNDO"))
                options->undo_prompt = ini_value(value, "PROMPT");
            else if (!stricmp(key, "OKAY_ENTRIES"))
                options->policies[CAT_OKAY] = action_value(value);
            else if (!stricmp(key, "BAD_CHAIN"))
                options->policies[CAT_BAD_CHAIN] = action_value(value);
            else if (!stricmp(key, "CROSSLINKS"))
                options->policies[CAT_CROSSLINK] = action_value(value);
            else if (!stricmp(key, "MISMATCH_FAT"))
                options->policies[CAT_MISMATCH] = action_value(value);
            else if (!stricmp(key, "BAD_CLUSTERS"))
                options->policies[CAT_BAD_CLUSTER] = action_value(value);
            else if (!stricmp(key, "BAD_ENTRIES"))
                options->policies[CAT_BAD_ENTRY] = action_value(value);
            else if (!stricmp(key, "LOSTCLUST"))
                options->policies[CAT_LOST] = action_value(value);
        }
    }
    fclose(file);
    if (options->check_only) options->autofix = 0;
}

static void report_problem(struct scan_state *state, const char *message)
{
    ++state->errors;
    puts(message);
}

static void put_journal_dword(unsigned char *p, unsigned long value)
{
    p[0] = (unsigned char)value;
    p[1] = (unsigned char)(value >> 8);
    p[2] = (unsigned char)(value >> 16);
    p[3] = (unsigned char)(value >> 24);
}

static int append_undo_sector(struct scan_state *state, unsigned long sector)
{
    unsigned char number[4];
    if (!state->undo_file)
        return 0;
    if (fat_volume_io(&state->volume, 0, sector, 1, journal_sector))
        return 1;
    put_journal_dword(number, sector);
    if (fwrite(number, 1, 4, state->undo_file) != 4 ||
        fwrite(journal_sector, 1, 512, state->undo_file) != 512)
        return 1;
    ++state->undo_records;
    return 0;
}

static int begin_undo_disk(struct scan_state *state)
{
    char path[] = "A:\\SCANDISK.UND";
    unsigned char header[20];
    unsigned long sector;
    int answer;

    if (state->undo_decided)
        return 0;
    state->undo_decided = 1;
    if (state->options.custom && !state->options.undo_prompt)
        return 0;
    if (state->options.no_summary)
        return 0;
    fputs("Create an Undo disk (Y/N)? ", stdout);
    fflush(stdout);
    do {
        answer = getchar();
        if (answer == EOF) {
            putchar('\n');
            return 0;
        }
        answer = toupper((unsigned char)answer);
    } while (answer == '\r' || answer == '\n' || answer == ' ' ||
             answer == '\t');
    putchar('\n');
    if (answer != 'Y')
        return 0;
    fputs("Undo drive [A]: ", stdout);
    fflush(stdout);
    do {
        answer = getchar();
        if (answer == EOF || answer == '\r' || answer == '\n') {
            answer = 'A';
            break;
        }
        answer = toupper((unsigned char)answer);
    } while (!isalpha(answer));
    putchar('\n');
    state->undo_drive = (unsigned)(answer - 'A');
    if (state->undo_drive == state->volume.drive) {
        puts("The Undo disk must be on a different drive.");
        return 0;
    }
    path[0] = (char)answer;
    state->undo_file = fopen(path, "wb+");
    if (!state->undo_file) {
        puts("The Undo disk cannot be created; repairs will continue without it.");
        return 0;
    }
    memset(header, 0, sizeof(header));
    memcpy(header, "SDUNDO1", 7);
    header[8] = (unsigned char)state->volume.drive;
    header[9] = (unsigned char)state->volume.media;
    if (fwrite(header, 1, sizeof(header), state->undo_file) != sizeof(header) ||
        fwrite(boot_sector, 1, 512, state->undo_file) != 512)
        goto failed;
    for (sector = state->volume.reserved_sectors;
         sector < state->volume.data_start; ++sector)
        if (append_undo_sector(state, sector))
            goto failed;
    puts("Undo information is being recorded.");
    return 0;
failed:
    fclose(state->undo_file);
    state->undo_file = NULL;
    remove(path);
    puts("The Undo disk is full; repairs will continue without it.");
    return 1;
}

static void finish_undo_disk(struct scan_state *state)
{
    unsigned char count[4];
    unsigned char hash_bytes[4];
    unsigned char number[4];
    unsigned long hash = 2166136261UL;
    unsigned long index;
    unsigned i;
    if (!state->undo_file)
        return;
    fflush(state->undo_file);
    for (index = 0; index < state->undo_records; ++index) {
        unsigned long sector;
        if (fseek(state->undo_file, 20UL + 512UL + index * 516UL,
                  SEEK_SET) || fread(number, 1, 4, state->undo_file) != 4)
            break;
        sector = get_dword(number);
        if (fat_volume_io(&state->volume, 0, sector, 1, journal_sector))
            break;
        for (i = 0; i < 4; ++i)
            hash = (hash ^ number[i]) * 16777619UL;
        for (i = 0; i < 512; ++i)
            hash = (hash ^ journal_sector[i]) * 16777619UL;
    }
    if (index != state->undo_records)
        hash = 0;
    put_journal_dword(count, state->undo_records);
    put_journal_dword(hash_bytes, hash);
    if (!fseek(state->undo_file, 10L, SEEK_SET)) {
        fwrite(count, 1, 4, state->undo_file);
        fwrite(hash_bytes, 1, 4, state->undo_file);
    }
    fclose(state->undo_file);
    state->undo_file = NULL;
}

static int permit_repair(struct scan_state *state, const char *action,
                         unsigned category)
{
    int answer;
    unsigned policy = category < 7 ? state->options.policies[category] : 0;
    if (state->options.check_only)
        return 0;
    if (state->options.autofix || state->repair_all)
        return begin_undo_disk(state), 1;
    if (state->options.custom && policy != POLICY_PROMPT) {
        if (policy == POLICY_QUIT)
            state->aborted = 1;
        if (policy == POLICY_FIX || policy == POLICY_DELETE ||
            policy == POLICY_SAVE)
            return begin_undo_disk(state), 1;
        return 0;
    }
    printf("%s (Y/N/A/Q)? ", action);
    fflush(stdout);
    do {
        answer = getchar();
        if (answer == EOF) {
            putchar('\n');
            return 0;
        }
        answer = toupper((unsigned char)answer);
    } while (answer == '\r' || answer == '\n' || answer == ' ' ||
             answer == '\t');
    putchar('\n');
    if (answer == 'A') {
        state->repair_all = 1;
        begin_undo_disk(state);
        return 1;
    }
    if (answer == 'Q')
        state->aborted = 1;
    if (answer == 'Y')
        begin_undo_disk(state);
    return answer == 'Y';
}

static int repair_fat(struct scan_state *state, unsigned cluster,
                      unsigned value, unsigned category)
{
    if (!permit_repair(state, "Repair this allocation-table error", category)) {
        ++state->unrepaired;
        return 1;
    }
    if (fat_volume_set(&state->volume, cluster, value, fat_buffer)) {
        ++state->unrepaired;
        return 1;
    }
    ++state->repaired;
    return 0;
}

static int repair_directory_sector(struct scan_state *state,
                                   unsigned long sector)
{
    if (append_undo_sector(state, sector)) {
        ++state->unrepaired;
        return 1;
    }
    if (fat_volume_io(&state->volume, 1, sector, 1, directory_sector)) {
        ++state->unrepaired;
        return 1;
    }
    return 0;
}

static unsigned scan_chain(struct scan_state *state, unsigned first,
                           unsigned long size, int directory,
                           unsigned char *entry, int *entry_changed)
{
    unsigned current = first;
    unsigned previous = 0;
    unsigned next = 0;
    unsigned count = 0;
    unsigned expected = 0;
    unsigned long cluster_bytes =
        (unsigned long)state->volume.sectors_per_cluster * 512UL;

    memset(chain_seen, 0, sizeof(chain_seen));
    if (!directory && size)
        expected = (unsigned)((size + cluster_bytes - 1) / cluster_bytes);
    if (!first) {
        if (size) {
            report_problem(state, "File size is nonzero but its cluster chain is empty.");
            if (permit_repair(state, "Set the file size to zero", CAT_BAD_CHAIN)) {
                put_dword(entry + 28, 0);
                *entry_changed = 1;
                ++state->repaired;
            } else ++state->unrepaired;
        }
        return 0;
    }
    if (!fat_volume_valid_cluster(&state->volume, first)) {
        report_problem(state, "A file or directory has an invalid starting cluster.");
        if (permit_repair(state, "Detach the invalid starting cluster", CAT_BAD_CHAIN)) {
            put_word(entry + 26, 0);
            if (!directory)
                put_dword(entry + 28, 0);
            *entry_changed = 1;
            ++state->repaired;
        } else ++state->unrepaired;
        return 0;
    }
    if (!directory && !size) {
        report_problem(state, "A zero-length file owns allocated clusters.");
        if (permit_repair(state, "Detach the unused cluster chain", CAT_OKAY)) {
            put_word(entry + 26, 0);
            *entry_changed = 1;
            ++state->repaired;
        } else ++state->unrepaired;
        return 0;
    }

    while (fat_volume_valid_cluster(&state->volume, current)) {
        if (state->aborted)
            break;
        if (bit_get(chain_seen, current)) {
            report_problem(state, "A cluster chain contains a loop.");
            if (previous)
                repair_fat(state, previous,
                           state->volume.fat16 ? 0xffffU : 0x0fffU,
                           CAT_BAD_CHAIN);
            break;
        }
        if (bit_get(claimed, current)) {
            report_problem(state, "Two files or directories share a cluster.");
            if (previous)
                repair_fat(state, previous,
                           state->volume.fat16 ? 0xffffU : 0x0fffU,
                           CAT_CROSSLINK);
            else if (permit_repair(state, "Detach the cross-linked file",
                                   CAT_CROSSLINK)) {
                put_word(entry + 26, 0);
                put_dword(entry + 28, 0);
                *entry_changed = 1;
                ++state->repaired;
            } else ++state->unrepaired;
            break;
        }
        bit_set(chain_seen, current);
        bit_set(claimed, current);
        ++count;
        if (fat_volume_get(&state->volume, current, &next, fat_buffer)) {
            report_problem(state, "The file allocation table cannot be read.");
            ++state->unrepaired;
            break;
        }
        if (fat_volume_bad(&state->volume, next)) {
            report_problem(state, "A file chain points to a bad cluster marker.");
            if (previous)
                repair_fat(state, previous,
                           state->volume.fat16 ? 0xffffU : 0x0fffU,
                           CAT_BAD_CHAIN);
            break;
        }
        if (fat_volume_valid_cluster(&state->volume, next) &&
            next != current + 1U)
            ++state->fragments;
        if (!directory && expected && count == expected &&
            !fat_volume_eoc(&state->volume, next)) {
            report_problem(state, "A file owns more clusters than its size requires.");
            repair_fat(state, current,
                       state->volume.fat16 ? 0xffffU : 0x0fffU,
                       CAT_BAD_CHAIN);
            break;
        }
        if (fat_volume_eoc(&state->volume, next))
            break;
        if (!fat_volume_valid_cluster(&state->volume, next)) {
            report_problem(state, "A cluster chain contains an invalid link.");
            repair_fat(state, current,
                       state->volume.fat16 ? 0xffffU : 0x0fffU,
                       CAT_BAD_CHAIN);
            break;
        }
        previous = current;
        current = next;
    }
    if (!directory && expected > count) {
        report_problem(state, "A file is longer than its available cluster chain.");
        if (permit_repair(state, "Shorten the file to its readable chain",
                          CAT_BAD_CHAIN)) {
            put_dword(entry + 28, (unsigned long)count * cluster_bytes);
            *entry_changed = 1;
            ++state->repaired;
        } else ++state->unrepaired;
    }
    return count;
}

static int dot_entry(const unsigned char *entry)
{
    return entry[0] == '.' && (entry[1] == ' ' || entry[1] == '.');
}

static void validate_dot_entries(struct scan_state *state,
                                 unsigned long sector, unsigned self,
                                 unsigned parent)
{
    static const unsigned char dot_name[11] =
        {'.',' ',' ',' ',' ',' ',' ',' ',' ',' ',' '};
    static const unsigned char dotdot_name[11] =
        {'.','.',' ',' ',' ',' ',' ',' ',' ',' ',' '};
    unsigned char *dot = directory_sector;
    unsigned char *dotdot = directory_sector + 32;
    int dot_bad = memcmp(dot, dot_name, 11) || !(dot[11] & 0x10) ||
        get_word(dot + 26) != self || get_dword(dot + 28) != 0;
    int dotdot_bad = memcmp(dotdot, dotdot_name, 11) ||
        !(dotdot[11] & 0x10) || get_word(dotdot + 26) != parent ||
        get_dword(dotdot + 28) != 0;
    int changed = 0;
    if (dot_bad) {
        report_problem(state, "A directory has an invalid . entry.");
        if (permit_repair(state, "Repair the . directory entry", CAT_OKAY)) {
            memset(dot, 0, 32); memcpy(dot, dot_name, 11);
            dot[11] = 0x10; put_word(dot + 26, self);
            ++state->repaired; changed = 1;
        } else ++state->unrepaired;
    }
    if (dotdot_bad) {
        report_problem(state, "A directory has an invalid .. entry.");
        if (permit_repair(state, "Repair the .. directory entry", CAT_OKAY)) {
            memset(dotdot, 0, 32); memcpy(dotdot, dotdot_name, 11);
            dotdot[11] = 0x10; put_word(dotdot + 26, parent);
            ++state->repaired; changed = 1;
        } else ++state->unrepaired;
    }
    if (changed && repair_directory_sector(state, sector))
        ++state->unrepaired;
}

static int valid_short_name(const unsigned char *name)
{
    static const char illegal[] = "\"*+,/:;<=>?[\\]|";
    unsigned index;
    int padding = 0;
    if (name[0] == ' ' || name[0] == 0)
        return 0;
    for (index = 0; index < 11; ++index) {
        unsigned char c = name[index];
        if (index == 8)
            padding = 0;
        if (c == ' ')
            padding = 1;
        else if (padding || c < 0x20 || strchr(illegal, c))
            return 0;
    }
    return 1;
}

static int valid_volume_label(const unsigned char *name)
{
    static const char illegal[] = "\"*+,./:;<=>?[\\]|";
    unsigned index;
    for (index = 0; index < 11; ++index)
        if (name[index] < 0x20 || strchr(illegal, name[index]))
            return 0;
    return name[0] != ' ';
}

static int name_seen_before(struct fat_volume *volume, unsigned first,
                            unsigned long current_sector,
                            unsigned current_offset,
                            const unsigned char name[11])
{
    unsigned cluster = first, next, sector_count, sector_index;
    unsigned long base;
    unsigned traversed = 0;
    int root = first == 0;
    do {
        if (root) {
            base = volume->root_start;
            sector_count = volume->root_sectors;
        } else {
            if (!fat_volume_valid_cluster(volume, cluster) ||
                traversed++ > volume->clusters)
                return 0;
            base = fat_volume_cluster_sector(volume, cluster);
            sector_count = volume->sectors_per_cluster;
        }
        for (sector_index = 0; sector_index < sector_count; ++sector_index) {
            unsigned offset;
            unsigned long sector = base + sector_index;
            if (fat_volume_io(volume, 0, sector, 1, compare_sector))
                return 0;
            for (offset = 0; offset < 512; offset += 32) {
                unsigned char *entry = compare_sector + offset;
                if (sector == current_sector && offset == current_offset)
                    return 0;
                if (!entry[0])
                    return 0;
                if (entry[0] != 0xe5 && (entry[11] & 0x0f) != 0x0f &&
                    !(entry[11] & 0x08) && !memcmp(entry, name, 11))
                    return 1;
            }
        }
        if (root || fat_volume_get(volume, cluster, &next, fat_buffer) ||
            fat_volume_eoc(volume, next))
            break;
        cluster = next;
    } while (1);
    return 0;
}

static void make_recovery_name(struct scan_state *state,
                               struct fat_volume *volume, unsigned directory,
                               unsigned char name[11])
{
    unsigned attempts = 0;
    do {
        char base[9];
        sprintf(base, "FOUND%03u", state->next_recovery_name++ % 1000U);
        memcpy(name, base, 8);
        memcpy(name + 8, "CHK", 3);
    } while (++attempts < 10000U &&
             name_seen_before(volume, directory, ~0UL, 0, name));
}

static int valid_write_timestamp(const unsigned char *entry)
{
    static const unsigned char month_days[12] =
        {31,28,31,30,31,30,31,31,30,31,30,31};
    unsigned time = get_word(entry + 22);
    unsigned date = get_word(entry + 24);
    unsigned year = 1980U + (date >> 9);
    unsigned month = (date >> 5) & 15U;
    unsigned day = date & 31U;
    unsigned limit;
    if ((time >> 11) > 23U || ((time >> 5) & 63U) > 59U ||
        month < 1U || month > 12U || day < 1U)
        return 0;
    limit = month_days[month - 1U];
    if (month == 2U && (!(year % 4U) && (year % 100U || !(year % 400U))))
        ++limit;
    return day <= limit;
}

static void set_current_timestamp(unsigned char *entry)
{
    union REGS regs;
    unsigned date, time;
    memset(&regs, 0, sizeof(regs));
    regs.h.ah = 0x2a;
    intdos(&regs, &regs);
    date = ((regs.x.cx - 1980U) << 9) |
        ((unsigned)regs.h.dh << 5) | regs.h.dl;
    memset(&regs, 0, sizeof(regs));
    regs.h.ah = 0x2c;
    intdos(&regs, &regs);
    time = ((unsigned)regs.h.ch << 11) |
        ((unsigned)regs.h.cl << 5) | ((unsigned)regs.h.dh >> 1);
    put_word(entry + 22, time);
    put_word(entry + 24, date);
}

static int scan_directory(struct scan_state *state, unsigned first,
                          unsigned parent, unsigned depth)
{
    unsigned cluster = first;
    unsigned next;
    unsigned sector_index;
    unsigned sectors;
    unsigned long base;
    int root = first == 0;

    if (depth > MAX_DEPTH) {
        report_problem(state, "Directory nesting exceeds the supported limit.");
        ++state->unrepaired;
        return 1;
    }
    do {
        if (root) {
            base = state->volume.root_start;
            sectors = state->volume.root_sectors;
        } else {
            if (!fat_volume_valid_cluster(&state->volume, cluster))
                return 1;
            base = fat_volume_cluster_sector(&state->volume, cluster);
            sectors = state->volume.sectors_per_cluster;
        }
        for (sector_index = 0; sector_index < sectors; ++sector_index) {
            unsigned entry_offset;
            unsigned long position = base + sector_index;
            if (fat_volume_io(&state->volume, 0, position, 1,
                              directory_sector)) {
                report_problem(state, "A directory sector cannot be read.");
                ++state->unrepaired;
                continue;
            }
            if (!root && cluster == first && sector_index == 0)
                validate_dot_entries(state, position, first, parent);
            for (entry_offset = 0; entry_offset < 512; entry_offset += 32) {
                unsigned char *entry = directory_sector + entry_offset;
                unsigned child;
                unsigned long size;
                unsigned count;
                int changed = 0;
                if (state->aborted)
                    return 1;
                if (entry[0] == 0)
                    break;
                /* 05h is the on-disk escape for a live E5h first byte. */
                if (entry[0] == 0xe5)
                    continue;
                if ((entry[11] & 0x0f) == 0x0f) {
                    if (!state->options.lfn_check) {
                        report_problem(state,
                            "A long-filename directory entry was found.");
                        if (permit_repair(state,
                                "Remove the long-filename entry",
                                CAT_BAD_ENTRY)) {
                            entry[0] = 0xe5;
                            repair_directory_sector(state, position);
                            ++state->repaired;
                        } else ++state->unrepaired;
                    }
                    continue;
                }
                if (entry[11] & 0x08) {
                    if (!root) {
                        report_problem(state,
                            "A subdirectory contains a volume-label entry.");
                        if (permit_repair(state,
                                "Remove the misplaced volume label",
                                CAT_BAD_ENTRY)) {
                            entry[0] = 0xe5;
                            repair_directory_sector(state, position);
                            ++state->repaired;
                        } else ++state->unrepaired;
                    } else if (state->options.label_check &&
                               !valid_volume_label(entry)) {
                        unsigned label_index;
                        report_problem(state,
                            "The volume label contains invalid characters.");
                        if (permit_repair(state,
                                "Repair the volume label", CAT_OKAY)) {
                            for (label_index = 0; label_index < 11;
                                 ++label_index)
                                if (entry[label_index] < 0x20 ||
                                    strchr("\"*+,./:;<=>?[\\]|",
                                           entry[label_index]))
                                    entry[label_index] = '_';
                            repair_directory_sector(state, position);
                            ++state->repaired;
                        } else ++state->unrepaired;
                    }
                    continue;
                }
                if (!dot_entry(entry) &&
                    (!valid_short_name(entry) ||
                     name_seen_before(&state->volume, first, position,
                                      entry_offset, entry))) {
                    report_problem(state,
                        "A directory entry has an invalid or duplicate name.");
                    if (permit_repair(state,
                            "Give the entry a unique recovery name",
                            CAT_OKAY)) {
                        make_recovery_name(state, &state->volume, first, entry);
                        repair_directory_sector(state, position);
                        ++state->repaired;
                    } else ++state->unrepaired;
                }
                if ((entry[11] & 0xc0) || (entry[11] & 0x18) == 0x18) {
                    report_problem(state,
                        "A directory entry has invalid attributes.");
                    if (permit_repair(state,
                            "Repair the directory-entry attributes",
                            CAT_OKAY)) {
                        entry[11] &= 0x3f;
                        if ((entry[11] & 0x18) == 0x18)
                            entry[11] &= (unsigned char)~0x08;
                        repair_directory_sector(state, position);
                        ++state->repaired;
                    } else ++state->unrepaired;
                }
                if (!valid_write_timestamp(entry)) {
                    report_problem(state,
                        "A directory entry has an invalid date or time.");
                    if (permit_repair(state,
                            "Replace the invalid date and time", CAT_OKAY)) {
                        set_current_timestamp(entry);
                        repair_directory_sector(state, position);
                        ++state->repaired;
                    } else ++state->unrepaired;
                }
                child = get_word(entry + 26);
                size = get_dword(entry + 28);
                if (entry[11] & 0x10) {
                    if (dot_entry(entry))
                        continue;
                    ++state->directories;
                    if (!fat_volume_valid_cluster(&state->volume, child)) {
                        report_problem(state,
                            "A directory has an invalid starting cluster.");
                        if (permit_repair(state,
                                "Remove the invalid directory entry",
                                CAT_BAD_ENTRY)) {
                            entry[0] = 0xe5;
                            repair_directory_sector(state, position);
                            ++state->repaired;
                        } else ++state->unrepaired;
                        continue;
                    }
                    if (size) {
                        report_problem(state,
                            "A directory entry has a nonzero file size.");
                        if (permit_repair(state,
                                "Set the directory size to zero", CAT_OKAY)) {
                            put_dword(entry + 28, 0);
                            changed = 1;
                            ++state->repaired;
                        } else ++state->unrepaired;
                    }
                    count = scan_chain(state, child, 0, 1, entry, &changed);
                    if (changed)
                        repair_directory_sector(state, position);
                    if (count && child) {
                        scan_directory(state, child, first, depth + 1);
                        if (fat_volume_io(&state->volume, 0, position, 1,
                                          directory_sector))
                            return 1;
                    }
                } else {
                    ++state->files;
                    state->bytes += size;
                    scan_chain(state, child, size, 0, entry, &changed);
                    if (changed)
                        repair_directory_sector(state, position);
                }
            }
        }
        if (root)
            break;
        if (fat_volume_get(&state->volume, cluster, &next, fat_buffer))
            return 1;
        if (fat_volume_eoc(&state->volume, next))
            break;
        cluster = next;
    } while (fat_volume_valid_cluster(&state->volume, cluster));
    return 0;
}

static int compare_fat_mirrors(struct scan_state *state)
{
    unsigned copy;
    unsigned sector_index;
    int difference = 0;
    for (copy = 1; copy < state->volume.fat_count; ++copy) {
        for (sector_index = 0;
             sector_index < state->volume.sectors_per_fat; ++sector_index) {
            unsigned long first;
            unsigned long other;
            if (state->aborted)
                return 1;
            first = state->volume.reserved_sectors + sector_index;
            other = state->volume.reserved_sectors +
                (unsigned long)copy * state->volume.sectors_per_fat + sector_index;
            if (fat_volume_io(&state->volume, 0, first, 1, fat_buffer) ||
                fat_volume_io(&state->volume, 0, other, 1, compare_sector)) {
                report_problem(state, "A file allocation table cannot be read.");
                ++state->unrepaired;
                return -1;
            }
            if (memcmp(fat_buffer, compare_sector, 512)) {
                if (!difference)
                    report_problem(state, "The file allocation table copies differ.");
                difference = 1;
                if (permit_repair(state, "Replace the damaged FAT copy",
                                  CAT_MISMATCH)) {
                    if (fat_volume_io(&state->volume, 1, other, 1, fat_buffer))
                        ++state->unrepaired;
                    else
                        ++state->repaired;
                } else ++state->unrepaired;
            }
        }
    }
    return difference;
}

static unsigned chain_length(struct scan_state *state, unsigned first)
{
    unsigned current = first;
    unsigned next;
    unsigned count = 0;
    memset(chain_seen, 0, sizeof(chain_seen));
    while (fat_volume_valid_cluster(&state->volume, current) &&
           !bit_get(chain_seen, current) && !bit_get(claimed, current)) {
        bit_set(chain_seen, current);
        bit_set(claimed, current);
        ++count;
        if (fat_volume_get(&state->volume, current, &next, fat_buffer))
            break;
        if (fat_volume_eoc(&state->volume, next))
            break;
        current = next;
    }
    return count;
}

static int create_chk_entry(struct scan_state *state, unsigned first,
                            unsigned long size)
{
    unsigned sector_index;
    for (sector_index = 0; sector_index < state->volume.root_sectors;
         ++sector_index) {
        unsigned offset;
        unsigned long position = state->volume.root_start + sector_index;
        if (fat_volume_io(&state->volume, 0, position, 1, directory_sector))
            return 1;
        for (offset = 0; offset < 512; offset += 32) {
            unsigned char *entry = directory_sector + offset;
            if (entry[0] == 0 || entry[0] == 0xe5) {
                char name[9];
                memset(entry, 0, 32);
                sprintf(name, "FILE%04u", state->next_chk++ % 10000U);
                memcpy(entry, name, 8);
                memcpy(entry + 8, "CHK", 3);
                entry[11] = 0x20;
                put_word(entry + 26, first);
                put_dword(entry + 28, size);
                set_current_timestamp(entry);
                return repair_directory_sector(state, position);
            }
        }
    }
    return 1;
}

static void find_lost_clusters(struct scan_state *state)
{
    unsigned cluster;
    unsigned value;
    unsigned long cluster_bytes =
        (unsigned long)state->volume.sectors_per_cluster * 512UL;
    if (state->options.custom &&
        state->options.policies[CAT_LOST] == POLICY_DELETE)
        state->options.no_save = 1;
    else if (state->options.custom &&
             state->options.policies[CAT_LOST] == POLICY_SAVE)
        state->options.no_save = 0;
    memset(incoming, 0, sizeof(incoming));
    for (cluster = 2; cluster <= state->volume.clusters + 1U; ++cluster) {
        if (state->aborted)
            return;
        if (fat_volume_get(&state->volume, cluster, &value, fat_buffer))
            continue;
        if (!bit_get(claimed, cluster) &&
            fat_volume_valid_cluster(&state->volume, value))
            bit_set(incoming, value);
    }
    for (cluster = 2; cluster <= state->volume.clusters + 1U; ++cluster) {
        unsigned count;
        if (state->aborted)
            return;
        if (bit_get(claimed, cluster) || bit_get(incoming, cluster))
            continue;
        if (fat_volume_get(&state->volume, cluster, &value, fat_buffer) ||
            (!fat_volume_valid_cluster(&state->volume, value) &&
             !fat_volume_eoc(&state->volume, value)))
            continue;
        ++state->lost_clusters;
        report_problem(state, "Lost clusters were found.");
        if (!permit_repair(state, state->options.no_save
                ? "Free this lost cluster chain"
                : "Save this lost cluster chain as a file", CAT_LOST)) {
            ++state->unrepaired;
            chain_length(state, cluster);
            continue;
        }
        if (state->options.no_save) {
            unsigned current = cluster;
            while (fat_volume_valid_cluster(&state->volume, current) &&
                   !bit_get(claimed, current)) {
                unsigned next;
                fat_volume_get(&state->volume, current, &next, fat_buffer);
                bit_set(claimed, current);
                repair_fat(state, current, 0, CAT_LOST);
                if (fat_volume_eoc(&state->volume, next))
                    break;
                current = next;
            }
        } else {
            count = chain_length(state, cluster);
            if (!count || create_chk_entry(state, cluster,
                                            (unsigned long)count * cluster_bytes))
                ++state->unrepaired;
        }
    }
    /* Cyclic orphan chains have no head. Preserve or free each remaining one. */
    for (cluster = 2; cluster <= state->volume.clusters + 1U; ++cluster) {
        unsigned current;
        unsigned next;
        unsigned count;
        if (state->aborted)
            return;
        if (bit_get(claimed, cluster))
            continue;
        if (fat_volume_get(&state->volume, cluster, &value, fat_buffer) ||
            (!fat_volume_valid_cluster(&state->volume, value) &&
             !fat_volume_eoc(&state->volume, value)))
            continue;
        ++state->lost_clusters;
        report_problem(state, "A cyclic lost cluster chain was found.");
        if (!permit_repair(state, state->options.no_save
                ? "Free this cyclic lost cluster chain"
                : "Save this cyclic lost cluster chain as a file", CAT_LOST)) {
            chain_length(state, cluster);
            ++state->unrepaired;
            continue;
        }
        memset(chain_seen, 0, sizeof(chain_seen));
        current = cluster;
        count = 0;
        while (fat_volume_valid_cluster(&state->volume, current) &&
               !bit_get(chain_seen, current)) {
            bit_set(chain_seen, current);
            bit_set(claimed, current);
            ++count;
            if (fat_volume_get(&state->volume, current, &next, fat_buffer))
                break;
            if (state->options.no_save)
                repair_fat(state, current, 0, CAT_LOST);
            else if (bit_get(chain_seen, next)) {
                repair_fat(state, current,
                           state->volume.fat16 ? 0xffffU : 0x0fffU,
                           CAT_LOST);
                break;
            }
            current = next;
        }
        if (!state->options.no_save &&
            create_chk_entry(state, cluster,
                (unsigned long)count * cluster_bytes))
            ++state->unrepaired;
    }
}

static int replace_directory_start(struct scan_state *state, unsigned first,
                                   unsigned bad, unsigned replacement,
                                   unsigned depth)
{
    unsigned cluster = first, next, sector_count, sector_index;
    unsigned long base;
    int root = first == 0;
    if (depth > MAX_DEPTH) return 0;
    do {
        if (root) {
            base = state->volume.root_start;
            sector_count = state->volume.root_sectors;
        } else {
            if (!fat_volume_valid_cluster(&state->volume, cluster)) return 0;
            base = fat_volume_cluster_sector(&state->volume, cluster);
            sector_count = state->volume.sectors_per_cluster;
        }
        for (sector_index = 0; sector_index < sector_count; ++sector_index) {
            unsigned offset;
            unsigned long sector = base + sector_index;
            if (fat_volume_io(&state->volume, 0, sector, 1, directory_sector))
                return 0;
            for (offset = 0; offset < 512; offset += 32) {
                unsigned char *entry = directory_sector + offset;
                unsigned child;
                if (!entry[0]) return 0;
                if (entry[0] == 0xe5 || (entry[11] & 0x0f) == 0x0f ||
                    (entry[11] & 0x08) || dot_entry(entry))
                    continue;
                child = get_word(entry + 26);
                if (child == bad) {
                    put_word(entry + 26, replacement);
                    return !repair_directory_sector(state, sector);
                }
                if ((entry[11] & 0x10) && child &&
                    replace_directory_start(state, child, bad, replacement,
                                            depth + 1))
                    return 1;
                if (fat_volume_io(&state->volume, 0, sector, 1,
                                  directory_sector))
                    return 0;
            }
        }
        if (root || fat_volume_get(&state->volume, cluster, &next, fat_buffer) ||
            fat_volume_eoc(&state->volume, next))
            break;
        cluster = next;
    } while (fat_volume_valid_cluster(&state->volume, cluster));
    return 0;
}

static unsigned find_verified_free_cluster(struct scan_state *state,
                                           unsigned avoid)
{
    unsigned candidate, value, sector_index;
    for (candidate = 2; candidate <= state->volume.clusters + 1U;
         ++candidate) {
        int good = 1;
        if (candidate == avoid ||
            fat_volume_get(&state->volume, candidate, &value, fat_buffer) ||
            value)
            continue;
        for (sector_index = 0;
             sector_index < state->volume.sectors_per_cluster; ++sector_index) {
            unsigned long sector =
                fat_volume_cluster_sector(&state->volume, candidate) +
                sector_index;
            if (fat_volume_io(&state->volume, 0, sector, 1, surface_sector) ||
                fat_volume_io(&state->volume, 1, sector, 1, surface_sector) ||
                fat_volume_io(&state->volume, 0, sector, 1, compare_sector) ||
                memcmp(surface_sector, compare_sector, 512)) {
                good = 0;
                break;
            }
        }
        if (good) return candidate;
    }
    return 0;
}

static int relocate_occupied_cluster(struct scan_state *state, unsigned bad)
{
    unsigned replacement, next, predecessor, value, sector_index;
    int linked = 0;
    if (!permit_repair(state, "Relocate data from the damaged cluster",
                       CAT_BAD_CLUSTER))
        return 1;
    replacement = find_verified_free_cluster(state, bad);
    if (!replacement ||
        fat_volume_get(&state->volume, bad, &next, fat_buffer))
        return 1;
    for (sector_index = 0;
         sector_index < state->volume.sectors_per_cluster; ++sector_index) {
        unsigned long source = fat_volume_cluster_sector(&state->volume, bad) +
            sector_index;
        unsigned long target =
            fat_volume_cluster_sector(&state->volume, replacement) + sector_index;
        if (fat_volume_io(&state->volume, 0, source, 1, surface_sector) ||
            fat_volume_io(&state->volume, 1, target, 1, surface_sector) ||
            fat_volume_io(&state->volume, 0, target, 1, compare_sector) ||
            memcmp(surface_sector, compare_sector, 512))
            return 1;
    }
    if (fat_volume_set(&state->volume, replacement, next, fat_buffer)) return 1;
    for (predecessor = 2; predecessor <= state->volume.clusters + 1U;
         ++predecessor)
        if (predecessor != bad &&
            !fat_volume_get(&state->volume, predecessor, &value, fat_buffer) &&
            value == bad) {
            if (fat_volume_set(&state->volume, predecessor, replacement,
                               fat_buffer))
                return 1;
            linked = 1;
            break;
        }
    if (!linked && !replace_directory_start(state, 0, bad, replacement, 0))
        return 1;
    if (fat_volume_set(&state->volume, bad,
            state->volume.fat16 ? 0xfff7U : 0x0ff7U, fat_buffer))
        return 1;
    bit_set(claimed, replacement);
    bit_clear(claimed, bad);
    ++state->repaired;
    return 0;
}

static void surface_scan(struct scan_state *state)
{
    unsigned cluster;
    for (cluster = 2; cluster <= state->volume.clusters + 1U; ++cluster) {
        unsigned sector_index;
        unsigned fat_value;
        int failed = 0;
        if (state->aborted)
            return;
        if (!fat_volume_get(&state->volume, cluster, &fat_value, fat_buffer) &&
            fat_volume_bad(&state->volume, fat_value))
            continue;
        for (sector_index = 0;
             sector_index < state->volume.sectors_per_cluster; ++sector_index) {
            unsigned long sector =
                fat_volume_cluster_sector(&state->volume, cluster) +
                sector_index;
            if (fat_volume_io(&state->volume, 0, sector, 1, surface_sector)) {
                failed = 1;
                break;
            }
            if (!injected_surface_fired &&
                injected_surface_cluster == (long)cluster) {
                injected_surface_fired = 1;
                failed = 1;
                break;
            }
            /* Free space can be verified through the complete write/read
               path without risking live file data.  Re-write the original
               bytes so /SURFACE remains non-destructive. */
            if (!bit_get(claimed, cluster) &&
                (fat_volume_io(&state->volume, 1, sector, 1, surface_sector) ||
                 fat_volume_io(&state->volume, 0, sector, 1, compare_sector) ||
                 memcmp(surface_sector, compare_sector, 512))) {
                failed = 1;
                break;
            }
        }
        if (failed) {
            ++state->bad_clusters;
            report_problem(state, "An unreadable data cluster was found.");
            if (!bit_get(claimed, cluster))
                repair_fat(state, cluster,
                           state->volume.fat16 ? 0xfff7U : 0x0ff7U,
                           CAT_BAD_CLUSTER);
            else if (relocate_occupied_cluster(state, cluster))
                ++state->unrepaired;
        }
    }
}

static void write_repair_log(const struct scan_state *state)
{
    FILE *file;
    if (!state->errors || !state->options.save_log)
        return;
    file = fopen("SCANDISK.LOG",
                 state->options.save_log == 2 ? "w" : "a");
    if (!file)
        return;
    fprintf(file,
            "Drive %c: %u problem(s), %u repair(s), %u unresolved.\n",
            'A' + state->volume.drive, state->errors, state->repaired,
            state->unrepaired);
    fclose(file);
}

static int restore_undo_disk(unsigned source_drive)
{
    char path[] = "A:\\SCANDISK.UND";
    unsigned char header[20];
    struct fat_volume volume;
    unsigned long count;
    unsigned long index;
    unsigned target;
    unsigned long expected_hash;
    unsigned long actual_hash = 2166136261UL;
    unsigned i;
    FILE *file;

    path[0] = (char)('A' + source_drive);
    file = fopen(path, "rb");
    if (!file) {
        fputs("ScanDisk cannot find SCANDISK.UND on the Undo disk.\n", stderr);
        return 2;
    }
    if (fread(header, 1, sizeof(header), file) != sizeof(header) ||
        memcmp(header, "SDUNDO1", 7) ||
        fread(compare_sector, 1, 512, file) != 512) {
        fclose(file);
        fputs("The Undo disk is invalid or incomplete.\n", stderr);
        return 2;
    }
    target = header[8];
    count = get_dword(header + 10);
    expected_hash = get_dword(header + 14);
    if (target >= 26 || target == source_drive ||
        fat_volume_open(&volume, target, boot_sector) != FATVOL_OK ||
        header[9] != volume.media ||
        memcmp(compare_sector + 11, boot_sector + 11, 25)) {
        fclose(file);
        fputs("The Undo disk does not match the drive it describes.\n", stderr);
        return 2;
    }
    for (index = 0; index < count; ++index) {
        unsigned char number[4];
        unsigned long sector;
        if (fseek(file, 20UL + 512UL + index * 516UL, SEEK_SET) ||
            fread(number, 1, 4, file) != 4) {
            fclose(file);
            fputs("The Undo disk is incomplete.\n", stderr);
            return 2;
        }
        sector = get_dword(number);
        if (sector >= volume.total_sectors ||
            fat_volume_io(&volume, 0, sector, 1, journal_sector)) {
            fclose(file);
            fputs("The repaired drive cannot be verified.\n", stderr);
            return 2;
        }
        for (i = 0; i < 4; ++i)
            actual_hash = (actual_hash ^ number[i]) * 16777619UL;
        for (i = 0; i < 512; ++i)
            actual_hash = (actual_hash ^ journal_sector[i]) * 16777619UL;
    }
    if (!expected_hash || actual_hash != expected_hash) {
        fclose(file);
        fputs("The drive changed after the Undo disk was created.\n", stderr);
        return 2;
    }
    for (index = count; index; --index) {
        unsigned char number[4];
        unsigned long offset = 20UL + 512UL + (index - 1UL) * 516UL;
        unsigned long sector;
        if (fseek(file, offset, SEEK_SET) ||
            fread(number, 1, 4, file) != 4 ||
            fread(journal_sector, 1, 512, file) != 512) {
            fclose(file);
            fputs("The Undo disk is incomplete.\n", stderr);
            return 2;
        }
        sector = get_dword(number);
        if (sector >= volume.total_sectors ||
            fat_volume_io(&volume, 1, sector, 1, journal_sector)) {
            fclose(file);
            fputs("ScanDisk could not restore a recorded disk sector.\n", stderr);
            return 2;
        }
    }
    fclose(file);
    printf("The changes to drive %c: were undone.\n", 'A' + target);
    return 0;
}

static int scan_drive(unsigned drive, const struct options *options)
{
    struct scan_state state;
    int result;
    memset(&state, 0, sizeof(state));
    state.options = *options;
    memset(claimed, 0, sizeof(claimed));
    printf("Checking drive %c:...\n", 'A' + drive);
    result = fat_volume_open(&state.volume, drive, boot_sector);
    if (result != FATVOL_OK) {
        fprintf(stderr, "SCANDISK cannot examine drive %c: (%s).\n",
                'A' + drive, result == FATVOL_IO_ERROR
                    ? "read error" : "unsupported or invalid FAT volume");
        return 1;
    }
    if (compare_fat_mirrors(&state) < 0) {
        puts("ScanDisk was stopped after a physical disk read failure.");
        return 3;
    }
    scan_directory(&state, 0, 0, 0);
    find_lost_clusters(&state);
    if (state.options.surface_prompt && !state.options.surface) {
        int answer;
        fputs("Perform a surface scan (Y/N)? ", stdout);
        fflush(stdout);
        do answer = toupper(getchar());
        while (answer == '\r' || answer == '\n' || answer == ' ');
        putchar('\n');
        state.options.surface = answer == 'Y';
    }
    if (state.options.surface) {
        unsigned pass;
        for (pass = 0; pass < state.options.surface_passes &&
                       !state.aborted; ++pass) {
            if (state.options.surface_passes > 1)
                printf("Surface scan pass %u of %u.\n", pass + 1,
                       state.options.surface_passes);
            surface_scan(&state);
        }
    }
    finish_undo_disk(&state);
    write_repair_log(&state);
    if (state.aborted) {
        puts("ScanDisk was stopped before checking completed.");
        return 3;
    }
    if (state.options.fragment)
        printf("Fragmented chain transitions: %lu\n", state.fragments);
    if (!state.options.no_summary) {
        printf("%lu file(s), %lu director%s, %lu byte(s) checked.\n",
               state.files, state.directories,
               state.directories == 1 ? "y" : "ies", state.bytes);
        printf("%u problem(s), %u repair(s), %u unresolved.\n",
               state.errors, state.repaired, state.unrepaired);
    }
    if (!state.errors)
        puts("ScanDisk found no problems.");
    else if (!state.unrepaired)
        puts("ScanDisk repaired the problems it found.");
    if (state.unrepaired)
        return 255;
    return state.errors ? 254 : 0;
}

static int make_short_name(const char *component, unsigned length,
                           unsigned char name[11])
{
    unsigned source = 0, target = 0;
    int extension = 0;
    memset(name, ' ', 11);
    if (!length)
        return 1;
    while (source < length) {
        unsigned char c = (unsigned char)component[source++];
        if (c == '.') {
            if (extension)
                return 1;
            extension = 1;
            target = 8;
            continue;
        }
        if (c <= ' ' || c == '"' || c == '+' || c == ',' || c == '/' ||
            c == ':' || c == ';' || c == '<' || c == '=' || c == '>' ||
            c == '[' || c == '\\' || c == ']' || c == '|')
            return 1;
        if ((!extension && target >= 8) || (extension && target >= 11))
            return 1;
        name[target++] = (unsigned char)toupper(c);
    }
    return name[0] == ' ';
}

static int find_directory_entry(struct fat_volume *volume, unsigned first,
                                const unsigned char name[11],
                                unsigned char result[32])
{
    unsigned cluster = first, next, sector_count, sector_index;
    unsigned long base;
    int root = first == 0;
    memset(chain_seen, 0, sizeof(chain_seen));
    do {
        if (root) {
            base = volume->root_start;
            sector_count = volume->root_sectors;
        } else {
            if (!fat_volume_valid_cluster(volume, cluster) ||
                bit_get(chain_seen, cluster))
                return 1;
            bit_set(chain_seen, cluster);
            base = fat_volume_cluster_sector(volume, cluster);
            sector_count = volume->sectors_per_cluster;
        }
        for (sector_index = 0; sector_index < sector_count; ++sector_index) {
            unsigned offset;
            if (fat_volume_io(volume, 0, base + sector_index, 1,
                              directory_sector))
                return 1;
            for (offset = 0; offset < 512; offset += 32) {
                unsigned char *entry = directory_sector + offset;
                if (!entry[0])
                    return 1;
                if (entry[0] != 0xe5 && (entry[11] & 0x0f) != 0x0f &&
                    !(entry[11] & 0x08) && !memcmp(entry, name, 11)) {
                    memcpy(result, entry, 32);
                    return 0;
                }
            }
        }
        if (root || fat_volume_get(volume, cluster, &next, fat_buffer) ||
            fat_volume_eoc(volume, next))
            break;
        cluster = next;
    } while (1);
    return 1;
}

static int analyze_fragmentation(const char *specification)
{
    struct fat_volume volume;
    union REGS regs;
    struct SREGS segments;
    char path[192], current[128];
    const char *source = specification;
    char *p, *component;
    unsigned drive, directory = 0, first, next = 0;
    unsigned transitions = 0, clusters = 0;
    unsigned char name[11], entry[32];

    memset(&regs, 0, sizeof(regs));
    regs.h.ah = 0x19;
    intdos(&regs, &regs);
    drive = regs.h.al;
    if (isalpha((unsigned char)source[0]) && source[1] == ':') {
        drive = toupper((unsigned char)source[0]) - 'A';
        source += 2;
    }
    if (*source != '\\' && *source != '/') {
        memset(current, 0, sizeof(current));
        memset(&regs, 0, sizeof(regs));
        regs.h.ah = 0x47;
        regs.h.dl = (unsigned char)(drive + 1);
        regs.x.si = FP_OFF(current);
        segread(&segments);
        segments.ds = FP_SEG(current);
        int86x(0x21, &regs, &regs, &segments);
        if (regs.x.cflag) {
            fputs("SCANDISK cannot determine the current directory.\n", stderr);
            return 2;
        }
        path[0] = '\\'; path[1] = 0;
        if (current[0]) { strcat(path, current); strcat(path, "\\"); }
        if (strlen(path) + strlen(source) >= sizeof(path)) return 2;
        strcat(path, source);
    } else {
        if (strlen(source) >= sizeof(path)) return 2;
        strcpy(path, source);
    }
    for (p = path; *p; ++p)
        if (*p == '/') *p = '\\';
    if (fat_volume_open(&volume, drive, boot_sector) != FATVOL_OK) {
        fprintf(stderr, "SCANDISK cannot examine drive %c:.\n", 'A' + drive);
        return 2;
    }
    component = path;
    while (*component == '\\') ++component;
    while (*component) {
        char *end = component;
        int last;
        while (*end && *end != '\\') ++end;
        last = *end == 0;
        if (make_short_name(component, (unsigned)(end - component), name) ||
            find_directory_entry(&volume, directory, name, entry)) {
            fprintf(stderr, "SCANDISK cannot find %s.\n", specification);
            return 2;
        }
        if (!last) {
            if (!(entry[11] & 0x10)) {
                fprintf(stderr, "SCANDISK cannot find %s.\n", specification);
                return 2;
            }
            directory = get_word(entry + 26);
            component = end + 1;
            while (*component == '\\') ++component;
        } else break;
    }
    if (!*component || (entry[11] & 0x10)) {
        fputs("/FRAGMENT requires a file name, not a directory.\n", stderr);
        return 2;
    }
    first = get_word(entry + 26);
    memset(chain_seen, 0, sizeof(chain_seen));
    while (fat_volume_valid_cluster(&volume, first) &&
           !bit_get(chain_seen, first)) {
        bit_set(chain_seen, first);
        ++clusters;
        if (fat_volume_get(&volume, first, &next, fat_buffer)) return 2;
        if (fat_volume_eoc(&volume, next)) break;
        if (!fat_volume_valid_cluster(&volume, next)) {
            fputs("The file has an invalid cluster chain.\n", stderr);
            return 2;
        }
        if (next != first + 1U) ++transitions;
        first = next;
    }
    if (!fat_volume_eoc(&volume, next) &&
        fat_volume_valid_cluster(&volume, first) && bit_get(chain_seen, first)) {
        fputs("The file has a cyclic cluster chain.\n", stderr);
        return 2;
    }
    printf("%s occupies %u cluster(s) in %u fragment(s).\n", specification,
           clusters, clusters ? transitions + 1U : 0U);
    return 0;
}

static int analyze_fragmentation_spec(const char *specification)
{
    struct find_t found;
    char resolved[192];
    const char *separator = specification;
    const char *scan;
    unsigned prefix;
    unsigned matches = 0;
    int status = 0;
    for (scan = specification; *scan; ++scan)
        if (*scan == '\\' || *scan == '/' || *scan == ':')
            separator = scan + 1;
    prefix = (unsigned)(separator - specification);
    if (_dos_findfirst(specification,
            _A_NORMAL | _A_RDONLY | _A_HIDDEN | _A_SYSTEM | _A_ARCH,
            &found)) {
        fprintf(stderr, "SCANDISK cannot find %s.\n", specification);
        return 2;
    }
    do {
        if (prefix + strlen(found.name) >= sizeof(resolved)) {
            status = 2;
            break;
        }
        memcpy(resolved, specification, prefix);
        strcpy(resolved + prefix, found.name);
        if (analyze_fragmentation(resolved))
            status = 2;
        ++matches;
    } while (!_dos_findnext(&found));
    return matches ? status : 2;
}

static void clear_interface(void)
{
    union REGS regs;
    memset(&regs, 0, sizeof(regs));
    regs.h.ah = 6;
    regs.h.bh = 7;
    regs.x.dx = 0x184f;
    int86(0x10, &regs, &regs);
    memset(&regs, 0, sizeof(regs));
    regs.h.ah = 2;
    int86(0x10, &regs, &regs);
}

static void initialize_ui_mouse(void)
{
    union REGS regs;
    void interrupt far (*handler)(void) = _dos_getvect(0x33);
    ui_mouse_available = 0;
    if (!handler || (!FP_SEG(handler) && !FP_OFF(handler))) return;
    memset(&regs, 0, sizeof(regs));
    int86(0x33, &regs, &regs);
    if (regs.x.ax != 0xffff) return;
    ui_mouse_available = 1;
    regs.x.ax = 1;
    int86(0x33, &regs, &regs);
}

static int interface_key(void)
{
    union REGS regs;
    for (;;) {
        if (kbhit()) return getch();
        if (ui_mouse_available) {
            memset(&regs, 0, sizeof(regs));
            regs.x.ax = 3;
            int86(0x33, &regs, &regs);
            if (!(regs.x.bx & 1)) {
                ui_mouse_latched = 0;
            } else if (!ui_mouse_latched) {
                ui_mouse_latched = 1;
                ui_mouse_x = regs.x.cx;
                ui_mouse_y = regs.x.dx;
                return UI_MOUSE_KEY;
            }
        }
        memset(&regs, 0, sizeof(regs));
        int86(0x28, &regs, &regs);
    }
}

static int interactive_setup(struct options *options, unsigned drive)
{
    int key;
    initialize_ui_mouse();
    options->interactive = 1;
again:
    clear_interface();
    puts("Microsoft ScanDisk");
    puts("==================");
    printf("Drive %c: is ready to be checked.\n", 'A' + drive);
    printf("Test type: %s; automatic repair: %s.\n",
           options->surface ? "thorough surface" : "standard",
           options->autofix ? "on" : "off");
    puts("[ Start ]   [ Thorough ]   [ Auto Fix ]   [ Exit ]");
    puts("ENTER starts; T and A change options; ESC exits.");
    printf("Mouse navigation: %s.\n",
           ui_mouse_available ? "available" : "not installed");
    key = interface_key();
    if (key == UI_MOUSE_KEY) {
        if (ui_mouse_y / 8U != 4) goto again;
        if (ui_mouse_x < 80) key = '\r';
        else if (ui_mouse_x < 208) key = 'T';
        else if (ui_mouse_x < 336) key = 'A';
        else key = 27;
    }
    if (key == 27) return -1;
    if (key == 't' || key == 'T') {
        options->surface = !options->surface;
        options->surface_explicit = 1;
        goto again;
    }
    if (key == 'a' || key == 'A') {
        options->autofix = !options->autofix;
        options->check_only = 0;
        goto again;
    }
    if (key != '\r' && key != '\n') goto again;
    return 0;
}

int main(int argc, char **argv)
{
    struct options options;
    unsigned drive;
    unsigned status = 0;
    union REGS regs;
    const char *surface_failure;
    if (parse_options(argc, argv, &options)) {
        usage();
        return 1;
    }
    surface_failure = getenv("SCANDISK_FAILCLUSTER");
    if (surface_failure && *surface_failure)
        injected_surface_cluster = strtol(surface_failure, NULL, 0);
    load_custom_options(&options, argv[0]);
    if (options.mono)
        puts("Output mode: monochrome text.");
    if (options.undo) {
        drive = options.drive_count ? 0 : 0;
        if (options.drive_count)
            while (!(options.drive_mask & (1UL << drive)))
                ++drive;
        return restore_undo_disk(drive);
    }
    if (options.fragment) {
        return analyze_fragmentation_spec(options.fragment_spec);
    }
    if (argc == 1 && !options.drive_count) {
        memset(&regs, 0, sizeof(regs));
        regs.h.ah = 0x19;
        intdos(&regs, &regs);
        options.drive_mask = 1UL << regs.h.al;
        options.drive_count = 1;
        if (interactive_setup(&options, regs.h.al) < 0) return 0;
    }
    if (options.all) {
        for (drive = 0; drive < 26; ++drive) {
            struct fat_volume probe;
            if (fat_volume_open(&probe, drive, boot_sector) == FATVOL_OK)
                {
                    unsigned result = scan_drive(drive, &options);
                    if (result == 3)
                        return 3;
                    if (result == 255 || (result == 254 && status == 0))
                        status = result;
                }
        }
    } else {
        if (!options.drive_count) {
            memset(&regs, 0, sizeof(regs));
            regs.h.ah = 0x19;
            intdos(&regs, &regs);
            options.drive_mask = 1UL << regs.h.al;
            options.drive_count = 1;
        }
        for (drive = 0; drive < 26; ++drive)
            if (options.drive_mask & (1UL << drive)) {
                unsigned result = scan_drive(drive, &options);
                if (result == 3)
                    return 3;
                if (result == 255 || (result == 254 && status == 0))
                    status = result;
            }
    }
    return status;
}
