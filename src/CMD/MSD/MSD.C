#include <conio.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static FILE *report;
static int skip_detection;
static char report_name[64];
static char report_company[64];
extern char **environ;
extern unsigned MsdXmsVersion;
extern unsigned MsdXmsDriverVersion;
extern unsigned MsdXmsHma;
extern unsigned MsdXmsA20;
extern unsigned MsdXmsLargestFree;
extern unsigned MsdXmsTotalFree;
extern int MsdReadXmsInfo(void);
extern unsigned MsdCpuClass(void);

/* DOS's internal tables contain unaligned words.  Decode them bytewise so
 * this remains correct regardless of the compiler's structure packing. */
static unsigned table_word(const unsigned char far *p)
{
    return p[0] | ((unsigned)p[1] << 8);
}

static unsigned long table_pointer(const unsigned char far *p)
{
    return (unsigned long)table_word(p) |
           ((unsigned long)table_word(p + 2) << 16);
}

static void usage(void)
{
    puts("Provides detailed technical information about your computer.");
    puts("MSD [/I] [/F[drive:][path]filename] [/P[drive:][path]filename]");
    puts("    [/S[drive:][path][filename]]");
    puts("MSD [/B][/I]");
    puts("  /B                         Runs MSD using a black and white color scheme.");
    puts("  /I                         Bypasses initial hardware detection.");
    puts("  /F[drive:][path]filename   Requests input and writes an MSD report to the");
    puts("                             specified file.");
    puts("  /P[drive:][path]filename   Writes an MSD report to the specified file");
    puts("                             without first requesting input.");
    puts("  /S[drive:][path][filename] Writes a summary MSD report to the specified");
    puts("                             file. If no filename is specified, output is to");
    puts("                             the screen.");
    puts("Use MSD [/B] [/I] to examine technical information through the MSD interface.");
}

static void heading(const char *name)
{
    fprintf(report, "\n%s\n", name);
    fprintf(report, "----------------------------------------\n");
}

static void report_os(void)
{
    union REGS inregs, outregs;
    unsigned oem, serial;
    heading("Operating System");
    inregs.h.ah = 0x30;
    inregs.h.al = 0;
    int86(0x21, &inregs, &outregs);
    fprintf(report, "Reported DOS version: %u.%02u\n",
            outregs.h.al, outregs.h.ah);
    oem = outregs.h.bh;
    serial = outregs.x.cx;
    fprintf(report, "DOS OEM/serial:        %u / %u\n", oem, serial);
    inregs.x.ax = 0x3306;
    int86(0x21, &inregs, &outregs);
    if (!outregs.x.cflag)
        fprintf(report, "True DOS version:     %u.%02u\n",
                outregs.h.bl, outregs.h.bh);
    inregs.h.ah = 0x19;
    int86(0x21, &inregs, &outregs);
    fprintf(report, "Current drive:        %c:\n", 'A' + outregs.h.al);
}

static void report_computer(void)
{
    union REGS inregs, outregs;
    unsigned equipment;
    static const char *display_types[] = {
        "EGA/VGA", "40-column color", "80-column color", "Monochrome"
    };
    const unsigned char far *bios_date =
        (const unsigned char far *)MK_FP(0xf000, 0xfff5);
    const unsigned char far *model =
        (const unsigned char far *)MK_FP(0xf000, 0xfffe);
    unsigned i;
    heading("Computer");
    int86(0x11, &inregs, &outregs);
    equipment = outregs.x.ax;
    fprintf(report, "Processor:             %u-class x86\n", MsdCpuClass());
    fprintf(report, "BIOS equipment word:  %04Xh\n", equipment);
    fprintf(report, "Math coprocessor:      %s\n",
            equipment & 2 ? "Present" : "Not reported");
    fprintf(report, "Startup display:       %s\n",
            display_types[(equipment >> 4) & 3]);
    fprintf(report, "Game adapter:          %s\n",
            equipment & 0x1000 ? "Present" : "Not reported");
    fprintf(report, "Floppy drives:         %u\n",
            equipment & 1 ? ((equipment >> 6) & 3) + 1 : 0);
    fprintf(report, "Serial ports:          %u\n", (equipment >> 9) & 7);
    fprintf(report, "Parallel ports:        %u\n", (equipment >> 14) & 3);
    fprintf(report, "BIOS machine ID:       %02Xh\n", *model);
    int86(0x12, &inregs, &outregs);
    fprintf(report, "BIOS base memory:      %u KB\n", outregs.x.ax);
    fputs("Bus type:              ISA/AT compatible\n", report);
    fputs("DMA controller:        Present\n", report);
    fputs("BIOS date:             ", report);
    for (i = 0; i < 8; ++i)
        fputc(bios_date[i] >= 32 && bios_date[i] < 127 ? bios_date[i] : '?',
              report);
    fputc('\n', report);
    if (skip_detection)
        fprintf(report, "Extended probing:      Skipped (/I)\n");
}

