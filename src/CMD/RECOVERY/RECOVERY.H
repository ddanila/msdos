#ifndef DOS5_RECOVERY_H
#define DOS5_RECOVERY_H

#define RECOVERY_VERSION 1
#define RECOVERY_KIND_HEADER 1
#define RECOVERY_KIND_DATA 2
#define RECOVERY_KIND_COMMIT 3
#define RECOVERY_PAYLOAD 492

#pragma pack(1)
struct recovery_record {
    char magic[8];
    unsigned long generation;
    unsigned short sequence;
    unsigned short kind;
    unsigned short length;
    unsigned short checksum;
    unsigned char payload[RECOVERY_PAYLOAD];
};

struct recovery_header {
    unsigned short version;
    unsigned char drive;
    unsigned char fat_count;
    unsigned short bytes_per_sector;
    unsigned short reserved_sectors;
    unsigned short root_entries;
    unsigned short sectors_per_fat;
    unsigned long total_sectors;
    unsigned long fat_start;
    unsigned long root_start;
    unsigned long snapshot_bytes;
    unsigned short source_checksum;
};

struct partition_file_header {
    char magic[8];
    unsigned short version;
    unsigned short count;
};

struct partition_record {
    unsigned char bios_drive;
    unsigned char heads;
    unsigned char sectors;
    unsigned short cylinders;
    unsigned short checksum;
    unsigned char mbr[512];
};

struct tracker_header {
    char magic[8];
    unsigned short version;
    unsigned char drive;
    unsigned short maximum_entries;
    unsigned short entry_count;
};

struct tracker_entry {
    unsigned short directory_cluster;
    unsigned char name[11];
    unsigned char attributes;
    unsigned short time;
    unsigned short date;
    unsigned short first_cluster;
    unsigned long size;
    unsigned short cluster_count;
};
#pragma pack()

#endif
