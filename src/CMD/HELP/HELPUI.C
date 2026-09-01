#include <conio.h>
#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_TOPICS 192
#define MAX_LINES 1024
#define PAGE_ROWS 19
#define MOUSE_KEY 0x100

typedef struct {
    char *name;
    unsigned first;
    unsigned count;
} Topic;

static Topic topics[MAX_TOPICS];
static char *lines[MAX_LINES];
static unsigned topic_count;
static unsigned line_count;
static char *database;
static unsigned matches[MAX_TOPICS];
static unsigned match_count;
static char search_text[32];
static int mouse_available;
static int mouse_latched;
static unsigned mouse_row;
static unsigned mouse_column;
static unsigned cursor_row = 1;
static unsigned cursor_column = 1;
static unsigned char screen_attribute = 7;
static unsigned short saved_screen[2000];
static unsigned char saved_mode;
static unsigned char saved_page;
static unsigned char saved_cursor_row;
static unsigned char saved_cursor_column;
static int changed_mode;

static unsigned short far *video_memory(void)
{
    union REGS regs;
    memset(&regs, 0, sizeof(regs));
    regs.h.ah = 0x0f;
    int86(0x10, &regs, &regs);
    return (unsigned short far *)MK_FP(regs.h.al == 7 ? 0xb000 : 0xb800,
                                       (unsigned)regs.h.bh * 0x1000U);
}

static void ui_gotoxy(unsigned column, unsigned row)
{
    cursor_column = column;
    cursor_row = row;
}

static void ui_textattr(unsigned char attribute)
{
    screen_attribute = attribute;
}

static void ui_putch(int character)
{
    unsigned short far *screen = video_memory();
    if (cursor_row >= 1 && cursor_row <= 25 &&
        cursor_column >= 1 && cursor_column <= 80)
        screen[(cursor_row - 1) * 80 + cursor_column - 1] =
            ((unsigned)screen_attribute << 8) | (unsigned char)character;
    if (cursor_column < 80) ++cursor_column;
}

#define gotoxy ui_gotoxy
#define textattr ui_textattr
#define putch ui_putch

static void usage(void)
{
    puts("Displays help for MS-DOS commands.");
    puts("HELP [command]");
    puts("With no command, HELP opens the full-screen Help browser.");
}

static int upper(int c)
{
    if (c >= 'a' && c <= 'z') return c - ('a' - 'A');
    return c;
}

static int equal_ci(const char *a, const char *b)
{
    while (*a && *b && upper((unsigned char)*a) == upper((unsigned char)*b)) {
        ++a;
        ++b;
    }
    return !*a && !*b;
}

static int contains_ci(const char *text, const char *needle)
{
    const char *p, *q;
    if (!*needle) return 1;
    for (; *text; ++text) {
        p = text;
        q = needle;
        while (*p && *q &&
               upper((unsigned char)*p) == upper((unsigned char)*q)) {
            ++p;
            ++q;
        }
        if (!*q) return 1;
    }
    return 0;
}

static int compare_ci(const char *a, const char *b)
{
    while (*a && *b && upper((unsigned char)*a) == upper((unsigned char)*b)) {
        ++a;
        ++b;
    }
    return upper((unsigned char)*a) - upper((unsigned char)*b);
}

static void database_path(char *path)
{
    char *slash;
    strncpy(path, _pgmptr ? _pgmptr : "", 127);
    path[127] = 0;
    slash = strrchr(path, '\\');
    if (!slash) slash = strrchr(path, '/');
    if (slash) strcpy(slash + 1, "HELP.HLP");
    else strcpy(path, "HELP.HLP");
}

