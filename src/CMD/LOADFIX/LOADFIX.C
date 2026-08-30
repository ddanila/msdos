#include <dos.h>
#include <process.h>
#include <stdio.h>
#include <string.h>

#define SIXTY_FOUR_K_PARAGRAPHS 0x1000

static void usage(void)
{
    puts("Loads a program above the first 64K of conventional memory.");
    puts("LOADFIX [drive:][path]filename [arguments]");
}

int main(int argc, char **argv)
{
    unsigned block;
    int status;

    if (argc < 2 || !stricmp(argv[1], "/?")) {
        usage();
        return argc < 2 ? 1 : 0;
    }
    if (_dos_allocmem(SIXTY_FOUR_K_PARAGRAPHS, &block)) {
        fputs("LOADFIX: insufficient memory.\n", stderr);
        return 8;
    }
    status = spawnvp(P_WAIT, argv[1], (const char * const *)(argv + 1));
    _dos_freemem(block);
    if (status == -1) {
        fputs("LOADFIX: cannot load program.\n", stderr);
        return 2;
    }
    return status;
}
