#include <ctype.h>
#include <conio.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../RECOVERY/FATVOL.H"

#define MAP_BYTES 8192
#define MAX_DEPTH 64
#define SORT_SWITCH "/S"

struct options {
    int full;
    int unfragment;
    int reboot;
    int skip_high;
    int lcd;
    int bw;
    int g0;
    int hidden;
    int sort_set;
    char sort[16];
    unsigned drive;
    int drive_set;
};

struct defrag_state {
    struct fat_volume volume;
    struct options options;
    unsigned long files;
    unsigned long directories;
    unsigned long fragmented;
    unsigned long moved;
    unsigned allocation_error;
    unsigned read_error;
    unsigned write_error;
};

static unsigned char boot_sector[512];
static unsigned char fat_buffer[1024];
static unsigned char directory_sector[512];
static unsigned char cluster_sector[512];
static unsigned char allocated[MAP_BYTES];
static unsigned char claimed[MAP_BYTES];
static unsigned char movable[MAP_BYTES];
static unsigned char chain_seen[MAP_BYTES];
static unsigned char sort_entries[512][32];
static char active_sort[16];
static unsigned transaction_step;
static int interrupt_at = -1;

static void transaction_boundary(void)
{
    const char *setting;
    if (interrupt_at < 0) {
        setting = getenv("DEFRAG_FAILSTEP");
        interrupt_at = setting ? atoi(setting) : 0;
    }
    ++transaction_step;
    if (interrupt_at && transaction_step == (unsigned)interrupt_at) {
        puts("DEFRAG interrupted at a recoverable transaction boundary.");
        exit(3);
    }
}

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

static int switch_is(const char *left, const char *right)
{
    while (*left && *right) {
        if (toupper((unsigned char)*left) !=
            toupper((unsigned char)*right))
            return 0;
        ++left;
        ++right;
    }
    return !*left && !*right;
}

static void usage(void)
{
    puts("Reorganizes files on a FAT12 or FAT16 disk.");
    puts("Syntax: DEFRAG [drive:] [/F [/S[:]order] | /U] [/B]");
    puts("              [/SKIPHIGH] [/LCD | /BW | /G0] [/H]");
}

static void describe_presentation(const struct options *options)
{
    if (options->lcd)
        puts("Display mode: LCD-compatible high contrast.");
    else if (options->bw)
        puts("Display mode: black and white.");
    else if (options->g0)
        puts("Display mode: basic text (graphics level 0).");
    else
        puts("Display mode: automatic text.");
    if (options->skip_high)
        puts("Memory policy: conventional memory only.");
}

static int valid_sort(const char *order)
{
    while (*order) {
        if (!strchr("NEDS", toupper((unsigned char)*order)))
            return 0;
        ++order;
        if (*order == '-')
            ++order;
    }
    return 1;
}

static int parse_options(int argc, char **argv, struct options *options)
{
    int index;
    memset(options, 0, sizeof(*options));
    for (index = 1; index < argc; ++index) {
        char *argument = argv[index];
        if (isalpha((unsigned char)argument[0]) && argument[1] == ':' &&
            !argument[2] && !options->drive_set) {
            options->drive = toupper((unsigned char)argument[0]) - 'A';
            options->drive_set = 1;
        } else if (argument[0] == '/' || argument[0] == '-') {
            char *name = argument + 1;
            if (switch_is(name, "?")) {
                usage();
                exit(0);
            } else if (switch_is(name, "F")) options->full = 1;
            else if (switch_is(name, "U")) options->unfragment = 1;
            else if (switch_is(name, "B")) options->reboot = 1;
            else if (switch_is(name, "SKIPHIGH")) options->skip_high = 1;
            else if (switch_is(name, "LCD")) options->lcd = 1;
            else if (switch_is(name, "BW")) options->bw = 1;
            else if (switch_is(name, "G0")) options->g0 = 1;
            else if (switch_is(name, "H")) options->hidden = 1;
            else if (toupper((unsigned char)name[0]) == SORT_SWITCH[1]) {
                char *order = name + 1;
                if (*order == ':')
                    ++order;
                if (!*order || strlen(order) >= sizeof(options->sort) ||
                    !valid_sort(order)) {
                    fputs("Invalid /S sort order.\n", stderr);
                    return 1;
                }
                strcpy(options->sort, order);
                options->sort_set = 1;
            } else {
                fprintf(stderr, "Invalid switch - %s\n", argument);
                return 1;
            }
        } else {
            fprintf(stderr, "Invalid parameter - %s\n", argument);
            return 1;
        }
    }
    if (options->full && options->unfragment) {
        fputs("/F and /U cannot be combined.\n", stderr);
        return 1;
    }
    if (options->sort_set && !options->full) {
        fputs("/S can be used only with /F.\n", stderr);
        return 1;
    }
    if ((unsigned)options->lcd + (unsigned)options->bw +
        (unsigned)options->g0 > 1U) {
        fputs("Specify only one display mode.\n", stderr);
        return 1;
    }
    if (!options->full && !options->unfragment)
        options->unfragment = 1;
    return 0;
}

