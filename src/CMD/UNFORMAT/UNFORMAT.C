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

static unsigned char sector[512];
static unsigned char present[8192];

static unsigned short get_word(const unsigned char *p)
{
    return (unsigned short)(p[0] | ((unsigned short)p[1] << 8));
}

static unsigned long get_dword(const unsigned char *p)
{
    return (unsigned long)get_word(p) | ((unsigned long)get_word(p + 2) << 16);
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

static int find_generation(unsigned drive, unsigned long total,
                           unsigned long *generation,
                           unsigned short *commit_sequence,
                           struct recovery_header *header)
{
    unsigned long pos;
    struct recovery_record *record = (struct recovery_record *)sector;
    struct recovery_header candidate;

    *generation = 0;
    for (pos = 1; pos < total; ++pos) {
        if (abs_read(drive, pos, 1, sector))
            continue;
        if (!valid_record(record))
            continue;
        if (record->kind != RECOVERY_KIND_COMMIT || record->length != sizeof(candidate))
            continue;
        memcpy(&candidate, record->payload, sizeof(candidate));
        if (geometry_matches(&candidate, drive, total) &&
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
        if (abs_read(drive, pos, 1, sector))
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
            if (abs_read(drive, target, 1, sector) ||
                offset + record->length > 512)
                return 1;
            memcpy(sector + offset, record->payload, record->length);
            if (abs_write(drive, target, 1, sector))
                return 1;
        }
    } else {
        target = header->root_start + stream_sector - fat_sectors;
        if (abs_read(drive, target, 1, sector) ||
            offset + record->length > 512)
            return 1;
        memcpy(sector + offset, record->payload, record->length);
        if (abs_write(drive, target, 1, sector))
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
        if (abs_read(drive, pos, 1, sector))
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
    unsigned drive;
    unsigned long total;
    unsigned long generation;
    unsigned short commit_sequence = 0;
    int verify_only = 0;
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
        fprintf(stderr, "UNFORMAT: that mode is not implemented yet: %s\n", argv[i]);
        return 1;
    }
    if (abs_read(drive, 0, 1, sector) || get_word(sector + 11) != 512) {
        fprintf(stderr, "UNFORMAT: cannot read drive %c:.\n", 'A' + drive);
        return 1;
    }
    total = get_word(sector + 19);
    if (!total)
        total = get_dword(sector + 32);
    if (find_generation(drive, total, &generation, &commit_sequence, &header) ||
        inventory_generation(drive, total, generation, commit_sequence)) {
        fprintf(stderr, "UNFORMAT: no complete recovery information exists for drive %c:.\n",
                'A' + drive);
        return 1;
    }
    printf("Complete recovery information found for drive %c:.\n", 'A' + drive);
    if (verify_only)
        return 0;
    printf("Restore the previous FAT and root directory (Y/N)? ");
    answer = getchar();
    if (toupper(answer) != 'Y') {
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