static void resident_name(unsigned owner, unsigned block_segment,
                          const unsigned char far *block, char *name)
{
    const unsigned char far *psp;
    const unsigned char far *primary;
    const unsigned char far *environment;
    unsigned env_segment, offset, start, length = 0;
    if (owner == 0) {
        strcpy(name, "Free");
        return;
    }
    if (owner == 8) {
        strcpy(name, "System");
        return;
    }
    if (owner == block_segment + 1U) {
        for (length = 0; length < 8 && block[8 + length] != ' '; ++length) {
            unsigned char ch = block[8 + length];
            if (ch < 33 || ch >= 127) {
                length = 0;
                break;
            }
            name[length] = ch;
        }
        if (length) {
            name[length] = 0;
            return;
        }
    }
    primary = (const unsigned char far *)MK_FP(owner - 1U, 0);
    if (primary[0] == 'M' || primary[0] == 'Z') {
        for (length = 0; length < 8 && primary[8 + length] != ' '; ++length) {
            unsigned char ch = primary[8 + length];
            if (ch < 33 || ch >= 127) {
                length = 0;
                break;
            }
            name[length] = ch;
        }
        if (length) {
            name[length] = 0;
            return;
        }
    }
    psp = (const unsigned char far *)MK_FP(owner, 0);
    env_segment = table_word(psp + 0x2c);
    if (!env_segment) {
        strcpy(name, "Program");
        return;
    }
    environment = (const unsigned char far *)MK_FP(env_segment, 0);
    for (offset = 0; offset < 32760; ++offset)
        if (!environment[offset] && !environment[offset + 1])
            break;
    if (offset >= 32760) {
        strcpy(name, "Program");
        return;
    }
    offset += 4; /* double NUL and the executable-path count word */
    start = offset;
    while (environment[offset] && offset < 32767) {
        if (environment[offset] == '\\' || environment[offset] == ':')
            start = offset + 1;
        ++offset;
    }
    length = 0;
    while (start + length < offset && length < 12) {
        unsigned char ch = environment[start + length];
        name[length] = ch >= 32 && ch < 127 ? ch : '?';
        ++length;
    }
    name[length] = 0;
    if (!length || !strchr(name, '.'))
        strcpy(name, "Program");
}

static void report_programs(void)
{
    union REGS inregs, outregs;
    struct SREGS segregs;
    unsigned char far *lists;
    unsigned segment, count = 0;

    heading("Resident Programs");
    segread(&segregs);
    inregs.h.ah = 0x52;
    intdosx(&inregs, &outregs, &segregs);
    lists = (unsigned char far *)MK_FP(segregs.es, outregs.x.bx);
    segment = table_word(lists - 2);
    while (segment && count++ < 256) {
        unsigned char far *mcb = (unsigned char far *)MK_FP(segment, 0);
        unsigned owner, paragraphs;
        char name[13];
        if (mcb[0] != 'M' && mcb[0] != 'Z') {
            fputs("MCB chain:             Invalid or unavailable\n", report);
            return;
        }
        owner = table_word(mcb + 1);
        paragraphs = table_word(mcb + 3);
        resident_name(owner, segment, mcb, name);
        fprintf(report, "%04X  %7lu bytes  owner=%04X  %s\n",
                segment, (unsigned long)paragraphs * 16UL, owner, name);
        if (mcb[0] == 'Z')
            return;
        if ((unsigned)(segment + paragraphs + 1U) <= segment)
            break;
        segment += paragraphs + 1U;
    }
    fputs("MCB chain:             Truncated\n", report);
}