static int compare_fats(struct defrag_state *state)
{
    unsigned copy;
    unsigned sector;
    unsigned char other[512];
    for (copy = 1; copy < state->volume.fat_count; ++copy)
        for (sector = 0; sector < state->volume.sectors_per_fat; ++sector) {
            unsigned long first = state->volume.reserved_sectors + sector;
            unsigned long second = state->volume.reserved_sectors +
                (unsigned long)copy * state->volume.sectors_per_fat + sector;
            if (fat_volume_io(&state->volume, 0, first, 1, fat_buffer) ||
                fat_volume_io(&state->volume, 0, second, 1, other)) {
                state->read_error = 1;
                return 1;
            }
            if (memcmp(fat_buffer, other, 512)) {
                state->allocation_error = 1;
                return 1;
            }
        }
    return 0;
}

static int build_allocation_map(struct defrag_state *state)
{
    unsigned cluster;
    unsigned value;
    unsigned free_count = 0;
    memset(allocated, 0, sizeof(allocated));
    for (cluster = 2; cluster <= state->volume.clusters + 1U; ++cluster) {
        if (fat_volume_get(&state->volume, cluster, &value, fat_buffer)) {
            state->read_error = 1;
            return 1;
        }
        if (value)
            bit_set(allocated, cluster);
        else
            ++free_count;
    }
    if (!free_count)
        return 2;
    return 0;
}

static unsigned inspect_chain(struct defrag_state *state, unsigned first,
                              unsigned *fragments)
{
    unsigned current = first;
    unsigned next;
    unsigned count = 0;
    *fragments = 0;
    memset(chain_seen, 0, sizeof(chain_seen));
    while (fat_volume_valid_cluster(&state->volume, current)) {
        if (bit_get(chain_seen, current) || bit_get(claimed, current)) {
            state->allocation_error = 1;
            return 0;
        }
        bit_set(chain_seen, current);
        bit_set(claimed, current);
        ++count;
        if (fat_volume_get(&state->volume, current, &next, fat_buffer)) {
            state->read_error = 1;
            return 0;
        }
        if (fat_volume_eoc(&state->volume, next))
            return count;
        if (!fat_volume_valid_cluster(&state->volume, next)) {
            state->allocation_error = 1;
            return 0;
        }
        if (next != current + 1U)
            ++*fragments;
        current = next;
    }
    state->allocation_error = 1;
    return 0;
}

static void mark_chain_movable(void)
{
    unsigned index;
    for (index = 0; index < MAP_BYTES; ++index)
        movable[index] |= chain_seen[index];
}

static unsigned find_free_run(const struct fat_volume *volume, unsigned count)
{
    unsigned cluster;
    unsigned run = 0;
    unsigned first = 0;
    for (cluster = 2; cluster <= volume->clusters + 1U; ++cluster) {
        if (!bit_get(allocated, cluster)) {
            if (!run)
                first = cluster;
            if (++run == count)
                return first;
        } else {
            run = 0;
        }
    }
    return 0;
}

static int copy_cluster(struct defrag_state *state, unsigned source,
                        unsigned target)
{
    unsigned sector;
    for (sector = 0; sector < state->volume.sectors_per_cluster; ++sector) {
        if (fat_volume_io(&state->volume, 0,
                fat_volume_cluster_sector(&state->volume, source) + sector,
                1, cluster_sector)) {
            state->read_error = 1;
            return 1;
        }
        if (fat_volume_io(&state->volume, 1,
                fat_volume_cluster_sector(&state->volume, target) + sector,
                1, cluster_sector)) {
            state->write_error = 1;
            return 1;
        }
    }
    return 0;
}

