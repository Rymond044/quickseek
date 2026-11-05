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

    readonly property bool light: luminance(background) > 0.5
    readonly property color dim: Qt.alpha(foreground, 0.55)
    readonly property color faint: Qt.alpha(foreground, 0.35)
    readonly property color surface: Qt.alpha(foreground, light ? 0.06 : 0.08)
    readonly property color border: Qt.alpha(foreground, light ? 0.14 : 0.12)
    readonly property color selection: accent
    readonly property color onSelection: luminance(accent) > 0.45 ? "#111111" : "#ffffff"

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
            return { background: bg, foreground: fg, accent: j.accent ?? j.colors?.color4 ?? root.accent };
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
            onLoaded: { root.loaded[index] = root.parse(text()); root.pick(); }
            onLoadFailed: { root.loaded[index] = null; root.pick(); }
        }
    }
}
