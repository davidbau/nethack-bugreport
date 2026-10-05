#!/bin/bash
# repro.sh -- bug 34: match_sym() resolves S_lava, S_ant, S_human and
# S_mimic to S_lavawall, S_anti_magic_trap, S_HUMANOID and S_MIMIC_DEF.
#
# Builds a clean NetHack-5.0 checkout (the upstream head, or the source tree
# given as $1) with the stock Linux hints, then links a small harness,
# symtest, against the game's object files (unixmain.o with its main()
# renamed).  symtest
#   1. looks up every name in loadsyms[] with match_sym(), as parsesymbols()
#      does for a SYMBOLS= line, and lists the names that find another name;
#   2. passes every S_ line of dat/symbols to match_sym(), as parse_sym_line()
#      does when a symset is loaded, and lists the lines that set a symbol
#      whose name only begins with the name on the line.  Sets with
#      "Handling: UTF8" are skipped; their S_ lines do not use match_sym().
#
#   bash repro.sh                 # clone and build the upstream head
#   bash repro.sh ~/src/NetHack   # build an existing checkout instead
#
# Exit 0 = bug seen, 1 = not seen, 2 = build failed.
set -e
WORK=$(mktemp -d -t bugrep34_XXXX)
trap 'rm -rf "$WORK"' EXIT

if [ -n "$1" ]; then
    SRC=$(cd "$1" && pwd)
    echo "=== Copying $SRC ($(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo '?'))"
    cp -r "$SRC" "$WORK/NetHack"
else
    echo "=== Cloning the NetHack-5.0 head"
    git clone -q --depth 1 -b NetHack-5.0 https://github.com/NetHack/NetHack.git "$WORK/NetHack"
fi
cd "$WORK/NetHack"
echo "    at $(git rev-parse --short HEAD 2>/dev/null): $(git log -1 --format='%cd %s' --date=short 2>/dev/null)"

echo "=== Building (sys/unix/hints/linux.501)"
( cd sys/unix && sh setup.sh hints/linux.501 >/dev/null )
make fetch-lua >/dev/null 2>&1 || true
if ! make PREFIX="$WORK/inst" -j4 >"$WORK/build.log" 2>&1; then
    tail -20 "$WORK/build.log"; exit 2
fi

cat >"$WORK/symtest.c" <<'CEOF'
/* symtest.c -- look up every name in loadsyms[] with match_sym(), as
   parsesymbols() does for SYMBOLS= lines, and list the names that find
   a different name; then pass every S_ line of dat/symbols to
   match_sym(), as parse_sym_line() does, and list the lines that resolve
   to a longer name that merely begins with the name on the line.
   Sets with "Handling: UTF8" are skipped: their S_ lines are applied
   through glyphrep_to_custom_map_entries(), not through match_sym(). */
#include "hack.h"

extern const struct symparse loadsyms[];

int
main(int argc, char **argv)
{
    char line[BUFSZ], set[BUFSZ] = "", nm[BUFSZ];
    FILE *fp;
    int bad = 0, bad2 = 0, n = 0, utf8 = 0, i;

    for (i = 0; loadsyms[i].range; ++i) {
        const struct symparse *sp;

        Strcpy(nm, loadsyms[i].name);
        sp = match_sym(nm);
        if (!sp || strcmpi(sp->name, loadsyms[i].name)) {
            ++bad;
            printf("  %-34s -> %s\n", loadsyms[i].name,
                   sp ? sp->name : "(none)");
        }
    }
    printf("%d of %d symbol names look up a different symbol\n", bad, i);
    if (argc < 2 || !(fp = fopen(argv[1], "r")))
        return 3;
    while (fgets(line, sizeof line, fp)) {
        char *p = line;
        const struct symparse *sp;
        size_t len;

        while (*p == ' ' || *p == '\t')
            ++p;
        p[strcspn(p, "\n")] = '\0';
        if (!strncmp(p, "start:", 6)) {
            (void) sscanf(p + 6, " %s", set);
            utf8 = 0;
            continue;
        }
        if (!strncmpi(p, "handling:", 9) && strstri(p, "UTF8"))
            utf8 = 1;
        if (utf8 || strncmp(p, "S_", 2))
            continue;
        len = strcspn(p, ":=");
        Snprintf(nm, sizeof nm, "%.*s", (int) len, p);
        ++n;
        sp = match_sym(p);
        if (sp && strcmpi(sp->name, nm) && !strncmpi(sp->name, nm, len)) {
            ++bad2;
            p[strcspn(p, "\t#")] = '\0';
            printf("  %-12s %-34s -> sets %s\n", set, p, sp->name);
        }
    }
    printf("%d of %d S_ lines in dat/symbols set a different symbol\n",
           bad2, n);
    return (bad || bad2) ? 0 : 1;
}
CEOF

echo "=== Linking symtest against the game objects"
cd src
# compile with the flags used for symbols.o, link with the line used for nethack
CC_LINE=$(make -s -n -W symbols.c symbols.o 2>/dev/null | grep -- '-o symbols.o')
LD_LINE=$(make -s -n -W Makefile Sysunix 2>/dev/null | sed -n '/-o nethack/,$p' \
          | grep -v '^touch\|^echo\|^true' | tr -d '\\\n')
objcopy --redefine-sym main=nh_unix_main unixmain.o unixmain_nm.o
if ! eval "${CC_LINE/-o symbols.o symbols.c/-o symtest.o $WORK/symtest.c}" \
   || ! eval "$(echo "$LD_LINE" | sed 's/-o nethack/-o symtest/; s/unixmain\.o/unixmain_nm.o symtest.o/')"; then
    exit 2
fi

echo "=== Running symtest"
set +e
./symtest ../dat/symbols
rc=$?
case $rc in
0) echo "=== BUG SEEN: match_sym() resolved a name to a longer name that begins with it" ;;
1) echo "=== not seen: every name resolved to itself" ;;
*) echo "=== symtest failed ($rc)"; exit 2 ;;
esac
exit $rc
