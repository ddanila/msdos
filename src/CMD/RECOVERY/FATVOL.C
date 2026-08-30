#include <dos.h>
#include <string.h>

#include "FATVOL.H"

extern unsigned __cdecl abs_read(unsigned drive, unsigned long sector,
                                 unsigned count, void *buffer);
extern unsigned __cdecl abs_write(unsigned drive, unsigned long sector,
                                  unsigned count, void *buffer);

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

int fat_volume_open(struct fat_volume *volume, unsigned drive,
                    unsigned char *sector)
{
    unsigned long data_sectors;
    unsigned long clusters;

    memset(volume, 0, sizeof(*volume));
    volume->drive = drive;
    if (abs_read(drive, 0, 1, sector))
        return FATVOL_IO_ERROR;
    volume->bytes_per_sector = get_word(sector + 11);
    volume->sectors_per_cluster = sector[13];
    volume->reserved_sectors = get_word(sector + 14);
    volume->fat_count = sector[16];
    volume->root_entries = get_word(sector + 17);
    volume->sectors_per_fat = get_word(sector + 22);
    volume->sectors_per_track = get_word(sector + 24);
    volume->heads = get_word(sector + 26);
    volume->media = sector[21];
    volume->total_sectors = get_word(sector + 19);
    if (!volume->total_sectors)
        volume->total_sectors = get_dword(sector + 32);
    if (volume->bytes_per_sector != 512 ||
        !volume->sectors_per_cluster ||
        (volume->sectors_per_cluster & (volume->sectors_per_cluster - 1)) ||
        !volume->reserved_sectors || !volume->fat_count ||
        !volume->root_entries || !volume->sectors_per_fat ||
        !volume->total_sectors)
        return FATVOL_BAD_BPB;
    volume->root_sectors =
        (volume->root_entries * 32U + 511U) / 512U;
    volume->root_start = volume->reserved_sectors +
        (unsigned long)volume->fat_count * volume->sectors_per_fat;
    volume->data_start = volume->root_start + volume->root_sectors;
    if (volume->data_start >= volume->total_sectors)
        return FATVOL_BAD_BPB;
    data_sectors = volume->total_sectors - volume->data_start;
    clusters = data_sectors / volume->sectors_per_cluster;
    if (clusters < 1 || clusters > 65533UL)
        return FATVOL_UNSUPPORTED;
    volume->clusters = (unsigned)clusters;
    volume->fat16 = clusters >= 4085UL;
    return FATVOL_OK;
}

int fat_volume_io(const struct fat_volume *volume, int write,
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
            if (fat_volume_io(volume, write, position + index, 1,
                              (unsigned char *)buffer + index * 512U))
                return FATVOL_IO_ERROR;
        return FATVOL_OK;
    }
    if (volume->drive >= 2 || !volume->sectors_per_track || !volume->heads)
        return (write ? abs_write(volume->drive, position, count, buffer)
                      : abs_read(volume->drive, position, count, buffer))
            ? FATVOL_IO_ERROR : FATVOL_OK;
    track = position / volume->sectors_per_track;
    cylinder = (unsigned)(track / volume->heads);
    head = (unsigned)(track % volume->heads);
    memset(&inregs, 0, sizeof(inregs));
    segread(&segregs);
    inregs.h.ah = (unsigned char)(write ? 3 : 2);
    inregs.h.al = 1;
    inregs.h.ch = (unsigned char)cylinder;
    inregs.h.cl = (unsigned char)(
        (position % volume->sectors_per_track) + 1 |
        ((cylinder >> 2) & 0xc0));
    inregs.h.dh = (unsigned char)head;
    inregs.h.dl = (unsigned char)volume->drive;
    inregs.x.bx = FP_OFF(far_buffer);
    segregs.es = FP_SEG(far_buffer);
    int86x(0x13, &inregs, &outregs, &segregs);
    return outregs.x.cflag ? FATVOL_IO_ERROR : FATVOL_OK;
}

int fat_volume_get(const struct fat_volume *volume, unsigned cluster,
                   unsigned *value, unsigned char *buffer)
{
    unsigned long byte_offset;
    unsigned long position;
    unsigned offset;

    if (cluster > volume->clusters + 1U)
        return FATVOL_BAD_BPB;
    byte_offset = volume->fat16
        ? (unsigned long)cluster * 2UL
        : (unsigned long)cluster * 3UL / 2UL;
    position = volume->reserved_sectors + byte_offset / 512UL;
    offset = (unsigned)(byte_offset & 511U);
    if (fat_volume_io(volume, 0, position, offset == 511 ? 2 : 1, buffer))
        return FATVOL_IO_ERROR;
    *value = get_word(buffer + offset);
    if (!volume->fat16)
        *value = cluster & 1 ? *value >> 4 : *value & 0x0fff;
    return FATVOL_OK;
}

int fat_volume_set(const struct fat_volume *volume, unsigned cluster,
                   unsigned value, unsigned char *buffer)
{
    unsigned long byte_offset;
    unsigned offset;
    unsigned count;
    unsigned copy;

    if (cluster > volume->clusters + 1U)
        return FATVOL_BAD_BPB;
    byte_offset = volume->fat16
        ? (unsigned long)cluster * 2UL
        : (unsigned long)cluster * 3UL / 2UL;
    offset = (unsigned)(byte_offset & 511U);
    count = offset == 511 ? 2 : 1;
    for (copy = 0; copy < volume->fat_count; ++copy) {
        unsigned long position = volume->reserved_sectors +
            (unsigned long)copy * volume->sectors_per_fat +
            byte_offset / 512UL;
        unsigned old;
        if (fat_volume_io(volume, 0, position, count, buffer))
            return FATVOL_IO_ERROR;
        if (volume->fat16)
            put_word(buffer + offset, value);
        else {
            old = get_word(buffer + offset);
            old = cluster & 1
                ? (old & 0x000f) | ((value & 0x0fff) << 4)
                : (old & 0xf000) | (value & 0x0fff);
            put_word(buffer + offset, old);
        }
        if (fat_volume_io(volume, 1, position, count, buffer))
            return FATVOL_IO_ERROR;
    }
    return FATVOL_OK;
}

unsigned long fat_volume_cluster_sector(const struct fat_volume *volume,
                                        unsigned cluster)
{
    return volume->data_start +
        (unsigned long)(cluster - 2U) * volume->sectors_per_cluster;
}

unsigned fat_volume_eoc(const struct fat_volume *volume, unsigned value)
{
    return value >= (volume->fat16 ? 0xfff8U : 0x0ff8U);
}

unsigned fat_volume_bad(const struct fat_volume *volume, unsigned value)
{
    return value == (volume->fat16 ? 0xfff7U : 0x0ff7U);
}

unsigned fat_volume_valid_cluster(const struct fat_volume *volume,
                                  unsigned value)
{
    return value >= 2U && value <= volume->clusters + 1U;
}
