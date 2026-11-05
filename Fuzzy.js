.pragma library

// Keyboard positions: the same key on a US QWERTY and a Russian ЙЦУКЕН layout.
const EN = "`qwertyuiop[]asdfghjkl;'zxcvbnm,./";
const RU = "ёйцукенгшщзхъфывапролджэячсмитьбю.";

function normalize(s) {
    return s.toLowerCase().replace(/[-_.,:;/\\|()'"’«»…]+/g, "").replace(/\s+/g, " ").trim();
}

// Text typed in the wrong layout, re-typed in the other one ("цфддзфзук" -> "wallpaper").
function swapLayout(s) {
    const lower = s.toLowerCase();
    const toEn = /[а-яё]/.test(lower);
    const from = toEn ? RU : EN, to = toEn ? EN : RU;
    let out = "";
    for (const ch of lower) {
        const i = from.indexOf(ch);
        out += i >= 0 ? to[i] : ch;
    }
    return out;
}

function isBoundary(t, i) {
    return i === 0 || t[i - 1] === " ";
}

// One token against one normalized text. 0 = no match.
function scoreToken(q, t) {
    if (!q || !t) return 0;
    if (t === q) return 1000;
    if (t.startsWith(q)) return 900 - Math.min(t.length - q.length, 60);
    let i = t.indexOf(q);
    if (i >= 0) {
        for (let j = i; j >= 0; j = t.indexOf(q, j + 1))
            if (isBoundary(t, j)) return 800 - Math.min(j, 60);
        return 600 - Math.min(i, 60);
    }
    if (q.length < 2) return 0;
    // Subsequence: rewards word starts and runs, penalizes gaps
    let score = 0, ti = 0, run = 0, firstAtStart = false;
    for (let qi = 0; qi < q.length; qi++) {
        const ch = q[qi];
        let found = -1;
        for (let k = ti; k < t.length; k++) {
            if (t[k] !== ch) continue;
            if (found < 0) found = k;
            if (isBoundary(t, k)) { found = k; break; }
            if (k === ti) break;
        }
        if (found < 0) return 0;
        if (qi === 0) firstAtStart = isBoundary(t, found);
        if (found === ti && qi > 0) { run++; score += 6 + run * 4; }
        else { run = 0; score -= Math.min(found - ti, 8); }
        if (isBoundary(t, found)) score += 18;
        ti = found + 1;
    }
    if (!firstAtStart) score -= 25;
    const s = 300 + score;
    return s > 120 ? Math.min(s, 590) : 0;
}

// Query against fields [[normalizedText, weight, minRawScore], ...]; every token has to match somewhere.
function scoreFields(query, fields) {
    const tokens = query.split(" ").filter(x => x);
    if (!tokens.length) return 0;
    let total = 0;
    for (const tok of tokens) {
        let best = 0;
        for (const [text, weight, min] of fields) {
            const raw = scoreToken(tok, text);
            if (raw < (min ?? 0)) continue;
            const s = raw * weight;
            if (s > best) best = s;
        }
        if (!best) return 0;
        total += best;
    }
    let s = total / tokens.length;
    // The whole query as a phrase in the title beats the same words scattered around
    if (tokens.length > 1 && fields.length && fields[0][0].includes(query)) s += 80;
    return s;
}
