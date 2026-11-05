// ~/.config/quickseek/settings.json merged over the defaults below, then every file
// listed in "include" (missing ones are skipped). All files are watched.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/quickseek"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/quickseek"
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/quickseek"

    readonly property var defaults: ({
        width: 680,
        maxRows: 9,
        opacity: 0.96,
        colors: "",
        include: [],
        fonts: { text: "sans-serif", icons: "Symbols Nerd Font", size: 11 },
        // Prepended to app launches and xdg-open, e.g. ["uwsm", "app", "--"]
        launchPrefix: [],
        plugins: [],
        web: {
            default: "g",
            engines: {
                g: { name: "Google", url: "https://www.google.com/search?q=%s" },
                yt: { name: "YouTube", url: "https://www.youtube.com/results?search_query=%s" },
                aw: { name: "Arch Wiki", url: "https://wiki.archlinux.org/index.php?search=%s" }
            }
        },
        power: {
            lock: ["loginctl", "lock-session"],
            suspend: ["systemctl", "suspend"],
            reboot: ["systemctl", "reboot"],
            shutdown: ["systemctl", "poweroff"],
            logout: ["sh", "-c", "command -v uwsm >/dev/null && exec uwsm stop || exec hyprctl dispatch exit"]
        }
    })

    property var s: defaults
    property var mainData: ({})
    property var includeData: ({})

    function expand(p) {
        return typeof p === "string" && p.startsWith("~/") ? home + p.slice(1) : p;
    }

    function merge(a, b) {
        if (b === null || typeof b !== "object" || Array.isArray(b) || typeof a !== "object" || Array.isArray(a))
            return b === undefined ? a : b;
        const out = Object.assign({}, a);
        for (const k in b) out[k] = merge(a[k], b[k]);
        return out;
    }

    function rebuild() {
        let r = merge(defaults, mainData);
        for (const p of r.include || [])
            if (includeData[p]) r = merge(r, includeData[p]);
        s = r;
    }

    function parse(view, label) {
        const t = view.text().trim();
        if (!t) return {};
        try {
            return JSON.parse(t);
        } catch (e) {
            console.warn("quickseek:", label, e);
            return {};
        }
    }

    FileView {
        id: main
        path: root.configDir + "/settings.json"
        watchChanges: true
        printErrors: false
        blockLoading: true
        onFileChanged: reload()
        onLoaded: { root.mainData = root.parse(main, path); root.rebuild(); }
        onLoadFailed: { root.mainData = {}; root.rebuild(); }
    }

    Variants {
        model: root.mainData.include || []
        FileView {
            required property string modelData
            path: root.expand(modelData)
            watchChanges: true
            printErrors: false
            blockLoading: true
            onFileChanged: reload()
            onLoaded: { root.includeData[modelData] = root.parse(this, path); root.rebuild(); }
            onLoadFailed: { delete root.includeData[modelData]; root.rebuild(); }
        }
    }
}
