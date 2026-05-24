// viewer.mjs — minimal session replay UI for nethack-bugreport.
//
// Loads a recorded NetHack session (clean v5 format) and renders each
// step's TTY screen as a 24x80 colored grid, with a scrubber to step
// through keystrokes. Metadata (seed, datetime, .nethackrc, full move
// stream) is shown alongside.
//
// URL state:
//   ?session=PATH   — fetch this session.json on load
//   #step=N         — start at step N (default: first step with a key)
//
// No build, no server, no JS port required.

import { decodeScreen, renderCell, colorToCss, ROWS_24, COLS_80 } from './screen-decode.mjs';

const $ = (sel) => document.querySelector(sel);

function setStatus(msg, cls = '') {
    const el = $('#status');
    el.textContent = msg;
    el.className = cls;
    el.style.display = msg ? '' : 'none';
}

// --- URL state ------------------------------------------------------------
function getQuery() {
    return new URLSearchParams(location.search);
}
function readHash() {
    const out = {};
    const h = (location.hash || '').replace(/^#/, '');
    if (!h) return out;
    for (const part of h.split('&')) {
        const eq = part.indexOf('=');
        if (eq < 0) continue;
        out[decodeURIComponent(part.slice(0, eq))] = decodeURIComponent(part.slice(eq + 1));
    }
    return out;
}
function writeHash(state) {
    const parts = [];
    if (typeof state.step === 'number') parts.push(`step=${state.step}`);
    const next = parts.length ? '#' + parts.join('&') : ' ';
    if (next !== location.hash) history.replaceState(null, '', next);
}

// --- Session loading ------------------------------------------------------
let SESSION = null;
let SEGMENT = null;
let STEPS = [];

// GitHub repo this viewer is published from. Used to turn the relative
// session path into a clickable "view on GitHub" link in the metadata
// panel. If you fork the viewer, update these two constants.
const GITHUB_REPO = 'davidbau/nethack-bugreport';
const GITHUB_BRANCH = 'main';

// Sessions are addressed as repo-relative paths in the `?session=` URL
// (e.g. `?session=bugs/01-foo/session.json`). The viewer lives two
// directories deep (`/tools/session-viewer/`), so we resolve the session
// path against the repo root, not the viewer's directory. Absolute paths
// (`/...` or `http(s)://...`) pass through unchanged.
function repoRoot() {
    return new URL('../../', document.baseURI);
}
async function fetchSession(path) {
    setStatus(`Loading ${path}…`);
    try {
        const url = new URL(path, repoRoot());
        const res = await fetch(url, { cache: 'no-cache' });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        loadSession(data, path, /*fromUrl=*/true);
    } catch (e) {
        setStatus(`Failed to load ${path}: ${e.message}`, 'error');
    }
}

function loadSession(data, sourcePath = '(file)', fromUrl = false) {
    SESSION = data;
    SEGMENT = (data.segments && data.segments[0]) || data;
    STEPS = SEGMENT.steps || [];
    renderMeta(sourcePath, fromUrl);
    setupScrubber();
    const hashStep = parseInt(readHash().step, 10);
    const initial = Number.isFinite(hashStep) && hashStep >= 0 && hashStep < STEPS.length
        ? hashStep
        : firstInterestingStep();
    showStep(initial);
    setStatus('');
}

function firstInterestingStep() {
    for (let i = 0; i < STEPS.length; i++) {
        if (STEPS[i].key != null) return i;
    }
    return 0;
}

// --- Metadata panel -------------------------------------------------------
function sessionGithubUrl(path) {
    // The session was loaded via `?session=...`, so `path` is the same
    // relative URL the browser used to fetch it. The repo root is the
    // GH Pages root, so the GitHub blob URL is just the same path
    // (leading slash stripped) under /blob/<branch>/.
    const clean = String(path || '').replace(/^\/+/, '');
    if (!clean) return null;
    return `https://github.com/${GITHUB_REPO}/blob/${GITHUB_BRANCH}/${clean}`;
}

function renderMeta(sourcePath, fromUrl) {
    const dl = $('#meta-list');
    dl.innerHTML = '';
    const ghUrl = fromUrl ? sessionGithubUrl(sourcePath) : null;
    const rows = [
        ['source', ghUrl
            ? { href: ghUrl, text: sourcePath }
            : sourcePath],
        ['seed', String(SEGMENT.seed ?? '—')],
        ['datetime', String(SEGMENT.datetime ?? '—')],
        ['version', String(SESSION.version ?? '—')],
        ['recorded source', String(SESSION.source ?? '—')],
        ['recorded with',
            SESSION.recorded_with
                ? `teleport ${SESSION.recorded_with.teleport ?? '?'} · nethack ${SESSION.recorded_with.nethack_c ?? '?'}`
                : '—'],
        ['total steps', String(STEPS.length)],
        ['moves length', String((SEGMENT.moves || '').length)],
    ];
    for (const [k, v] of rows) {
        const dt = document.createElement('dt'); dt.textContent = k;
        const dd = document.createElement('dd');
        if (v && typeof v === 'object' && v.href) {
            const a = document.createElement('a');
            a.href = v.href;
            a.target = '_blank';
            a.rel = 'noopener';
            a.textContent = v.text;
            dd.appendChild(a);
        } else {
            dd.textContent = v;
        }
        dl.appendChild(dt); dl.appendChild(dd);
    }
    $('#rc-content').textContent = SEGMENT.nethackrc || '(none)';
    $('#moves-content').textContent = SEGMENT.moves || '(none)';
    wireCopyButton('#rc-copy', () => SEGMENT.nethackrc || '');
    wireCopyButton('#moves-copy', () => SEGMENT.moves || '');
}

function wireCopyButton(sel, getter) {
    const btn = $(sel);
    if (!btn) return;
    btn.onclick = async (e) => {
        // Don't toggle the surrounding <details> when clicking copy.
        e.preventDefault();
        e.stopPropagation();
        const text = getter();
        try {
            await navigator.clipboard.writeText(text);
            const orig = btn.textContent;
            btn.textContent = 'copied';
            btn.classList.add('copied');
            setTimeout(() => {
                btn.textContent = orig;
                btn.classList.remove('copied');
            }, 1200);
        } catch (err) {
            btn.textContent = 'copy failed';
            setTimeout(() => { btn.textContent = 'copy'; }, 1500);
        }
    };
}

// --- Scrubber + navigation ------------------------------------------------
let CURRENT_STEP = 0;

function setupScrubber() {
    const sc = $('#scrubber');
    sc.min = 0;
    sc.max = Math.max(0, STEPS.length - 1);
    sc.value = 0;
    sc.oninput = () => showStep(parseInt(sc.value, 10));
    $('#prev-btn').onclick = () => showStep(CURRENT_STEP - 1);
    $('#next-btn').onclick = () => showStep(CURRENT_STEP + 1);
    document.addEventListener('keydown', (e) => {
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
        if (e.key === 'ArrowLeft') { showStep(CURRENT_STEP - 1); e.preventDefault(); }
        else if (e.key === 'ArrowRight') { showStep(CURRENT_STEP + 1); e.preventDefault(); }
        else if (e.key === 'Home') { showStep(0); e.preventDefault(); }
        else if (e.key === 'End') { showStep(STEPS.length - 1); e.preventDefault(); }
        else if (e.key === 'PageDown') { showStep(CURRENT_STEP + 10); e.preventDefault(); }
        else if (e.key === 'PageUp') { showStep(CURRENT_STEP - 10); e.preventDefault(); }
    });
}

function showStep(n) {
    if (!STEPS.length) return;
    n = Math.max(0, Math.min(STEPS.length - 1, n));
    CURRENT_STEP = n;
    $('#scrubber').value = n;
    $('#step-label').textContent = `step ${n} / ${STEPS.length - 1}`;
    renderStep(STEPS[n], n);
    writeHash({ step: n });
}

// --- Key + screen rendering -----------------------------------------------
function escapeKey(k) {
    if (k == null) return '∅';
    if (k === ' ') return '␠';
    if (k === '\n' || k === '\r') return '↵';
    if (k === '\x1b') return 'ESC';
    if (k === '\t') return '⇥';
    const code = k.charCodeAt(0);
    if (code < 32) return `^${String.fromCharCode(64 + code)}`;
    return k;
}

function renderStep(step, n) {
    $('#current-key').textContent = escapeKey(step.key);

    // Show ~12 prior + ~12 upcoming non-null keystrokes around the
    // current step, so the reader can see both how we got here and
    // what's about to be fed into the next frame.
    const past = [];
    for (let i = n - 1; i >= 0 && past.length < 12; i--) {
        const k = STEPS[i].key;
        if (k != null) past.unshift(escapeKey(k));
    }
    const next = [];
    for (let i = n + 1; i < STEPS.length && next.length < 12; i++) {
        const k = STEPS[i].key;
        if (k != null) next.push(escapeKey(k));
    }
    $('#key-past').textContent = past.length ? `… ${past.join(' ')} →` : '';
    $('#key-context').textContent = next.length ? `→ ${next.join(' ')} …` : '';

    renderScreen(step.screen || '', step.cursor);

    if (step.cursor) {
        const [c, r, vis] = step.cursor;
        $('#cursor-info').textContent =
            `cursor: col=${c} row=${r}${vis ? '' : ' (hidden)'}`;
    } else {
        $('#cursor-info').textContent = '';
    }
}

function renderScreen(screenStr, cursor) {
    const grid = decodeScreen(screenStr);
    const pre = $('#screen');
    pre.innerHTML = '';
    const [cx, cy, cVis] = cursor || [-1, -1, 0];

    for (let r = 0; r < ROWS_24; r++) {
        const rowEl = document.createElement('div');
        rowEl.className = 'screen-row';
        let runCh = '', runColor = null, runAttr = null;
        const flush = () => {
            if (!runCh) return;
            const span = document.createElement('span');
            span.textContent = runCh;
            span.style.color = colorToCss(runColor);
            if (runAttr & 1) {
                // inverse: swap fg/bg
                span.style.background = colorToCss(runColor);
                span.style.color = '#000';
            }
            if (runAttr & 2) span.style.fontWeight = 'bold';
            if (runAttr & 4) span.style.textDecoration = 'underline';
            rowEl.appendChild(span);
            runCh = '';
        };
        for (let c = 0; c < COLS_80; c++) {
            const cell = grid[r][c];
            const ch = renderCell(cell);
            const isCursor = cVis && r === cy && c === cx;
            if (isCursor) {
                flush();
                const cspan = document.createElement('span');
                cspan.textContent = ch === ' ' ? ' ' : ch;
                cspan.className = 'cursor-cell';
                cspan.style.color = '#000';
                cspan.style.background = colorToCss(cell.color);
                rowEl.appendChild(cspan);
                continue;
            }
            if (cell.color === runColor && cell.attr === runAttr) {
                runCh += ch === ' ' ? ' ' : ch;
            } else {
                flush();
                runCh = ch === ' ' ? ' ' : ch;
                runColor = cell.color;
                runAttr = cell.attr;
            }
        }
        flush();
        if (!rowEl.childNodes.length) rowEl.appendChild(document.createTextNode(' '));
        pre.appendChild(rowEl);
    }
}

// --- File picker fallback -------------------------------------------------
$('#session-file').addEventListener('change', async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const text = await file.text();
    try {
        loadSession(JSON.parse(text), file.name);
    } catch (err) {
        setStatus(`Failed to parse ${file.name}: ${err.message}`, 'error');
    }
});

// --- Boot -----------------------------------------------------------------
const q = getQuery();
const sessionPath = q.get('session');
if (sessionPath) {
    fetchSession(sessionPath);
} else {
    setStatus('No session loaded. Use the file picker above, or append ?session=PATH to the URL.', 'hint');
}
