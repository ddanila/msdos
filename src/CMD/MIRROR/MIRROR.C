#include <ctype.h>
#include <dos.h>
#include <process.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "../RECOVERY/RECOVERY.H"

extern unsigned __cdecl abs_read(unsigned drive, unsigned long sector,
                                 unsigned count, void *buffer);

static unsigned char sector[512];
static struct recovery_record record;

static unsigned long next_generation(const char *save_name)
{
    unsigned long value = (unsigned long)time(NULL);
    FILE *file = fopen(save_name, "rb");
    if (file) {
        if (fread(&record, 1, sizeof(record), file) == sizeof(record) &&
            !memcmp(record.magic, "MSD5REC", 8) &&
            record.generation >= value)
            value = record.generation + 1;
        fclose(file);
    }
    return value;
}

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

static int save_partitions(void)
{
    struct partition_file_header file_header;
    struct partition_record part;
    FILE *file;
    unsigned drive;

    memset(&file_header, 0, sizeof(file_header));
    memcpy(file_header.magic, "MSD5PRT", 8);
    file_header.version = RECOVERY_VERSION;
    file = fopen("PARTNSAV.TMP", "wb");
    if (!file) {
        fputs("MIRROR: cannot create PARTNSAV.TMP.\n", stderr);
        return 1;
    }
    if (fwrite(&file_header, 1, sizeof(file_header), file) != sizeof(file_header))
        goto part_write_error;
    for (drive = 0x80; drive < 0x88; ++drive) {
        memset(&part, 0, sizeof(part));
        if (bios_call(8, drive, NULL, &part.heads, &part.sectors,
                      &part.cylinders))
            break;
        if (bios_call(2, drive, part.mbr, &part.heads, &part.sectors,
                      &part.cylinders))
            continue;
        part.bios_drive = (unsigned char)drive;
        part.checksum = checksum(part.mbr, sizeof(part.mbr));
        if (fwrite(&part, 1, sizeof(part), file) != sizeof(part))
            goto part_write_error;
        ++file_header.count;
    }
    if (!file_header.count) {
        fclose(file);
        remove("PARTNSAV.TMP");
        fputs("MIRROR: no fixed disks were found.\n", stderr);
        return 1;
    }
    rewind(file);
    if (fwrite(&file_header, 1, sizeof(file_header), file) != sizeof(file_header) ||
        fclose(file)) {
        remove("PARTNSAV.TMP");
        return 1;
    }
    remove("PARTNSAV.FIL");
    if (rename("PARTNSAV.TMP", "PARTNSAV.FIL")) {
        fputs("MIRROR: cannot commit PARTNSAV.FIL.\n", stderr);
        return 1;
    }
    printf("Partition information for %u fixed disk(s) saved in PARTNSAV.FIL.\n",
           file_header.count);
    return 0;

part_write_error:
    fclose(file);
    remove("PARTNSAV.TMP");
    fputs("MIRROR: cannot write partition information.\n", stderr);
    return 1;
}

static int write_record(FILE *file, unsigned long generation,
                        unsigned short sequence, unsigned char kind,
                        const void *payload, unsigned length)
{
    memset(&record, 0, sizeof(record));
    memcpy(record.magic, "MSD5REC", 8);
    record.generation = generation;
    record.sequence = sequence;
    record.kind = kind;
    record.length = (unsigned short)length;
    if (length)
        memcpy(record.payload, payload, length);
    record.checksum = 0;
    record.checksum = checksum((const unsigned char *)&record, sizeof(record));
    return fwrite(&record, 1, sizeof(record), file) == sizeof(record) ? 0 : 1;
}