static void report_windows(void)
{
    const char *windir = getenv("WINDIR");
    char path[96];
    FILE *candidate = 0;
    heading("Windows Information");
    if (windir && *windir && strlen(windir) + 9 < sizeof(path)) {
        strcpy(path, windir);
        if (path[strlen(path) - 1] != '\\')
            strcat(path, "\\");
        strcat(path, "WIN.COM");
        candidate = fopen(path, "rb");
    }
    if (candidate) {
        fclose(candidate);
        fprintf(report, "Windows installation:  %s\n", windir);
    } else {
        fputs("Windows installation:  Not detected\n", report);
    }
}

static void report_ports(void)
{
    const unsigned far *bda = (const unsigned far *)MK_FP(0x40, 0);
    union REGS inregs, outregs;
    unsigned i;
    heading("COM and LPT Ports");
    for (i = 0; i < 4; ++i)
        if (bda[i]) {
            fprintf(report, "COM%u base address:     %04Xh\n", i + 1, bda[i]);
            if (!skip_detection) {
                inregs.h.ah = 3;
                inregs.x.dx = i;
                int86(0x14, &inregs, &outregs);
                fprintf(report, "COM%u BIOS status:      %04Xh\n", i + 1,
                        outregs.x.ax);
            }
        } else
            fprintf(report, "COM%u base address:     Not installed\n", i + 1);
    for (i = 0; i < 3; ++i)
        if (bda[4 + i]) {
            fprintf(report, "LPT%u base address:     %04Xh\n", i + 1,
                    bda[4 + i]);
            if (!skip_detection) {
                inregs.h.ah = 2;
                inregs.x.dx = i;
                int86(0x17, &inregs, &outregs);
                fprintf(report, "LPT%u BIOS status:      %02Xh\n", i + 1,
                        outregs.h.ah);
            }
        } else
            fprintf(report, "LPT%u base address:     Not installed\n", i + 1);
    if (skip_detection)
        fputs("Port status probing:   Skipped (/I)\n", report);
}

static void report_input(void)
{
    union REGS inregs, outregs;
    void interrupt far (*mouse)(void);
    heading("Input Devices");
    inregs.h.ah = 2;
    int86(0x16, &inregs, &outregs);
    fprintf(report, "Keyboard shift flags:  %02Xh\n", outregs.h.al);
    if (skip_detection) {
        fputs("Mouse driver:          Not probed (/I)\n", report);
        return;
    }
    mouse = _dos_getvect(0x33);
    if (!mouse || (FP_SEG(mouse) == 0 && FP_OFF(mouse) == 0)) {
        fputs("Mouse driver:          Not installed\n", report);
        return;
    }
    inregs.x.ax = 0;
    int86(0x33, &inregs, &outregs);
    if (outregs.x.ax == 0xffff)
        fprintf(report, "Mouse driver:          Installed, %u buttons\n",
                outregs.x.bx);
    else
        fputs("Mouse driver:          Not installed\n", report);
}

