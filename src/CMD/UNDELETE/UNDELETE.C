#include <ctype.h>
#include <direct.h>
#include <dos.h>
#include <process.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "../RECOVERY/RECOVERY.H"

extern unsigned __cdecl abs_read(unsigned drive, unsigned long sector,
                                 unsigned count, void *buffer);
extern unsigned __cdecl abs_write(unsigned drive, unsigned long sector,
                                  unsigned count, void *buffer);
extern unsigned __cdecl tracker_install(void);
extern unsigned __cdecl tracker_probe(void);
extern unsigned __cdecl tracker_remove(void);
extern unsigned __cdecl tracker_keep_paragraphs(void);
extern void __cdecl tracker_set_sentry(unsigned mode);

#define SENTRY_VERSION 2
#define SENTRY_RULES_SIZE 160

struct sentry_header {
    char magic[8];
    unsigned version;
    unsigned long next_id;
};

struct sentry_record {
    unsigned active;
    unsigned long deleted_time;
    unsigned long size;
    char stored_name[13];
    char original_path[128];
};

struct volume {
    unsigned drive;
    unsigned sectors_per_cluster;
    unsigned reserved;
    unsigned fats;
    unsigned root_entries;
    unsigned sectors_per_fat;
    unsigned root_sectors;
    unsigned long total_sectors;
    unsigned long root_start;
    unsigned long data_start;
    int fat16;
};

static unsigned char io_buffer[1024];
static unsigned char entry[32];
static char sentry_rules[SENTRY_RULES_SIZE] =
    "*.* -*.TMP -*.VM? -*.WOA -*.SWP -*.SPL -*.RMG -*.IMG -*.THM -*.DOV";
static unsigned sentry_archive = 0;
static unsigned sentry_days = 7;
static unsigned sentry_percentage = 20;

static int create_sentry(unsigned drive);