static int load_database(void)
{
    FILE *file;
    long size;
    char path[128];
    char *p, *line;
    Topic *current = 0;
    database_path(path);
    file = fopen(path, "rb");
    if (!file && strcmp(path, "HELP.HLP")) file = fopen("HELP.HLP", "rb");
    if (!file) return 0;
    fseek(file, 0, SEEK_END);
    size = ftell(file);
    rewind(file);
    if (size <= 0 || size > 60000L) { fclose(file); return 0; }
    database = malloc((unsigned)size + 1);
    if (!database) { fclose(file); return 0; }
    if (fread(database, 1, (unsigned)size, file) != (unsigned)size) {
        fclose(file);
        free(database);
        database = 0;
        return 0;
    }
    fclose(file);
    database[size] = 0;
    p = database;
    while (*p) {
        line = p;
        while (*p && *p != '\r' && *p != '\n') ++p;
        if (*p) {
            *p++ = 0;
            if (*p == '\n' || *p == '\r') *p++ = 0;
        }
        if (line[0] == '@' && line[1]) {
            if (topic_count >= MAX_TOPICS) return 0;
            current = &topics[topic_count++];
            current->name = line + 1;
            current->first = line_count;
            current->count = 0;
        } else if (current) {
            if (line_count >= MAX_LINES) return 0;
            lines[line_count++] = line;
            ++current->count;
        }
    }
    return topic_count != 0;
}

static int find_topic(const char *name)
{
    unsigned i;
    for (i = 0; i < topic_count; ++i)
        if (equal_ci(topics[i].name, name)) return i;
    return -1;
}

static int console_handles(void)
{
    union REGS inregs, outregs;
    inregs.x.ax = 0x4400;
    inregs.x.bx = 0;
    int86(0x21, &inregs, &outregs);
    if (outregs.x.cflag || (outregs.x.dx & 0x81) != 0x81) return 0;
    inregs.x.ax = 0x4400;
    inregs.x.bx = 1;
    int86(0x21, &inregs, &outregs);
    return !outregs.x.cflag && (outregs.x.dx & 0x82) == 0x82;
}

static void text_topic(unsigned index)
{
    unsigned i;
    Topic *topic = &topics[index];
    for (i = 0; i < topic->count; ++i) puts(lines[topic->first + i]);
}

static void fill_line(unsigned row, unsigned char attribute)
{
    unsigned i;
    gotoxy(1, row);
    textattr(attribute);
    for (i = 0; i < 80; ++i) putch(' ');
}

static void print_at(unsigned column, unsigned row, unsigned char attribute,
                     const char *text, unsigned width)
{
    unsigned i = 0;
    gotoxy(column, row);
    textattr(attribute);
    while (text[i] && i < width) putch(text[i++]);
    while (i++ < width) putch(' ');
}

static void frame(const char *title, const char *footer)
{
    fill_line(1, 0x1f);
    print_at(2, 1, 0x1f, "MS-DOS 6.22 Help", 22);
    print_at(27, 1, 0x1f, title, 51);
    fill_line(2, 0x70);
    print_at(2, 2, 0x70, "File  Search  Index  Back  Exit", 76);
    fill_line(24, 0x70);
    print_at(2, 24, 0x70, footer, 76);
    fill_line(25, 0x1f);
    print_at(2, 25, 0x1f,
             "Arrows/PgUp/PgDn move   Enter opens   F3 searches   Esc exits", 76);
    textattr(0x07);
}

static void save_screen(void)
{
    union REGS regs;
    unsigned short far *screen;
    unsigned i;
    memset(&regs, 0, sizeof(regs));
    regs.h.ah = 0x0f;
    int86(0x10, &regs, &regs);
    saved_mode = regs.h.al;
    saved_page = regs.h.bh;
    memset(&regs, 0, sizeof(regs));
    regs.h.ah = 3;
    regs.h.bh = saved_page;
    int86(0x10, &regs, &regs);
    saved_cursor_row = regs.h.dh;
    saved_cursor_column = regs.h.dl;
    screen = video_memory();
    for (i = 0; i < 2000; ++i) saved_screen[i] = screen[i];
    changed_mode = saved_mode != 2 && saved_mode != 3 && saved_mode != 7;
    if (changed_mode) {
        memset(&regs, 0, sizeof(regs));
        regs.x.ax = 3;
        int86(0x10, &regs, &regs);
    }
}

static void restore_screen(void)
{
    union REGS regs;
    unsigned short far *screen;
    unsigned i;
    if (changed_mode) {
        memset(&regs, 0, sizeof(regs));
        regs.h.ah = 0;
        regs.h.al = saved_mode;
        int86(0x10, &regs, &regs);
    }
    screen = video_memory();
    for (i = 0; i < 2000; ++i) screen[i] = saved_screen[i];
    memset(&regs, 0, sizeof(regs));
    regs.h.ah = 2;
    regs.h.bh = saved_page;
    regs.h.dh = saved_cursor_row;
    regs.h.dl = saved_cursor_column;
    int86(0x10, &regs, &regs);
}

