// Sources, search, ranking and actions. The window only renders `rows` and calls back here.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Fuzzy.js" as Fuzzy

Singleton {
    id: root

    property bool shown: false     // requested state
    property bool mapped: false    // window exists (stays true during the close animation)
    property string query: ""
    property var stack: []         // folder keys, innermost last
    property var prompt: null      // { plugin, id, title, message, password }
    property var rows: []          // { header } | { item, crumb, big }
    property int sel: -1
    property bool userMoved: false // keep the selection across refreshes only if the user picked it
    property string confirmKey: ""
    property string busyKey: ""

    readonly property var folder: stack.length ? byKey[stack[stack.length - 1]] ?? null : null
    readonly property var current: sel >= 0 ? rows[sel]?.item ?? null : null

    property var all: []
    property var byKey: ({})
    property var savedQuery: ({})  // folder key -> query typed before entering it
    property var menuItems: []
    property int menuSeq: 0
    property var calc: null        // { query, result }

    // Preview (Space): opens only after moving through the list with keys, so a space
    // typed into the query stays a space; follows the selection while open
    signal queryReplaced()
    signal typeRequested(string text)   // IPC "type": goes through the field like typing
    property string fieldText: ""       // what the search field shows (tests)
    property bool listMode: false
    // Opened straight into a folder (Super+V…): Esc there closes instead of going up
    property int baseDepth: 0
    property bool previewOpen: false
    readonly property var previewItem: previewOpen && previewable(current) ? current : null
    onStackChanged: previewOpen = false

    function previewable(i) {
        return !!i && ((i.kind === "file" && !i.dir) || i.kind === "clip");
    }

    // ------------------------------------------------------------------ window

    function open(folderKey) {
        query = "";
        listMode = false;
        previewOpen = false;
        prompt = null;
        confirmKey = "";
        clearMenus();
        stack = folderKey && byKey[folderKey] ? [folderKey] : [];
        baseDepth = stack.length;
        fileCache = {};
        if (Files.inline || stack[0] === "files") Files.open();
        for (const p of plugins) p.list(p.refresh);
        if (stack.length) pluginOf(stack[0])?.list(2);
        refresh(false);
        if (mapped) { shown = true; return; }
        opening = true;
        monitorProc.running = true;
    }

    // Focused monitor, asked once per open: the Hyprland singleton would keep an event
    // stream open and wake the daemon on every window title change.
    property string screenName: ""
    property bool opening: false
    Process {
        id: monitorProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.screenName = JSON.parse(text).find(m => m.focused)?.name ?? "";
                } catch (e) {
                    root.screenName = "";
                }
                if (!root.opening) return;
                root.opening = false;
                root.mapped = true;
                root.shown = true;
            }
        }
    }

    function close() {
        opening = false;
        shown = false;
    }

    // The window stays mapped (invisible, still holding the keyboard) until every key pressed
    // in it is released: otherwise the release, or the rest of a key press, lands in the window below.
    property var held: ({})
    property bool unmapPending: false
    function keyDown(key) { held[key] = true; }
    function keyUp(key) {
        delete held[key];
        if (unmapPending && !Object.keys(held).length) unmap();
    }
    function unmap() {
        unmapTimer.stop();
        unmapPending = false;
        if (shown) return;
        held = {};
        mapped = false;
    }
    function closed() {
        unmapPending = true;
        if (Object.keys(held).length) unmapTimer.restart();
        else unmap();
    }
    // In case a release never arrives (focus taken away)
    Timer { id: unmapTimer; interval: 1500; onTriggered: root.unmap() }

    function toggle() {
        shown || opening ? close() : open();
    }

    // ------------------------------------------------------------------ sources

    readonly property var plugins: pluginInst.instances

    Variants {
        id: pluginInst
        model: Settings.s.plugins ?? []
        onInstancesChanged: rebuildTimer.restart()
        Plugin {
            required property var modelData
            config: modelData
            onItemsChanged: rebuildTimer.restart()
        }
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { rebuildTimer.restart(); }
    }

    // Settings and pins only change statuses of the settings folder
    Connections {
        target: Settings
        function onSChanged() { rebuildTimer.restart(); }
    }
    Connections {
        target: History
        function onPinsChanged() { rebuildTimer.restart(); }
    }
    Connections {
        target: Clipboard
        function onUpdated() { if (root.shown && root.folder?.key === "clipboard") root.refresh(true); }
        function onAvailableChanged() { rebuildTimer.restart(); }
    }
    Connections {
        target: Files
        function onUpdated() { if (root.shown) root.refresh(true); }
        function onIndexingChanged() { rebuildTimer.restart(); }
    }

    Timer {
        id: rebuildTimer
        interval: 30
        onTriggered: root.rebuild()
    }
    Component.onCompleted: rebuildTimer.start()

    function make(o) {
        o.nTitle = Fuzzy.normalize(o.title ?? "");
        o.nKeywords = Fuzzy.normalize(o.keywords ?? "");
        o.ancestors = o.ancestors ?? [];
        return o;
    }

    function appItems() {
        const hidden = Settings.s.hidden ?? [];
        return DesktopEntries.applications.values.filter(e => !e.noDisplay && !hidden.includes("app:" + e.id)).map(e => make({
            key: "app:" + e.id,
            kind: "app",
            group: "Applications",
            title: e.name,
            keywords: [e.genericName, e.comment, (e.keywords ?? []).join(" "), e.id].join(" "),
            icon: e.icon,
            iconType: "theme",
            entry: e
        }));
    }

    // Session actions live in the "session" folder and show up in search like any folder child.
    // settings.power: id -> command, or { title, icon, keywords, confirm, order, command }; null hides one.
    function powerItems() {
        const defs = {
            lock: ["Lock", "󰌾", "screen", false],
            suspend: ["Suspend", "󰤄", "sleep", false],
            reboot: ["Restart", "󰜉", "reboot", true],
            shutdown: ["Shut down", "󰐥", "power off poweroff", true],
            logout: ["Log out", "󰍃", "exit sign out session", true]
        };
        const out = [make({ key: "session", kind: "folder", folder: true, group: "System", title: "Session",
            icon: "󰐥", iconType: "glyph", keywords: "power menu shutdown restart lock" })];
        let n = 0;
        for (const [id, v] of Object.entries(Settings.s.power ?? {})) {
            const o = Array.isArray(v) ? { command: v } : v;
            if (!o?.command) continue;
            const d = defs[id] ?? [];
            out.push(make({
                key: "power:" + id,
                kind: "power",
                group: "System",
                ancestors: ["session"],
                order: o.order ?? 10 * n++,
                title: o.title ?? d[0] ?? id,
                icon: o.icon ?? d[1] ?? "󰐥",
                keywords: o.keywords ?? d[2] ?? "",
                confirm: o.confirm ?? d[3] ?? false,
                iconType: "glyph",
                command: o.command
            }));
        }
        return out;
    }

    // ---- files

    property var fileCache: ({})   // key -> item, cleared on open
    property var iconCache: ({})   // file type -> theme icon name that exists

    readonly property var fileIcons: [
        [/\.(png|jpe?g|webp|gif|svg|bmp|avif|heic|tiff?|ico|jxl)$/, ["image-x-generic"]],
        [/\.(mp4|mkv|webm|avi|mov|m4v|flv|wmv)$/, ["video-x-generic"]],
        [/\.(mp3|flac|ogg|opus|wav|m4a|aac|wma)$/, ["audio-x-generic"]],
        [/\.pdf$/, ["application-pdf", "x-office-document"]],
        [/\.(epub|fb2|djvu|mobi)$/, ["x-office-document"]],
        [/\.(docx?|odt|rtf)$/, ["x-office-document"]],
        [/\.(xlsx?|ods|csv|tsv)$/, ["x-office-spreadsheet"]],
        [/\.(pptx?|odp)$/, ["x-office-presentation"]],
        [/\.(zip|tar|gz|tgz|xz|zst|bz2|7z|rar|deb|rpm|pkg\.tar\.zst)$/, ["package-x-generic"]],
        [/\.(iso|img|qcow2)$/, ["media-optical", "package-x-generic"]],
        [/\.(ttf|otf|woff2?)$/, ["font-x-generic"]],
        [/\.(sh|zsh|bash|fish|py|js|ts|lua|go|rs|c|cc|cpp|h|hpp|java|kt|rb|php|qml|nix)$/, ["text-x-script"]],
        [/\.(html?|css)$/, ["text-html", "text-x-script"]],
        [/\.(appimage|exe|run|bin)$/, ["application-x-executable"]],
        [/\.desktop$/, ["application-x-desktop", "application-x-executable"]]
    ]

    function themeIcon(type, names) {
        if (iconCache[type] === undefined)
            iconCache[type] = names.concat(["text-x-generic"]).find(n => Quickshell.iconPath(n, true)) ?? "";
        return iconCache[type];
    }

    function fileIcon(path, dir) {
        if (dir) {
            const special = { [home]: "user-home", [home + "/Desktop"]: "user-desktop", [home + "/Downloads"]: "folder-download",
                [home + "/Documents"]: "folder-documents", [home + "/Pictures"]: "folder-pictures",
                [home + "/Music"]: "folder-music", [home + "/Videos"]: "folder-videos" }[path];
            return special ? themeIcon(special, [special, "folder"]) : themeIcon("dir", ["folder"]);
        }
        const name = path.slice(path.lastIndexOf("/") + 1).toLowerCase();
        for (const [re, names] of fileIcons)
            if (re.test(name)) return themeIcon(names[0], names);
        return themeIcon("file", ["text-x-generic"]);
    }

    readonly property string home: Settings.home

    function tilde(p) {
        return p === home ? "~" : p.startsWith(home + "/") ? "~" + p.slice(home.length) : p;
    }

    // Folder keys end with "/", so a key alone is enough to rebuild the item (pins, recents)
    function fileItem(path, dir) {
        const key = "file:" + path + (dir ? "/" : "");
        if (fileCache[key]) return fileCache[key];
        const slash = path.lastIndexOf("/");
        const parent = path.slice(0, slash) || "/";
        const it = make({
            key, path, dir,
            kind: "file",
            group: dir ? "Folders" : "Files",
            title: path.slice(slash + 1),
            status: tilde(parent),
            icon: fileIcon(path, dir),
            iconType: "theme",
            glyph: dir ? "\uf07b" : "\uf15b",   // when the icon theme has nothing
            depth: (tilde(path).match(/\//g) ?? []).length
        });
        // "Report_2027.pdf" -> words "report 2027 pdf"; the glued form still matches as a keyword
        it.nKeywords = it.nTitle;
        it.nTitle = Fuzzy.normalize(it.title.replace(/[._-]+/g, " "));
        fileCache[key] = it;
        return it;
    }

    function fromKey(key) {
        if (key.startsWith("file:")) {
            const dir = key.endsWith("/");
            return fileItem(dir ? key.slice(5, -1) : key.slice(5), dir);
        }
        return pinnable(byKey[key]) ? byKey[key] : null;
    }

    function pinnable(i) {
        return !!i && !i.key.startsWith("menu:") && !["web", "calc", "clip", "cmd", "emoji"].includes(i.kind);
    }

    function togglePin(i) {
        if (pinnable(i)) History.togglePin(i.key);
    }

    function showInFolder(path) {
        const uri = "file://" + path.split("/").map(encodeURIComponent).join("/").replace(/'/g, "%27");
        const parent = path.slice(0, path.lastIndexOf("/")) || "/";
        Quickshell.execDetached(["sh", "-c",
            'gdbus call --session --dest org.freedesktop.FileManager1 --object-path /org/freedesktop/FileManager1 '
            + '--method org.freedesktop.FileManager1.ShowItems "$1" "" >/dev/null 2>&1 || exec "$@"',
            "sh", `['${uri}']`].concat(Settings.s.launchPrefix ?? [], Settings.s.opener ?? ["xdg-open"], [parent]));
    }

    // ---- quickseek's own settings, a folder like a plugin's

    // "f report" or Tab on this item: a folder whose search is files only
    function filesFolder() {
        if (!Files.enabled) return [];
        return [make({ key: "files", kind: "folder", folder: true, group: "Files", title: "Find files",
            status: Files.prefix ? Files.prefix + " …" : "", icon: "\uf07b", iconType: "glyph",
            keywords: "files folders documents search " + Files.prefix })];
    }

    function clipboardFolder() {
        if (!Clipboard.available) return [];
        return [make({ key: "clipboard", kind: "folder", folder: true, group: "Clipboard", title: "Clipboard history",
            status: Clipboard.prefix ? Clipboard.prefix + " …" : "", icon: "󰅌", iconType: "glyph",
            keywords: "clipboard paste copy history " + Clipboard.prefix })];
    }

    function clipItem(e, n) {
        const one = e.text.replace(/\s+/g, " ").trim();
        return make({
            key: "clip:" + e.time + ":" + n,
            kind: "clip",
            group: "Clipboard",
            title: e.image ? "Image" : one.slice(0, 300),
            keywords: e.image ? "image picture screenshot png" : "",
            status: (e.pinned ? "pinned · " : "") + Clipboard.age(e.time),
            icon: e.image || "󰅌",
            iconType: e.image ? "theme" : "glyph",
            glyph: "󰋩",
            entry: e
        });
    }

    // Newest first, clipse pins on top; a query ranks by match, then by age
    function clipRows(raw, q) {
        const items = Clipboard.entries.map(clipItem);
        const order = (a, b) => (b.entry.pinned - a.entry.pinned) || (b.entry.time - a.entry.time);
        if (!q) return items.sort(order).map(item => ({ item }));
        const alt = Fuzzy.normalize(Fuzzy.swapLayout(raw));
        const scored = [];
        for (const i of items) {
            const fields = [[i.nTitle, 1], [i.nKeywords, 0.7]];
            let sc = Fuzzy.scoreFields(q, fields);
            if (alt !== q) sc = Math.max(sc, 0.97 * Fuzzy.scoreFields(alt, fields));
            if (sc > 0) scored.push({ item: i, score: sc });
        }
        scored.sort((a, b) => (b.score - a.score) || order(a.item, b.item));
        return scored.map(x => ({ item: x.item }));
    }

    // ---- ":fire" / ":огонь": emoji, Enter copies

    function emojiFolder() {
        if (!Emoji.enabled) return [];
        return [make({ key: "emoji", kind: "folder", folder: true, group: "Emoji", title: "Emoji",
            status: Emoji.prefix + " …", icon: "😀", iconType: "emoji", keywords: "emoji smiley symbols эмодзи смайлы " + Emoji.prefix })];
    }

    property var emojiItems: []
    Connections {
        target: Emoji
        function onUpdated() {
            root.emojiItems = Emoji.items.map((e, n) => root.make({ key: "emoji:" + e.char, kind: "emoji", group: "Emoji",
                title: e.name, keywords: e.keywords, status: e.ru, nRu: Fuzzy.normalize(e.ru), icon: e.char, iconType: "emoji", order: n }));
            if (root.folder?.key === "emoji") root.refresh(false);
        }
    }

    // Empty query: recently used first, then all in Unicode order
    function emojiRows(raw, q) {
        if (!q) {
            const recent = History.recent().filter(k => k.startsWith("emoji:")).slice(0, 16);
            const byChar = {};
            for (const i of emojiItems) byChar[i.key] = i;
            const top = recent.map(k => byChar[k]).filter(i => i);
            const out = [];
            if (top.length) out.push({ header: "Recent" }, ...top.map(item => ({ item })), { header: "All" });
            return out.concat(emojiItems.map(item => ({ item })));
        }
        const alt = Fuzzy.normalize(Fuzzy.swapLayout(raw));
        const scored = [];
        for (const i of emojiItems) {
            const fields = [[i.nTitle, 1], [i.nRu, 1], [i.nKeywords, 0.8]];
            let sc = Fuzzy.scoreFields(q, fields);
            if (alt !== q) sc = Math.max(sc, 0.97 * Fuzzy.scoreFields(alt, fields));
            if (sc > 0) scored.push({ item: i, score: sc + History.frecency(i.key) });
        }
        scored.sort((a, b) => (b.score - a.score) || (a.item.order - b.item.order));
        return scored.slice(0, 200).map(x => ({ item: x.item }));
    }

    // ---- "> command": runs in a terminal, the shell stays open afterwards

    readonly property string commandPrefix: Settings.s.command?.prefix ?? ">"
    property var executables: []

    function commandFolder() {
        if (!commandPrefix) return [];
        return [make({ key: "command", kind: "folder", folder: true, group: "Command", title: "Run command",
            status: commandPrefix + " …", icon: "\uf120", iconType: "glyph", keywords: "terminal shell run execute " + commandPrefix })];
    }

    function cmdItem(text, status) {
        return make({ key: "cmd:" + text, kind: "cmd", group: "Command", title: text, status,
            icon: "\uf120", iconType: "glyph", command: text });
    }

    // What is typed, then past commands containing it (frecency), then programs from $PATH
    // starting with it (Tab puts one into the query)
    function commandRows(raw) {
        const t = raw.trim();
        const out = [];
        if (t) out.push({ item: cmdItem(t, "run in terminal"), big: true });
        const lt = t.toLowerCase();
        const past = History.recent().filter(k => k.startsWith("cmd:")).map(k => k.slice(4))
            .filter(c => c !== t && c.toLowerCase().includes(lt))
            .sort((a, b) => History.frecency("cmd:" + b) - History.frecency("cmd:" + a));
        if (past.length) out.push({ header: "History" });
        for (const c of past.slice(0, 50)) out.push({ item: cmdItem(c, "") });
        if (t && !/\s/.test(t)) {
            const progs = executables.filter(e => e.startsWith(t) && e !== t && !past.includes(e)).slice(0, 30);
            if (progs.length) out.push({ header: "Programs" });
            for (const e of progs) out.push({ item: cmdItem(e, "") });
        }
        return out;
    }

    function runCommand(text) {
        const sh = Quickshell.env("SHELL") || "sh";
        launch((Settings.s.terminal ?? ["kitty", "-e"]).concat([sh, "-ic", text + "; exec " + sh]));
    }

    Process {
        id: pathProc
        command: ["sh", "-c", 'IFS=:; for d in $PATH; do [ -d "$d" ] && ls -1 -- "$d"; done 2>/dev/null | sort -u']
        stdout: StdioCollector {
            onStreamFinished: {
                root.executables = text.split("\n").filter(x => x);
                if (root.folder?.key === "command") root.refresh(true);
            }
        }
    }

    function settingsItems() {
        const base = "settings";
        const ev = Settings.emptyView;
        const names = emptyNames;
        const toggle = (key, title, on, run, extra) => Object.assign({
            key: base + ":" + key, kind: "setting", group: "quickseek", title, status: on ? "on" : "off",
            icon: "\uf00c", iconType: "glyph", ancestors: [base], run
        }, extra ?? {});
        const emptyToggle = (name, n) => toggle("empty:" + name, names[name], ev.includes(name), () =>
            Settings.set(["emptyView"], Object.keys(names).filter(x => x === name ? !ev.includes(x) : ev.includes(x))),
            { ancestors: [base + ":empty", base], order: n, keywords: "empty screen" });
        const list = [
            { key: base, kind: "folder", folder: true, group: "quickseek", title: "quickseek settings",
              icon: "\uf1de", iconType: "glyph", keywords: "preferences options config" },
            { key: base + ":empty", kind: "folder", folder: true, group: "quickseek", title: "Empty screen",
              status: ev.map(x => names[x]).join(", ") || "nothing", icon: "\uf009", iconType: "glyph",
              ancestors: [base], order: 0, keywords: "start pinned recent frequent" },
            emptyToggle("pinned", 0), emptyToggle("recent", 1), emptyToggle("popular", 2),
            toggle("files", "File search", Files.enabled, () => Settings.set(["files", "enabled"], !Files.enabled),
                { order: 1, icon: "\uf002", keywords: "files folders index" }),
            toggle("inline", "Files in every search", Files.inline, () => Settings.set(["files", "inline"], !Files.inline),
                { order: 1, icon: "\uf002", keywords: "files folders prefix" }),
            toggle("index", "Rebuild file index", false, () => Files.rebuild(),
                { order: 2, icon: "\uf021", status: Files.indexing ? "…" : "", keywords: "files update" }),
            toggle("unpin", "Unpin all", false, () => History.unpinAll(),
                { order: 3, icon: "\uf08d", status: History.pins.length ? String(History.pins.length) : "", confirm: true, keywords: "pins" }),
            toggle("hidden", "Show hidden apps", false, () => Settings.set(["hidden"], []),
                { order: 5, icon: "\uf06e", status: (Settings.s.hidden ?? []).length ? String(Settings.s.hidden.length) : "",
                  keywords: "unhide applications" }),
            toggle("history", "Clear history", false, () => History.clear(),
                { order: 4, icon: "\uf1da", status: "", confirm: true, keywords: "frecency forget" }),
            toggle("file", "Open settings file", false, null,
                { order: 5, icon: "\uf044", status: "", closes: true, keywords: "edit json",
                  run: () => { Settings.ensureFile(); openPath(Settings.file); } })
        ];
        return list.map(make);
    }

    function pluginOf(key) {
        return plugins.find(p => key === "plugin:" + p.pid || key.startsWith("plugin:" + p.pid + ":")) ?? null;
    }

    function pluginItems(p) {
        const rootKey = "plugin:" + p.pid;
        const out = [make({
            key: rootKey,
            kind: "folder",
            group: p.config.name,
            title: p.config.name,
            icon: p.config.icon ?? "󰏗",
            iconType: "glyph",
            keywords: p.config.keywords ?? "",
            folder: true
        })];
        const parentOf = {};
        for (const r of p.items) parentOf[r.id] = r.parent ? rootKey + ":" + r.parent : rootKey;
        let order = 0;
        for (const r of p.items) {
            const key = rootKey + ":" + r.id;
            const ancestors = [];
            for (let k = parentOf[r.id]; k; k = k === rootKey ? null : parentOf[k.slice(rootKey.length + 1)])
                ancestors.push(k);
            out.push(make(pluginEntry(p, r, key, ancestors, order++)));
        }
        return out;
    }

    function pluginEntry(p, r, key, ancestors, order) {
        return {
            key, ancestors, order,
            kind: r.folder ? "folder" : "plugin",
            folder: !!r.folder,
            group: p.config.name,
            title: r.title ?? "",
            status: r.status ?? "",
            icon: r.icon ?? "",
            iconType: r.iconType ?? "glyph",
            keywords: Array.isArray(r.keywords) ? r.keywords.join(" ") : r.keywords ?? "",
            closes: !!r.close,
            action: r.action ?? "",
            plugin: p,
            id: r.id
        };
    }

    function rebuild() {
        let list = appItems().concat(powerItems(), filesFolder(), clipboardFolder(), commandFolder(), emojiFolder(), settingsItems());
        for (const p of plugins) list = list.concat(pluginItems(p));
        list = list.concat(menuItems);
        const map = {};
        for (const i of list) map[i.key] = i;
        all = list;
        byKey = map;
        if (shown) refresh(true);
    }

    // ------------------------------------------------------------------ search

    readonly property var engines: Settings.s.web?.engines ?? {}

    function webItem(prefix, text) {
        const e = engines[prefix];
        if (!e) return null;
        return make({
            key: "web:" + prefix,
            kind: "web",
            group: "Web",
            title: `Search ${e.name} for “${text}”`,
            icon: "󰖟",
            iconType: "glyph",
            url: e.url.replace("%s", encodeURIComponent(text))
        });
    }

    function crumb(i) {
        const p = i.ancestors[0];
        if (!p || p === folder?.key || p.startsWith("menu:")) return "";
        const it = byKey[p];
        return it && it.ancestors.length ? it.title : "";
    }

    function childrenOf(f) {
        return all.filter(i => i.ancestors[0] === f.key).sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
    }

    function refresh(keepSelection) {
        const keepKey = keepSelection && userMoved ? current?.key : null;
        if (!keepSelection) userMoved = false;
        rows = compute();
        let s = -1;
        if (keepKey) s = rows.findIndex(r => r.item?.key === keepKey);
        if (s < 0) s = rows.findIndex(r => r.item);
        sel = s;
    }

    function compute() {
        const f = folder;
        const raw = query.trim();

        if (prompt) return [];

        // "yt lofi": the engine goes first, the rest of the results stay below
        const m = f ? null : raw.match(/^(\S+)\s+(.+)$/);
        const prefixed = m && engines[m[1]] ? webItem(m[1], m[2]) : null;

        const q = Fuzzy.normalize(raw);
        if (f?.key === "files") return fileRows(raw, q);
        if (f?.key === "clipboard") return clipRows(raw, q);
        if (f?.key === "command") return commandRows(query);
        if (f?.key === "emoji") return emojiRows(raw, q);
        if (!q) return f ? childrenOf(f).map(item => ({ item })) : emptyRows();

        const alt = Fuzzy.normalize(Fuzzy.swapLayout(raw));
        const scored = [];
        for (const i of all) {
            if (f ? !i.ancestors.includes(f.key) : i.ancestors.some(a => a.startsWith("menu:"))) continue;
            const fields = [[i.nTitle, 1], [i.nKeywords, 0.7, 700]];   // descriptions: word starts only
            let s = Fuzzy.scoreFields(q, fields);
            if (alt !== q) s = Math.max(s, 0.97 * Fuzzy.scoreFields(alt, fields));
            if (s <= 0) continue;
            s += History.frecency(i.key) + History.memory(i.key, q);
            if (History.pinned(i.key)) s += 2000;
            scored.push({ item: i, score: s });
        }
        if (!f) scoreFiles(raw, q, alt, scored, Files.inline);
        scored.sort((a, b) => b.score - a.score);

        if (f) return scored.map(x => ({ item: x.item, crumb: crumb(x.item) }));

        const out = [];
        let top = null;
        if (prefixed) {
            top = prefixed;
            out.push({ header: "Top hit" }, { item: top, big: true });
        } else if (calc && calc.query === raw) {
            const rates = ratesDate && isMoney(calc.query + " " + calc.result) ? "rates " + ratesDate : "";
            top = make({ key: "calc", kind: "calc", group: "Calculator", title: calc.result, status: rates || "copy", icon: "󰃬", iconType: "glyph" });
            out.push({ header: "Calculator" }, { item: top, big: true });
        } else if (scored.length) {
            top = scored[0].item;
            out.push({ header: "Top hit" }, { item: top, crumb: crumb(top), big: true });
        }

        const groups = new Map();
        for (const x of scored) {
            if (x.item === top) continue;
            const g = groups.get(x.item.group) ?? [];
            if (g.length < 6) g.push(x.item);
            groups.set(x.item.group, g);
        }
        for (const [name, items] of groups) {
            out.push({ header: name });
            for (const item of items) out.push({ item, crumb: crumb(item) });
        }

        if (!prefixed) out.push({ header: "Web" }, { item: webItem(Settings.s.web.default, raw) });
        return out;
    }

    // Files mode: pinned and recently opened files until something is typed
    function fileRows(raw, q) {
        if (!q) {
            const keys = History.pins.concat(History.recent()).filter(k => k.startsWith("file:"));
            return keys.filter((k, n) => keys.indexOf(k) === n).slice(0, Settings.s.maxRows).map(k => ({ item: fromKey(k) }));
        }
        const scored = [];
        scoreFiles(raw, q, Fuzzy.normalize(Fuzzy.swapLayout(raw)), scored, true);
        scored.sort((a, b) => b.score - a.score);
        return scored.map(x => ({ item: x.item }));
    }

    // Files: below other results of the same score, deeper ones lower. Pinned files always
    // take part; the index only when `all`
    function scoreFiles(raw, q, alt, scored, all) {
        if (q.length < 2) return;
        const key = fileQueries(raw).join("\n");
        const dotQuery = raw.trim().startsWith(".");
        const seen = {};
        const cands = [];
        for (const k of History.pins) if (k.startsWith("file:")) cands.push(fromKey(k));
        if (Files.enabled && all) {
            for (const x of Files.live) cands.push(fileItem(x.path, x.dir));
            if (Files.foundFor === key) for (const x of Files.found) cands.push(fileItem(x.path, x.dir));
        }
        for (const i of cands) {
            if (seen[i.key]) continue;
            seen[i.key] = true;
            if (!dotQuery && i.path.includes("/.")) continue;
            const fields = [[i.nTitle, 1], [i.nKeywords, 0.9, 700]];
            let s = Fuzzy.scoreFields(q, fields);
            if (alt !== q) s = Math.max(s, 0.97 * Fuzzy.scoreFields(alt, fields));
            if (s <= 0) continue;
            // A whole-name match deep in a project tree loses to a word match in ~ or ~/Downloads
            s = 0.9 * Math.min(s, 850) - Math.min(15 * (i.depth - 1), 150) + History.frecency(i.key) + History.memory(i.key, q);
            if (History.pinned(i.key)) s += 2000;
            scored.push({ item: i, score: s });
        }
    }

    readonly property var emptyNames: ({ pinned: "Pinned", recent: "Recent", popular: "Frequent" })

    function emptyRows() {
        const out = [];
        const used = {};
        for (const sec of Settings.emptyView) {
            const keys = sec === "pinned" ? History.pins : sec === "recent" ? History.recent() : sec === "popular" ? History.popular() : [];
            const max = sec === "pinned" ? Settings.s.maxRows : 5;
            const items = [];
            for (const k of keys) {
                if (items.length >= max) break;
                const i = used[k] ? null : fromKey(k);
                if (!i) continue;
                used[k] = true;
                items.push(i);
            }
            if (!items.length) continue;
            out.push({ header: emptyNames[sec] });
            for (const item of items) out.push({ item, crumb: crumb(item) });
        }
        return out;
    }

    function fileQueries(raw) {
        const words = s => s.toLowerCase().trim().split(/\s+/).join(" ");
        return [words(raw), words(Fuzzy.swapLayout(raw))].filter((x, n, a) => a.indexOf(x) === n);
    }

    function setQuery(q) {
        const pf = !prompt && !folder ? prefixFolder(q) : null;
        if (pf) {
            enter(byKey[pf.key]);
            savedQuery[pf.key] = "";
            q = pf.rest;
        }
        query = q;
        // The field still shows the prefix when the query itself did not change (">" typed first)
        if (pf) queryReplaced();
        confirmKey = "";
        listMode = false;
        if (!prompt && (folder?.key === "files" || (!folder && Files.inline))) Files.search(fileQueries(q));
        refresh(false);
        if (!prompt && !folder && looksLikeMath(q.trim())) calcTimer.restart();
    }

    // Folders behind a prefix. A word prefix needs a space after it and also works in the other
    // layout ("f " / "а "); a web engine with that name wins. A symbol prefix works at once (":fire").
    function prefixFolder(q) {
        const words = [["files", Files.prefix], ["clipboard", Clipboard.prefix]];
        const m = q.match(/^\s*(\S+)\s/);
        if (m && !engines[m[1]])
            for (const [key, p] of words)
                if (p && byKey[key] && (m[1] === p || Fuzzy.swapLayout(m[1]) === p))
                    return { key, rest: q.slice(m[0].length) };
        for (const [key, p] of symbolPrefixes())
            if (p && byKey[key] && q.startsWith(p)) return { key, rest: q.slice(p.length).replace(/^\s+/, "") };
        return null;
    }

    function symbolPrefixes() {
        return [["command", commandPrefix], ["emoji", Emoji.prefix]];
    }

    // ------------------------------------------------------------------ keys

    // Keys of the search field; true = handled. `atEnd`: the text cursor is at the end.
    function onKey(k, mods, atEnd, empty) {
        const ctrl = mods & Qt.ControlModifier;
        if (!shown) return true;   // closing: swallow everything until the window is gone
        if (k === Qt.Key_Space && !mods && listMode && !prompt && previewable(current)) {
            previewOpen = !previewOpen;
            return true;
        }
        if (k === Qt.Key_Escape) {
            // Out of a preview, prompt, menu or folder first; close from the top
            if (!previewOpen && !prompt && stack.length <= baseDepth) close();
            else if (!back()) close();
        } else if (k === Qt.Key_Down || (ctrl && k === Qt.Key_J) || (ctrl && k === Qt.Key_N)) {
            move(1);
        } else if (k === Qt.Key_Up || (ctrl && k === Qt.Key_K)) {
            move(-1);
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            activate(null, mods & Qt.AltModifier);
        } else if (ctrl && k === Qt.Key_P) {
            togglePin(current);
        } else if ((ctrl && k === Qt.Key_O) || (k === Qt.Key_Right && atEnd && !prompt)) {
            return openActions();
        } else if (k === Qt.Key_Tab) {
            // In the command folder Tab completes the query with the selected command
            if (folder?.key === "command" && current?.kind === "cmd") setQuery(current.command + " ");
            else enter(current);
        } else if (k === Qt.Key_Backspace && empty) {
            back();
        } else {
            return false;
        }
        return true;
    }

    // The same from IPC, for scripts and tests: "esc", "down", "ctrl+o", "alt+enter"…
    function pressKey(name) {
        const keys = { esc: Qt.Key_Escape, tab: Qt.Key_Tab, enter: Qt.Key_Return, up: Qt.Key_Up, down: Qt.Key_Down,
            left: Qt.Key_Left, right: Qt.Key_Right, space: Qt.Key_Space, backspace: Qt.Key_Backspace };
        const parts = name.toLowerCase().split("+");
        const last = parts.pop();
        let mods = 0;
        for (const m of parts) mods |= m === "ctrl" ? Qt.ControlModifier : m === "alt" ? Qt.AltModifier : m === "shift" ? Qt.ShiftModifier : 0;
        const k = keys[last] ?? (last.length === 1 ? last.toUpperCase().charCodeAt(0) : 0);
        return onKey(k, mods, true, !query);
    }

    // ------------------------------------------------------------------ actions menu

    // → or Ctrl+O on a result: what else can be done with it. A menu is a folder on the stack
    // like a plugin menu, so Esc and Backspace lead back.
    function openActions(item) {
        item = item ?? current;
        if (!item || prompt || item.kind === "action" || item.key.startsWith("menu:")) return false;
        const acts = actionsFor(item);
        if (!acts.length) return false;
        showMenu(item.title, acts);
        return true;
    }

    function showMenu(title, acts) {
        const key = "menu:" + (++menuSeq);
        const menu = make({ key, kind: "folder", folder: true, title, ancestors: [] });
        menuItems = menuItems.concat([menu], acts.map((a, n) => make(Object.assign({
            key: key + ":" + n, kind: "action", group: "Actions", ancestors: [key], order: n, iconType: "glyph"
        }, a))));
        savedQuery[key] = query;
        stack = stack.concat([key]);
        query = "";
        rebuild();
    }

    function copyText(t) {
        Quickshell.execDetached(["wl-copy", "--", t]);
    }

    function inTerminal(dir) {
        Quickshell.execDetached(["sh", "-c", 'cd "$1" || exit; shift; exec "$@"', "sh", dir]
            .concat(Settings.s.launchPrefix ?? [], Settings.s.terminal ?? ["kitty", "-e"], [Quickshell.env("SHELL") || "sh"]));
    }

    function actionsFor(i) {
        const a = [];
        const add = (title, icon, run, extra) => a.push(Object.assign({ title, icon, run }, extra ?? {}));
        const close = { closes: true };
        // The item's own action runs where the item was, not inside the menu
        const main = (title, icon) => add(title, icon, () => { back(); activate(i); return "stay"; });
        switch (i.kind) {
        case "file":
            main("Open", i.dir ? "\uf07c" : "\uf15b");
            if (!i.dir) add("Open with…", "\uf1b2", () => { openWith(i); return "stay"; });
            add("Show in folder", "\uf07b", () => showInFolder(i.path), close);
            if (i.dir) add("Open in terminal", "\uf120", () => inTerminal(i.path), close);
            add("Copy path", "\uf0c5", () => copyText(i.path), close);
            add("Copy name", "\uf0c5", () => copyText(i.title), close);
            add("Move to trash", "\uf1f8", () => {
                Quickshell.execDetached(["gio", "trash", "--", i.path]);
                delete fileCache[i.key];
            }, { confirm: true, keywords: "delete remove" });
            break;
        case "app":
            main("Open", "\uf04b");
            add("Hide from results", "\uf070", () => Settings.set(["hidden"], (Settings.s.hidden ?? []).concat([i.key])),
                { keywords: "remove" });
            break;
        case "clip":
            main("Copy", "\uf0c5");
            add(i.entry.pinned ? "Unpin" : "Pin", "\uf08d", () => Clipboard.edit(i.entry, "pin"));
            add("Delete from history", "\uf1f8", () => Clipboard.edit(i.entry, "delete"), { keywords: "remove" });
            break;
        case "calc":
            main("Copy result", "\uf0c5");
            add("Copy as equation", "\uf0c5", () => copyText(calc.query + " = " + i.title), close);
            break;
        case "cmd":
            main("Run in terminal", "\uf120");
            if (History.items["cmd:" + i.command])
                add("Remove from history", "\uf1f8", () => { History.forget(i.key); refresh(true); }, { keywords: "delete forget" });
            break;
        case "emoji":
            main("Copy", "\uf0c5");
            add("Copy name", "\uf0c5", () => copyText(i.title), close);
            break;
        case "web":
            main("Open", "\uf0ac");
            add("Copy link", "\uf0c1", () => copyText(i.url), close);
            break;
        default:
            if (i.folder) add("Open", "\uf07c", () => { back(); enter(i); return "stay"; });
            else main("Run", "\uf04b");
        }
        if (pinnable(i)) add(History.pinned(i.key) ? "Unpin" : "Pin", "\uf08d", () => togglePin(i), { keywords: "favorite" });
        return a;
    }

    // Applications registered for the file's type, the default first
    function openWith(i) {
        openWithProc.path = i.path;
        openWithProc.title = i.title;
        openWithProc.running = true;
    }

    Process {
        id: openWithProc
        property string path
        property string title
        command: ["sh", "-c", 't=$(gio info -a standard::content-type -- "$1" | sed -n "s/^ *standard::content-type: //p"); ' +
            'gio mime "$t" 2>/dev/null | sed -n "s/^Default application.*: //p; /^Registered applications:/,/^\$/s/^\t//p; /^Recommended applications:/,/^\$/s/^\t//p"',
            "sh", path]
        stdout: StdioCollector {
            onStreamFinished: {
                const ids = [...new Set(text.split("\n").map(x => x.trim().replace(/\.desktop$/, "")).filter(x => x))];
                const acts = [];
                for (const id of ids) {
                    const e = DesktopEntries.byId(id);
                    if (!e) continue;
                    acts.push({ title: e.name, icon: e.icon, iconType: "theme", glyph: "\uf2d0", closes: true,
                        run: () => root.launch((Settings.s.launchPrefix ?? []).length
                            ? [id + ".desktop", openWithProc.path] : ["gtk-launch", id, openWithProc.path]) });
                }
                if (root.shown && acts.length) root.showMenu("Open " + openWithProc.title + " with", acts);
            }
        }
    }

    // ------------------------------------------------------------------ calculator

    function looksLikeMath(s) {
        if (s.startsWith("=")) return s.length > 1;
        if (!/\d/.test(s)) return false;
        if (/^[\d\s.,+\-*\/^%()]+$/.test(s)) return /[+\-*\/^%]/.test(s.replace(/^-/, ""));
        if (/^[$€£¥₽]?-?[\d.,]+\s*\S+(\s+\S+)?\s+(to|in)\s+\S+/i.test(s)) return true;
        return /^[a-z]+\(.*\d/i.test(s);
    }

    // "5 km in mi" -> "5 km to -mi": qalc reads "in" as inches, and "-" turns off
    // mixed units ("3 mi + 188 yd + …")
    function qalcExpr(s) {
        return s.replace(/^=/, "").replace(/\s+(?:to|in|->|→)\s+(?!\+)-?/i, " to -");
    }

    Timer {
        id: calcTimer
        interval: 90
        onTriggered: {
            if (calcProc.running) calcProc.running = false;
            calcProc.expr = root.query.trim();
            calcProc.command = ["qalc", "-t", "--", root.qalcExpr(calcProc.expr)];
            calcProc.running = true;
        }
    }

    Process {
        id: calcProc
        property string expr
        stdout: StdioCollector {
            onStreamFinished: {
                const r = text.trim().split("\n")[0] ?? "";
                const same = r.replace(/\s/g, "") === calcProc.expr.replace(/^=|\s/g, "");
                root.calc = r && !same && /\d/.test(r) && !/error/i.test(r) ? { query: calcProc.expr, result: r } : null;
                if (root.calc && root.isMoney(calcProc.expr + " " + r)) root.checkRates();
                if (root.shown && root.query.trim() === calcProc.expr) root.refresh(false);
            }
        }
    }

    // Exchange rates: qalc keeps whatever it downloaded last (could be months old). On a money
    // query, rates older than a day are fetched in the background and the result recomputed.
    readonly property string ratesFile: Quickshell.env("HOME") + "/.local/share/qalculate/eurofxref-daily.xml"
    property string ratesDate: ""
    property real ratesCheckedAt: 0

    function isMoney(s) {
        return /[$€£¥₽₴₹₩₺₿]|\b(usd|eur|rub|gbp|jpy|cny|uah|pln|byn|kzt|chf|try|czk|sek|nok|dkk|huf|ron|bgn|cad|aud|nzd|inr|krw|brl|mxn|ils|aed|gel|amd|btc)\b/i.test(s);
    }

    function checkRates() {
        if (ratesProc.running || Date.now() - ratesCheckedAt < 3600 * 1000) return;
        ratesCheckedAt = Date.now();
        ratesProc.running = true;
    }

    Process {
        id: ratesProc
        // Prints "<date> <updated: 1|0>"
        command: ["sh", "-c", 'f="$1"; u=0; if [ -z "$(find "$f" -mmin -1440 2>/dev/null)" ]; then ' +
            'timeout 20 qalc -e >/dev/null 2>&1 </dev/null && u=1; fi; echo "$(date -r "$f" +%F 2>/dev/null) $u"', "sh", root.ratesFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const [date, updated] = text.trim().split(" ");
                root.ratesDate = date ?? "";
                if (updated === "1" && root.calc) calcTimer.restart();
                else if (root.shown) root.refresh(true);
            }
        }
    }

    // ------------------------------------------------------------------ navigation

    function move(d) {
        listMode = true;
        if (!rows.length) return;
        let i = sel;
        do i += d; while (i >= 0 && i < rows.length && !rows[i].item);
        if (i >= 0 && i < rows.length) select(i);
    }

    function select(i) {
        sel = i;
        userMoved = true;
        confirmKey = "";
    }

    function enter(item) {
        if (!item?.folder) return false;
        savedQuery[item.key] = query;
        stack = stack.filter(k => !k.startsWith("menu:")).concat([item.key]);
        pluginOf(item.key)?.list(2);   // statuses are what a folder is opened for
        if (item.key === "files") {
            Files.open();
            Files.search([""]);
        }
        if (item.key === "clipboard") Clipboard.load();
        if (item.key === "command" && !pathProc.running) pathProc.running = true;
        if (item.key === "emoji") Emoji.load();
        query = "";
        refresh(false);
        return true;
    }

    function back() {
        if (previewOpen) { previewOpen = false; return true; }
        if (prompt) { prompt = null; query = ""; refresh(false); return true; }
        if (!stack.length) return false;
        const top = stack[stack.length - 1];
        stack = stack.slice(0, -1);
        if (top.startsWith("menu:")) {
            menuItems = menuItems.filter(i => i.key !== top && !i.ancestors.includes(top));
            rebuild();
        }
        query = savedQuery[top] ?? "";
        delete savedQuery[top];
        refresh(false);
        return true;
    }

    // ------------------------------------------------------------------ actions

    function launch(cmd) {
        Quickshell.execDetached((Settings.s.launchPrefix ?? []).concat(cmd));
    }

    function openPath(target) {
        launch((Settings.s.opener ?? ["xdg-open"]).concat([target]));
    }

    function activate(item, alt) {
        if (prompt) return answerPrompt();
        item = item ?? current;
        if (!item) return;
        if (item.folder) { History.record(item.key, Fuzzy.normalize(query)); enter(item); return; }
        if (item.action === "back") { back(); return; }
        if (item.confirm && confirmKey !== item.key) { confirmKey = item.key; return; }

        if (item.kind !== "clip" && item.kind !== "action") History.record(item.key, Fuzzy.normalize(query));
        switch (item.kind) {
        case "action":
            if (item.run() === "stay") return;
            if (!item.closes) { back(); return; }
            break;
        case "clip":
            Clipboard.copy(item.entry);
            break;
        case "cmd":
            runCommand(item.command);
            break;
        case "emoji":
            copyText(item.icon);
            break;
        case "file":
            if (alt) showInFolder(item.path);
            else openPath(item.path);
            break;
        case "setting":
            item.run?.();
            if (!item.closes) return;
            break;
        case "app":
            if ((Settings.s.launchPrefix ?? []).length) launch([item.entry.id + ".desktop"]);
            else item.entry.execute();
            break;
        case "power":
            Quickshell.execDetached(item.command);
            break;
        case "web":
            openPath(item.url);
            break;
        case "calc":
            Quickshell.execDetached(["wl-copy", "--", item.title]);
            break;
        case "plugin":
            runPlugin(item.plugin, item.id, undefined, item.title, item.key);
            if (!item.closes) return;
            break;
        }
        close();
    }

    function runPlugin(p, id, input, title, key) {
        busyKey = key ?? "";
        p.run(id, input, lines => {
            busyKey = "";
            handleRun(p, lines, title);
        });
    }

    function handleRun(p, lines, title) {
        if (lines.some(l => l.type === "close")) { close(); return; }
        const pr = lines.find(l => l.type === "prompt");
        if (pr) {
            prompt = { plugin: p, id: pr.id, title: pr.title ?? title, message: pr.message ?? "", password: !!pr.password };
            query = "";
            refresh(false);
            return;
        }
        const entries = lines.filter(l => !l.type && l.id !== undefined);
        const menus = stack.filter(k => k.startsWith("menu:"));
        if (menus.length) query = savedQuery[menus[0]] ?? "";
        clearMenus();
        stack = stack.filter(k => !k.startsWith("menu:"));
        if (entries.length) {
            const head = lines.find(l => l.type === "menu");
            const key = "menu:" + (++menuSeq);
            const menu = make({ key, kind: "folder", folder: true, title: head?.title ?? title, ancestors: [] });
            menuItems = [menu].concat(entries.map((r, n) =>
                make(pluginEntry(p, r, key + ":" + n, [key], n))));
            savedQuery[key] = query;
            stack = stack.concat([key]);
            query = "";
        }
        p.list();   // refresh statuses; rebuild() keeps the selection
        rebuild();
    }

    function answerPrompt() {
        const pr = prompt;
        const text = query;
        prompt = null;
        query = "";
        refresh(false);
        runPlugin(pr.plugin, pr.id, text, pr.title);
    }

    function clearMenus() {
        if (!menuItems.length) return;
        menuItems = [];
        rebuildTimer.restart();
    }
}
