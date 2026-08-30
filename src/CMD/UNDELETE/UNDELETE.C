#include <ctype.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern unsigned __cdecl abs_read(unsigned drive, unsigned long sector,
                                 unsigned count, void *buffer);
extern unsigned __cdecl abs_write(unsigned drive, unsigned long sector,
                                  unsigned count, void *buffer);

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

static void usage(void)
{
    puts("Restores files deleted with DEL.");
    puts("UNDELETE [[drive:][path]filename] [/LIST|/ALL] [/DOS|/DT]");
}

int main(int argc, char **argv)
{
    struct volume volume;
    unsigned drive;
    unsigned directory;
    unsigned char pattern[11];
    char path[128] = "*.*";
    char combined[128];
    char directory_path[67];
    char *filespec;
    int list_only = 0;
    int automatic = 0;
    int source_dos = 0;
    int have_operand = 0;
    int i;

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
            fputs("UNDELETE: deletion tracking is not implemented yet.\n", stderr);
            return 1;
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
    if (resolve_directory(&volume, path, &directory, &filespec)) {
        fputs("UNDELETE: directory not found.\n", stderr);
        return 1;
    }
    if (!*filespec)
        filespec = "*.*";
    make_83(filespec, pattern, 1);
    (void)source_dos;
    i = process_directory(&volume, directory, pattern, list_only, automatic);
    if (!list_only) {
        union REGS inregs, outregs;
        inregs.h.ah = 0x0d;
        intdos(&inregs, &outregs);
    }
    return i;
}