static void report_configuration(void)
{
    union REGS inregs, outregs;
    struct SREGS segregs;
    unsigned char country_info[34];
    unsigned env_count = 0;
    unsigned long env_bytes = 0;
    char **entry;
    heading("DOS Configuration");
    memset(&inregs, 0, sizeof(inregs));
    inregs.x.ax = 0x5800;
    intdos(&inregs, &outregs);
    fprintf(report, "Allocation strategy:   %04Xh\n", outregs.x.ax);
    inregs.x.ax = 0x5802;
    intdos(&inregs, &outregs);
    fprintf(report, "UMB chain linked:      %s\n",
            outregs.x.ax ? "Yes" : "No");
    inregs.h.ah = 0x54;
    intdos(&inregs, &outregs);
    fprintf(report, "Write verification:    %s\n",
            outregs.h.al ? "On" : "Off");
    inregs.x.ax = 0x3300;
    intdos(&inregs, &outregs);
    fprintf(report, "Extended BREAK check:  %s\n",
            outregs.h.dl ? "On" : "Off");
    inregs.x.ax = 0x6601;
    intdos(&inregs, &outregs);
    if (!outregs.x.cflag)
        fprintf(report, "Code pages:            %u active, %u system\n",
                outregs.x.bx, outregs.x.dx);
    memset(country_info, 0, sizeof(country_info));
    memset(&inregs, 0, sizeof(inregs));
    segread(&segregs);
    inregs.x.ax = 0x3800;
    inregs.x.dx = FP_OFF(country_info);
    segregs.ds = FP_SEG(country_info);
    intdosx(&inregs, &outregs, &segregs);
    if (!outregs.x.cflag) {
        static const char *orders[] = {
            "month-day-year", "day-month-year", "year-month-day"
        };
        unsigned order = table_word(country_info);
        fprintf(report, "Country code:          %u\n", outregs.x.bx);
        fprintf(report, "Date format:           %s\n",
                order < 3 ? orders[order] : "Unknown");
    }
    for (entry = environ; entry && *entry; ++entry) {
        ++env_count;
        env_bytes += strlen(*entry) + 1UL;
    }
    fprintf(report, "Environment:           %u variables, %lu bytes\n",
            env_count, env_bytes);
}

static int ems_present(void)
{
    void interrupt far (*handler)(void) = _dos_getvect(0x67);
    union REGS inregs, outregs;

    if (!handler || (FP_SEG(handler) == 0 && FP_OFF(handler) == 0))
        return 0;
    inregs.h.ah = 0x40;
    int86(0x67, &inregs, &outregs);
    return outregs.h.ah == 0;
}

static void report_memory(void)
{
    union REGS inregs, outregs;
    unsigned conventional, largest;
    int have_ems;
    heading("Memory");
    int86(0x12, &inregs, &outregs);
    conventional = outregs.x.ax;
    fprintf(report, "Conventional memory:   %u KB\n", conventional);
    inregs.h.ah = 0x48;
    inregs.x.bx = 0xffff;
    int86(0x21, &inregs, &outregs);
    largest = outregs.x.bx;
    fprintf(report, "Largest free block:    %lu bytes\n",
            (unsigned long)largest * 16UL);
    if (MsdReadXmsInfo()) {
        fputs("XMS manager:           Installed\n", report);
        fprintf(report, "XMS version:           %u.%02u\n",
                MsdXmsVersion >> 8, MsdXmsVersion & 0xff);
        fprintf(report, "XMS driver version:    %u.%02u\n",
                MsdXmsDriverVersion >> 8, MsdXmsDriverVersion & 0xff);
        fprintf(report, "HMA available:         %s\n",
                MsdXmsHma ? "Yes" : "No");
        fprintf(report, "A20 line:              %s\n",
                MsdXmsA20 == 1 ? "Enabled" : "Disabled");
        fprintf(report, "Largest free XMS:      %u KB\n", MsdXmsLargestFree);
        fprintf(report, "Total free XMS:        %u KB\n", MsdXmsTotalFree);
    } else {
        fputs("XMS manager:           Not installed\n", report);
    }
    have_ems = ems_present();
    fprintf(report, "EMS manager:           %s\n",
            have_ems ? "Installed" : "Not installed");
    if (have_ems) {
        inregs.h.ah = 0x46;
        int86(0x67, &inregs, &outregs);
        if (outregs.h.ah == 0)
            fprintf(report, "EMS version:           %u.%u\n",
                    outregs.h.al >> 4, outregs.h.al & 0x0f);
        inregs.h.ah = 0x41;
        int86(0x67, &inregs, &outregs);
        if (outregs.h.ah == 0)
            fprintf(report, "EMS page frame:        %04Xh\n", outregs.x.bx);
        inregs.h.ah = 0x42;
        int86(0x67, &inregs, &outregs);
        if (outregs.h.ah == 0) {
            fprintf(report, "Free EMS pages:        %u (%lu KB)\n",
                    outregs.x.bx, (unsigned long)outregs.x.bx * 16UL);
            fprintf(report, "Total EMS pages:       %u (%lu KB)\n",
                    outregs.x.dx, (unsigned long)outregs.x.dx * 16UL);
        }
    }
}

