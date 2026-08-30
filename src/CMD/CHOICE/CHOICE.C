#include <ctype.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_CHOICES 128
#define MAX_PROMPT 256

static void usage(void)
{
    puts("Selects one item from a choice list.");
    puts("CHOICE [/C[:]choices] [/N] [/S] [/T[:]choice,seconds] [text]");
}

static int same_char(int a, int b, int sensitive)
{
    if (sensitive)
        return a == b;
    return toupper((unsigned char)a) == toupper((unsigned char)b);
}

static int ready(void)
{
    union REGS inregs, outregs;
    inregs.h.ah = 0x0b;
    int86(0x21, &inregs, &outregs);
    return outregs.h.al == 0xff;
}

static void append_prompt(char *prompt, const char *word)
{
    unsigned used = strlen(prompt);
    unsigned left = MAX_PROMPT - used - 1;
    if (used && left) {
        prompt[used++] = ' ';
        prompt[used] = 0;
        --left;
    }
    strncat(prompt, word, left);
}

int main(int argc, char **argv)
{
    char choices[MAX_CHOICES] = "YN";
    char prompt[MAX_PROMPT] = "";
    int sensitive = 0, show_choices = 1;
    int timeout = -1, timeout_choice = 0;
    int i, j, c;
    clock_t deadline = 0;

    for (i = 1; i < argc; ++i) {
        char *arg = argv[i];
        char *value;
        if (arg[0] != '/' && arg[0] != '-') {
            append_prompt(prompt, arg);
            continue;
        }
        if (!stricmp(arg + 1, "?")) {
            usage();
            return 0;
        }
        if (!stricmp(arg + 1, "N")) {
            show_choices = 0;
            continue;
        }
        if (!stricmp(arg + 1, "S")) {
            sensitive = 1;
            continue;
        }
        if (toupper((unsigned char)arg[1]) == 'C') {
            value = arg + 2;
            if (*value == ':')
                ++value;
            if (!*value || strlen(value) >= sizeof(choices))
                goto bad_syntax;
            strcpy(choices, value);
            continue;
        }
        if (toupper((unsigned char)arg[1]) == 'T') {
            char *comma;
            char *end;
            long seconds;
            value = arg + 2;
            if (*value == ':')
                ++value;
            comma = strchr(value, ',');
            if (!value[0] || value[1] != ',' || !comma[1])
                goto bad_syntax;
            timeout_choice = (unsigned char)value[0];
            seconds = strtol(comma + 1, &end, 10);
            if (*end || seconds < 0 || seconds > 99)
                goto bad_syntax;
            timeout = (int)seconds;
            continue;
        }
        goto bad_syntax;
    }

    for (i = 0; choices[i]; ++i) {
        for (j = 0; j < i; ++j)
            if (same_char(choices[i], choices[j], sensitive))
                goto bad_syntax;
    }
    if (timeout_choice) {
        for (i = 0; choices[i]; ++i)
            if (same_char(timeout_choice, choices[i], sensitive))
                break;
        if (!choices[i])
            goto bad_syntax;
    }

    if (*prompt)
        fputs(prompt, stdout);
    if (show_choices) {
        putchar('[');
        for (i = 0; choices[i]; ++i) {
            if (i)
                putchar(',');
            putchar(choices[i]);
        }
        fputs("]?", stdout);
    }
    fflush(stdout);

    if (timeout >= 0)
        deadline = clock() + (clock_t)timeout * CLOCKS_PER_SEC;
    for (;;) {
        if (timeout >= 0 && !ready() && clock() >= deadline) {
            c = timeout_choice;
        } else if (timeout >= 0 && !ready()) {
            continue;
        } else {
            c = getchar();
            if (c == EOF)
                return 0;
            if (c == '\r' || c == '\n')
                continue;
        }
        for (i = 0; choices[i]; ++i) {
            if (same_char(c, choices[i], sensitive)) {
                if (!show_choices)
                    putchar(c);
                puts("");
                return i + 1;
            }
        }
        putchar('\a');
        fflush(stdout);
    }

bad_syntax:
    fputs("Invalid choice switch.\n", stderr);
    return 255;
}