static int relocate_file(struct defrag_state *state, unsigned first,
                         unsigned count, unsigned char *entry,
                         unsigned long directory_position)
{
    unsigned target = find_free_run(&state->volume, count);
    unsigned current = first;
    unsigned next;
    unsigned index;
    if (!target)
        return 0;
    for (index = 0; index < count; ++index) {
        if (fat_volume_get(&state->volume, current, &next, fat_buffer)) {
            state->read_error = 1;
            return 1;
        }
        if (copy_cluster(state, current, target + index))
            return 1;
        current = next;
    }
    transaction_boundary();
    for (index = 0; index < count; ++index) {
        unsigned value = index + 1U == count
            ? (state->volume.fat16 ? 0xffffU : 0x0fffU)
            : target + index + 1U;
        if (fat_volume_set(&state->volume, target + index, value, fat_buffer)) {
            state->write_error = 1;
            return 1;
        }
        bit_set(allocated, target + index);
        bit_set(claimed, target + index);
        bit_set(movable, target + index);
    }
    transaction_boundary();
    put_word(entry + 26, target);
    if (fat_volume_io(&state->volume, 1, directory_position, 1,
                      directory_sector)) {
        state->write_error = 1;
        return 1;
    }
    transaction_boundary();
    current = first;
    for (index = 0; index < count; ++index) {
        if (fat_volume_get(&state->volume, current, &next, fat_buffer)) {
            state->read_error = 1;
            return 1;
        }
        if (fat_volume_set(&state->volume, current, 0, fat_buffer)) {
            state->write_error = 1;
            return 1;
        }
        bit_clear(allocated, current);
        bit_clear(claimed, current);
        bit_clear(movable, current);
        current = next;
    }
    ++state->moved;
    return 0;
}

static int dot_entry(const unsigned char *entry)
{
    return entry[0] == '.' && (entry[1] == ' ' || entry[1] == '.');
}

static int process_directory(struct defrag_state *state, unsigned first,
                             unsigned depth, int relocate)
{
    unsigned cluster = first;
    int root = first == 0;
    if (depth > MAX_DEPTH) {
        state->allocation_error = 1;
        return 1;
    }
    do {
        unsigned long base = root ? state->volume.root_start
            : fat_volume_cluster_sector(&state->volume, cluster);
        unsigned sectors = root ? state->volume.root_sectors
            : state->volume.sectors_per_cluster;
        unsigned sector_index;
        for (sector_index = 0; sector_index < sectors; ++sector_index) {
            unsigned offset;
            unsigned long position = base + sector_index;
            if (fat_volume_io(&state->volume, 0, position, 1,
                              directory_sector)) {
                state->read_error = 1;
                return 1;
            }
            for (offset = 0; offset < 512; offset += 32) {
                unsigned char *entry = directory_sector + offset;
                unsigned child;
                unsigned fragments;
                unsigned count;
                if (!entry[0])
                    break;
                if (entry[0] == 0xe5 || (entry[11] & 0x0f) == 0x0f ||
                    (entry[11] & 0x08))
                    continue;
                child = get_word(entry + 26);
                if (entry[11] & 0x10) {
                    if (dot_entry(entry))
                        continue;
                    ++state->directories;
                    count = inspect_chain(state, child, &fragments);
                    if (!count)
                        return 1;
                    if (fragments)
                        ++state->fragmented;
                    if (!(entry[11] & 0x02) || state->options.hidden)
                        mark_chain_movable();
                    if (process_directory(state, child, depth + 1, relocate))
                        return 1;
                    if (fat_volume_io(&state->volume, 0, position, 1,
                                      directory_sector)) {
                        state->read_error = 1;
                        return 1;
                    }
                } else {
                    ++state->files;
                    if (!child)
                        continue;
                    count = inspect_chain(state, child, &fragments);
                    if (!count)
                        return 1;
                    if (!(entry[11] & 0x02) || state->options.hidden)
                        mark_chain_movable();
                    if (fragments) {
                        ++state->fragmented;
                        if (relocate && (!(entry[11] & 0x02) ||
                                         state->options.hidden)) {
                            if (relocate_file(state, child, count, entry,
                                              position))
                                return 1;
                            if (fat_volume_io(&state->volume, 0, position, 1,
                                              directory_sector)) {
                                state->read_error = 1;
                                return 1;
                            }
                        }
                    }
                }
            }
        }
        if (root)
            break;
        {
            unsigned next;
            if (fat_volume_get(&state->volume, cluster, &next, fat_buffer)) {
                state->read_error = 1;
                return 1;
            }
            if (fat_volume_eoc(&state->volume, next))
                break;
            cluster = next;
        }
    } while (fat_volume_valid_cluster(&state->volume, cluster));
    return 0;
}