static void report_video(void)
{
    union REGS inregs, outregs;
    const unsigned char far *bda =
        (const unsigned char far *)MK_FP(0x40, 0);
    static const char *displays[] = {
        "None", "MDA", "CGA", "Reserved", "EGA color", "EGA monochrome",
        "PGA", "VGA monochrome", "VGA color", "Reserved", "MCGA color",
        "MCGA monochrome", "MCGA color"
    };
    heading("Video");
    inregs.h.ah = 0x0f;
    int86(0x10, &inregs, &outregs);
    fprintf(report, "Video mode:            %u\n", outregs.h.al);
    fprintf(report, "Text columns:          %u\n", outregs.h.ah);
    fprintf(report, "Active display page:   %u\n", outregs.h.bh);
    fprintf(report, "Text rows:             %u\n", (unsigned)bda[0x84] + 1);
    fprintf(report, "Character height:      %u scan lines\n",
            table_word(bda + 0x85));
    inregs.x.ax = 0x1a00;
    int86(0x10, &inregs, &outregs);
    if (outregs.h.al == 0x1a) {
        fprintf(report, "Active adapter:        %s\n",
                outregs.h.bl < 13 ? displays[outregs.h.bl] : "Unknown");
        fprintf(report, "Alternate adapter:     %s\n",
                outregs.h.bh < 13 ? displays[outregs.h.bh] : "Unknown");
    }
}

static void report_disks(void)
{
    union REGS inregs, outregs;
    struct SREGS segregs;
    unsigned char far *lists;
    unsigned char far *dpb;
    unsigned char far *cds;
    unsigned drive, count = 0, i, floppy_count;
    unsigned long pointer;
    heading("Disk Drives");

    segread(&segregs);
    inregs.h.ah = 0x52;
    intdosx(&inregs, &outregs, &segregs);
    lists = (unsigned char far *)MK_FP(segregs.es, outregs.x.bx);

    int86(0x11, &inregs, &outregs);
    floppy_count = outregs.x.ax & 1 ? ((outregs.x.ax >> 6) & 3) + 1 : 0;

    inregs.h.ah = 0x19;
    int86(0x21, &inregs, &outregs);
    drive = outregs.h.al + 1;
    inregs.h.ah = 0x36;
    inregs.h.dl = (unsigned char)drive;
    int86(0x21, &inregs, &outregs);
    if (outregs.x.ax != 0xffff) {
        unsigned long cluster = (unsigned long)outregs.x.ax * outregs.x.cx;
        fprintf(report, "%c:  total %10lu  free %10lu bytes\n",
                'A' + drive - 1, cluster * outregs.x.dx,
                cluster * outregs.x.bx);
    }

    pointer = table_pointer(lists);
    /* DOS code in this tree checks both forms used by its initializers: an
     * FFFFh offset or an FFFFh segment marks the end of the chain. */
    while ((unsigned)pointer != 0xffff &&
           (unsigned)(pointer >> 16) != 0xffff && count++ < 26) {
        unsigned long clusters, bytes;
        unsigned max_cluster, sector_size;
        unsigned char dpb_drive;
        dpb = (unsigned char far *)
            MK_FP((unsigned)(pointer >> 16), (unsigned)pointer);
        dpb_drive = dpb[0];
        if ((unsigned)dpb_drive + 1 != drive &&
            dpb_drive == 1 && floppy_count < 2) {
            fprintf(report, "B:  logical alias of A: (one physical floppy)\n");
        } else if ((unsigned)dpb_drive + 1 != drive) {
            max_cluster = table_word(dpb + 13);
            sector_size = table_word(dpb + 2);
            clusters = max_cluster > 1 ? max_cluster - 1UL : 0;
            bytes = clusters * (dpb[4] + 1UL) * sector_size;
            fprintf(report,
                    "%c:  total %10lu bytes  %u-byte sectors  FAT%u\n",
                    'A' + dpb_drive, bytes, sector_size,
                    max_cluster < 4087 ? 12 : 16);
        }
        pointer = table_pointer(dpb + 25);
    }

    pointer = table_pointer(lists + 22);
    cds = (unsigned char far *)MK_FP((unsigned)(pointer >> 16),
                                     (unsigned)pointer);
    for (i = 0; i < lists[33] && i < 26; ++i, cds += 88) {
        unsigned flags = table_word(cds + 67);
        if (flags & (0x8000 | 0x2000 | 0x1000)) {
            char path[68];
            unsigned j;
            for (j = 0; j < 67 && cds[j]; ++j)
                path[j] = cds[j];
            path[j] = 0;
            fprintf(report, "%c:  %s %s\n", 'A' + i,
                    flags & 0x8000 ? "network mapping " :
                    flags & 0x2000 ? "joined path      " :
                                     "substituted path",
                    path);
        }
    }
}

