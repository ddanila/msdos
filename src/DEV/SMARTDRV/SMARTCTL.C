#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    unsigned char write_through, write_buff, enable_13, nuldev;
    unsigned int ticksetting;
    unsigned char lock_cache, reboot_flush, all_cache, pad;
    unsigned long total_writes, write_hits, total_reads, read_hits;
    unsigned int ttracks, total_used, total_locked, total_dirty;
    unsigned int current_size, initial_size, minimum_size;
} status;

extern int IOCTLOpen(char *);
extern int IOCTLWrite(int, char *, int);
extern int IOCTLRead(int, status *, int);
extern int IOCTLClose(int);

static int quiet;

static int upper(c)
int c;
{
    return c >= 'a' && c <= 'z' ? c - ('a' - 'A') : c;
}

static int same(a, b)
char *a, *b;
{
    while (*a && *b && upper(*a) == upper(*b)) { ++a; ++b; }
    return *a == 0 && *b == 0;
}

static void usage()
{
    puts("Caches disk data in extended memory.");
    puts("SMARTDRV [/X] [[drive[+|-]]...] [/U] [/C|/R] [/F|/N]");
    puts("         [/L] [/V|/Q|/S] [InitCacheSize [WinCacheSize]]");
    puts("         [/E:ElementSize] [/B:BufferSize]");
}

static void fail(h, message)
int h;
char *message;
{
    if (h >= 0) IOCTLClose(h);
    fprintf(stderr, "SMARTDRV: %s\n", message);
    exit(1);
}

static void send(h, packet, count)
int h, count;
char *packet;
{
    if (IOCTLWrite(h, packet, count) == -1)
        fail(h, "cache device rejected the request");
}

static unsigned getnum(s, ok)
char *s;
int *ok;
{
    unsigned long n = 0;
    *ok = 0;
    if (!*s) return 0;
    while (*s) {
        if (*s < '0' || *s > '9') return 0;
        n = n * 10 + (*s++ - '0');
        if (n > 65535L) return 0;
    }
    *ok = 1;
    return (unsigned)n;
}

static void show_status(h, extended)
int h, extended;
{
    status s;
    char p[3];
    int drive;
    if (IOCTLRead(h, &s, sizeof(s)) == -1)
        fail(h, "cannot read cache status");
    printf("Microsoft SMARTDrive-compatible disk cache\n\n");
    puts("Disk Caching Status");
    for (drive = 0; drive < 16; ++drive) {
        p[0] = 0x0e; p[1] = drive; p[2] = 0xff;
        if (IOCTLWrite(h, p, 3) == -1) break;
        if (drive == 0 || p[2] != 1)
            printf("  %c:  Read cache %s  Write cache %s\n",
                'C' + drive, p[2] ? "yes" : "no",
                p[2] == 2 && s.write_buff ? "yes" : "no");
    }
    printf("Cache enabled: %s   Delayed writes: %s\n",
        s.enable_13 ? "yes" : "no", s.write_buff ? "yes" : "no");
    if (extended)
        printf("Tracks: %u total, %u used, %u dirty; reads %lu/%lu hits, writes %lu/%lu hits\n",
            s.ttracks, s.total_used, s.total_dirty,
            s.read_hits, s.total_reads, s.write_hits, s.total_writes);
}

int main(argc, argv)
int argc;
char **argv;
{
    int h, i, action = 0, extended = 0, verbose = 0, numbers = 0, ok;
    unsigned n;
    char p[3];

    for (i = 1; i < argc; ++i)
        if (strlen(argv[i]) == 2 && argv[i][0] == '/' && argv[i][1] == '?') {
            usage();
            return 0;
        }
    h = IOCTLOpen("SMARTAAR");
    if (h == -1) fail(-1, "SMARTDrive is not installed (load SMARTDRV.SYS in CONFIG.SYS)");

    for (i = 1; i < argc; ++i) {
        char *a = argv[i];
        int len = strlen(a), drive, policy;
        if (len == 2 && a[0] == '/' && a[1] == '?') {
            usage(); IOCTLClose(h); return 0;
        }
        if (len >= 1 && upper(a[0]) >= 'A' && upper(a[0]) <= 'Z' &&
            (len == 1 || (len == 2 && (a[1] == '+' || a[1] == '-')))) {
            drive = upper(a[0]) - 'C';
            if (drive < 0 || drive >= 16) fail(h, "only fixed drives C: through R: are cacheable");
            policy = len == 1 ? 1 : (a[1] == '+' ? 2 : 0);
            p[0] = 0x0d; p[1] = drive; p[2] = policy; send(h, p, 3);
            action = 1;
            continue;
        }
        if (a[0] == '/' || a[0] == '-') {
            ++a;
            if (same(a, "C")) { p[0] = 0; send(h, p, 1); action = 1; }
            else if (same(a, "R")) { p[0] = 1; send(h, p, 1); p[0] = 3; send(h, p, 1); action = 1; }
            else if (same(a, "X") || same(a, "N")) { p[0] = 4; p[1] = 2; send(h, p, 2); action = 1; }
            else if (same(a, "F")) { p[0] = 4; p[1] = 3; send(h, p, 2); action = 1; }
            else if (same(a, "Q")) quiet = 1;
            else if (same(a, "V")) verbose = 1;
            else if (same(a, "S")) extended = 1;
            else if (same(a, "L") || same(a, "U")) action = 1;
            else if ((upper(a[0]) == 'E' || upper(a[0]) == 'B') && a[1] == ':') {
                n = getnum(a + 2, &ok);
                if (!ok || (upper(a[0]) == 'E' && n != 1024 && n != 2048 && n != 4096 && n != 8192))
                    fail(h, "invalid cache element or read-ahead size");
                action = 1;
            } else fail(h, "invalid switch; use SMARTDRV /?");
            continue;
        }
        n = getnum(a, &ok);
        if (!ok || ++numbers > 2) fail(h, "invalid cache size");
        action = 1;
    }
    if (!quiet && (!action || verbose || extended)) show_status(h, extended || verbose);
    IOCTLClose(h);
    return 0;
}
