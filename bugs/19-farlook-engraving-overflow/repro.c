/*
 * repro.c -- bug 19: farlook writes one byte past temp_buf for a long
 * remembered engraving.
 *
 * This copies the string handling of NetHack 5.0.0's src/pager.c
 * (16ff59115) for the farlook of an engraving:
 *
 *   do_screen_description()  pager.c:1611-1613
 *       Sprintf(temp_buf, " (%s", *firstmatch);
 *       (void) add_quoted_engraving(cc.x, cc.y, temp_buf, FALSE);
 *       Strcat(temp_buf, ")");
 *
 *   add_quoted_engraving()   pager.c:1657-1665
 *       Snprintf(temp_buf, sizeof temp_buf, " with %s: \"%s\"",
 *                "remembered text", ep->engr_txt[remembered_text]);
 *       (void) strncat(buf, temp_buf, BUFSZ - strlen(buf) - 1);
 *
 * The caller's temp_buf is BUFSZ bytes.  Here it is the first BUFSZ bytes
 * of a larger allocation, so a write to byte BUFSZ lands in memory we own
 * and can check, instead of in whatever the compiler put next on the stack.
 *
 * For every engraving length it reports whether byte BUFSZ was written,
 * for the upstream code and for proposed-fix.patch.  Exit 0 if the upstream
 * code overflows for some length (bug present), 1 if not.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define BUFSZ 256                     /* include/global.h */
#define GUARD 0x5a

/* add_quoted_engraving(), text part only (ep->eread is set) */
static void
add_quoted_engraving(char *buf, const char *what, const char *text)
{
    char temp_buf[BUFSZ];

    snprintf(temp_buf, sizeof temp_buf, " with %s: \"%s\"", what, text);
    (void) strncat(buf, temp_buf, BUFSZ - strlen(buf) - 1);
}

/* returns 1 if byte BUFSZ of the caller's temp_buf was written */
static int
farlook(const char *firstmatch, const char *what, const char *text,
        int fixed, size_t *outlen)
{
    unsigned char *mem = malloc(BUFSZ + 8);
    char *temp_buf = (char *) mem;    /* char temp_buf[BUFSZ]; */
    int hit;

    memset(mem, GUARD, BUFSZ + 8);
    sprintf(temp_buf, " (%s", firstmatch);
    add_quoted_engraving(temp_buf, what, text);
    if (fixed) /* proposed-fix.patch */
        temp_buf[BUFSZ - 2] = '\0';
    strcat(temp_buf, ")");
    hit = (mem[BUFSZ] != GUARD);
    *outlen = strlen(temp_buf);
    free(mem);
    return hit;
}

int
main(void)
{
    static const struct {
        const char *firstmatch, *what;
    } kinds[] = {
        { "engraving", "remembered text" },  /* floor engraving */
        { "grave", "headstone reading" },    /* headstone */
    };
    char text[BUFSZ];
    int k, n, first_bad[2] = { -1, -1 }, fixed_bad = 0;

    for (k = 0; k < 2; k++) {
        for (n = 0; n < BUFSZ; n++) {
            size_t len, flen;
            int bad, fbad;

            memset(text, 'x', n);
            text[n] = '\0';
            bad = farlook(kinds[k].firstmatch, kinds[k].what, text, 0, &len);
            fbad = farlook(kinds[k].firstmatch, kinds[k].what, text, 1, &flen);
            if (bad && first_bad[k] < 0) {
                first_bad[k] = n;
                printf("%-9s text %3d chars: upstream strlen(temp_buf)=%zu,"
                       " NUL written at temp_buf[%d]  <-- one past the end\n",
                       kinds[k].firstmatch, n, len, BUFSZ);
                printf("%-9s text %3d chars: patched  strlen(temp_buf)=%zu,"
                       " in bounds\n", kinds[k].firstmatch, n, flen);
            }
            if (fbad)
                fixed_bad++;
        }
        if (first_bad[k] < 0)
            printf("%-9s: no overflow for any length\n", kinds[k].firstmatch);
        else
            printf("%-9s: upstream overflows for every text of %d chars"
                   " or more\n\n", kinds[k].firstmatch, first_bad[k]);
    }
    printf("patched: %s\n", fixed_bad ? "OVERFLOWS (unexpected)"
                                      : "no overflow for any length");

    if (first_bad[0] >= 0 || first_bad[1] >= 0) {
        printf("\nBUG CONFIRMED -- Strcat(temp_buf, \")\") writes its NUL"
               " one byte past temp_buf.\n");
        return 0;
    }
    printf("\nBUG NOT REPRODUCED\n");
    return 1;
}