static void report_irqs(void)
{
    unsigned irq, vector;
    void interrupt far (*handler)(void);
    heading("IRQ Vectors");
    for (irq = 0; irq < 16; ++irq) {
        vector = irq < 8 ? irq + 8 : irq + 0x68;
        handler = _dos_getvect(vector);
        fprintf(report, "IRQ %-2u  INT %02Xh  %04X:%04X\n", irq, vector,
                FP_SEG(handler), FP_OFF(handler));
    }
}

static void report_drivers(void)
{
    union REGS inregs, outregs;
    struct SREGS segregs;
    unsigned far *link;
    unsigned segment, offset, count = 0;
    char name[9];
    unsigned i;
    heading("Device Drivers");
    segread(&segregs);
    inregs.h.ah = 0x52;
    intdosx(&inregs, &outregs, &segregs);
    segment = segregs.es;
    link = (unsigned far *)MK_FP(segment, outregs.x.bx + 0x22);
    offset = link[0];
    segment = link[1];
    while (offset != 0xffff && segment != 0xffff && count++ < 64) {
        unsigned far *header = (unsigned far *)MK_FP(segment, offset);
        unsigned attributes = header[2];
        if (attributes & 0x8000) {
            char far *raw = (char far *)MK_FP(segment, offset + 10);
            for (i = 0; i < 8; ++i)
                name[i] = raw[i];
            name[8] = 0;
            fprintf(report, "%-8s  character  attr=%04Xh  %04X:%04X\n",
                    name, attributes, segment, offset);
        } else {
            fprintf(report, "%u unit(s) block driver  attr=%04Xh  %04X:%04X\n",
                    *((unsigned char far *)MK_FP(segment, offset + 10)),
                    attributes, segment, offset);
        }
        link = header;
        offset = link[0];
        segment = link[1];
    }
}

static void report_network(void)
{
    union REGS inregs, outregs;
    heading("Network");
    inregs.x.ax = 0x1100;
    int86(0x2f, &inregs, &outregs);
    fprintf(report, "DOS redirector:        %s\n",
            outregs.h.al == 0xff ? "Installed" : "Not installed");
    inregs.x.ax = 0xb800;
    int86(0x2f, &inregs, &outregs);
    fprintf(report, "Network services:      %s\n",
            outregs.h.al == 0xff ? "Reported" : "Not reported");
}

static void report_summary(void)
{
    fprintf(report, "Microsoft Diagnostics-compatible report\n");
    report_os();
    report_computer();
    report_memory();
    report_video();
    report_ports();
    report_input();
    report_configuration();
    report_disks();
    report_irqs();
    report_programs();
    report_drivers();
    report_network();
    report_windows();
}