static int replace_directory_references(struct defrag_state *state,
                                        unsigned first, unsigned old_cluster,
                                        unsigned new_cluster, unsigned depth)
{
    unsigned cluster = first;
    int root = first == 0;
    if (depth > MAX_DEPTH)
        return 1;
    do {
        unsigned long base = root ? state->volume.root_start
            : fat_volume_cluster_sector(&state->volume, cluster);
        unsigned sectors = root ? state->volume.root_sectors
            : state->volume.sectors_per_cluster;
        unsigned sector_index;
        for (sector_index = 0; sector_index < sectors; ++sector_index) {
            unsigned offset;
            int changed = 0;
            unsigned long position = base + sector_index;
            if (fat_volume_io(&state->volume, 0, position, 1,
                              directory_sector)) {
                state->read_error = 1;
                return 1;
            }
            for (offset = 0; offset < 512; offset += 32) {
                unsigned char *entry = directory_sector + offset;
                unsigned child;
                if (!entry[0])
                    break;
                if (entry[0] == 0xe5 || (entry[11] & 0x0f) == 0x0f ||
                    (entry[11] & 0x08))
                    continue;
                child = get_word(entry + 26);
                if (child == old_cluster) {
                    put_word(entry + 26, new_cluster);
                    child = new_cluster;
                    changed = 1;
                }
                if ((entry[11] & 0x10) && !dot_entry(entry) && child) {
                    if (changed && fat_volume_io(&state->volume, 1, position,
                                                 1, directory_sector)) {
                        state->write_error = 1;
                        return 1;
                    }
                    if (replace_directory_references(state, child, old_cluster,
                                                     new_cluster, depth + 1))
                        return 1;
                    if (fat_volume_io(&state->volume, 0, position, 1,
                                      directory_sector)) {
                        state->read_error = 1;
                        return 1;
                    }
                    changed = 0;
                }
            }
            if (changed && fat_volume_io(&state->volume, 1, position, 1,
                                         directory_sector)) {
                state->write_error = 1;
                return 1;
            }
        }
        if (root)
            break;
        {
            unsigned next;
            if (fat_volume_get(&state->volume, cluster, &next, fat_buffer)) {
                state->read_error = 1;
                return 1;
            }
            if (fat_volume_eoc(&state->volume, next))
                break;
            cluster = next;
        }
    } while (fat_volume_valid_cluster(&state->volume, cluster));
    return 0;
}

static int move_cluster(struct defrag_state *state, unsigned source,
                        unsigned target)
{
    unsigned link;
    unsigned cluster;
    unsigned value;
    if (copy_cluster(state, source, target))
        return 1;
    transaction_boundary();
    if (fat_volume_get(&state->volume, source, &link, fat_buffer) ||
        fat_volume_set(&state->volume, target, link, fat_buffer)) {
        state->write_error = 1;
        return 1;
    }
    transaction_boundary();
    for (cluster = 2; cluster <= state->volume.clusters + 1U; ++cluster) {
        if (fat_volume_get(&state->volume, cluster, &value, fat_buffer)) {
            state->read_error = 1;
            return 1;
        }
        if (value == source &&
            fat_volume_set(&state->volume, cluster, target, fat_buffer)) {
            state->write_error = 1;
            return 1;
        }
    }
    if (replace_directory_references(state, 0, source, target, 0))
        return 1;
    transaction_boundary();
    if (fat_volume_set(&state->volume, source, 0, fat_buffer)) {
        state->write_error = 1;
        return 1;
    }
    bit_set(allocated, target);
    bit_set(claimed, target);
    bit_set(movable, target);
    bit_clear(allocated, source);
    bit_clear(claimed, source);
    bit_clear(movable, source);
    return 0;
}

