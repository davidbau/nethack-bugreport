#!/usr/bin/env python3
"""Build index.html for the bug 10 proof explainer.

Reads NetHack source at the proof's pinned commit, annotates the excerpts
that the explainer shows, and inlines them (plus model.js and the proof's
model sources) into template.html.

Usage:
    python3 build.py [--nethack-repo PATH]

NetHack source comes from nethack-c/upstream when that submodule is checked
out at the pin, or else from `git show PIN:path` in --nethack-repo (any
clone of NetHack/NetHack that contains the pinned commit).
"""
import argparse, json, os, subprocess, sys

PIN = '16ff59115315917b93185d026aeefea06db9b0f4'
HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, '..') + '/'
REPO = os.path.abspath(os.path.join(HERE, '../../../..'))
UPSTREAM = os.path.join(REPO, 'nethack-c/upstream')

ap = argparse.ArgumentParser()
ap.add_argument('--nethack-repo', help='NetHack clone containing the pinned commit')
args = ap.parse_args()

def upstream_at_pin():
    if not os.path.exists(os.path.join(UPSTREAM, 'src/polyself.c')):
        return False
    head = subprocess.run(['git', '-C', UPSTREAM, 'rev-parse', 'HEAD'],
                          capture_output=True, text=True).stdout.strip()
    return head == PIN

_cache = {}
def read_src(rel):
    if rel not in _cache:
        if upstream_at_pin():
            _cache[rel] = open(os.path.join(UPSTREAM, rel)).read()
        elif args.nethack_repo:
            _cache[rel] = subprocess.run(['git', '-C', args.nethack_repo, 'show', f'{PIN}:{rel}'],
                                         capture_output=True, text=True, check=True).stdout
        else:
            sys.exit('nethack-c/upstream is not checked out at the pin; pass --nethack-repo')
    return _cache[rel]

def lines(f): return read_src('src/' + f).split('\n')
G='if (uasmon_generation != my_generation)'
def find(L, start, end, text, nth=1):
    for i in range(start-1, end):
        if text in L[i]:
            nth-=1
            if nth==0: return i+1
    raise SystemExit('not found: '+text)
def excerpt(f, start, end, ann):
    L=lines(f)
    rows=[]
    for n in range(start, end+1):
        rows.append({'n':n,'t':L[n-1]})
    out={'file':'src/'+f,'start':start,'end':end,'rows':rows,'ann':{}}
    for a in ann:
        n=find(L,start,end,a['match'],a.get('nth',1))
        a=dict(a); del a['match']; a.pop('nth',None)
        out['ann'].setdefault(str(n),[]).append(a)
    return out