static void initialize_mouse(void)
{
    union REGS regs;
    void interrupt far (*handler)(void) = _dos_getvect(0x33);
    mouse_available = 0;
    if (!handler || (!FP_SEG(handler) && !FP_OFF(handler))) return;
    memset(&regs, 0, sizeof(regs));
    int86(0x33, &regs, &regs);
    if (regs.x.ax != 0xffff) return;
    mouse_available = 1;
    regs.x.ax = 1;
    int86(0x33, &regs, &regs);
}

static int input_key(void)
{
    union REGS regs;
    for (;;) {
        if (kbhit()) {
            int key = getch();
            if (!key || key == 0xe0) return 0x100 | getch();
            return key;
        }
        if (mouse_available) {
            memset(&regs, 0, sizeof(regs));
            regs.x.ax = 3;
            int86(0x33, &regs, &regs);
            if (!(regs.x.bx & 1)) mouse_latched = 0;
            else if (!mouse_latched) {
                mouse_latched = 1;
                mouse_column = regs.x.cx / 8U + 1;
                mouse_row = regs.x.dx / 8U + 1;
                return MOUSE_KEY;
            }
        }
        memset(&regs, 0, sizeof(regs));
        int86(0x28, &regs, &regs);
    }
}

static void rebuild_matches(void)
{
    unsigned i, j, value;
    match_count = 0;
    for (i = 1; i < topic_count; ++i) {
        int matched = contains_ci(topics[i].name, search_text);
        for (j = 0; !matched && j < topics[i].count; ++j)
            matched = contains_ci(lines[topics[i].first + j], search_text);
        if (matched) matches[match_count++] = i;
    }
    for (i = 1; i < match_count; ++i) {
        value = matches[i];
        j = i;
        while (j && compare_ci(topics[matches[j - 1]].name,
                               topics[value].name) > 0) {
            matches[j] = matches[j - 1];
            --j;
        }
        matches[j] = value;
    }
}

static void prompt_search(void)
{
    unsigned length = 0;
    int key;
    search_text[0] = 0;
    fill_line(24, 0x70);
    print_at(2, 24, 0x70, "Search for: ", 12);
    for (;;) {
        gotoxy(14 + length, 24);
        key = getch();
        if (key == 13) break;
        if (key == 27) { search_text[0] = 0; break; }
        if (key == 8 && length) {
            search_text[--length] = 0;
            putch('\b'); putch(' '); putch('\b');
        } else if (key >= 32 && key < 127 && length < sizeof(search_text)-1) {
            search_text[length++] = key;
            search_text[length] = 0;
            putch(key);
        }
    }
    rebuild_matches();
}

static int index_browser(void)
{
    unsigned selected = 0, page, i, slot, row, column;
    int key;
    if (!match_count) rebuild_matches();
    for (;;) {
        if (selected >= match_count && match_count) selected = match_count - 1;
        page = (selected / (PAGE_ROWS * 2)) * (PAGE_ROWS * 2);
        frame(search_text[0] ? "Search results" : "Command index",
              mouse_available ? "Mouse: click a topic to open it" :
                                "Mouse driver not installed; use the keyboard");
        for (slot = 0; slot < PAGE_ROWS * 2; ++slot) {
            i = page + slot;
            row = 4 + slot % PAGE_ROWS;
            column = slot < PAGE_ROWS ? 3 : 42;
            if (i < match_count)
                print_at(column, row, i == selected ? 0x1f : 0x07,
                         topics[matches[i]].name, 34);
            else
                print_at(column, row, 0x07, "", 34);
        }
        if (!match_count) print_at(3, 4, 0x0c, "No matching topics.", 70);
        key = input_key();
        if (key == 27) return -1;
        if (key == 0x13d || key == '/') { prompt_search(); selected = 0; continue; }
        if (key == 0x147) selected = 0;
        else if (key == 0x14f && match_count) selected = match_count - 1;
        else if (key == 0x148 && selected) --selected;
        else if (key == 0x150 && selected + 1 < match_count) ++selected;
        else if (key == 0x149) selected = selected > PAGE_ROWS ? selected - PAGE_ROWS : 0;
        else if (key == 0x151 && selected + PAGE_ROWS < match_count) selected += PAGE_ROWS;
        else if (key == MOUSE_KEY && mouse_row >= 4 && mouse_row < 4 + PAGE_ROWS) {
            i = page + mouse_row - 4;
            if (mouse_column >= 40) i += PAGE_ROWS;
            if (i < match_count) return matches[i];
        } else if (key == 13 && match_count) return matches[selected];
    }
}

