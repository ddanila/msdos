#include <ctype.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../RECOVERY/RECOVERY.H"

extern unsigned __cdecl abs_read(unsigned drive, unsigned long sector,
                                 unsigned count, void *buffer);
extern unsigned __cdecl abs_write(unsigned drive, unsigned long sector,
                                  unsigned count, void *buffer);

static unsigned char sector[1024];
static unsigned char directory_sector[512];
static unsigned char present[8192];

struct scan_volume {
    unsigned drive;
    unsigned sectors_per_cluster;
    unsigned reserved;
    unsigned fats;
    unsigned root_entries;
    unsigned sectors_per_fat;
    unsigned root_sectors;
    unsigned sectors_per_track;
    unsigned heads;
    unsigned media;
    unsigned long total_sectors;
    unsigned long root_start;
    unsigned long data_start;
    unsigned clusters;
    int fat16;
};

static struct scan_volume recovery_volume;
static int read_choice(const char *prompt, const char *choices);

static unsigned short get_word(const unsigned char *p)
{
    return (unsigned short)(p[0] | ((unsigned short)p[1] << 8));
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

static int load_scan_volume(struct scan_volume *volume, unsigned drive)
{
    unsigned long data_sectors;

    if (abs_read(drive, 0, 1, sector) || get_word(sector + 11) != 512)
        return 1;
    memset(volume, 0, sizeof(*volume));
    volume->drive = drive;
    volume->sectors_per_cluster = sector[13];
    volume->reserved = get_word(sector + 14);
    volume->fats = sector[16];
    volume->root_entries = get_word(sector + 17);
    volume->sectors_per_fat = get_word(sector + 22);
    volume->sectors_per_track = get_word(sector + 24);
    volume->heads = get_word(sector + 26);
    volume->media = sector[21];
    volume->total_sectors = get_word(sector + 19);
    if (!volume->total_sectors)
        volume->total_sectors = get_dword(sector + 32);
    if (!volume->sectors_per_cluster || !volume->fats ||
        !volume->sectors_per_fat || !volume->root_entries)
        return 1;
    volume->root_sectors = (volume->root_entries * 32U + 511U) / 512U;
    volume->root_start = volume->reserved +
                         (unsigned long)volume->fats * volume->sectors_per_fat;
    volume->data_start = volume->root_start + volume->root_sectors;
    if (volume->data_start >= volume->total_sectors)
        return 1;
    data_sectors = volume->total_sectors - volume->data_start;
    volume->clusters = (unsigned)(data_sectors / volume->sectors_per_cluster);
    volume->fat16 = volume->clusters >= 4085;
    return volume->clusters > 65533U ? 1 : 0;
}

static int scan_io(const struct scan_volume *volume, int write,
                   unsigned long position, unsigned count, void *buffer)
{
    union REGS inregs, outregs;
    struct SREGS segregs;
    void far *far_buffer = (void far *)buffer;
    unsigned long track;
    unsigned cylinder;
    unsigned head;

    if (count != 1) {
        unsigned index;
        for (index = 0; index < count; ++index)
            if (scan_io(volume, write, position + index, 1,
                        (unsigned char *)buffer + index * 512U))
                return 1;
        return 0;
    }
    if (volume->drive >= 2 ||
        !volume->sectors_per_track || !volume->heads)
        return write ? abs_write(volume->drive, position, count, buffer)
                     : abs_read(volume->drive, position, count, buffer);
    track = position / volume->sectors_per_track;
    cylinder = (unsigned)(track / volume->heads);
    head = (unsigned)(track % volume->heads);
    memset(&inregs, 0, sizeof(inregs));
    segread(&segregs);
    inregs.h.ah = (unsigned char)(write ? 3 : 2);
    inregs.h.al = 1;
    inregs.h.ch = (unsigned char)cylinder;
    inregs.h.cl = (unsigned char)((position % volume->sectors_per_track) + 1 |
                    ((cylinder >> 2) & 0xc0));
    inregs.h.dh = (unsigned char)head;
    inregs.h.dl = (unsigned char)volume->drive;
    inregs.x.bx = FP_OFF(far_buffer);
    segregs.es = FP_SEG(far_buffer);
    int86x(0x13, &inregs, &outregs, &segregs);
    return outregs.x.cflag ? 1 : 0;
}

static unsigned scan_fat_get(const struct scan_volume *volume, unsigned cluster)
{
    unsigned long byte_offset = volume->fat16
        ? (unsigned long)cluster * 2UL
        : (unsigned long)cluster * 3UL / 2UL;
    unsigned long position = volume->reserved + byte_offset / 512UL;
    unsigned offset = (unsigned)(byte_offset & 511U);
    unsigned value;

    if (scan_io(volume, 0, position, offset == 511 ? 2 : 1, sector))
        return 0xffff;
    value = get_word(sector + offset);
    if (!volume->fat16)
        value = cluster & 1 ? value >> 4 : value & 0x0fff;
    return value;
}

static int scan_fat_set(const struct scan_volume *volume, unsigned cluster,
                        unsigned value)
{
    unsigned long byte_offset = volume->fat16
        ? (unsigned long)cluster * 2UL
        : (unsigned long)cluster * 3UL / 2UL;
    unsigned copy;
    unsigned offset = (unsigned)(byte_offset & 511U);
    unsigned count = offset == 511 ? 2 : 1;

    for (copy = 0; copy < volume->fats; ++copy) {
        unsigned long position = volume->reserved +
            (unsigned long)copy * volume->sectors_per_fat + byte_offset / 512UL;
        unsigned old;
        if (scan_io(volume, 0, position, count, sector))
            return 1;
        if (volume->fat16)
            put_word(sector + offset, value);
        else {
            old = get_word(sector + offset);
            old = cluster & 1
                ? (old & 0x000f) | ((value & 0x0fff) << 4)
                : (old & 0xf000) | (value & 0x0fff);
            put_word(sector + offset, old);
        }
        if (scan_io(volume, 1, position, count, sector))
            return 1;
    }
    return 0;
}

static unsigned long scan_cluster_sector(const struct scan_volume *volume,
                                         unsigned cluster)
{
    return volume->data_start +
           (unsigned long)(cluster - 2) * volume->sectors_per_cluster;
}

static void scan_name(const unsigned char *raw, char *name)
{
    unsigned source;
    unsigned target = 0;
    for (source = 0; source < 8 && raw[source] != ' '; ++source)
        name[target++] = (char)raw[source];
    if (raw[8] != ' ') {
        name[target++] = '.';
        for (source = 8; source < 11 && raw[source] != ' '; ++source)
            name[target++] = (char)raw[source];
    }
    name[target] = 0;
}

static int cluster_claimed(unsigned cluster)
{
    return present[cluster >> 3] & (1 << (cluster & 7));
}

static void claim_cluster(unsigned cluster)
{
    present[cluster >> 3] |= 1 << (cluster & 7);
}

static void release_cluster(unsigned cluster)
{
    present[cluster >> 3] &= ~(1 << (cluster & 7));
}

static int rebuild_chain(const struct scan_volume *volume, unsigned first,
                         unsigned count, int test_only, unsigned *partial)
{
    unsigned cluster;
    unsigned next;
    unsigned index;
    unsigned visited = 0;
    unsigned maximum = volume->clusters + 1;

    *partial = 0;
    if (!count)
        return 0;
    if (first < 2 || first > maximum)
        return 1;
    cluster = first;
    for (index = 0; index < count; ++index) {
        if (cluster < 2 || cluster > maximum || cluster_claimed(cluster))
            break;
        claim_cluster(cluster);
        ++visited;
        next = scan_fat_get(volume, cluster);
        if (index + 1 == count) {
            if (!test_only) {
                cluster = first;
                for (index = 0; index < count; ++index) {
                    next = scan_fat_get(volume, cluster);
                    if (scan_fat_set(volume, cluster, index + 1 == count
                            ? (volume->fat16 ? 0xffff : 0x0fff) : next))
                        return 1;
                    cluster = next;
                }
            }
            return 0;
        }
        if (next == 0xffff)
            break;
        cluster = next;
    }
    *partial = visited;
    cluster = first;
    for (index = 0; index < visited; ++index) {
        next = scan_fat_get(volume, cluster);
        release_cluster(cluster);
        cluster = next;
    }
    if (count > maximum - first + 1)
        return 1;
    for (index = 0, cluster = first; index < count; ++index, ++cluster)
        if (cluster_claimed(cluster))
            return 1;
    for (index = 0, cluster = first; index < count; ++index, ++cluster)
        claim_cluster(cluster);
    *partial = 0;
    if (test_only)
        return 0;
    for (index = 0, cluster = first; index < count; ++index, ++cluster) {
        unsigned next = index + 1 == count
            ? (volume->fat16 ? 0xffff : 0x0fff) : cluster + 1;
        if (scan_fat_set(volume, cluster, next))
            return 1;
    }
    return 0;
}

static int truncate_chain(const struct scan_volume *volume, unsigned first,
                          unsigned count)
{
    unsigned cluster = first;
    unsigned next;
    unsigned index;

    for (index = 0; index < count; ++index) {
        next = scan_fat_get(volume, cluster);
        claim_cluster(cluster);
        if (scan_fat_set(volume, cluster, index + 1 == count
                ? (volume->fat16 ? 0xffff : 0x0fff) : next))
            return 1;
        cluster = next;
    }
    return 0;
}

static int scan_directory(const struct scan_volume *volume, unsigned directory,
                          int list_all, int test_only, unsigned depth,
                          unsigned *found, unsigned *damaged)
{
    unsigned long base;
    unsigned sectors;
    unsigned entries_left;
    unsigned sector_index;
    unsigned offset;
    unsigned char saved[32];
    char name[13];

    if (depth > 32)
        return 1;
    base = directory ? scan_cluster_sector(volume, directory) : volume->root_start;
    sectors = directory ? volume->sectors_per_cluster : volume->root_sectors;
    entries_left = directory ? 0xffff : volume->root_entries;
    for (sector_index = 0; sector_index < sectors; ++sector_index) {
        if (scan_io(volume, 0, base + sector_index, 1, directory_sector))
            return 1;
        for (offset = 0; offset < 512 && entries_left; offset += 32) {
            unsigned attributes;
            unsigned first;
            unsigned count;
            unsigned partial;
            unsigned long size;
            unsigned long cluster_bytes;
            if (!directory)
                --entries_left;
            if (!directory_sector[offset])
                return 0;
            if (directory_sector[offset] == 0xe5 ||
                directory_sector[offset + 11] == 0x0f)
                continue;
            attributes = directory_sector[offset + 11];
            if (attributes & 0x08)
                continue;
            memcpy(saved, directory_sector + offset, sizeof(saved));
            if ((attributes & 0x10) && saved[0] == '.')
                continue;
            first = get_word(saved + 26);
            size = get_dword(saved + 28);
            cluster_bytes = (unsigned long)volume->sectors_per_cluster * 512UL;
            count = attributes & 0x10 ? (first ? 1 : 0)
                    : (size ? (unsigned)((size + cluster_bytes - 1) /
                                         cluster_bytes) : 0);
            scan_name(saved, name);
            ++*found;
            if (rebuild_chain(volume, first, count, test_only, &partial)) {
                ++*damaged;
                printf("Fragmented or conflicting: %s\n", name);
                if (partial && !(attributes & 0x10) && !test_only) {
                    int choice = read_choice("Truncate or delete this file (T/D)? ",
                                             "TD");
                    if (choice == 'T') {
                        if (truncate_chain(volume, first, partial))
                            return 1;
                        put_dword(directory_sector + offset + 28,
                                  (unsigned long)partial * cluster_bytes);
                        if (scan_io(volume, 1, base + sector_index, 1,
                                    directory_sector))
                            return 1;
                        puts("File truncated to its recoverable prefix.");
                        --*damaged;
                    } else if (choice == 'D') {
                        directory_sector[offset] = 0xe5;
                        if (scan_io(volume, 1, base + sector_index, 1,
                                    directory_sector))
                            return 1;
                        puts("File removed from the rebuilt directory.");
                        --*damaged;
                    }
                }
                continue;
            }
            if (list_all)
                printf("%s%s\n", name, attributes & 0x10 ? "\\" : "");
            if ((attributes & 0x10) && first &&
                scan_directory(volume, first, list_all, test_only,
                               depth + 1, found, damaged))
                return 1;
        }
    }
    return 0;
}

static int reconstruct_without_mirror(unsigned drive, int list_all,
                                      int test_only)
{
    struct scan_volume volume;
    unsigned found = 0;
    unsigned damaged = 0;

    if (load_scan_volume(&volume, drive)) {
        fprintf(stderr, "UNFORMAT: cannot inspect drive %c:.\n", 'A' + drive);
        return 1;
    }
    memset(present, 0, sizeof(present));
    if (!test_only &&
        (scan_fat_set(&volume, 0, volume.fat16
            ? 0xff00U | volume.media : 0x0f00U | volume.media) ||
         scan_fat_set(&volume, 1, volume.fat16 ? 0xffff : 0x0fff))) {
        fputs("UNFORMAT: cannot initialize the file allocation tables.\n", stderr);
        return 1;
    }
    if (scan_directory(&volume, 0, list_all, test_only, 0, &found, &damaged)) {
        fputs("UNFORMAT: directory scan failed.\n", stderr);
        return 1;
    }
    if (!found) {
        puts("No recoverable directory records were found.");
        return 1;
    }
    printf("%u file or subdirectory record(s) found; %u fragmented or conflicting.\n",
           found, damaged);
    if (test_only)
        puts("Test completed; the disk was not changed.");
    else
        puts("Disk reconstruction completed.");
    return damaged ? 1 : 0;
}

static unsigned short checksum(const unsigned char *p, unsigned count)
{
    unsigned short value = 0;
    while (count--)
        value = (unsigned short)((value << 1) | (value >> 15)) ^ *p++;
    return value;
}

static int bios_call(unsigned function, unsigned drive, void *buffer,
                     unsigned char *heads, unsigned char *sectors,
                     unsigned short *cylinders)
{
    union REGS inregs, outregs;
    struct SREGS segregs;
    void far *far_buffer = (void far *)buffer;

    memset(&inregs, 0, sizeof(inregs));
    segread(&segregs);
    inregs.h.ah = (unsigned char)function;
    inregs.h.dl = (unsigned char)drive;
    if (function == 8) {
        int86x(0x13, &inregs, &outregs, &segregs);
        if (outregs.x.cflag)
            return 1;
        *heads = (unsigned char)(outregs.h.dh + 1);
        *sectors = (unsigned char)(outregs.h.cl & 0x3f);
        *cylinders = (unsigned short)(((outregs.h.cl & 0xc0) << 2) |
                                      outregs.h.ch) + 1;
        return 0;
    }
    inregs.h.al = 1;
    inregs.h.ch = 0;
    inregs.h.cl = 1;
    inregs.h.dh = 0;
    inregs.x.bx = FP_OFF(far_buffer);
    segregs.es = FP_SEG(far_buffer);
    int86x(0x13, &inregs, &outregs, &segregs);
    return outregs.x.cflag ? 1 : 0;
}

static int restore_partitions(int list_only)
{
    struct partition_file_header file_header;
    struct partition_record part;
    FILE *file;
    unsigned index;
    unsigned char heads, sectors;
    unsigned short cylinders;
    int answer;

    file = fopen("PARTNSAV.FIL", "rb");
    if (!file || fread(&file_header, 1, sizeof(file_header), file) != sizeof(file_header) ||
        memcmp(file_header.magic, "MSD5PRT", 8) ||
        file_header.version != RECOVERY_VERSION || !file_header.count) {
        if (file)
            fclose(file);
        fputs("UNFORMAT: PARTNSAV.FIL is missing or invalid.\n", stderr);
        return 1;
    }
    for (index = 0; index < file_header.count; ++index) {
        if (fread(&part, 1, sizeof(part), file) != sizeof(part) ||
            checksum(part.mbr, sizeof(part.mbr)) != part.checksum ||
            bios_call(8, part.bios_drive, NULL, &heads, &sectors, &cylinders) ||
            heads != part.heads || sectors != part.sectors ||
            cylinders != part.cylinders) {
            fclose(file);
            fputs("UNFORMAT: saved and current fixed-disk parameters do not match.\n", stderr);
            return 1;
        }
        printf("Disk %u: %u cylinders, %u heads, %u sectors per track.\n",
               part.bios_drive - 0x7f, cylinders, heads, sectors);
    }
    if (list_only) {
        fclose(file);
        return 0;
    }
    printf("Restore the saved partition table(s) (Y/N)? ");
    answer = getchar();
    if (toupper(answer) != 'Y') {
        fclose(file);
        puts("Cancelled.");
        return 1;
    }
    rewind(file);
    fread(&file_header, 1, sizeof(file_header), file);
    for (index = 0; index < file_header.count; ++index) {
        if (fread(&part, 1, sizeof(part), file) != sizeof(part) ||
            bios_call(3, part.bios_drive, part.mbr, &heads, &sectors, &cylinders)) {
            fclose(file);
            fputs("UNFORMAT: partition-table write failed.\n", stderr);
            return 1;
        }
    }
    fclose(file);
    puts("Partition information restored. Restart the computer before using the disk.");
    return 0;
}

static int valid_record(struct recovery_record *record)
{
    unsigned short expected;
    if (memcmp(record->magic, "MSD5REC", 8) ||
        record->length > RECOVERY_PAYLOAD)
        return 0;
    expected = record->checksum;
    record->checksum = 0;
    if (checksum((unsigned char *)record, sizeof(*record)) != expected) {
        record->checksum = expected;
        return 0;
    }
    record->checksum = expected;
    return 1;
}

static int geometry_matches(const struct recovery_header *header,
                            unsigned drive, unsigned long total)
{
    return header->version == RECOVERY_VERSION &&
           header->drive == drive &&
           header->bytes_per_sector == 512 &&
           header->total_sectors == total &&
           header->fat_count != 0 && header->sectors_per_fat != 0;
}

static int find_generation_before(unsigned drive, unsigned long total,
                                  unsigned long before,
                                  unsigned long *generation,
                                  unsigned short *commit_sequence,
                                  struct recovery_header *header)
{
    unsigned long pos;
    struct recovery_record *record = (struct recovery_record *)sector;
    struct recovery_header candidate;

    *generation = 0;
    for (pos = 1; pos < total; ++pos) {
        if (scan_io(&recovery_volume, 0, pos, 1, sector))
            continue;
        if (!valid_record(record))
            continue;
        if (record->kind != RECOVERY_KIND_COMMIT || record->length != sizeof(candidate))
            continue;
        memcpy(&candidate, record->payload, sizeof(candidate));
        if (record->generation < before &&
            geometry_matches(&candidate, drive, total) &&
            record->generation >= *generation) {
            *generation = record->generation;
            *commit_sequence = record->sequence;
            *header = candidate;
        }
    }
    return *generation ? 0 : 1;
}

static int inventory_generation(unsigned drive, unsigned long total,
                                unsigned long generation,
                                unsigned short commit_sequence)
{
    unsigned long pos;
    unsigned sequence;
    struct recovery_record *record = (struct recovery_record *)sector;

    memset(present, 0, sizeof(present));
    for (pos = 1; pos < total; ++pos) {
        if (scan_io(&recovery_volume, 0, pos, 1, sector))
            continue;
        if (!valid_record(record) || record->generation != generation ||
            record->kind != RECOVERY_KIND_DATA || !record->sequence ||
            record->sequence >= commit_sequence)
            continue;
        present[record->sequence >> 3] |= 1 << (record->sequence & 7);
    }
    for (sequence = 1; sequence < commit_sequence; ++sequence)
        if (!(present[sequence >> 3] & (1 << (sequence & 7))))
            return 1;
    return 0;
}

static int find_complete_generation(unsigned drive, unsigned long total,
                                    unsigned long before,
                                    unsigned long *generation,
                                    unsigned short *commit_sequence,
                                    struct recovery_header *header)
{
    unsigned long candidate_before = before;

    while (!find_generation_before(drive, total, candidate_before, generation,
                                   commit_sequence, header)) {
        if (!inventory_generation(drive, total, *generation, *commit_sequence))
            return 0;
        candidate_before = *generation;
    }
    return 1;
}

static void display_generation(const char *label, unsigned long generation)
{
    printf("%s: generation %lu\n", label, generation);
}

static int read_choice(const char *prompt, const char *choices)
{
    int answer;
    int next;

    fputs(prompt, stdout);
    answer = getchar();
    do {
        next = getchar();
    } while (next != '\n' && next != EOF);
    answer = toupper(answer);
    return strchr(choices, answer) ? answer : 0;
}

static int restore_piece(unsigned drive, const struct recovery_header *header,
                         const struct recovery_record *record)
{
    unsigned long stream_sector = (record->sequence - 1UL) / 2UL;
    unsigned offset = ((record->sequence - 1) & 1) ? RECOVERY_PAYLOAD : 0;
    unsigned long fat_sectors = header->sectors_per_fat;
    unsigned long target;
    unsigned copy;

    if (stream_sector < fat_sectors) {
        for (copy = 0; copy < header->fat_count; ++copy) {
            target = header->fat_start + copy * fat_sectors + stream_sector;
            if (scan_io(&recovery_volume, 0, target, 1, sector) ||
                offset + record->length > 512)
                return 1;
            memcpy(sector + offset, record->payload, record->length);
            if (scan_io(&recovery_volume, 1, target, 1, sector))
                return 1;
        }
    } else {
        target = header->root_start + stream_sector - fat_sectors;
        if (scan_io(&recovery_volume, 0, target, 1, sector) ||
            offset + record->length > 512)
            return 1;
        memcpy(sector + offset, record->payload, record->length);
        if (scan_io(&recovery_volume, 1, target, 1, sector))
            return 1;
    }
    return 0;
}

static int restore_generation(unsigned drive, unsigned long total,
                              unsigned long generation,
                              unsigned short commit_sequence,
                              const struct recovery_header *header)
{
    unsigned long pos;
    struct recovery_record saved;
    struct recovery_record *record = (struct recovery_record *)sector;

    for (pos = 1; pos < total; ++pos) {
        if (scan_io(&recovery_volume, 0, pos, 1, sector))
            continue;
        if (!valid_record(record) || record->generation != generation ||
            record->kind != RECOVERY_KIND_DATA || !record->sequence ||
            record->sequence >= commit_sequence)
            continue;
        memcpy(&saved, record, sizeof(saved));
        if (restore_piece(drive, header, &saved))
            return 1;
    }
    return 0;
}

static void usage(void)
{
    puts("Restores a disk erased by FORMAT.");
    puts("UNFORMAT drive: [/J]");
    puts("UNFORMAT drive: [/U] [/L] [/TEST] [/P]");
    puts("UNFORMAT /PARTN [/L]");
}

int main(int argc, char **argv)
{
    struct recovery_header header;
    struct recovery_header prior_header;
    unsigned drive;
    unsigned long total;
    unsigned long generation;
    unsigned short commit_sequence = 0;
    unsigned long prior_generation = 0;
    unsigned short prior_commit_sequence = 0;
    int verify_only = 0;
    int force_scan = 0;
    int list_all = 0;
    int test_only = 0;
    int printer = 0;
    int i;
    int answer;

    if (argc >= 2 && !stricmp(argv[1], "/PARTN")) {
        if (argc == 2)
            return restore_partitions(0);
        if (argc == 3 && !stricmp(argv[2], "/L"))
            return restore_partitions(1);
        usage();
        return 1;
    }
    if (argc < 2 || strlen(argv[1]) != 2 || argv[1][1] != ':' ||
        !isalpha(argv[1][0])) {
        usage();
        return 1;
    }
    drive = (unsigned)(toupper(argv[1][0]) - 'A');
    for (i = 2; i < argc; ++i) {
        if (!stricmp(argv[i], "/?")) {
            usage();
            return 0;
        }
        if (!stricmp(argv[i], "/J")) {
            verify_only = 1;
            continue;
        }
        if (!stricmp(argv[i], "/U"))
            force_scan = 1;
        else if (!stricmp(argv[i], "/L")) {
            force_scan = 1;
            list_all = 1;
        } else if (!stricmp(argv[i], "/TEST")) {
            force_scan = 1;
            test_only = 1;
        } else if (!stricmp(argv[i], "/P"))
            printer = 1;
        else {
            usage();
            return 1;
        }
    }
    if ((verify_only && argc != 3) || (test_only && list_all)) {
        usage();
        return 1;
    }
    if (printer && !freopen("LPT1", "w", stdout)) {
        fputs("UNFORMAT: cannot open LPT1.\n", stderr);
        return 1;
    }
    if (abs_read(drive, 0, 1, sector) || get_word(sector + 11) != 512) {
        fprintf(stderr, "UNFORMAT: cannot read drive %c:.\n", 'A' + drive);
        return 1;
    }
    total = get_word(sector + 19);
    if (!total)
        total = get_dword(sector + 32);
    if (load_scan_volume(&recovery_volume, drive)) {
        fprintf(stderr, "UNFORMAT: unsupported filesystem on drive %c:.\n",
                'A' + drive);
        return 1;
    }
    if (force_scan)
        return reconstruct_without_mirror(drive, list_all, test_only);
    if (find_complete_generation(drive, total, 0xffffffffUL, &generation,
                                 &commit_sequence, &header)) {
        puts("No complete mirror information was found; scanning the disk.");
        return reconstruct_without_mirror(drive, 0, 0);
    }
    printf("Complete recovery information found for drive %c:.\n", 'A' + drive);
    if (verify_only)
        return 0;
    if (!find_complete_generation(drive, total, generation, &prior_generation,
                                  &prior_commit_sequence, &prior_header)) {
        display_generation("Latest mirror", generation);
        display_generation("Prior mirror", prior_generation);
        answer = read_choice("Use latest or prior information (L/P)? ", "LP");
        if (answer == 'P') {
            generation = prior_generation;
            commit_sequence = prior_commit_sequence;
            header = prior_header;
        } else if (answer != 'L') {
            puts("Cancelled.");
            return 1;
        }
    }
    answer = read_choice("Restore the previous FAT and root directory (Y/N)? ",
                         "YN");
    if (answer != 'Y') {
        puts("Cancelled.");
        return 1;
    }
    if (restore_generation(drive, total, generation, commit_sequence, &header)) {
        fprintf(stderr, "UNFORMAT: disk write failed.\n");
        return 1;
    }
    {
        union REGS inregs, outregs;
        inregs.h.ah = 0x0d;
        intdos(&inregs, &outregs);
    }
    puts("Disk recovery completed.");
    return 0;
}
