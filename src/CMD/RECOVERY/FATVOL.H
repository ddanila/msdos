#ifndef FATVOL_H
#define FATVOL_H

struct fat_volume {
    unsigned drive;
    unsigned bytes_per_sector;
    unsigned sectors_per_cluster;
    unsigned reserved_sectors;
    unsigned fat_count;
    unsigned root_entries;
    unsigned sectors_per_fat;
    unsigned sectors_per_track;
    unsigned heads;
    unsigned media;
    unsigned root_sectors;
    unsigned clusters;
    unsigned fat16;
    unsigned long total_sectors;
    unsigned long root_start;
    unsigned long data_start;
};

enum fat_volume_result {
    FATVOL_OK = 0,
    FATVOL_IO_ERROR = 1,
    FATVOL_BAD_BPB = 2,
    FATVOL_UNSUPPORTED = 3
};

int fat_volume_open(struct fat_volume *volume, unsigned drive,
                    unsigned char *sector);
int fat_volume_io(const struct fat_volume *volume, int write,
                  unsigned long sector, unsigned count, void *buffer);
int fat_volume_get(const struct fat_volume *volume, unsigned cluster,
                   unsigned *value, unsigned char *buffer);
int fat_volume_set(const struct fat_volume *volume, unsigned cluster,
                   unsigned value, unsigned char *buffer);
unsigned long fat_volume_cluster_sector(const struct fat_volume *volume,
                                        unsigned cluster);
unsigned fat_volume_eoc(const struct fat_volume *volume, unsigned value);
unsigned fat_volume_bad(const struct fat_volume *volume, unsigned value);
unsigned fat_volume_valid_cluster(const struct fat_volume *volume,
                                  unsigned value);

#endif