static int bracket_link(const char *line, unsigned column, char *name)
{
    unsigned start, end, length;
    for (start = 0; line[start]; ++start) {
        if (line[start] != '[') continue;
        for (end = start + 1; line[end] && line[end] != ']'; ++end) ;
        if (line[end] != ']') return -1;
        if (!column || (column > start && column <= end + 1)) {
            length = end - start - 1;
            if (length > 15) length = 15;
            memcpy(name, line + start + 1, length);
            name[length] = 0;
            return find_topic(name);
        }
        start = end;
    }
    return -1;
}

static int topic_browser(unsigned index)
{
    unsigned top = 0, i;
    int key, linked;
    char link[16];
    Topic *topic;
    for (;;) {
        topic = &topics[index];
        if (top >= topic->count) top = topic->count ? topic->count - 1 : 0;
        frame(topic->name, "Esc returns to the index; bracketed topics are links");
        for (i = 0; i < PAGE_ROWS; ++i)
            print_at(3, 4 + i, 0x07,
                     top + i < topic->count ? lines[topic->first + top + i] : "", 75);
        key = input_key();
        if (key == 27 || key == 0x13b) return -1;
        if (key == 0x13d || key == '/') { prompt_search(); return -1; }
        if (key == 0x148 && top) --top;
        else if (key == 0x150 && top + PAGE_ROWS < topic->count) ++top;
        else if (key == 0x149) top = top > PAGE_ROWS ? top - PAGE_ROWS : 0;
        else if (key == 0x151 && top + PAGE_ROWS < topic->count) top += PAGE_ROWS;
        else if (key == 0x147) top = 0;
        else if (key == MOUSE_KEY && mouse_row >= 4 && mouse_row < 4 + PAGE_ROWS &&
                 top + mouse_row - 4 < topic->count) {
            linked = bracket_link(lines[topic->first + top + mouse_row - 4],
                                  mouse_column > 3 ? mouse_column - 3 : 1, link);
            if (linked >= 0) { index = linked; top = 0; }
        } else if (key == 9 || key == 13) {
            for (i = top; i < topic->count && i < top + PAGE_ROWS; ++i) {
                linked = bracket_link(lines[topic->first + i], 0, link);
                if (linked >= 0 && (unsigned)linked != index) {
                    index = linked; top = 0; break;
                }
            }
        }
    }
}

static void interactive(void)
{
    int topic;
    union REGS regs;
    search_text[0] = 0;
    rebuild_matches();
    save_screen();
    initialize_mouse();
    while ((topic = index_browser()) >= 0) topic_browser(topic);
    if (mouse_available) {
        memset(&regs, 0, sizeof(regs));
        regs.x.ax = 2;
        int86(0x33, &regs, &regs);
    }
    textattr(0x07);
    restore_screen();
}

int main(int argc, char **argv)
{
    int topic;
    if (argc > 2 || (argc == 2 && !strcmp(argv[1], "/?"))) {
        usage();
        return argc > 2 ? 1 : 0;
    }
    if (!load_database()) {
        fputs("HELP.HLP was not found or is invalid.\n", stderr);
        return 1;
    }
    if (argc == 2) {
        topic = find_topic(argv[1]);
        if (topic < 0) {
            fputs("No help is available for that command.\n", stderr);
            return 1;
        }
        text_topic(topic);
        return 0;
    }
    if (!console_handles()) {
        topic = find_topic("INDEX");
        if (topic >= 0) text_topic(topic);
        return topic < 0;
    }
    interactive();
    return 0;
}