static void report_short_summary(void)
{
    union REGS inregs, outregs;
    unsigned conventional;

    int86(0x12, &inregs, &outregs);
    conventional = outregs.x.ax;
    fprintf(report, "           Computer: IBM PC/AT compatible\n");
    fprintf(report, "             Memory: %uK conventional\n", conventional);
    fprintf(report, "              Video: BIOS mode detected\n");
    inregs.x.ax = 0x1100;
    int86(0x2f, &inregs, &outregs);
    fprintf(report, "            Network: %s\n",
            outregs.h.al == 0xff ? "DOS Redirector" : "No Network");
    inregs.x.ax = 0x3306;
    int86(0x21, &inregs, &outregs);
    fprintf(report, "         OS Version: MS-DOS %u.%02u\n",
            outregs.h.bl, outregs.h.bh);
}

static void request_report_input(void)
{
    fputs("Name: ", stdout);
    if (!fgets(report_name, sizeof(report_name), stdin)) report_name[0] = 0;
    fputs("Company: ", stdout);
    if (!fgets(report_company, sizeof(report_company), stdin)) report_company[0] = 0;
    report_name[strcspn(report_name, "\r\n")] = 0;
    report_company[strcspn(report_company, "\r\n")] = 0;
}

static void interactive(void)
{
    int key;
    for (;;) {
        puts("\nMicrosoft Diagnostics");
        puts("  C  Computer       M  Memory        V  Video");
        puts("  D  Disk drives    I  IRQs          R  Drivers");
        puts("  P  Ports          K  Input         G  DOS configuration");
        puts("  N  Network        T  Resident programs  W  Windows");
        puts("  O  Operating system");
        puts("  A  All reports    X  Exit");
        fputs("Selection: ", stdout);
        key = getch();
        putchar(key); puts("");
        switch (key) {
        case 'c': case 'C': report_computer(); break;
        case 'm': case 'M': report_memory(); break;
        case 'v': case 'V': report_video(); break;
        case 'p': case 'P': report_ports(); break;
        case 'k': case 'K': report_input(); break;
        case 'g': case 'G': report_configuration(); break;
        case 'd': case 'D': report_disks(); break;
        case 'i': case 'I': report_irqs(); break;
        case 'r': case 'R': report_drivers(); break;
        case 'n': case 'N': report_network(); break;
        case 't': case 'T': report_programs(); break;
        case 'w': case 'W': report_windows(); break;
        case 'o': case 'O': report_os(); break;
        case 'a': case 'A': report_summary(); break;
        case 'x': case 'X': return;
        default: putchar('\a'); break;
        }
    }
}

int main(int argc, char **argv)
{
    const char *filename = 0;
    int summary = 0, request_input = 0, i;
    report = stdout;
    for (i = 1; i < argc; ++i) {
        char *arg = argv[i];
        char option;
        if (arg[0] != '/' && arg[0] != '-')
            goto bad_switch;
        option = arg[1] >= 'a' && arg[1] <= 'z' ? arg[1] - 32 : arg[1];
        if (option == '?' && !arg[2]) { usage(); return 0; }
        if (option == 'B' && !arg[2]) continue;
        if (option == 'I' && !arg[2]) { skip_detection = 1; continue; }
        if (option == 'F' || option == 'P' || option == 'S') {
            char *value = arg + 2;
            if (!*value && i + 1 < argc && argv[i + 1][0] != '/' &&
                argv[i + 1][0] != '-')
                value = argv[++i];
            if (option != 'S' && !*value) goto bad_switch;
            if (*value) filename = value;
            summary = option == 'S';
            request_input = option == 'F';
            continue;
        }
        goto bad_switch;
    }
    if (request_input)
        request_report_input();
    if (filename) {
        report = fopen(filename, "w");
        if (!report) { fprintf(stderr, "Unable to create %s\n", filename); return 2; }
    }
    setvbuf(report, 0, _IONBF, 0);
    if (summary)
        report_short_summary();
    else if (report != stdout) {
        fprintf(report, "MSD Microsoft Diagnostics Version 2.11\n");
        if (report_name[0]) fprintf(report, "Name: %s\n", report_name);
        if (report_company[0]) fprintf(report, "Company: %s\n", report_company);
        report_summary();
    } else
        interactive();
    if (report != stdout && fclose(report))
        return 2;
    return 0;
bad_switch:
    fprintf(stderr, "Invalid switch - %s\n", argv[i]);
    return 1;
}