GUARD=lambda ret: [f'    {G}', f'        return{ret};']
files={}
files['polymon']=excerpt('polyself.c',735,1075,[
 {'match':'polymon(int mntmp)','tag':'entry','note':'polymon(mntmp) installs form mntmp and then applies its consequences. In the model this is verify_polymon_guards(), with mntmp as FORM_TARGET (y).'},
 {'match':'Strcpy(buf, (u.umonnum != mntmp) ? "" : "new ");','tag':'aba','note':'Polymorphing into the form you already have is allowed ("You feel like a new yellow light!"). u.umonnum ends up unchanged, which is the A→A case an identity guard cannot see.'},
 {'match':'u.umonnum = mntmp;','tag':'install','note':'The form installation. The patch records the old light state first, then updates the light immediately after set_uasmon(). set_uasmon() itself bumps the generation counter (see its excerpt under the light-ownership bug), and polymon() saves the value it just installed as my_generation. Model: install_form(FORM_TARGET).',
   'before':['    old_light = emits_light(gy.youmonst.data);'],
   'after_line':'set_uasmon();','after':['    uasmon_light(old_light);','    my_generation = uasmon_generation;']},
 {'match':'drop_weapon(1);','tag':'B0','note':'Boundary B0, POLY_BREAK_ARMOR. break_armor() and drop_weapon() can drop an artifact whose invoked levitation is holding you up. You fall into water or lava, the damage reverts you with rehumanize(), or a polymorph trap re-polymorphs you.','after':GUARD(' 1')},
 {'match':'expels(u.ustuck, u.ustuck->data, expels_mesg);','tag':'B1','note':'Boundary B1, POLY_EXPELS. expels() ends in spoteffects(), which can land you on a trap or in lava.'},
 {'match':'/* FIXME? if expels() triggered rehumanize then we should','tag':'fixme','note':'The DevTeam already knew about this boundary. The patch replaces this FIXME with the guard below.','remove':2,'after_n':1,'after':GUARD(' 1')},
 {'match':'instapetrify(buf);','tag':'B2','note':'Boundary B2, POLY_DISMOUNT. instapetrify() can call polymon() directly (stone golem), and dismount_steed() → teleds() → spoteffects().'},
 {'match':'find_ac();','nth':2,'tag':'B2g','note':'Guard for B2, placed after the whole steed block.','before':GUARD(' 1')},
 {'match':'spoteffects(TRUE);','tag':'B3','note':'Boundary B3, POLY_SPOTEFFECTS. Landing in water or lava while polymorphed damages u.mh; at zero you are reverted.'},
 {'match':'/* FIXME? if spoteffects() triggered rehumanize then we should','tag':'fixme','note':'The second DevTeam FIXME, replaced by the guard.','remove':2,'after_n':1,'after':GUARD(' 1')},
 {'match':'encumber_msg();','tag':'cleanup','note':'End-of-form-change cleanup. rehumanize() runs its own encumber_msg() and retouch_equipment() (polyself.c:1410-1415) after polyman() reinstalls the base form. When a nested revert has already done this, running it again here is bug 06. Model: cleanup_current_form(), which asserts it runs at most once per generation.'},
 {'match':'retouch_equipment(2);','tag':'B4','note':'Boundary B4, POLY_RETOUCH. A cross-aligned artifact blasts you, and the damage can revert a frail form. Stone-to-flesh can also polymon() recursively.'},
 {'match':'if (!uarmg)','tag':'B4g','note':'Guard for B4. selftouch() below is left unguarded; the model checks only that the light stays consistent after it.','before':GUARD(' 1')},
 {'match':'return 1;','nth':1,'tag':'end','note':'Normal completion.'},
])
files['break_armor']=excerpt('polyself.c',1157,1300,[
 {'match':'break_armor(void)','tag':'entry','note':'break_armor() decides what to strip by asking the form it cached at entry. Model: verify_break_armor_guards().'},
 {'match':'struct permonst *uptr = gy.youmonst.data;','tag':'install','note':'uptr is cached once. Every test below (nohands(uptr), slithy(uptr), has_head(uptr)) asks about this form, even after a nested change replaces it. The generation patch saves my_generation here too.','after':['    unsigned long my_generation = uasmon_generation;']},
 {'match':'drop_weapon(0);','tag':'B5','note':'Boundary B5, ARMOR_AFTER_GLOVES. Dropping the weapon can release an #invoked levitation artifact. float_down() then puts you in lava, the damage kills the newt form, and rehumanize() makes you human.'},
 {'match':'if ((otmp = uarms) != 0) {','tag':'B5g','note':'Guard for B5, at the end of the gloves sub-block so no item is left half-removed.','before':GUARD('')},
 {'match':'if (nohands(uptr) || verysmall(uptr)','nth':2,'tag':'B6','note':'Boundary B6, ARMOR_BEFORE_BOOTS. Without a guard here, bug 08 continues: a human standing in lava has their water walking boots removed because a newt could not wear them.','before':GUARD('')},
 {'match':'(void) Boots_off();','tag':'reent','note':'Boots_off() → spoteffects() is another re-entrant call (water walking ends while you are over water or lava).'},
 {'match':'if ((otmp = ublindf) != 0 && !has_head(uptr)) {','tag':'B7','note':'Boundary B7, ARMOR_BEFORE_EYEWEAR. The guard stops here if the boots block changed the form.','before':GUARD('')},
])
L=lines('polyself.c')
files['light']={'parts':[
 excerpt('polyself.c',118,127,[
  {'match':'/* we can reset this now, having just done what it is meant to trigger */','tag':'install','note':'The end of set_uasmon(). The generation patch bumps the counter here, inside the one function every form installation calls, so each installation (a same-form one included) gets a new generation. note_uasmon_install() panics rather than let the counter wrap back to an old value.','before':['    note_uasmon_install();']},
 ]),
 excerpt('polyself.c',688,731,[
  {'match':'(void) polymon(mntmp);','nth':1,'tag':'reent','note':'polymon() returns here. Any nested revert inside it has already happened.'},
  {'match':' made_change:','tag':'removed','note':'Before the patch, polyself() created the hero light source only here, after polymon() had returned. A rehumanize() nested inside polymon() therefore ran before any light source existed and tried to delete it: bug 07. The patch removes this block and calls uasmon_light() immediately after each set_uasmon().','remove':11},
 ]),
 excerpt('polyself.c',574,584,[
  {'match':'old_light = 0; /* rehumanize() extinguishes u-as-mon light */','tag':'removed','note':'A hand-written workaround for one case of the same ownership problem. The patch removes it.','remove':2,'after':['                return;']},
 ]),
 excerpt('polyself.c',1386,1395,[
  {'match':'if (emits_light(gy.youmonst.data))','tag':'removed','note':'rehumanize() deletes the glowing form\'s light source. Called from inside polymon() (before made_change: has run), it deletes a source that was never created: del_light_source: not found, then "Program in disorder!".','remove':2},
 ]),
 excerpt('polyself.c',200,216,[
  {'match':'set_uasmon();','tag':'install','note':'polyman(), the path back to human form. It now does its own light bookkeeping right after installing the form; set_uasmon() has already bumped the generation.','after':['    uasmon_light(old_light);']},
 ]),
 excerpt('timeout.c',480,495,[
  {'match':'del_light_source(LS_MONSTER','tag':'removed','note':'Another manual workaround, now redundant because polymon() does the light bookkeeping itself.','remove':1,'back':1},
 ]),
]}
files['aba']={'parts':[
 excerpt('artifact.c',2205,2216,[{'match':'float_down(I_SPECIAL | TIMEOUT, W_ARTI);','tag':'B5','note':'Step 1: invoked levitation ends when the artifact leaves your inventory (for example, dropped by break_armor()).'}]),
 excerpt('trap.c',4160,4172,[{'match':'dotrap(trap, NO_TRAP_FLAGS);','tag':'reent','note':'Step 2: float_down() triggers the trap you land on.'}]),
 excerpt('trap.c',2485,2497,[{'match':'polyself(POLY_NOFLAGS);','tag':'reent','note':'Step 3: a polymorph trap calls polyself(). With polymorph control you can choose the form you already have.'}]),
 excerpt('polyself.c',796,816,[
  {'match':'Strcpy(buf, (u.umonnum != mntmp) ? "" : "new ");','tag':'aba','note':'Step 4: the same-form polymorph is accepted ("You feel like a new …").'},
  {'match':'u.umonnum = mntmp;','tag':'install','note':'Step 5: the form is installed again. u.umonnum is the same number as before, but this is a new installation with its own cleanup. An outer polymon() that compares u.umonnum != mntmp sees no change.'},
 ]),
]}
models={'cbmc':open(P+'polyself_model.c').read(),'acsl':open(P+'polyself_acsl.c').read(),'runcbmc':open(P+'run-cbmc.sh').read()}

def inline(obj):
    return json.dumps(obj).replace('</', '<\\/')

page = open(os.path.join(HERE, 'template.html')).read()
page = page.replace('/*__MODEL_JS__*/', open(os.path.join(HERE, 'model.js')).read())
page = page.replace('/*__SRC_DATA__*/', inline(files))
page = page.replace('/*__MODEL_SRC__*/', inline(models))
# template.html is an Artifact body (no doctype/head); wrap it so the built
# file also works as a standalone page, e.g. on GitHub Pages.
doc = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
       '<meta name="viewport" content="width=device-width, initial-scale=1">\n</head>\n'
       '<body style="margin:0">\n' + page + '\n</body>\n</html>\n')
open(os.path.join(HERE, 'index.html'), 'w').write(doc)
print('wrote index.html,', len(doc), 'bytes;',
      {k: (len(v['rows']) if 'rows' in v else len(v['parts'])) for k, v in files.items()})