static int snapshot_drive(unsigned drive, int latest_only)
{
    struct recovery_header header;
    unsigned long generation;
    unsigned long total;
    unsigned long fat_start;
    unsigned long root_start;
    unsigned long source_bytes;
    unsigned long source_sector;
    unsigned long source_index;
    unsigned long fat_sectors;
    unsigned long remaining;
    unsigned short sequence = 1;
    unsigned short source_sum = 0;
    unsigned chunk;
    char temp_name[] = "A:\\MIRORSAV.TMP";
    char save_name[] = "A:\\MIRORSAV.FIL";
    char prior_name[] = "A:\\MIRORSAV.BAK";
    FILE *file;
    unsigned i;

    if (abs_read(drive, 0, 1, sector)) {
        fprintf(stderr, "MIRROR: cannot read drive %c:.\n", 'A' + drive);
        return 1;
    }
    for (i = 0; i < sizeof(sector) && sector[i] == 0; ++i)
        ;
    if (i == sizeof(sector))
        return 2;               /* blank media: there is nothing to preserve */
    if (get_word(sector + 11) != 512 || !sector[16] || !get_word(sector + 22)) {
        fprintf(stderr, "MIRROR: drive %c: has an unsupported filesystem.\n", 'A' + drive);
        return 1;
    }

    total = get_word(sector + 19);
    if (!total)
        total = get_dword(sector + 32);
    fat_start = get_word(sector + 14);
    root_start = fat_start + (unsigned long)sector[16] * get_word(sector + 22);
    fat_sectors = get_word(sector + 22);
    source_bytes = fat_sectors * 512UL;
    source_bytes += ((unsigned long)get_word(sector + 17) * 32UL + 511UL) & ~511UL;

    memset(&header, 0, sizeof(header));
    header.version = RECOVERY_VERSION;
    header.drive = (unsigned char)drive;
    header.fat_count = sector[16];
    header.bytes_per_sector = 512;
    header.reserved_sectors = get_word(sector + 14);
    header.root_entries = get_word(sector + 17);
    header.sectors_per_fat = get_word(sector + 22);
    header.total_sectors = total;
    header.fat_start = fat_start;
    header.root_start = root_start;
    header.snapshot_bytes = source_bytes;
    temp_name[0] = save_name[0] = prior_name[0] = (char)('A' + drive);
    generation = next_generation(save_name);
    remove(temp_name);
    file = fopen(temp_name, "wb");
    if (!file) {
        fprintf(stderr, "MIRROR: cannot create recovery data on drive %c:.\n", 'A' + drive);
        return 1;
    }
    if (write_record(file, generation, 0, RECOVERY_KIND_HEADER,
                     &header, sizeof(header)))
        goto write_error;

    source_index = 0;
    remaining = source_bytes;
    while (remaining) {
        source_sector = source_index < fat_sectors
                      ? fat_start + source_index
                      : root_start + source_index - fat_sectors;
        ++source_index;
        if (abs_read(drive, source_sector, 1, sector))
            goto read_error;
        source_sum ^= checksum(sector, 512);
        chunk = remaining > 512UL ? 512 : (unsigned)remaining;
        if (write_record(file, generation, sequence++, RECOVERY_KIND_DATA,
                         sector, chunk > RECOVERY_PAYLOAD ? RECOVERY_PAYLOAD : chunk))
            goto write_error;
        if (chunk > RECOVERY_PAYLOAD &&
            write_record(file, generation, sequence++, RECOVERY_KIND_DATA,
                         sector + RECOVERY_PAYLOAD, chunk - RECOVERY_PAYLOAD))
            goto write_error;
        remaining -= chunk;
    }
    header.source_checksum = source_sum;
    if (write_record(file, generation, sequence, RECOVERY_KIND_COMMIT,
                     &header, sizeof(header)))
        goto write_error;
    if (fclose(file)) {
        remove(temp_name);
        return 1;
    }

    if (latest_only) {
        remove(save_name);
        remove(prior_name);
    } else {
        remove(prior_name);
        rename(save_name, prior_name);
    }
    if (rename(temp_name, save_name)) {
        fprintf(stderr, "MIRROR: cannot commit recovery data on drive %c:.\n", 'A' + drive);
        return 1;
    }
    printf("Recovery information saved for drive %c:.\n", 'A' + drive);
    return 0;

read_error:
    fprintf(stderr, "MIRROR: cannot read recovery information from drive %c:.\n", 'A' + drive);
    fclose(file);
    remove(temp_name);
    return 1;
write_error:
    fprintf(stderr, "MIRROR: cannot write recovery information on drive %c:.\n", 'A' + drive);
    fclose(file);
    remove(temp_name);
    return 1;
}

