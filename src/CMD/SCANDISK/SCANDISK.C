#include <ctype.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../RECOVERY/FATVOL.H"

#define BIT_BYTES 8192
#define MAX_DEPTH 64

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
    int undo;
    unsigned drive_count;
    unsigned long drive_mask;
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
    puts("Syntax: SCANDISK [drive:] [/ALL] [/AUTOFIX] [/CHECKONLY]");
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
            else if (equal_switch(argument, "SURFACE")) options->surface = 1;
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

static void load_custom_options(struct options *options)
{
    FILE *file;
    char line[96];
    if (!options->custom)
        return;
    file = fopen("SCANDISK.INI", "r");
    if (!file)
        return;
    while (fgets(line, sizeof(line), file)) {
        char *equal = strchr(line, '=');
        char *p;
        if (!equal)
            continue;
        *equal++ = 0;
        for (p = line; *p; ++p)
            *p = (char)toupper((unsigned char)*p);
        while (*equal == ' ' || *equal == '\t')
            ++equal;
        if (!strcmp(line, "AUTOFIX"))
            options->autofix = toupper((unsigned char)*equal) == 'Y';
        else if (!strcmp(line, "SURFACE"))
            options->surface = toupper((unsigned char)*equal) == 'Y';
        else if (!strcmp(line, "SAVELOST"))
            options->no_save = toupper((unsigned char)*equal) != 'Y';
    }
    fclose(file);
    if (options->check_only)
        options->autofix = 0;
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

static int permit_repair(struct scan_state *state, const char *action)
{
    int answer;
    if (state->options.check_only)
        return 0;
    if (state->options.autofix || state->repair_all)
        return begin_undo_disk(state), 1;
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
                      unsigned value)
{
    if (!permit_repair(state, "Repair this allocation-table error")) {
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
            if (permit_repair(state, "Set the file size to zero")) {
                put_dword(entry + 28, 0);
                *entry_changed = 1;
                ++state->repaired;
            } else ++state->unrepaired;
        }
        return 0;
    }
    if (!directory && !size) {
        report_problem(state, "A zero-length file owns allocated clusters.");
        if (permit_repair(state, "Detach the unused cluster chain")) {
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
                           state->volume.fat16 ? 0xffffU : 0x0fffU);
            break;
        }
        if (bit_get(claimed, current)) {
            report_problem(state, "Two files or directories share a cluster.");
            if (previous)
                repair_fat(state, previous,
                           state->volume.fat16 ? 0xffffU : 0x0fffU);
            else if (permit_repair(state, "Detach the cross-linked file")) {
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
                           state->volume.fat16 ? 0xffffU : 0x0fffU);
            break;
        }
        if (fat_volume_valid_cluster(&state->volume, next) &&
            next != current + 1U)
            ++state->fragments;
        if (!directory && expected && count == expected &&
            !fat_volume_eoc(&state->volume, next)) {
            report_problem(state, "A file owns more clusters than its size requires.");
            repair_fat(state, current,
                       state->volume.fat16 ? 0xffffU : 0x0fffU);
            break;
        }
        if (fat_volume_eoc(&state->volume, next))
            break;
        if (!fat_volume_valid_cluster(&state->volume, next)) {
            report_problem(state, "A cluster chain contains an invalid link.");
            repair_fat(state, current,
                       state->volume.fat16 ? 0xffffU : 0x0fffU);
            break;
        }
        previous = current;
        current = next;
    }
    if (!directory && expected > count) {
        report_problem(state, "A file is longer than its available cluster chain.");
        if (permit_repair(state, "Shorten the file to its readable chain")) {
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
        if (permit_repair(state, "Repair the . directory entry")) {
            memset(dot, 0, 32); memcpy(dot, dot_name, 11);
            dot[11] = 0x10; put_word(dot + 26, self);
            ++state->repaired; changed = 1;
        } else ++state->unrepaired;
    }
    if (dotdot_bad) {
        report_problem(state, "A directory has an invalid .. entry.");
        if (permit_repair(state, "Repair the .. directory entry")) {
            memset(dotdot, 0, 32); memcpy(dotdot, dotdot_name, 11);
            dotdot[11] = 0x10; put_word(dotdot + 26, parent);
            ++state->repaired; changed = 1;
        } else ++state->unrepaired;
    }
    if (changed && repair_directory_sector(state, sector))
        ++state->unrepaired;
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
                if (entry[0] == 0xe5 ||
                    (entry[11] & 0x0f) == 0x0f || (entry[11] & 0x08))
                    continue;
                child = get_word(entry + 26);
                size = get_dword(entry + 28);
                if (entry[11] & 0x10) {
                    if (dot_entry(entry))
                        continue;
                    ++state->directories;
                    if (!child) {
                        report_problem(state,
                            "A directory has no starting cluster.");
                        ++state->unrepaired;
                        continue;
                    }
                    if (size) {
                        report_problem(state,
                            "A directory entry has a nonzero file size.");
                        if (permit_repair(state,
                                "Set the directory size to zero")) {
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
                return 1;
            }
            if (memcmp(fat_buffer, compare_sector, 512)) {
                if (!difference)
                    report_problem(state, "The file allocation table copies differ.");
                difference = 1;
                if (permit_repair(state, "Replace the damaged FAT copy")) {
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
                : "Save this lost cluster chain as a file")) {
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
                repair_fat(state, current, 0);
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
                : "Save this cyclic lost cluster chain as a file")) {
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
                repair_fat(state, current, 0);
            else if (bit_get(chain_seen, next)) {
                repair_fat(state, current,
                           state->volume.fat16 ? 0xffffU : 0x0fffU);
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

static void surface_scan(struct scan_state *state)
{
    unsigned cluster;
    for (cluster = 2; cluster <= state->volume.clusters + 1U; ++cluster) {
        unsigned sector_index;
        int failed = 0;
        if (state->aborted)
            return;
        for (sector_index = 0;
             sector_index < state->volume.sectors_per_cluster; ++sector_index) {
            unsigned long sector =
                fat_volume_cluster_sector(&state->volume, cluster) +
                sector_index;
            if (fat_volume_io(&state->volume, 0, sector, 1, surface_sector)) {
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
                           state->volume.fat16 ? 0xfff7U : 0x0ff7U);
            else
                ++state->unrepaired;
        }
    }
}

static void write_repair_log(const struct scan_state *state)
{
    FILE *file;
    if (!state->errors)
        return;
    file = fopen("SCANDISK.LOG", "a");
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
    compare_fat_mirrors(&state);
    scan_directory(&state, 0, 0, 0);
    find_lost_clusters(&state);
    if (state.options.surface)
        surface_scan(&state);
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

int main(int argc, char **argv)
{
    struct options options;
    unsigned drive;
    unsigned status = 0;
    union REGS regs;
    if (parse_options(argc, argv, &options)) {
        usage();
        return 1;
    }
    load_custom_options(&options);
    if (options.undo) {
        drive = options.drive_count ? 0 : 0;
        if (options.drive_count)
            while (!(options.drive_mask & (1UL << drive)))
                ++drive;
        return restore_undo_disk(drive);
    }
    if (options.fragment) {
        return analyze_fragmentation(options.fragment_spec);
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