static int compact_free_space(struct defrag_state *state)
{
    unsigned target;
    unsigned source = 2;
    for (target = 2; target <= state->volume.clusters + 1U; ++target) {
        if (bit_get(allocated, target))
            continue;
        if (source <= target)
            source = target + 1U;
        while (source <= state->volume.clusters + 1U &&
               !bit_get(movable, source))
            ++source;
        if (source > state->volume.clusters + 1U)
            break;
        if (move_cluster(state, source, target))
            return 1;
        ++state->moved;
        ++source;
    }
    return 0;
}

static int compare_field(const unsigned char *left, const unsigned char *right,
                         char key)
{
    int result = 0;
    if (key == 'N')
        result = memcmp(left, right, 8);
    else if (key == 'E')
        result = memcmp(left + 8, right + 8, 3);
    else if (key == 'D') {
        unsigned left_date = get_word(left + 24);
        unsigned right_date = get_word(right + 24);
        unsigned left_time = get_word(left + 22);
        unsigned right_time = get_word(right + 22);
        if (left_date != right_date)
            result = left_date < right_date ? -1 : 1;
        else if (left_time != right_time)
            result = left_time < right_time ? -1 : 1;
    } else if (key == 'S') {
        unsigned long left_size = get_dword(left + 28);
        unsigned long right_size = get_dword(right + 28);
        if (left_size != right_size)
            result = left_size < right_size ? -1 : 1;
    }
    return result;
}

static int _WCCALLBACK compare_directory_entries(const void *left_value,
                                                 const void *right_value)
{
    const unsigned char *left = left_value;
    const unsigned char *right = right_value;
    const char *order = active_sort;
    while (*order) {
        char key = (char)toupper((unsigned char)*order++);
        int reverse = *order == '-';
        int result;
        if (reverse)
            ++order;
        result = compare_field(left, right, key);
        if (result)
            return reverse ? -result : result;
    }
    return memcmp(left, right, 11);
}

static int sortable_entry(const unsigned char *entry)
{
    return entry[0] && entry[0] != 0xe5 &&
        (entry[11] & 0x0f) != 0x0f && !(entry[11] & 0x08) &&
        !dot_entry(entry);
}

