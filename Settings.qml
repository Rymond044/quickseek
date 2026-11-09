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
        // Empty text font = the desktop font (gsettings font-name), else sans-serif
        fonts: { text: "", icons: "Symbols Nerd Font", size: 11 },
        // Soft drop shadow under the window; turn off for compositor blur/glass
        shadow: true,
        // Prepended to app launches and the opener, e.g. ["uwsm", "app", "--"]
        launchPrefix: [],
        // Opens files, folders and URLs. gio runs Terminal=true apps (nvim) in a terminal, xdg-open does not
        opener: ["gio", "open"],
        // What an empty query shows: any of "pinned", "recent", "popular", in this order
        emptyView: [],
        // "f report" searches files only; inline: true adds files to every search
        files: { enabled: true, prefix: "f", inline: false },
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
    property string systemFont: ""
    readonly property string textFont: s.fonts.text || systemFont || "sans-serif"
    property var mainData: ({})
    property bool mainBroken: false   // never overwrite a file we could not parse
    property bool mainExists: false

    readonly property string file: configDir + "/settings.json"

    // Create an empty settings.json so it can be opened in an editor
    function ensureFile() {
        if (!mainExists) main.setText("{}\n");
    }
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
            return null;
        }
    }

    // Change one key of settings.json, e.g. set(["files", "enabled"], false). Writes through
    // symlinks (dotfiles), drops nothing else, but reformats the file.
    function set(path, value) {
        if (mainBroken) {
            console.warn("quickseek: settings.json does not parse, not writing it");
            return;
        }
        const d = JSON.parse(JSON.stringify(mainData));
        let o = d;
        for (const k of path.slice(0, -1)) {
            if (!o[k] || typeof o[k] !== "object" || Array.isArray(o[k])) o[k] = {};
            o = o[k];
        }
        o[path[path.length - 1]] = value;
        mainData = d;
        rebuild();
        main.setText(JSON.stringify(d, null, 2) + "\n");
    }

    readonly property var emptyView: {
        const v = s.emptyView;
        return (Array.isArray(v) ? v : v ? [v] : []).filter(x => x !== "none");
    }

    Process {
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "font-name"]
        stdout: StdioCollector {
            // 'Family Name 11' -> Family Name
            onStreamFinished: root.systemFont = text.trim().replace(/^'|'$/g, "").replace(/\s+[\d.]+$/, "")
        }
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", configDir])

    FileView {
        id: main
        path: root.file
        watchChanges: true
        printErrors: false
        blockLoading: true
        onFileChanged: reload()
        onLoaded: {
            const d = root.parse(main, path);
            root.mainBroken = d === null;
            root.mainExists = true;
            root.mainData = d ?? {};
            root.rebuild();
        }
        onLoadFailed: { root.mainBroken = false; root.mainExists = false; root.mainData = {}; root.rebuild(); }
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
            onLoaded: { root.includeData[modelData] = root.parse(this, path) ?? {}; root.rebuild(); }
            onLoadFailed: { delete root.includeData[modelData]; root.rebuild(); }
        }
    }
}
