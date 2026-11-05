pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Colors: the first readable file of
//   1. "colors" in settings.json
//   2. ~/.cache/quickseek/colors.json (written by templates/ for wallust or matugen)
//   3. ~/.cache/wal/colors.json (pywal)
// else the built-in palette. Accepted formats: pywal ({special: {background, foreground},
// colors: {color0..15}}, optional "accent") or flat {background, foreground, accent}.
Singleton {
    id: root

    property color background: "#1c1d21"
    property color foreground: "#e8e8ec"
    property color accent: "#5b8def"
    // Icon tile colors: color1..6 of a pywal-style palette, else hues around the accent
    property var tints: []

    readonly property bool light: luminance(background) > 0.5
    readonly property color dim: Qt.alpha(foreground, 0.55)
    readonly property color faint: Qt.alpha(foreground, 0.35)
    readonly property color surface: Qt.alpha(foreground, light ? 0.06 : 0.08)
    readonly property color border: Qt.alpha(foreground, light ? 0.14 : 0.12)
    readonly property color selection: Qt.alpha(accent, light ? 0.16 : 0.26)
    readonly property color onSelection: foreground
    readonly property color shadow: Qt.alpha("#000000", light ? 0.16 : 0.4)

    function tint(key) {
        const t = tints.length ? tints : [0, 60, 150, 210, 270, 320].map(d => Qt.hsla((accent.hslHue + d / 360) % 1, Math.max(accent.hslSaturation, 0.45), light ? 0.4 : 0.65, 1));
        let h = 0;
        for (let i = 0; i < key.length; i++) h = (h * 31 + key.charCodeAt(i)) >>> 0;
        let c = Qt.darker(t[h % t.length], 1);   // string -> color
        // Dark enough for a white glyph on top
        for (let i = 0; i < 12 && luminance(c) > 0.2; i++) c = Qt.darker(c, 1.12);
        return c;
    }

    function luminance(c) {
        const f = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }

    readonly property var candidates: [
        Settings.expand(Settings.s.colors || ""),
        Settings.cacheDir + "/colors.json",
        Settings.home + "/.cache/wal/colors.json"
    ]
    property var loaded: [null, null, null]

    function parse(text) {
        try {
            const j = JSON.parse(text);
            const bg = j.special?.background ?? j.background;
            const fg = j.special?.foreground ?? j.foreground;
            if (!bg || !fg) return null;
            const tints = [1, 2, 3, 4, 5, 6].map(n => j.colors?.["color" + n]).filter(c => c);
            return { background: bg, foreground: fg, accent: j.accent ?? j.colors?.color4 ?? root.accent, tints };
        } catch (e) {
            return null;
        }
    }

    function pick() {
        const p = loaded.find(x => x);
        if (!p) return;
        background = p.background;
        foreground = p.foreground;
        accent = p.accent;
        tints = p.tints;
    }

    Variants {
        model: [0, 1, 2]
        FileView {
            required property int modelData
            readonly property int index: modelData
            path: root.candidates[index]
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onPathChanged: if (!path) { root.loaded[index] = null; root.pick(); }
            onLoaded: { root.loaded[index] = root.parse(text()); root.pick(); }
            onLoadFailed: { root.loaded[index] = null; root.pick(); }
        }
    }
}