static int sort_directory(struct defrag_state *state, unsigned first,
                          unsigned depth)
{
    unsigned cluster = first;
    unsigned count = 0;
    int root = first == 0;
    if (depth > MAX_DEPTH)
        return 9;
    do {
        unsigned long base = root ? state->volume.root_start
            : fat_volume_cluster_sector(&state->volume, cluster);
        unsigned sectors = root ? state->volume.root_sectors
            : state->volume.sectors_per_cluster;
        unsigned sector_index;
        for (sector_index = 0; sector_index < sectors; ++sector_index) {
            unsigned offset;
            if (fat_volume_io(&state->volume, 0, base + sector_index, 1,
                              directory_sector))
                return 5;
            for (offset = 0; offset < 512; offset += 32) {
                unsigned char *entry = directory_sector + offset;
                if (!entry[0])
                    break;
                if (sortable_entry(entry)) {
                    if (count >= 512)
                        return 9;
                    memcpy(sort_entries[count++], entry, 32);
                }
            }
        }
        if (root)
            break;
        {
            unsigned next;
            if (fat_volume_get(&state->volume, cluster, &next, fat_buffer))
                return 5;
            if (fat_volume_eoc(&state->volume, next))
                break;
            cluster = next;
        }
    } while (fat_volume_valid_cluster(&state->volume, cluster));

    if (count > 1)
        qsort(sort_entries, count, 32, compare_directory_entries);
    cluster = first;
    count = 0;
    do {
        unsigned long base = root ? state->volume.root_start
            : fat_volume_cluster_sector(&state->volume, cluster);
        unsigned sectors = root ? state->volume.root_sectors
            : state->volume.sectors_per_cluster;
        unsigned sector_index;
        for (sector_index = 0; sector_index < sectors; ++sector_index) {
            unsigned offset;
            int changed = 0;
            if (fat_volume_io(&state->volume, 0, base + sector_index, 1,
                              directory_sector))
                return 5;
            for (offset = 0; offset < 512; offset += 32) {
                unsigned char *entry = directory_sector + offset;
                if (!entry[0])
                    break;
                if (sortable_entry(entry)) {
                    memcpy(entry, sort_entries[count++], 32);
                    changed = 1;
                }
            }
            if (changed && fat_volume_io(&state->volume, 1,
                    base + sector_index, 1, directory_sector))
                return 6;
        }
        if (root)
            break;
        {
            unsigned next;
            if (fat_volume_get(&state->volume, cluster, &next, fat_buffer))
                return 5;
            if (fat_volume_eoc(&state->volume, next))
                break;
            cluster = next;
        }
    } while (fat_volume_valid_cluster(&state->volume, cluster));
    cluster = first;
    do {
        unsigned long base = root ? state->volume.root_start
            : fat_volume_cluster_sector(&state->volume, cluster);
        unsigned sectors = root ? state->volume.root_sectors
            : state->volume.sectors_per_cluster;
        unsigned sector_index;
        for (sector_index = 0; sector_index < sectors; ++sector_index) {
            unsigned offset;
            if (fat_volume_io(&state->volume, 0, base + sector_index, 1,
                              directory_sector))
                return 5;
            for (offset = 0; offset < 512; offset += 32) {
                unsigned char *entry = directory_sector + offset;
                if (!entry[0])
                    break;
                if ((entry[11] & 0x10) && !dot_entry(entry) &&
                    entry[0] != 0xe5 && (entry[11] & 0x0f) != 0x0f) {
                    unsigned child = get_word(entry + 26);
                    if (child) {
                        int result = sort_directory(state, child, depth + 1);
                        if (result)
                            return result;
                        if (fat_volume_io(&state->volume, 0,
                                base + sector_index, 1, directory_sector))
                            return 5;
                    }
                }
            }
        }
        if (root)
            break;
        {
            unsigned next;
            if (fat_volume_get(&state->volume, cluster, &next, fat_buffer))
                return 5;
            if (fat_volume_eoc(&state->volume, next))
                break;
            cluster = next;
        }
    } while (fat_volume_valid_cluster(&state->volume, cluster));
    return 0;
}

static int validate_claimed_allocations(struct defrag_state *state)
{
    unsigned cluster;
    unsigned value;
    for (cluster = 2; cluster <= state->volume.clusters + 1U; ++cluster) {
        if (!bit_get(allocated, cluster) || bit_get(claimed, cluster))
            continue;
        if (fat_volume_get(&state->volume, cluster, &value, fat_buffer)) {
            state->read_error = 1;
            return 1;
        }
        if (!fat_volume_bad(&state->volume, value)) {
            state->allocation_error = 1;
            return 1;
        }
    }
    return 0;
}

