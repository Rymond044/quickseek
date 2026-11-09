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

    // ------------------------------------------------------------------ window

    function open(folderKey) {
        query = "";
        prompt = null;
        confirmKey = "";
        clearMenus();
        stack = folderKey && byKey[folderKey] ? [folderKey] : [];
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
        return DesktopEntries.applications.values.filter(e => !e.noDisplay).map(e => make({
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

    function powerItems() {
        const defs = [
            ["lock", "Lock", "󰌾", "screen", false],
            ["suspend", "Suspend", "󰤄", "sleep", false],
            ["reboot", "Restart", "󰜉", "reboot", true],
            ["shutdown", "Shut down", "󰐥", "power off poweroff", true],
            ["logout", "Log out", "󰍃", "exit sign out session", true]
        ];
        return defs.map(([id, title, icon, kw, confirm]) => make({
            key: "power:" + id,
            kind: "power",
            group: "System",
            title, icon, keywords: kw, confirm,
            iconType: "glyph",
            command: Settings.s.power[id]
        }));
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
        return !!i && !i.key.startsWith("menu:") && i.kind !== "web" && i.kind !== "calc";
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
        let list = appItems().concat(powerItems(), filesFolder(), settingsItems());
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
            top = make({ key: "calc", kind: "calc", group: "Calculator", title: calc.result, status: "copy", icon: "󰃬", iconType: "glyph" });
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
        if (!prompt && !folder && filePrefix(q)) {
            const rest = q.replace(/^\s*\S+\s+/, "");
            enter(byKey["files"]);
            savedQuery["files"] = "";
            q = rest;
        }
        query = q;
        confirmKey = "";
        if (!prompt && (folder?.key === "files" || (!folder && Files.inline))) Files.search(fileQueries(q));
        refresh(false);
        if (!prompt && !folder && looksLikeMath(q.trim())) calcTimer.restart();
    }

    // "f " or the same key in the other layout ("а "); a web engine with that name wins
    function filePrefix(q) {
        const m = q.match(/^\s*(\S+)\s/);
        if (!m || !byKey["files"] || !Files.prefix || engines[m[1]]) return false;
        return m[1] === Files.prefix || Fuzzy.swapLayout(m[1]) === Files.prefix;
    }

    // ------------------------------------------------------------------ calculator

    function looksLikeMath(s) {
        if (s.startsWith("=")) return s.length > 1;
        if (!/\d/.test(s)) return false;
        if (/^[\d\s.,+\-*\/^%()]+$/.test(s)) return /[+\-*\/^%]/.test(s.replace(/^-/, ""));
        if (/^-?[\d.,]+\s*\S+(\s+\S+)?\s+(to|in)\s+\S+/i.test(s)) return true;
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
                if (root.shown && root.query.trim() === calcProc.expr) root.refresh(false);
            }
        }
    }

    // ------------------------------------------------------------------ navigation

    function move(d) {
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
        query = "";
        refresh(false);
        return true;
    }

    function back() {
        if (prompt) { prompt = null; query = ""; refresh(false); return true; }
        if (!stack.length) return false;
        const top = stack[stack.length - 1];
        stack = stack.slice(0, -1);
        if (top.startsWith("menu:")) clearMenus();
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

        History.record(item.key, Fuzzy.normalize(query));
        switch (item.kind) {
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
