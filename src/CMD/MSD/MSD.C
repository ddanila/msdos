#include <conio.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static FILE *report;
static int skip_detection;

static void usage(void)
{
    puts("Displays Microsoft Diagnostics information.");
    puts("MSD [/B] [/I] [/F [filename]] [/P] [/S]");
}

static void heading(const char *name)
{
    fprintf(report, "\n%s\n", name);
    fprintf(report, "----------------------------------------\n");
}

static void report_os(void)
{
    union REGS inregs, outregs;
    heading("Operating System");
    inregs.h.ah = 0x30;
    inregs.h.al = 0;
    int86(0x21, &inregs, &outregs);
    fprintf(report, "Reported DOS version: %u.%02u\n",
            outregs.h.al, outregs.h.ah);
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
    heading("Computer");
    int86(0x11, &inregs, &outregs);
    equipment = outregs.x.ax;
    fprintf(report, "BIOS equipment word:  %04Xh\n", equipment);
    fprintf(report, "Math coprocessor:      %s\n",
            equipment & 2 ? "Present" : "Not reported");
    fprintf(report, "Floppy drives:         %u\n",
            equipment & 1 ? ((equipment >> 6) & 3) + 1 : 0);
    fprintf(report, "Serial ports:          %u\n", (equipment >> 9) & 7);
    fprintf(report, "Parallel ports:        %u\n", (equipment >> 14) & 3);
    if (skip_detection)
        fprintf(report, "Extended probing:      Skipped (/I)\n");
}

static int ems_present(void)
{
    void interrupt far (*handler)(void) = _dos_getvect(0x67);
    const char far *signature;
    static const char expected[] = "EMMXXXX0";
    unsigned i;

    if (handler == 0)
        return 0;
    signature = (const char far *)MK_FP(FP_SEG(handler),
                                        FP_OFF(handler) + 10);
    for (i = 0; i < 8; ++i)
        if (signature[i] != expected[i])
            return 0;
    return 1;
}

static void report_memory(void)
{
    union REGS inregs, outregs;
    unsigned conventional, largest;
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
    inregs.x.ax = 0x4300;
    int86(0x2f, &inregs, &outregs);
    fprintf(report, "XMS manager:           %s\n",
            outregs.h.al == 0x80 ? "Installed" : "Not installed");
    fprintf(report, "EMS manager:           %s\n",
            ems_present() ? "Installed" : "Not installed");
}

static void report_video(void)
{
    union REGS inregs, outregs;
    heading("Video");
    inregs.h.ah = 0x0f;
    int86(0x10, &inregs, &outregs);
    fprintf(report, "Video mode:            %u\n", outregs.h.al);
    fprintf(report, "Text columns:          %u\n", outregs.h.ah);
    fprintf(report, "Active display page:   %u\n", outregs.h.bh);
}

static void report_disks(void)
{
    union REGS inregs, outregs;
    unsigned drive;
    heading("Disk Drives");
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
    report_disks();
    report_irqs();
    report_drivers();
    report_network();
}

static void interactive(void)
{
    int key;
    for (;;) {
        puts("\nMicrosoft Diagnostics");
        puts("  C  Computer       M  Memory        V  Video");
        puts("  D  Disk drives    I  IRQs          R  Drivers");
        puts("  N  Network        O  Operating system");
        puts("  A  All reports    X  Exit");
        fputs("Selection: ", stdout);
        key = getch();
        putchar(key); puts("");
        switch (key) {
        case 'c': case 'C': report_computer(); break;
        case 'm': case 'M': report_memory(); break;
        case 'v': case 'V': report_video(); break;
        case 'd': case 'D': report_disks(); break;
        case 'i': case 'I': report_irqs(); break;
        case 'r': case 'R': report_drivers(); break;
        case 'n': case 'N': report_network(); break;
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
    int summary = 0, printer = 0, i;
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
        if (option == 'P' && !arg[2]) { printer = 1; continue; }
        if (option == 'S' && !arg[2]) { summary = 1; continue; }
        if (option == 'F') {
            char *value = arg + 2;
            if (*value == ':') ++value;
            if (!*value && i + 1 < argc && argv[i + 1][0] != '/' &&
                argv[i + 1][0] != '-')
                value = argv[++i];
            filename = *value ? value : "MSD.TXT";
            continue;
        }
        goto bad_switch;
    }
    if (filename) {
        report = fopen(filename, "w");
        if (!report) { fprintf(stderr, "Unable to create %s\n", filename); return 2; }
    } else if (printer) {
        report = fopen("PRN", "w");
        if (!report) { fputs("Unable to open printer.\n", stderr); return 2; }
    }
    setvbuf(report, 0, _IONBF, 0);
    if (summary || report != stdout)
        report_summary();
    else
        interactive();
    if (report != stdout && fclose(report))
        return 2;
    return 0;
bad_switch:
    fprintf(stderr, "Invalid switch - %s\n", argv[i]);
    return 1;
}
