/* Open Watcom compatibility calls used by the cdecl assembly helpers. */

unsigned fc_strlen(s)
char *s;
{
    char *start = s;

    while (*s)
        s++;
    return s - start;
}