static int defragment(unsigned drive, const struct options *options)
{
    struct defrag_state state;
    int allocation_result;
    memset(&state, 0, sizeof(state));
    state.options = *options;
    describe_presentation(options);
    printf("Analyzing drive %c:...\n", 'A' + drive);
    if (fat_volume_open(&state.volume, drive, boot_sector) != FATVOL_OK) {
        fputs("DEFRAG cannot access the selected FAT12/FAT16 drive.\n", stderr);
        return 4;
    }
    if (compare_fats(&state))
        return state.read_error ? 5 : 7;
    allocation_result = build_allocation_map(&state);
    if (allocation_result == 2) {
        fputs("The disk contains no free clusters.\n", stderr);
        return 2;
    }
    if (allocation_result)
        return 5;
    memset(claimed, 0, sizeof(claimed));
    memset(movable, 0, sizeof(movable));
    if (process_directory(&state, 0, 0, 1)) {
        if (state.read_error) return 5;
        if (state.write_error) return 6;
        return 7;
    }
    if (validate_claimed_allocations(&state))
        return state.read_error ? 5 : 7;
    printf("Optimizing drive %c: (%s, hidden files %s)\n", 'A' + drive,
           state.options.full ? "full compaction" : "file unfragmentation",
           state.options.hidden ? "included" : "left in place");
    if (state.options.full && compact_free_space(&state)) {
        if (state.read_error) return 5;
        if (state.write_error) return 6;
        return 7;
    }
    if (state.options.sort_set) {
        int sort_result;
        strcpy(active_sort, state.options.sort);
        sort_result = sort_directory(&state, 0, 0);
        if (sort_result)
            return sort_result;
    }
    printf("%lu file(s), %lu director%s; %lu fragmented, %lu moved.\n",
           state.files, state.directories,
           state.directories == 1 ? "y" : "ies", state.fragmented,
           state.moved);
    return 0;
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

static int drive_available(unsigned drive)
{
    union REGS regs;
    memset(&regs, 0, sizeof(regs));
    regs.h.ah = 0x36;
    regs.h.dl = (unsigned char)(drive + 1);
    intdos(&regs, &regs);
    return regs.x.ax != 0xffff;
}

static int interactive_select(struct options *options)
{
    union REGS regs;
    unsigned selected, drive;
    int key;
    memset(&regs, 0, sizeof(regs));
    regs.h.ah = 0x19;
    intdos(&regs, &regs);
    selected = regs.h.al;
    if (!drive_available(selected))
        for (selected = 0; selected < 26 && !drive_available(selected);
             ++selected) { }
    if (selected >= 26) {
        fputs("DEFRAG cannot find an accessible drive.\n", stderr);
        return 4;
    }
select_again:
    clear_interface();
    puts("Microsoft Defragmenter");
    puts("======================");
    puts("Select a drive to optimize:");
    for (drive = 0; drive < 26; ++drive)
        if (drive_available(drive))
            printf("  %c %c:\n", drive == selected ? '>' : ' ', 'A' + drive);
    printf("Selected drive %c:\n", 'A' + selected);
    puts("Use UP/DOWN or a drive letter; ENTER selects, ESC exits.");
    key = getch();
    if (key == 0 || key == 0xe0) {
        int scan = getch();
        int direction = scan == 72 ? -1 : scan == 80 ? 1 : 0;
        if (direction) {
            int candidate = (int)selected;
            do {
                candidate = (candidate + 26 + direction) % 26;
            } while (!drive_available((unsigned)candidate) &&
                     candidate != (int)selected);
            selected = (unsigned)candidate;
        }
        goto select_again;
    }
    if (key == 27) return -1;
    if (isalpha((unsigned char)key)) {
        drive = toupper((unsigned char)key) - 'A';
        if (drive_available(drive)) selected = drive;
        goto select_again;
    }
    if (key != '\r' && key != '\n') goto select_again;

configure_again:
    clear_interface();
    printf("Drive %c: selected.\n", 'A' + selected);
    puts("Recommended optimization: unfragment files.");
    printf("Current method: %s; hidden files: %s.\n",
           options->full ? "full compaction" : "file unfragmentation",
           options->hidden ? "included" : "left in place");
    puts("Press ENTER to begin, C to configure, or ESC to cancel.");
    key = getch();
    if (key == 27) return -1;
    if (key == 'c' || key == 'C') {
        clear_interface();
        puts("Optimize configuration");
        puts("U  Unfragment files");
        puts("F  Full compaction");
        puts("H  Toggle hidden-file movement");
        puts("ENTER accepts the current settings; ESC cancels.");
        key = getch();
        if (key == 27) return -1;
        if (key == 'u' || key == 'U') {
            options->full = 0; options->unfragment = 1;
        } else if (key == 'f' || key == 'F') {
            options->full = 1; options->unfragment = 0;
        } else if (key == 'h' || key == 'H') {
            options->hidden = !options->hidden;
        }
        goto configure_again;
    }
    if (key != '\r' && key != '\n') goto configure_again;
    options->drive = selected;
    options->drive_set = 1;
    return 0;
}

int main(int argc, char **argv)
{
    struct options options;
    union REGS regs;
    int result;
    if (parse_options(argc, argv, &options)) {
        usage();
        return 4;
    }
    if (argc == 1) {
        result = interactive_select(&options);
        if (result < 0) return 0;
        if (result) return result;
    }
    if (!options.drive_set) {
        memset(&regs, 0, sizeof(regs));
        regs.h.ah = 0x19;
        intdos(&regs, &regs);
        options.drive = regs.h.al;
    }
    result = defragment(options.drive, &options);
    if (!result && options.reboot) {
        union REGS reboot;
        memset(&reboot, 0, sizeof(reboot));
        int86(0x19, &reboot, &reboot);
    }
    return result;
}