static unsigned default_tracker_entries(unsigned drive)
{
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

static int install_tracker(unsigned drive, unsigned entries)
{
    char drive_arg[] = "A:";
    char count_arg[5];
    int result;

    if (!entries)
        entries = default_tracker_entries(drive);
    if (!entries) {
        fprintf(stderr, "MIRROR: cannot inspect drive %c:.\n", 'A' + drive);
        return 1;
    }
    drive_arg[0] = (char)('A' + drive);
    sprintf(count_arg, "%u", entries);
    result = spawnlp(P_WAIT, "UNDELETE.COM", "UNDELETE.COM", "/TRACK",
                     drive_arg, count_arg, NULL);
    if (result && spawnlp(P_WAIT, "UNDELETE.COM", "UNDELETE.COM",
                          "/TRACKSTATUS", NULL)) {
        fprintf(stderr, "MIRROR: deletion tracking failed for drive %c:.\n",
                'A' + drive);
        return 1;
    }
    printf("Deletion tracking enabled for drive %c: (%u entries).\n",
           'A' + drive, entries);
    return 0;
}

static int unload_trackers(void)
{
    char active_name[] = "A:\\PCTRACKR.ACT";
    unsigned drive;
    unsigned removed = 0;
    int resident_result;

    resident_result = spawnlp(P_WAIT, "UNDELETE.COM", "UNDELETE.COM",
                              "/UNTRACK", NULL);
    if (resident_result &&
        !spawnlp(P_WAIT, "UNDELETE.COM", "UNDELETE.COM",
                 "/TRACKSTATUS", NULL)) {
        fputs("MIRROR: unload resident programs loaded after deletion tracking first.\n",
              stderr);
        return 1;
    }
    for (drive = 0; drive < 26; ++drive) {
        active_name[0] = (char)('A' + drive);
        _dos_setfileattr(active_name, 0);
        if (!remove(active_name))
            ++removed;
    }
    puts((removed || !resident_result) ? "Deletion tracking disabled."
                                      : "Deletion tracking was not active.");
    return (removed || !resident_result) ? 0 : 1;
}

static void usage(void)
{
    puts("Records disk information for UNFORMAT.");
    puts("MIRROR [drive: [...]] [/1]");
    puts("MIRROR /Tdrive[-entries] | /U | /PARTN");
}

int main(int argc, char **argv)
{
    unsigned drives[26];
    unsigned tracker_drives[26];
    unsigned tracker_entries[26];
    unsigned count = 0;
    unsigned tracker_count = 0;
    unsigned drive;
    int latest_only = 0;
    int partition_mode = 0;
    int unload_mode = 0;
    int status = 0;
    int i;

    for (i = 1; i < argc; ++i) {
        if (!stricmp(argv[i], "/?")) {
            usage();
            return 0;
        }
        if (!stricmp(argv[i], "/1")) {
            latest_only = 1;
            continue;
        }
        if (!stricmp(argv[i], "/PARTN")) {
            partition_mode = 1;
            continue;
        }
        if (!stricmp(argv[i], "/U")) {
            unload_mode = 1;
            continue;
        }
        if ((argv[i][0] == '/' || argv[i][0] == '-') &&
            toupper(argv[i][1]) == 'T' && isalpha(argv[i][2])) {
            char *suffix = argv[i] + 3;
            unsigned entries = 0;
            if (*suffix) {
                if (*suffix++ != '-' || !*suffix) {
                    usage();
                    return 1;
                }
                entries = (unsigned)atoi(suffix);
                if (!entries || entries > 999) {
                    usage();
                    return 1;
                }
            }
            tracker_drives[tracker_count] =
                (unsigned)(toupper(argv[i][2]) - 'A');
            tracker_entries[tracker_count++] = entries;
            continue;
        }
        if (argv[i][0] == '/' || argv[i][0] == '-') {
            fprintf(stderr, "MIRROR: that mode is not implemented yet: %s\n", argv[i]);
            return 1;
        }
        if (strlen(argv[i]) != 2 || argv[i][1] != ':' || !isalpha(argv[i][0])) {
            usage();
            return 1;
        }
        drive = (unsigned)(toupper(argv[i][0]) - 'A');
        drives[count++] = drive;
    }
    if (partition_mode) {
        if (count || latest_only || argc != 2) {
            usage();
            return 1;
        }
        return save_partitions();
    }
    if (unload_mode) {
        if (count || tracker_count || latest_only || argc != 2) {
            usage();
            return 1;
        }
        return unload_trackers();
    }
    if (!count && !tracker_count) {
        _dos_getdrive(&drive);
        drives[count++] = drive - 1;
    }
    for (i = 0; i < (int)count; ++i)
        status |= snapshot_drive(drives[i], latest_only);
    for (i = 0; i < (int)tracker_count; ++i)
        status |= install_tracker(tracker_drives[i], tracker_entries[i]);
    return status;
}
