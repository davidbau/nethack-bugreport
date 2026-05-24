// screen-decode.mjs — Parses canonical session screen strings into a
// 24×80 grid of {ch, color, attr, decgfx} cells. Vendored from the
// Teleport contest template (frozen/screen-decode.mjs) so the bug-
// report viewer is self-contained — no contest infrastructure needed.
//
// Wire format:
//   - '\n' → next row, col=0
//   - ESC[Nm   → SGR (0 reset, 1 bold, 4 underline, 7 inverse,
//                39 default fg, 30..37 fg dim, 90..97 fg bright)
//   - ESC[NC   → cursor forward N columns
//   - 0x0e/0x0f → DEC line-drawing mode on/off
//   - other printable bytes → place at cursor

const ROWS = 24;
const COLS = 80;
const DEFAULT_COLOR = 8;

export const ROWS_24 = ROWS;
export const COLS_80 = COLS;

export function makeBlankGrid() {
    const g = [];
    for (let r = 0; r < ROWS; r++) {
        const row = [];
        for (let c = 0; c < COLS; c++) {
            row.push({ ch: ' ', color: DEFAULT_COLOR, attr: 0, decgfx: 0 });
        }
        g.push(row);
    }
    return g;
}

export function decodeScreen(s) {
    const grid = makeBlankGrid();
    if (!s) return grid;
    let row = 0, col = 0;
    let curFg = DEFAULT_COLOR, curAttr = 0, decgfx = 0;
    const len = s.length;
    let i = 0;
    while (i < len) {
        const c = s[i];
        if (c === '\n') { row += 1; col = 0; i += 1; continue; }
        if (c === '\x0e') { decgfx = 1; i += 1; continue; }
        if (c === '\x0f') { decgfx = 0; i += 1; continue; }
        if (c === '\x1b' && s[i + 1] === '[') {
            let j = i + 2;
            while (j < len && /[0-9;?]/.test(s[j])) j += 1;
            const params = s.slice(i + 2, j);
            const final = s[j];
            i = j + 1;
            if (final === 'C') {
                col += parseInt(params, 10) || 1;
            } else if (final === 'm') {
                ({ fg: curFg, attr: curAttr } = sgrApply(params, curFg, curAttr));
            }
            continue;
        }
        if (row >= 0 && row < ROWS && col >= 0 && col < COLS) {
            grid[row][col] = { ch: c, color: curFg, attr: curAttr, decgfx };
        }
        col += 1;
        i += 1;
    }
    return grid;
}

function sgrApply(params, fg, attr) {
    if (params === '') params = '0';
    for (const tok of params.split(';')) {
        const n = parseInt(tok || '0', 10);
        if (n === 0) { fg = DEFAULT_COLOR; attr = 0; }
        else if (n === 1) attr |= 2;
        else if (n === 4) attr |= 4;
        else if (n === 7) attr |= 1;
        else if (n === 22) attr &= ~2;
        else if (n === 24) attr &= ~4;
        else if (n === 27) attr &= ~1;
        else if (n === 39) fg = DEFAULT_COLOR;
        else if (n >= 30 && n <= 37) fg = n - 30;
        else if (n >= 90 && n <= 97) fg = (n - 90) + 8;
    }
    return { fg, attr };
}

const COLORS = [
    '#000000', '#cd0000', '#00cd00', '#cdcd00',
    '#0000ee', '#cd00cd', '#00cdcd', '#e5e5e5',
    '#7f7f7f', '#ff0000', '#00ff00', '#ffff00',
    '#5c5cff', '#ff00ff', '#00ffff', '#ffffff',
];
export function colorToCss(idx) {
    if (idx === DEFAULT_COLOR || idx == null) return '#c0c0c0';
    if (idx < 0 || idx > 15) return '#c0c0c0';
    return COLORS[idx];
}

const DEC_MAP = {
    'l': '┌', 'q': '─', 'k': '┐',
    'x': '│', 'm': '└', 'j': '┘',
    't': '├', 'u': '┤', 'w': '┬',
    'v': '┴', 'n': '┼', 'a': '▒',
    '~': '·',
};
export function renderCell(cell) {
    if (cell.decgfx && DEC_MAP[cell.ch]) return DEC_MAP[cell.ch];
    return cell.ch;
}