static unsigned get_word(const unsigned char *p)
{
    return p[0] | ((unsigned)p[1] << 8);
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

static int load_volume(struct volume *volume, unsigned drive)
{
    unsigned long data_sectors;
    unsigned long clusters;

    if (abs_read(drive, 0, 1, io_buffer) || get_word(io_buffer + 11) != 512)
        return 1;
    memset(volume, 0, sizeof(*volume));
    volume->drive = drive;
    volume->sectors_per_cluster = io_buffer[13];
    volume->reserved = get_word(io_buffer + 14);
    volume->fats = io_buffer[16];
    volume->root_entries = get_word(io_buffer + 17);
    volume->sectors_per_fat = get_word(io_buffer + 22);
    volume->total_sectors = get_word(io_buffer + 19);
    if (!volume->total_sectors)
        volume->total_sectors = get_dword(io_buffer + 32);
    if (!volume->sectors_per_cluster || !volume->fats ||
        !volume->sectors_per_fat || !volume->root_entries)
        return 1;
    volume->root_sectors = (volume->root_entries * 32U + 511U) / 512U;
    volume->root_start = volume->reserved +
                         (unsigned long)volume->fats * volume->sectors_per_fat;
    volume->data_start = volume->root_start + volume->root_sectors;
    data_sectors = volume->total_sectors - volume->data_start;
    clusters = data_sectors / volume->sectors_per_cluster;
    volume->fat16 = clusters >= 4085;
    return 0;
}

static unsigned fat_get(const struct volume *volume, unsigned cluster)
{
    unsigned long byte_offset;
    unsigned long sector_number;
    unsigned offset;
    unsigned value;

    byte_offset = volume->fat16 ? (unsigned long)cluster * 2UL
                                : (unsigned long)cluster * 3UL / 2UL;
    sector_number = volume->reserved + byte_offset / 512UL;
    offset = (unsigned)(byte_offset & 511U);
    if (abs_read(volume->drive, sector_number, offset == 511 ? 2 : 1, io_buffer))
        return 0xffff;
    value = get_word(io_buffer + offset);
    if (!volume->fat16) {
        if (cluster & 1)
            value >>= 4;
        else
            value &= 0x0fff;
    }
    return value;
}

static int fat_set_copy(const struct volume *volume, unsigned copy,
                        unsigned cluster, unsigned value)
{
    unsigned long byte_offset;
    unsigned long sector_number;
    unsigned offset;
    unsigned count;
    unsigned old;

    byte_offset = volume->fat16 ? (unsigned long)cluster * 2UL
                                : (unsigned long)cluster * 3UL / 2UL;
    sector_number = volume->reserved +
                    (unsigned long)copy * volume->sectors_per_fat +
                    byte_offset / 512UL;
    offset = (unsigned)(byte_offset & 511U);
    count = offset == 511 ? 2 : 1;
    if (abs_read(volume->drive, sector_number, count, io_buffer))
        return 1;
    if (volume->fat16) {
        put_word(io_buffer + offset, value);
    } else {
        old = get_word(io_buffer + offset);
        if (cluster & 1)
            old = (old & 0x000f) | ((value & 0x0fff) << 4);
        else
            old = (old & 0xf000) | (value & 0x0fff);
        put_word(io_buffer + offset, old);
    }
    return abs_write(volume->drive, sector_number, count, io_buffer) ? 1 : 0;
}

static int fat_set(const struct volume *volume, unsigned cluster, unsigned value)
{
    unsigned copy;
    for (copy = 0; copy < volume->fats; ++copy)
        if (fat_set_copy(volume, copy, cluster, value))
            return 1;
    return 0;
}

static unsigned long cluster_sector(const struct volume *volume, unsigned cluster)
{
    return volume->data_start +
           (unsigned long)(cluster - 2) * volume->sectors_per_cluster;
}

static void make_83(const char *source, unsigned char result[11], int pattern)
{
    unsigned index = 0;
    unsigned ext = 8;
    memset(result, ' ', 11);
    while (*source && *source != '\\' && *source != '/') {
        if (*source == '.') {
            index = ext;
            ++source;
            continue;
        }
        if (*source == '*' && pattern) {
            while (index < (index < 8 ? 8 : 11))
                result[index++] = '?';
            ++source;
            continue;
        }
        if (index < 11)
            result[index++] = (unsigned char)toupper(*source);
        ++source;
    }
}

static int name_matches(const unsigned char candidate[11],
                        const unsigned char pattern[11], int deleted)
{
    unsigned index;
    for (index = deleted ? 1 : 0; index < 11; ++index)
        if (pattern[index] != '?' && pattern[index] != candidate[index])
            return 0;
    return 1;
}

static void display_name(const unsigned char raw[11], int deleted)
{
    unsigned index;
    putchar(deleted ? '?' : raw[0]);
    for (index = 1; index < 8 && raw[index] != ' '; ++index)
        putchar(raw[index]);
    if (raw[8] != ' ') {
        putchar('.');
        for (index = 8; index < 11 && raw[index] != ' '; ++index)
            putchar(raw[index]);
    }
}

static int find_in_directory(const struct volume *volume, unsigned directory,
                             const unsigned char wanted[11], unsigned *found_cluster)
{
    unsigned long sector_number;
    unsigned sector_index;
    unsigned offset;
    unsigned cluster = directory;
    unsigned entries_left = volume->root_entries;

    for (;;) {
        if (!directory)
            sector_number = volume->root_start;
        else
            sector_number = cluster_sector(volume, cluster);
        for (sector_index = 0;
             sector_index < (directory ? volume->sectors_per_cluster
                                       : volume->root_sectors);
             ++sector_index) {
            if (abs_read(volume->drive, sector_number + sector_index, 1, io_buffer))
                return 1;
            for (offset = 0; offset < 512 && (directory || entries_left); offset += 32) {
                if (!directory)
                    --entries_left;
                if (io_buffer[offset] == 0)
                    return 1;
                if (io_buffer[offset] == 0xe5 || io_buffer[offset + 11] == 0x0f)
                    continue;
                if ((io_buffer[offset + 11] & 0x10) &&
                    name_matches(io_buffer + offset, wanted, 0)) {
                    *found_cluster = get_word(io_buffer + offset + 26);
                    return 0;
                }
            }
        }
        if (!directory)
            break;
        cluster = fat_get(volume, cluster);
        if (cluster < 2 || cluster >= (volume->fat16 ? 0xfff8 : 0x0ff8))
            break;
    }
    return 1;
}

static int resolve_directory(const struct volume *volume, char *path,
                             unsigned *directory, char **filespec)
{
    char *part = path;
    char *slash;
    unsigned char wanted[11];

    *directory = 0;
    while (*part == '\\' || *part == '/')
        ++part;
    for (;;) {
        slash = strpbrk(part, "\\/");
        if (!slash) {
            *filespec = part;
            return 0;
        }
        *slash = 0;
        if (*part) {
            make_83(part, wanted, 0);
            if (find_in_directory(volume, *directory, wanted, directory))
                return 1;
        }
        part = slash + 1;
    }
}

static int name_exists(const struct volume *volume, unsigned directory,
                       const unsigned char wanted[11])
{
    unsigned long sector_number;
    unsigned sector_index;
    unsigned offset;
    unsigned cluster = directory;
    unsigned entries_left = volume->root_entries;

    for (;;) {
        sector_number = directory ? cluster_sector(volume, cluster)
                                  : volume->root_start;
        for (sector_index = 0;
             sector_index < (directory ? volume->sectors_per_cluster
                                       : volume->root_sectors);
             ++sector_index) {
            if (abs_read(volume->drive, sector_number + sector_index, 1, io_buffer))
                return 1;
            for (offset = 0; offset < 512 && (directory || entries_left); offset += 32) {
                if (!directory)
                    --entries_left;
                if (io_buffer[offset] == 0)
                    return 0;
                if (io_buffer[offset] != 0xe5 && io_buffer[offset + 11] != 0x0f &&
                    name_matches(io_buffer + offset, wanted, 0))
                    return 1;
            }
        }
        if (!directory)
            break;
        cluster = fat_get(volume, cluster);
        if (cluster < 2 || cluster >= (volume->fat16 ? 0xfff8 : 0x0ff8))
            break;
    }
    return 0;
}

static int restore_entry(const struct volume *volume, unsigned directory,
                         unsigned long dir_sector, unsigned dir_offset,
                         unsigned char raw[32], int automatic)
{
    static const char replacements[] = "#%&-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    unsigned char wanted[11];
    unsigned first_cluster = get_word(raw + 26);
    unsigned long size = get_dword(raw + 28);
    unsigned long cluster_bytes = (unsigned long)volume->sectors_per_cluster * 512UL;
    unsigned count = size ? (unsigned)((size + cluster_bytes - 1) / cluster_bytes) : 0;
    unsigned cluster;
    unsigned index;
    int answer;

    memcpy(wanted, raw, 11);
    if (automatic) {
        for (index = 0; replacements[index]; ++index) {
            wanted[0] = replacements[index];
            if (!name_exists(volume, directory, wanted))
                break;
        }
        if (!replacements[index])
            return 1;
    } else {
        printf("Restore ");
        display_name(raw, 1);
        printf(" (Y/N)? ");
        answer = getchar();
        while (answer != '\n' && getchar() != '\n')
            ;
        if (toupper(answer) != 'Y')
            return 0;
        printf("First character of filename: ");
        answer = getchar();
        while (answer != '\n' && getchar() != '\n')
            ;
        if (!isalnum(answer) && strchr("#%&-_$!", answer) == NULL)
            return 1;
        wanted[0] = (unsigned char)toupper(answer);
        if (name_exists(volume, directory, wanted)) {
            puts("A file with that name already exists.");
            return 1;
        }
    }
    for (index = 0, cluster = first_cluster; index < count; ++index, ++cluster)
        if (cluster < 2 || fat_get(volume, cluster) != 0) {
            puts("File data has been reused; recovery is unsafe.");
            return 1;
        }
    for (index = 0, cluster = first_cluster; index < count; ++index, ++cluster) {
        unsigned next = index + 1 == count ? (volume->fat16 ? 0xffff : 0x0fff)
                                           : cluster + 1;
        if (fat_set(volume, cluster, next)) {
            while (index--)
                fat_set(volume, first_cluster + index, 0);
            return 1;
        }
    }
    if (abs_read(volume->drive, dir_sector, 1, io_buffer))
        goto rollback;
    io_buffer[dir_offset] = wanted[0];
    if (abs_write(volume->drive, dir_sector, 1, io_buffer))
        goto rollback;
    printf("Restored ");
    display_name(wanted, 0);
    putchar('\n');
    return 0;

rollback:
    for (index = 0; index < count; ++index)
        fat_set(volume, first_cluster + index, 0);
    return 1;
}

static int current_path(unsigned drive, char *path)
{
    union REGS inregs, outregs;
    struct SREGS segregs;
    void far *far_path = (void far *)path;

    memset(&inregs, 0, sizeof(inregs));
    segread(&segregs);
    inregs.h.ah = 0x47;
    inregs.h.dl = (unsigned char)(drive + 1);
    inregs.x.si = FP_OFF(far_path);
    segregs.ds = FP_SEG(far_path);
    intdosx(&inregs, &outregs, &segregs);
    return outregs.x.cflag ? 1 : 0;
}

static int process_directory(const struct volume *volume, unsigned directory,
                             const unsigned char pattern[11], int list_only,
                             int automatic)
{
    unsigned long sector_number;
    unsigned sector_index;
    unsigned offset;
    unsigned cluster = directory;
    unsigned entries_left = volume->root_entries;
    unsigned found = 0;
    int status = 0;

    for (;;) {
        sector_number = directory ? cluster_sector(volume, cluster)
                                  : volume->root_start;
        for (sector_index = 0;
             sector_index < (directory ? volume->sectors_per_cluster
                                       : volume->root_sectors);
             ++sector_index) {
            if (abs_read(volume->drive, sector_number + sector_index, 1, io_buffer))
                return 1;
            for (offset = 0; offset < 512 && (directory || entries_left); offset += 32) {
                if (!directory)
                    --entries_left;
                if (io_buffer[offset] == 0)
                    goto done;
                if (io_buffer[offset] != 0xe5 || io_buffer[offset + 11] == 0x0f ||
                    (io_buffer[offset + 11] & 0x18) ||
                    !name_matches(io_buffer + offset, pattern, 1))
                    continue;
                memcpy(entry, io_buffer + offset, sizeof(entry));
                ++found;
                if (list_only) {
                    display_name(entry, 1);
                    printf("  %lu bytes\n", get_dword(entry + 28));
                } else {
                    status |= restore_entry(volume, directory,
                                            sector_number + sector_index,
                                            offset, entry, automatic);
                }
            }
        }
        if (!directory)
            break;
        cluster = fat_get(volume, cluster);
        if (cluster < 2 || cluster >= (volume->fat16 ? 0xfff8 : 0x0ff8))
            break;
    }
done:
    if (!found) {
        puts("No deleted files were found.");
        return 1;
    }
    return status;
}

static int tracker_name(const unsigned char name[11])
{
    return !memcmp(name, "PCTRACKRDEL", 11) ||
           !memcmp(name, "PCTRACKRTMP", 11) ||
           !memcmp(name, "PCTRACKRACT", 11);
}

static unsigned chain_length(const struct volume *volume, unsigned first)
{
    unsigned cluster = first;
    unsigned count = 0;
    unsigned limit = (unsigned)((volume->total_sectors - volume->data_start) /
                                volume->sectors_per_cluster);

    while (cluster >= 2 && cluster < (volume->fat16 ? 0xfff8 : 0x0ff8) &&
           count < limit) {
        ++count;
        cluster = fat_get(volume, cluster);
        if (cluster == 0xffff)
            return 0;
    }
    return count;
}

static int write_tracked_file(const struct volume *volume, unsigned directory,
                              const unsigned char raw[32], FILE *file)
{
    struct tracker_entry tracked;
    unsigned cluster;
    unsigned index;

    memset(&tracked, 0, sizeof(tracked));
    tracked.directory_cluster = directory;
    memcpy(tracked.name, raw, 11);
    tracked.attributes = raw[11];
    tracked.time = get_word(raw + 22);
    tracked.date = get_word(raw + 24);
    tracked.first_cluster = get_word(raw + 26);
    tracked.size = get_dword(raw + 28);
    tracked.cluster_count = chain_length(volume, tracked.first_cluster);
    if (tracked.size && !tracked.cluster_count)
        return 1;
    if (fwrite(&tracked, 1, sizeof(tracked), file) != sizeof(tracked))
        return 1;
    cluster = tracked.first_cluster;
    for (index = 0; index < tracked.cluster_count; ++index) {
        if (fwrite(&cluster, 1, sizeof(cluster), file) != sizeof(cluster))
            return 1;
        cluster = fat_get(volume, cluster);
    }
    return 0;
}

static int create_tracker(unsigned drive, unsigned maximum)
{
    struct volume volume;
    struct tracker_header header;
    char final_name[] = "A:\\PCTRACKR.DEL";
    char active_name[] = "A:\\PCTRACKR.ACT";
    FILE *file;

    if (!maximum || maximum > 999 || load_volume(&volume, drive))
        return 1;
    final_name[0] = active_name[0] = (char)('A' + drive);
    memset(&header, 0, sizeof(header));
    memcpy(header.magic, "MSD5TRK", 8);
    header.version = RECOVERY_VERSION;
    header.drive = (unsigned char)drive;
    header.maximum_entries = maximum;
    _dos_setfileattr(final_name, 0);
    remove(final_name);
    _dos_setfileattr(active_name, 0);
    remove(active_name);
    file = fopen(active_name, "wb");
    if (!file)
        return 1;
    if (fwrite(&header, 1, sizeof(header), file) != sizeof(header)) {
        fclose(file);
        remove(active_name);
        return 1;
    }
    if (fclose(file)) {
        remove(active_name);
        return 1;
    }
    _dos_setfileattr(active_name, 0x06);
    printf("Deletion tracking file initialized on drive %c:.\n", 'A' + drive);
    return 0;
}

static unsigned default_tracker_entries(unsigned drive)
{
    unsigned char sector[512];
    unsigned long total;

    if (abs_read(drive, 0, 1, sector))
        return 0;
    total = get_word(sector + 19);
    if (!total)
        total = get_dword(sector + 32);
    if (total <= 720)
        return 25;
    if (total <= 1440)
        return 50;
    if (total <= 2880)
        return 75;
    if (total <= 40960UL)
        return 101;
    if (total <= 65536UL)
        return 202;
    return 303;
}

static int parse_tracker_switch(const char *argument, unsigned *drive,
                                unsigned *entries)
{
    const char *value = argument + 2;
    char *end;
    unsigned long parsed;

    if (!isalpha(value[0]))
        return 1;
    *drive = (unsigned)(toupper(value[0]) - 'A');
    value++;
    if (!*value) {
        *entries = default_tracker_entries(*drive);
        return *entries ? 0 : 1;
    }
    if (*value++ != '-' || !isdigit(*value))
        return 1;
    parsed = strtoul(value, &end, 10);
    if (*end || parsed < 1 || parsed > 999)
        return 1;
    *entries = (unsigned)parsed;
    return 0;
}

static int report_protection_status(void)
{
    char active_name[] = "A:\\PCTRACKR.ACT";
    char final_name[] = "A:\\PCTRACKR.DEL";
    char sentry_name[] = "A:\\SENTRY\\CONTROL.DAT";
    unsigned drive;
    unsigned found = 0;
    int resident = tracker_probe() != 0;

    for (drive = 0; drive < 26; ++drive) {
        FILE *file;
        active_name[0] = final_name[0] = (char)('A' + drive);
        sentry_name[0] = (char)('A' + drive);
        file = fopen(sentry_name, "rb");
        if (file) {
            fclose(file);
            ++found;
            printf("Drive %c: Delete Sentry %s.\n", 'A' + drive,
                   resident ? "is active" : "is configured but not loaded");
            continue;
        }
        file = fopen(active_name, "rb");
        if (!file)
            file = fopen(final_name, "rb");
        if (!file)
            continue;
        fclose(file);
        ++found;
        printf("Drive %c: Delete Tracker %s.\n", 'A' + drive,
               resident ? "is active" : "is configured but not loaded");
    }
    if (!found)
        puts("No Undelete protection is configured.");
    else if (!resident)
        puts("The Undelete memory-resident program is not loaded.");
    return 0;
}

static void keep_tracker_resident(void)
{
    unsigned environment;
    unsigned paragraphs;

    tracker_install();
    environment = *(unsigned far *)MK_FP(_psp, 0x2c);
    if (environment)
        _dos_freemem(environment);
    paragraphs = tracker_keep_paragraphs();
    if (paragraphs < 0x0c00)
        paragraphs = 0x0c00;
    _dos_keep(0, paragraphs);
}

static char *trim_text(char *text)
{
    char *end;

    while (*text && isspace(*text))
        ++text;
    end = text + strlen(text);
    while (end > text && isspace(end[-1]))
        *--end = 0;
    return text;
}

static int true_value(const char *value)
{
    return !stricmp(value, "TRUE") || !stricmp(value, "YES") ||
           !strcmp(value, "1") || !stricmp(value, "ON");
}

static int write_default_undelete_ini(unsigned drive)
{
    FILE *file = fopen("UNDELETE.INI", "wt");
    if (!file)
        return 1;
    fprintf(file,
            "[sentry.drives]\n%c=\n"
            "[sentry.files]\n%s\n"
            "[mirror.drives]\n"
            "[configuration]\narchive=FALSE\ndays=7\npercentage=20\n"
            "[defaults]\nd.sentry=TRUE\nd.tracker=FALSE\n",
            'A' + drive, sentry_rules);
    return fclose(file) ? 1 : 0;
}

static int load_undelete_ini(int forced_sentry_drive)
{
    enum {
        SECTION_NONE, SECTION_SENTRY_DRIVES, SECTION_SENTRY_FILES,
        SECTION_MIRROR, SECTION_CONFIGURATION, SECTION_DEFAULTS
    } section = SECTION_NONE;
    unsigned tracker_drives[26];
    unsigned sentry_drives[26];
    unsigned drive;
    unsigned current_drive;
    unsigned configured = 0;
    int tracker_default = 0;
    int sentry_default = 1;
    int installed = tracker_probe();
    int read_error;
    char line[160];
    FILE *file;

    if (installed) {
        fputs("UNDELETE: unload the current protection method first.\n", stderr);
        return 1;
    }
    memset(tracker_drives, 0, sizeof(tracker_drives));
    memset(sentry_drives, 0, sizeof(sentry_drives));
    strcpy(sentry_rules,
           "*.* -*.TMP -*.VM? -*.WOA -*.SWP -*.SPL -*.RMG -*.IMG -*.THM -*.DOV");
    sentry_archive = 0;
    sentry_days = 7;
    sentry_percentage = 20;
    file = fopen("UNDELETE.INI", "rt");
    if (!file) {
        _dos_getdrive(&current_drive);
        drive = forced_sentry_drive >= 0 ? (unsigned)forced_sentry_drive
                                          : current_drive - 1;
        if (write_default_undelete_ini(drive)) {
            fputs("UNDELETE: cannot create UNDELETE.INI.\n", stderr);
            return 1;
        }
        sentry_drives[drive] = 1;
        sentry_default = 1;
        tracker_default = 0;
        goto configure;
    }
    while (fgets(line, sizeof(line), file)) {
        char *text = trim_text(line);
        char *equals;
        if (!*text || *text == ';' || *text == '#')
            continue;
        if (*text == '[') {
            char *close = strchr(text, ']');
            if (!close) {
                fclose(file);
                fputs("UNDELETE: invalid UNDELETE.INI section.\n", stderr);
                return 1;
            }
            *close = 0;
            if (!stricmp(text + 1, "sentry.drives"))
                section = SECTION_SENTRY_DRIVES;
            else if (!stricmp(text + 1, "sentry.files"))
                section = SECTION_SENTRY_FILES;
            else if (!stricmp(text + 1, "mirror.drives"))
                section = SECTION_MIRROR;
            else if (!stricmp(text + 1, "configuration"))
                section = SECTION_CONFIGURATION;
            else if (!stricmp(text + 1, "defaults"))
                section = SECTION_DEFAULTS;
            else
                section = SECTION_NONE;
            continue;
        }
        if (section == SECTION_SENTRY_FILES) {
            if (strlen(text) >= sizeof(sentry_rules)) {
                fclose(file);
                fputs("UNDELETE: sentry.files is too long.\n", stderr);
                return 1;
            }
            strcpy(sentry_rules, text);
            continue;
        }
        equals = strchr(text, '=');
        if (!equals)
            continue;
        *equals++ = 0;
        text = trim_text(text);
        equals = trim_text(equals);
        if (section == SECTION_SENTRY_DRIVES &&
            isalpha(text[0]) && !text[1]) {
            sentry_drives[toupper(text[0]) - 'A'] = 1;
        } else if (section == SECTION_MIRROR && forced_sentry_drive < 0 &&
                   isalpha(text[0]) && !text[1]) {
            unsigned entries;
            drive = (unsigned)(toupper(text[0]) - 'A');
            if (*equals) {
                char *end;
                unsigned long value = strtoul(equals, &end, 10);
                if (*end || value < 1 || value > 999) {
                    fclose(file);
                    fputs("UNDELETE: invalid tracker entry count in UNDELETE.INI.\n",
                          stderr);
                    return 1;
                }
                entries = (unsigned)value;
            } else {
                entries = default_tracker_entries(drive);
                if (!entries) {
                    fclose(file);
                    fprintf(stderr, "UNDELETE: cannot inspect drive %c:.\n",
                            'A' + drive);
                    return 1;
                }
            }
            tracker_drives[drive] = entries;
        } else if (section == SECTION_CONFIGURATION) {
            char *end;
            unsigned long value;
            if (!stricmp(text, "archive")) {
                sentry_archive = true_value(equals);
            } else if (!stricmp(text, "days")) {
                value = strtoul(equals, &end, 10);
                if (*end || value > 3650) {
                    fclose(file);
                    fputs("UNDELETE: invalid days value in UNDELETE.INI.\n", stderr);
                    return 1;
                }
                sentry_days = (unsigned)value;
            } else if (!stricmp(text, "percentage")) {
                value = strtoul(equals, &end, 10);
                if (*end || value < 1 || value > 100) {
                    fclose(file);
                    fputs("UNDELETE: invalid percentage in UNDELETE.INI.\n", stderr);
                    return 1;
                }
                sentry_percentage = (unsigned)value;
            }
        } else if (section == SECTION_DEFAULTS) {
            if (!stricmp(text, "d.tracker"))
                tracker_default = true_value(equals);
            else if (!stricmp(text, "d.sentry"))
                sentry_default = true_value(equals);
        }
    }
    read_error = ferror(file);
    if (fclose(file) || read_error) {
        fputs("UNDELETE: cannot read UNDELETE.INI.\n", stderr);
        return 1;
    }
configure:
    if (forced_sentry_drive >= 0) {
        sentry_default = 1;
        tracker_default = 0;
        sentry_drives[forced_sentry_drive] = 1;
    }
    if (tracker_default && sentry_default) {
        fputs("UNDELETE: UNDELETE.INI enables conflicting protection methods.\n",
              stderr);
        return 1;
    }
    if (sentry_default) {
        for (drive = 0; drive < 26; ++drive) {
            if (!sentry_drives[drive])
                continue;
            if (create_sentry(drive))
                return 1;
            ++configured;
        }
        if (!configured) {
            _dos_getdrive(&current_drive);
            drive = current_drive - 1;
            if (create_sentry(drive))
                return 1;
        }
        tracker_set_sentry(1);
        keep_tracker_resident();
        return 0;
    }
    if (!tracker_default) {
            fputs("UNDELETE: no protection method is enabled in UNDELETE.INI.\n",
                  stderr);
        return 1;
    }
    for (drive = 0; drive < 26; ++drive) {
        if (!tracker_drives[drive])
            continue;
        if (create_tracker(drive, tracker_drives[drive])) {
            fprintf(stderr, "UNDELETE: cannot enable Delete Tracker on drive %c:.\n",
                    'A' + drive);
            return 1;
        }
        printf("Delete Tracker enabled on drive %c: for %u entries.\n",
               'A' + drive, tracker_drives[drive]);
        ++configured;
    }
    if (!configured) {
        _dos_getdrive(&current_drive);
        drive = current_drive - 1;
        tracker_drives[drive] = default_tracker_entries(drive);
        if (!tracker_drives[drive] || create_tracker(drive, tracker_drives[drive])) {
            fputs("UNDELETE: cannot configure the current drive.\n", stderr);
            return 1;
        }
        printf("Delete Tracker enabled on drive %c: for %u entries.\n",
               'A' + drive, tracker_drives[drive]);
    }
    if (!installed)
        keep_tracker_resident();
    return 0;
}

static int path_exists(const char *path)
{
    struct find_t found;
    return !_dos_findfirst(path, 0x37, &found);
}

static int create_sentry(unsigned drive)
{
    struct sentry_header header;
    char directory[] = "A:\\SENTRY";
    char control[] = "A:\\SENTRY\\CONTROL.DAT";
    FILE *file;

    directory[0] = control[0] = (char)('A' + drive);
    if (_mkdir(directory) && !path_exists(directory)) {
        fprintf(stderr, "UNDELETE: cannot create SENTRY on drive %c:.\n",
                'A' + drive);
        return 1;
    }
    _dos_setfileattr(directory, 0x06);
    file = fopen(control, "rb");
    if (file) {
        int valid = fread(&header, 1, sizeof(header), file) == sizeof(header) &&
                    !memcmp(header.magic, "MSD6SNT", 8) &&
                    header.version == SENTRY_VERSION;
        fclose(file);
        if (!valid) {
            fprintf(stderr, "UNDELETE: invalid SENTRY metadata on drive %c:.\n",
                    'A' + drive);
            return 1;
        }
        return 0;
    }
    memset(&header, 0, sizeof(header));
    memcpy(header.magic, "MSD6SNT", 8);
    header.version = SENTRY_VERSION;
    header.next_id = 1;
    file = fopen(control, "wb");
    if (!file) {
        fprintf(stderr, "UNDELETE: cannot initialize SENTRY on drive %c:.\n",
                'A' + drive);
        return 1;
    }
    {
        int write_error = fwrite(&header, 1, sizeof(header), file) != sizeof(header);
        int close_error = fclose(file);
        if (write_error || close_error) {
            remove(control);
            fprintf(stderr, "UNDELETE: cannot initialize SENTRY on drive %c:.\n",
                    'A' + drive);
            return 1;
        }
    }
    _dos_setfileattr(control, 0x06);
    printf("Delete Sentry enabled on drive %c:.\n", 'A' + drive);
    return 0;
}

static int canonical_delete_path(const char far *far_path, char path[128],
                                 unsigned *drive)
{
    char relative[128];
    char current[67];
    unsigned index;
    unsigned current_drive;

    for (index = 0; index + 1 < sizeof(relative) && far_path[index]; ++index)
        relative[index] = far_path[index];
    relative[index] = 0;
    if (!*relative || strchr(relative, '*') || strchr(relative, '?'))
        return 1;
    _dos_getdrive(&current_drive);
    *drive = current_drive - 1;
    if (isalpha(relative[0]) && relative[1] == ':') {
        *drive = (unsigned)(toupper(relative[0]) - 'A');
        memmove(relative, relative + 2, strlen(relative + 2) + 1);
    }
    if (relative[0] == '\\' || relative[0] == '/') {
        if (strlen(relative) + 3 > 128)
            return 1;
        sprintf(path, "%c:%s", 'A' + *drive, relative);
    } else {
        if (current_path(*drive, current))
            return 1;
        if (strlen(current) + strlen(relative) + 4 > 128)
            return 1;
        if (*current)
            sprintf(path, "%c:\\%s\\%s", 'A' + *drive, current, relative);
        else
            sprintf(path, "%c:\\%s", 'A' + *drive, relative);
    }
    return !strnicmp(path + 2, "\\SENTRY\\", 8);
}

static int wildcard_match(const char *pattern, const char *name)
{
    while (*pattern) {
        if (*pattern == '*') {
            ++pattern;
            if (!*pattern)
                return 1;
            while (*name) {
                if (wildcard_match(pattern, name))
                    return 1;
                ++name;
            }
            return wildcard_match(pattern, name);
        }
        if (*pattern != '?' && toupper(*pattern) != toupper(*name))
            return 0;
        if (!*name)
            return 0;
        ++pattern;
        ++name;
    }
    return !*name;
}

static int sentry_file_policy(const char *path, unsigned long *size)
{
    struct find_t found;
    char rules[SENTRY_RULES_SIZE];
    char *token;
    const char *name = strrchr(path, '\\');
    int protect = 0;

    name = name ? name + 1 : path;
    if (_dos_findfirst(path, 0x27, &found) || (found.attrib & 0x10))
        return 0;
    if (!sentry_archive && (found.attrib & 0x20))
        return 0;
    *size = found.size;
    strcpy(rules, sentry_rules);
    token = strtok(rules, " \t");
    while (token) {
        int include = *token != '-';
        if (!include)
            ++token;
        if (*token && wildcard_match(token, name))
            protect = include;
        token = strtok(NULL, " \t");
    }
    return protect;
}

static int discard_sentry_record(unsigned drive, FILE *file, long offset,
                                 struct sentry_record *record)
{
    char stored[32];

    sprintf(stored, "%c:\\SENTRY\\%s", 'A' + drive, record->stored_name);
    _dos_setfileattr(stored, 0);
    if (remove(stored))
        return 1;
    record->active = 0;
    fseek(file, offset, SEEK_SET);
    if (fwrite(record, 1, sizeof(*record), file) != sizeof(*record))
        return 1;
    return 0;
}

static int enforce_sentry_limits(unsigned drive, unsigned long incoming)
{
    struct sentry_header header;
    struct sentry_record record;
    struct volume volume;
    char control[] = "A:\\SENTRY\\CONTROL.DAT";
    unsigned long total = 0;
    unsigned long limit;
    unsigned long now = (unsigned long)time(NULL);
    unsigned long maximum_age = (unsigned long)sentry_days * 86400UL;
    long offset;
    FILE *file;

    if (load_volume(&volume, drive))
        return 1;
    limit = (volume.total_sectors * 512UL / 100UL) * sentry_percentage;
    if (incoming > limit)
        return 1;
    control[0] = (char)('A' + drive);
    file = fopen(control, "rb+");
    if (!file || fread(&header, 1, sizeof(header), file) != sizeof(header) ||
        memcmp(header.magic, "MSD6SNT", 8) || header.version != SENTRY_VERSION) {
        if (file)
            fclose(file);
        return 1;
    }
    for (;;) {
        offset = ftell(file);
        if (fread(&record, 1, sizeof(record), file) != sizeof(record))
            break;
        if (!record.active)
            continue;
        if (sentry_days && record.deleted_time && now >= record.deleted_time &&
            now - record.deleted_time > maximum_age) {
            if (discard_sentry_record(drive, file, offset, &record)) {
                fclose(file);
                return 1;
            }
            fseek(file, offset + (long)sizeof(record), SEEK_SET);
        } else {
            total += record.size;
        }
    }
    while (total + incoming > limit) {
        int discarded = 0;
        fseek(file, sizeof(header), SEEK_SET);
        for (;;) {
            offset = ftell(file);
            if (fread(&record, 1, sizeof(record), file) != sizeof(record))
                break;
            if (!record.active)
                continue;
            if (discard_sentry_record(drive, file, offset, &record)) {
                fclose(file);
                return 1;
            }
            total = total >= record.size ? total - record.size : 0;
            discarded = 1;
            break;
        }
        if (!discarded) {
            fclose(file);
            return 1;
        }
    }
    return fclose(file) ? 1 : 0;
}

unsigned __cdecl sentry_capture_far(const char far *far_path)
{
    struct sentry_header header;
    struct sentry_record record;
    char original[128];
    char control[] = "A:\\SENTRY\\CONTROL.DAT";
    char stored[32];
    unsigned drive;
    unsigned long file_size;
    FILE *file;

    if (canonical_delete_path(far_path, original, &drive))
        return 0;
    if (!sentry_file_policy(original, &file_size))
        return 0;
    if (enforce_sentry_limits(drive, file_size))
        return 0;
    control[0] = (char)('A' + drive);
    file = fopen(control, "rb+");
    if (!file)
        return 0;
    if (fread(&header, 1, sizeof(header), file) != sizeof(header) ||
        memcmp(header.magic, "MSD6SNT", 8) ||
        header.version != SENTRY_VERSION) {
        fclose(file);
        return 0;
    }
    for (;;) {
        sprintf(stored, "%c:\\SENTRY\\%08lX.DEL", 'A' + drive,
                header.next_id++);
        if (!path_exists(stored))
            break;
        if (!header.next_id) {
            fclose(file);
            return 0;
        }
    }
    if (rename(original, stored)) {
        fclose(file);
        return 0;
    }
    memset(&record, 0, sizeof(record));
    record.active = 1;
    record.deleted_time = (unsigned long)time(NULL);
    record.size = file_size;
    strcpy(record.stored_name, strrchr(stored, '\\') + 1);
    strcpy(record.original_path, original);
    fseek(file, 0, SEEK_END);
    if (fwrite(&record, 1, sizeof(record), file) != sizeof(record)) {
        fclose(file);
        rename(stored, original);
        return 0;
    }
    rewind(file);
    {
        int write_error = fwrite(&header, 1, sizeof(header), file) != sizeof(header);
        int close_error = fclose(file);
        if (write_error || close_error) {
            rename(stored, original);
            return 0;
        }
    }
    return 1;
}

unsigned __cdecl sentry_capture_fcb(const unsigned char far *far_fcb)
{
    struct find_t found;
    union REGS inregs, outregs;
    struct SREGS segregs;
    void far *old_dta;
    char pattern[16];
    char candidate[16];
    unsigned drive;
    unsigned source;
    unsigned target = 0;
    unsigned handled = 0;

    if (far_fcb[0] == 0xff)
        far_fcb += 7;
    drive = far_fcb[0];
    if (drive) {
        pattern[target++] = candidate[0] = (char)('A' + drive - 1);
        pattern[target++] = candidate[1] = ':';
    }
    for (source = 1; source < 9 && far_fcb[source] != ' '; ++source)
        pattern[target++] = (char)far_fcb[source];
    if (far_fcb[9] != ' ') {
        pattern[target++] = '.';
        for (source = 9; source < 12 && far_fcb[source] != ' '; ++source)
            pattern[target++] = (char)far_fcb[source];
    }
    pattern[target] = 0;
    memset(&inregs, 0, sizeof(inregs));
    segread(&segregs);
    inregs.h.ah = 0x2f;
    int86x(0x21, &inregs, &outregs, &segregs);
    old_dta = MK_FP(segregs.es, outregs.x.bx);
    if (!_dos_findfirst(pattern, 0x27, &found)) {
        do {
            target = 0;
            if (drive) {
                candidate[target++] = (char)('A' + drive - 1);
                candidate[target++] = ':';
            }
            strcpy(candidate + target, found.name);
            handled |= sentry_capture_far(candidate);
        } while (!_dos_findnext(&found));
    }
    memset(&inregs, 0, sizeof(inregs));
    inregs.h.ah = 0x1a;
    inregs.x.dx = FP_OFF(old_dta);
    segregs.ds = FP_SEG(old_dta);
    int86x(0x21, &inregs, &outregs, &segregs);
    return handled;
}

static int sentry_requested_directory(unsigned drive, const char *path,
                                      char directory[128])
{
    const char *slash;
    const char *other;
    unsigned length;

    while (*path == '\\' || *path == '/')
        ++path;
    slash = strrchr(path, '\\');
    other = strrchr(path, '/');
    if (!slash || (other && other > slash))
        slash = other;
    sprintf(directory, "%c:\\", 'A' + drive);
    if (!slash)
        return 0;
    length = (unsigned)(slash - path);
    if (length && 3 + length >= 128)
        return 1;
    memcpy(directory + 3, path, length);
    directory[3 + length] = 0;
    return 0;
}

static int process_sentry(unsigned drive, const char *path,
                          const unsigned char pattern[11], int list_only,
                          int automatic)
{
    struct sentry_header header;
    struct sentry_record record;
    char control[] = "A:\\SENTRY\\CONTROL.DAT";
    char stored[32];
    char wanted_directory[128];
    char record_path[128];
    char original_name[13];
    char *name;
    unsigned char raw_name[11];
    unsigned found = 0;
    int status = 0;
    long record_offset;
    FILE *file;

    control[0] = (char)('A' + drive);
    if (sentry_requested_directory(drive, path, wanted_directory))
        return 1;
    file = fopen(control, "rb+");
    if (!file || fread(&header, 1, sizeof(header), file) != sizeof(header) ||
        memcmp(header.magic, "MSD6SNT", 8) || header.version != SENTRY_VERSION) {
        if (file)
            fclose(file);
        puts("No Delete Sentry files were found.");
        return 1;
    }
    for (;;) {
        record_offset = ftell(file);
        if (fread(&record, 1, sizeof(record), file) != sizeof(record))
            break;
        if (!record.active)
            continue;
        strcpy(record_path, record.original_path);
        name = strrchr(record_path, '\\');
        if (!name)
            continue;
        strcpy(original_name, name + 1);
        *name = 0;
        if (record_path[1] == ':' && !record_path[2])
            strcat(record_path, "\\");
        if (stricmp(record_path, wanted_directory))
            continue;
        make_83(original_name, raw_name, 0);
        if (!name_matches(raw_name, pattern, 0))
            continue;
        ++found;
        if (list_only) {
            printf("%s  protected by Delete Sentry\n", original_name);
            continue;
        }
        if (!automatic) {
            int answer;
            printf("Restore %s (Y/N)? ", original_name);
            answer = getchar();
            while (answer != '\n' && getchar() != '\n')
                ;
            if (toupper(answer) != 'Y')
                continue;
        }
        if (path_exists(record.original_path)) {
            printf("%s already exists.\n", record.original_path);
            status = 1;
            continue;
        }
        sprintf(stored, "%c:\\SENTRY\\%s", 'A' + drive,
                record.stored_name);
        if (rename(stored, record.original_path)) {
            printf("Cannot restore %s.\n", record.original_path);
            status = 1;
            continue;
        }
        record.active = 0;
        fseek(file, record_offset, SEEK_SET);
        if (fwrite(&record, 1, sizeof(record), file) != sizeof(record)) {
            rename(record.original_path, stored);
            fclose(file);
            return 1;
        }
        fseek(file, record_offset + (long)sizeof(record), SEEK_SET);
        printf("Restored %s\n", record.original_path);
    }
    fclose(file);
    if (!found) {
        puts("No Delete Sentry files were found.");
        return 1;
    }
    return status;
}

static int purge_sentry(unsigned drive)
{
    struct sentry_header header;
    struct sentry_record record;
    char control[] = "A:\\SENTRY\\CONTROL.DAT";
    char stored[32];
    FILE *file;
    unsigned purged = 0;

    control[0] = (char)('A' + drive);
    file = fopen(control, "rb");
    if (!file || fread(&header, 1, sizeof(header), file) != sizeof(header) ||
        memcmp(header.magic, "MSD6SNT", 8) || header.version != SENTRY_VERSION) {
        if (file)
            fclose(file);
        puts("No Delete Sentry files were found.");
        return 1;
    }
    while (fread(&record, 1, sizeof(record), file) == sizeof(record)) {
        if (!record.active)
            continue;
        sprintf(stored, "%c:\\SENTRY\\%s", 'A' + drive,
                record.stored_name);
        _dos_setfileattr(stored, 0);
        if (remove(stored)) {
            fclose(file);
            fprintf(stderr, "UNDELETE: cannot purge %s.\n", stored);
            return 1;
        }
        ++purged;
    }
    fclose(file);
    header.next_id = 1;
    file = fopen(control, "wb");
    if (!file || fwrite(&header, 1, sizeof(header), file) != sizeof(header)) {
        if (file)
            fclose(file);
        return 1;
    }
    if (fclose(file))
        return 1;
    _dos_setfileattr(control, 0x06);
    printf("Purged %u Delete Sentry file(s) from drive %c:.\n",
           purged, 'A' + drive);
    return 0;
}

static int find_live_entry(const struct volume *volume, unsigned directory,
                           const unsigned char wanted[11], unsigned char raw[32])
{
    unsigned long sector_number;
    unsigned sector_index;
    unsigned offset;
    unsigned cluster = directory;
    unsigned entries_left = volume->root_entries;

    for (;;) {
        sector_number = directory ? cluster_sector(volume, cluster)
                                  : volume->root_start;
        for (sector_index = 0;
             sector_index < (directory ? volume->sectors_per_cluster
                                       : volume->root_sectors);
             ++sector_index) {
            if (abs_read(volume->drive, sector_number + sector_index, 1, io_buffer))
                return 1;
            for (offset = 0; offset < 512 && (directory || entries_left);
                 offset += 32) {
                if (!directory)
                    --entries_left;
                if (!io_buffer[offset])
                    return 1;
                if (io_buffer[offset] != 0xe5 &&
                    io_buffer[offset + 11] != 0x0f &&
                    !(io_buffer[offset + 11] & 0x10) &&
                    !memcmp(io_buffer + offset, wanted, 11)) {
                    memcpy(raw, io_buffer + offset, 32);
                    return 0;
                }
            }
        }
        if (!directory)
            break;
        cluster = fat_get(volume, cluster);
        if (cluster < 2 || cluster >= (volume->fat16 ? 0xfff8 : 0x0ff8))
            break;
    }
    return 1;
}

static int copy_tracker_record(FILE *source, FILE *target)
{
    struct tracker_entry tracked;
    unsigned cluster;
    unsigned index;

    if (fread(&tracked, 1, sizeof(tracked), source) != sizeof(tracked) ||
        (target && fwrite(&tracked, 1, sizeof(tracked), target) != sizeof(tracked)))
        return 1;
    for (index = 0; index < tracked.cluster_count; ++index) {
        if (fread(&cluster, 1, sizeof(cluster), source) != sizeof(cluster) ||
            (target && fwrite(&cluster, 1, sizeof(cluster), target) != sizeof(cluster)))
            return 1;
    }
    return 0;
}

static int append_tracker(const struct volume *volume, unsigned directory,
                          const unsigned char raw[32])
{
    struct tracker_header header;
    char final_name[] = "A:\\PCTRACKR.DEL";
    char temp_name[] = "A:\\PCTRACKR.TMP";
    FILE *source;
    FILE *target;
    unsigned index;

    final_name[0] = temp_name[0] = (char)('A' + volume->drive);
    source = fopen(final_name, "rb+");
    if (!source) {
        char active_name[] = "A:\\PCTRACKR.ACT";
        active_name[0] = (char)('A' + volume->drive);
        source = fopen(active_name, "rb");
        if (!source || fread(&header, 1, sizeof(header), source) != sizeof(header)) {
            if (source)
                fclose(source);
            return 1;
        }
        fclose(source);
        source = fopen(final_name, "wb+");
        if (!source || fwrite(&header, 1, sizeof(header), source) != sizeof(header)) {
            if (source)
                fclose(source);
            return 1;
        }
        _dos_setfileattr(final_name, 0x06);
        rewind(source);
    }
    if (!source || fread(&header, 1, sizeof(header), source) != sizeof(header) ||
        memcmp(header.magic, "MSD5TRK", 8) ||
        header.version != RECOVERY_VERSION || header.drive != volume->drive) {
        if (source)
            fclose(source);
        return 1;
    }
    if (header.entry_count < header.maximum_entries) {
        fseek(source, 0, SEEK_END);
        if (write_tracked_file(volume, directory, raw, source)) {
            fclose(source);
            return 1;
        }
        ++header.entry_count;
        rewind(source);
        if (fwrite(&header, 1, sizeof(header), source) != sizeof(header) ||
            fclose(source))
            return 1;
        return 0;
    }

    remove(temp_name);
    target = fopen(temp_name, "wb");
    if (!target) {
        fclose(source);
        return 1;
    }
    if (fwrite(&header, 1, sizeof(header), target) != sizeof(header) ||
        copy_tracker_record(source, NULL))
        goto rotate_error;
    for (index = 1; index < header.entry_count; ++index)
        if (copy_tracker_record(source, target))
            goto rotate_error;
    if (write_tracked_file(volume, directory, raw, target) ||
        fclose(source) || fclose(target)) {
        remove(temp_name);
        return 1;
    }
    _dos_setfileattr(final_name, 0);
    remove(final_name);
    if (rename(temp_name, final_name))
        return 1;
    _dos_setfileattr(final_name, 0x06);
    return 0;

rotate_error:
    fclose(source);
    fclose(target);
    remove(temp_name);
    return 1;
}

static int find_deleted_entry(const struct volume *volume, unsigned directory,
                              const struct tracker_entry *tracked,
                              unsigned long *found_sector, unsigned *found_offset,
                              unsigned char raw[32])
{
    unsigned long sector_number;
    unsigned sector_index;
    unsigned offset;
    unsigned cluster = directory;
    unsigned entries_left = volume->root_entries;

    for (;;) {
        sector_number = directory ? cluster_sector(volume, cluster)
                                  : volume->root_start;
        for (sector_index = 0;
             sector_index < (directory ? volume->sectors_per_cluster
                                       : volume->root_sectors);
             ++sector_index) {
            if (abs_read(volume->drive, sector_number + sector_index, 1, io_buffer))
                return 1;
            for (offset = 0; offset < 512 && (directory || entries_left); offset += 32) {
                if (!directory)
                    --entries_left;
                if (io_buffer[offset] == 0)
                    return 1;
                if (io_buffer[offset] == 0xe5 &&
                    !memcmp(io_buffer + offset + 1, tracked->name + 1, 10) &&
                    get_word(io_buffer + offset + 26) == tracked->first_cluster &&
                    get_dword(io_buffer + offset + 28) == tracked->size) {
                    memcpy(raw, io_buffer + offset, 32);
                    *found_sector = sector_number + sector_index;
                    *found_offset = offset;
                    return 0;
                }
            }
        }
        if (!directory)
            break;
        cluster = fat_get(volume, cluster);
        if (cluster < 2 || cluster >= (volume->fat16 ? 0xfff8 : 0x0ff8))
            break;
    }
    return 1;
}

static int tracked_name(const struct volume *volume, unsigned directory,
                        const struct tracker_entry *tracked, int automatic,
                        unsigned char wanted[11])
{
    static const char replacements[] = "#%&-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    unsigned index;
    int answer;

    memcpy(wanted, tracked->name, 11);
    if (!name_exists(volume, directory, wanted)) {
        if (!automatic) {
            printf("Restore ");
            display_name(wanted, 0);
            printf(" (Y/N)? ");
            answer = getchar();
            while (answer != '\n' && getchar() != '\n')
                ;
            if (toupper(answer) != 'Y')
                return 1;
        }
        return 0;
    }
    if (!automatic) {
        puts("The original filename is already in use.");
        return 1;
    }
    for (index = 0; replacements[index]; ++index) {
        wanted[0] = replacements[index];
        if (!name_exists(volume, directory, wanted))
            return 0;
    }
    return 1;
}

static int restore_tracked(const struct volume *volume, unsigned directory,
                           const struct tracker_entry *tracked, FILE *file,
                           long chain_offset, unsigned long dir_sector,
                           unsigned dir_offset, int automatic)
{
    unsigned char wanted[11];
    unsigned cluster;
    unsigned next;
    unsigned index;
    unsigned expected = tracked->size
        ? (unsigned)((tracked->size +
            (unsigned long)volume->sectors_per_cluster * 512UL - 1) /
            ((unsigned long)volume->sectors_per_cluster * 512UL)) : 0;

    if (expected != tracked->cluster_count ||
        tracked_name(volume, directory, tracked, automatic, wanted))
        return 1;
    fseek(file, chain_offset, SEEK_SET);
    for (index = 0; index < tracked->cluster_count; ++index) {
        if (fread(&cluster, 1, sizeof(cluster), file) != sizeof(cluster) ||
            cluster < 2 || fat_get(volume, cluster) != 0) {
            puts("Tracked file data has been reused; recovery is unsafe.");
            return 1;
        }
    }
    fseek(file, chain_offset, SEEK_SET);
    if (tracked->cluster_count) {
        fread(&cluster, 1, sizeof(cluster), file);
        for (index = 1; index < tracked->cluster_count; ++index) {
            fread(&next, 1, sizeof(next), file);
            if (fat_set(volume, cluster, next))
                goto rollback;
            cluster = next;
        }
        if (fat_set(volume, cluster, volume->fat16 ? 0xffff : 0x0fff))
            goto rollback;
    }
    if (abs_read(volume->drive, dir_sector, 1, io_buffer))
        goto rollback;
    memcpy(io_buffer + dir_offset, wanted, 11);
    io_buffer[dir_offset + 11] = tracked->attributes;
    put_word(io_buffer + dir_offset + 22, tracked->time);
    put_word(io_buffer + dir_offset + 24, tracked->date);
    if (abs_write(volume->drive, dir_sector, 1, io_buffer))
        goto rollback;
    printf("Restored ");
    display_name(wanted, 0);
    putchar('\n');
    return 0;

rollback:
    fseek(file, chain_offset, SEEK_SET);
    for (index = 0; index < tracked->cluster_count; ++index) {
        if (fread(&cluster, 1, sizeof(cluster), file) != sizeof(cluster))
            break;
        fat_set(volume, cluster, 0);
    }
    return 1;
}

static int process_tracker(const struct volume *volume, unsigned directory,
                           const unsigned char pattern[11], int list_only,
                           int automatic)
{
    struct tracker_header header;
    struct tracker_entry tracked;
    unsigned char raw[32];
    char filename[] = "A:\\PCTRACKR.DEL";
    unsigned long dir_sector;
    unsigned dir_offset;
    unsigned index;
    unsigned found = 0;
    int status = 0;
    long chain_offset;
    FILE *file;

    filename[0] = (char)('A' + volume->drive);
    file = fopen(filename, "rb");
    if (!file || fread(&header, 1, sizeof(header), file) != sizeof(header) ||
        memcmp(header.magic, "MSD5TRK", 8) ||
        header.version != RECOVERY_VERSION || header.drive != volume->drive) {
        if (file)
            fclose(file);
        fputs("UNDELETE: valid deletion-tracking data was not found.\n", stderr);
        return 1;
    }
    for (index = 0; index < header.entry_count; ++index) {
        if (fread(&tracked, 1, sizeof(tracked), file) != sizeof(tracked)) {
            status = 1;
            break;
        }
        chain_offset = ftell(file);
        if (tracked.directory_cluster == directory &&
            name_matches(tracked.name, pattern, 0) &&
            !find_deleted_entry(volume, directory, &tracked, &dir_sector,
                                &dir_offset, raw)) {
            ++found;
            if (list_only) {
                display_name(tracked.name, 0);
                printf("  %lu bytes\n", tracked.size);
            } else {
                status |= restore_tracked(volume, directory, &tracked, file,
                                          chain_offset, dir_sector, dir_offset,
                                          automatic);
            }
        }
        fseek(file, chain_offset +
                    (long)tracked.cluster_count * sizeof(unsigned), SEEK_SET);
    }
    fclose(file);
    if (!found) {
        puts("No tracked deleted files were found.");
        return 1;
    }
    return status;
}

static void usage(void)
{
    puts("Restores files deleted with DEL.");
    puts("UNDELETE [[drive:][path]filename] [/LIST|/ALL] [/DOS|/DT|/DS]");
    puts("UNDELETE /LOAD | /S[drive] | /Tdrive[-entries]");
    puts("         /PURGE[drive] | /STATUS | /UNLOAD");
}

void __cdecl tracker_capture_far(const char far *far_path)
{
    struct volume volume;
    unsigned drive;
    unsigned directory;
    unsigned char wanted[11];
    unsigned char raw[32];
    char path[128];
    char combined[128];
    char directory_path[67];
    char *filespec;
    unsigned index;

    for (index = 0; index + 1 < sizeof(path) && far_path[index]; ++index)
        path[index] = far_path[index];
    path[index] = 0;
    if (!*path || strchr(path, '*') || strchr(path, '?'))
        return;
    _dos_getdrive(&drive);
    --drive;
    if (isalpha(path[0]) && path[1] == ':') {
        drive = (unsigned)(toupper(path[0]) - 'A');
        memmove(path, path + 2, strlen(path + 2) + 1);
    }
    if (load_volume(&volume, drive))
        return;
    if (path[0] != '\\' && path[0] != '/') {
        if (current_path(drive, directory_path))
            return;
        if (*directory_path) {
            if (strlen(directory_path) + strlen(path) + 2 > sizeof(combined))
                return;
            strcpy(combined, directory_path);
            strcat(combined, "\\");
            strcat(combined, path);
            strcpy(path, combined);
        }
    }
    if (resolve_directory(&volume, path, &directory, &filespec) || !*filespec)
        return;
    make_83(filespec, wanted, 0);
    if (tracker_name(wanted) ||
        find_live_entry(&volume, directory, wanted, raw))
        return;
    append_tracker(&volume, directory, raw);
}

void __cdecl tracker_capture_fcb(const unsigned char far *far_fcb)
{
    struct find_t found;
    union REGS inregs, outregs;
    struct SREGS segregs;
    void far *old_dta;
    char pattern[16];
    char candidate[16];
    unsigned drive;
    unsigned source;
    unsigned target = 0;

    if (far_fcb[0] == 0xff)
        far_fcb += 7;
    drive = far_fcb[0];
    if (drive) {
        pattern[target++] = candidate[0] = (char)('A' + drive - 1);
        pattern[target++] = candidate[1] = ':';
    }
    for (source = 1; source < 9 && far_fcb[source] != ' '; ++source)
        pattern[target++] = (char)far_fcb[source];
    if (far_fcb[9] != ' ') {
        pattern[target++] = '.';
        for (source = 9; source < 12 && far_fcb[source] != ' '; ++source)
            pattern[target++] = (char)far_fcb[source];
    }
    pattern[target] = 0;
    memset(&inregs, 0, sizeof(inregs));
    segread(&segregs);
    inregs.h.ah = 0x2f;
    int86x(0x21, &inregs, &outregs, &segregs);
    old_dta = MK_FP(segregs.es, outregs.x.bx);
    if (!_dos_findfirst(pattern, 0x27, &found)) {
        do {
            target = 0;
            if (drive) {
                candidate[target++] = (char)('A' + drive - 1);
                candidate[target++] = ':';
            }
            strcpy(candidate + target, found.name);
            tracker_capture_far(candidate);
        } while (!_dos_findnext(&found));
    }
    memset(&inregs, 0, sizeof(inregs));
    inregs.h.ah = 0x1a;
    inregs.x.dx = FP_OFF(old_dta);
    segregs.ds = FP_SEG(old_dta);
    int86x(0x21, &inregs, &outregs, &segregs);
}

int main(int argc, char **argv)
{
    struct volume volume;
    unsigned drive;
    unsigned directory;
    unsigned char pattern[11];
    char path[128] = "*.*";
    char sentry_path[128];
    char combined[128];
    char directory_path[67];
    char *filespec;
    int list_only = 0;
    int automatic = 0;
    int source_dos = 0;
    int source_dt = 0;
    int source_ds = 0;
    int have_operand = 0;
    int i;

    if (argc == 2 && argv[1][0] == '/' && toupper(argv[1][1]) == 'S' &&
        (argv[1][2] == 0 || (isalpha(argv[1][2]) && argv[1][3] == 0))) {
        _dos_getdrive(&drive);
        --drive;
        if (argv[1][2])
            drive = (unsigned)(toupper(argv[1][2]) - 'A');
        return load_undelete_ini((int)drive);
    }
    if (argc == 2 && !strnicmp(argv[1], "/T", 2) &&
        stricmp(argv[1], "/TRACK") && stricmp(argv[1], "/TRACKSTATUS")) {
        unsigned entries;
        int installed;
        if (parse_tracker_switch(argv[1], &drive, &entries)) {
            usage();
            return 1;
        }
        installed = tracker_probe();
        if (create_tracker(drive, entries)) {
            fprintf(stderr, "UNDELETE: cannot enable Delete Tracker on drive %c:.\n",
                    'A' + drive);
            return 1;
        }
        printf("Delete Tracker enabled on drive %c: for %u entries.\n",
               'A' + drive, entries);
        if (installed)
            return 0;
        keep_tracker_resident();
        return 0;
    }
    if (argc == 2 && !stricmp(argv[1], "/LOAD"))
        return load_undelete_ini(-1);
    if (argc == 2 && !stricmp(argv[1], "/STATUS"))
        return report_protection_status();
    if (argc == 2 && !stricmp(argv[1], "/UNLOAD")) {
        unsigned resident = tracker_remove();
        if (!resident) {
            puts("The Undelete memory-resident program is not loaded.");
            return 1;
        }
        if (_dos_freemem(resident))
            return 1;
        puts("The Undelete memory-resident program was unloaded.");
        return 0;
    }
    if (argc == 2 && !strnicmp(argv[1], "/PURGE", 6) &&
        (argv[1][6] == 0 || (isalpha(argv[1][6]) && argv[1][7] == 0))) {
        _dos_getdrive(&drive);
        --drive;
        if (argv[1][6])
            drive = (unsigned)(toupper(argv[1][6]) - 'A');
        return purge_sentry(drive);
    }
    if (argc == 4 && !stricmp(argv[1], "/TRACK")) {
        int installed;
        if (strlen(argv[2]) != 2 || argv[2][1] != ':' || !isalpha(argv[2][0]))
            return 1;
        drive = (unsigned)(toupper(argv[2][0]) - 'A');
        installed = tracker_probe();
        if (create_tracker(drive, (unsigned)atoi(argv[3])))
            return 1;
        if (installed)
            return 0;
        keep_tracker_resident();
        return 0;
    }
    if (argc == 2 && !stricmp(argv[1], "/UNTRACK")) {
        unsigned resident = tracker_remove();
        if (!resident)
            return 1;
        return _dos_freemem(resident);
    }
    if (argc == 2 && !stricmp(argv[1], "/TRACKSTATUS"))
        return tracker_probe() ? 0 : 1;

    _dos_getdrive(&drive);
    --drive;
    for (i = 1; i < argc; ++i) {
        if (!stricmp(argv[i], "/?")) {
            usage();
            return 0;
        } else if (!stricmp(argv[i], "/LIST")) {
            list_only = 1;
        } else if (!stricmp(argv[i], "/ALL")) {
            automatic = 1;
        } else if (!stricmp(argv[i], "/DOS")) {
            source_dos = 1;
        } else if (!stricmp(argv[i], "/DT")) {
            source_dt = 1;
        } else if (!stricmp(argv[i], "/DS")) {
            source_ds = 1;
        } else if (argv[i][0] == '/' || argv[i][0] == '-') {
            usage();
            return 1;
        } else if (have_operand) {
            usage();
            return 1;
        } else {
            if (strlen(argv[i]) >= sizeof(path)) {
                usage();
                return 1;
            }
            strcpy(path, argv[i]);
            have_operand = 1;
        }
    }
    if (list_only && automatic) {
        usage();
        return 1;
    }
    if ((source_dos + source_dt + source_ds > 1) ||
        (automatic && (source_dos || source_dt || source_ds))) {
        usage();
        return 1;
    }
    if (isalpha(path[0]) && path[1] == ':') {
        drive = (unsigned)(toupper(path[0]) - 'A');
        memmove(path, path + 2, strlen(path + 2) + 1);
    }
    if (load_volume(&volume, drive)) {
        fprintf(stderr, "UNDELETE: cannot read drive %c:.\n", 'A' + drive);
        return 1;
    }
    if (path[0] != '\\' && path[0] != '/') {
        if (current_path(drive, directory_path)) {
            fputs("UNDELETE: cannot determine the current directory.\n", stderr);
            return 1;
        }
        if (*directory_path) {
            if (strlen(directory_path) + strlen(path) + 2 > sizeof(combined)) {
                usage();
                return 1;
            }
            strcpy(combined, directory_path);
            strcat(combined, "\\");
            strcat(combined, path);
            strcpy(path, combined);
        }
    }
    strcpy(sentry_path, path);
    if (resolve_directory(&volume, path, &directory, &filespec)) {
        fputs("UNDELETE: directory not found.\n", stderr);
        return 1;
    }
    if (!*filespec)
        filespec = "*.*";
    make_83(filespec, pattern, 1);
    if (!source_dos && !source_dt && !source_ds) {
        char sentry_name[] = "A:\\SENTRY\\CONTROL.DAT";
        FILE *sentry;
        sentry_name[0] = (char)('A' + drive);
        sentry = fopen(sentry_name, "rb");
        if (sentry) {
            fclose(sentry);
            source_ds = 1;
        }
    }
    if (!source_dos && !source_ds && !source_dt) {
        char tracker_name[] = "A:\\PCTRACKR.DEL";
        FILE *tracker;
        tracker_name[0] = (char)('A' + drive);
        tracker = fopen(tracker_name, "rb");
        if (tracker) {
            fclose(tracker);
            source_dt = 1;
        }
    }
    if (source_ds)
        i = process_sentry(drive, sentry_path, pattern, list_only, automatic);
    else if (source_dt)
        i = process_tracker(&volume, directory, pattern, list_only, automatic);
    else
        i = process_directory(&volume, directory, pattern, list_only, automatic);
    if (!list_only) {
        union REGS inregs, outregs;
        inregs.h.ah = 0x0d;
        intdos(&inregs, &outregs);
    }
    return i;
}
