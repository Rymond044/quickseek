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
        for (const p of plugins) p.list();
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
        let list = appItems().concat(powerItems());
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
        if (!q) return f ? childrenOf(f).map(item => ({ item })) : [];

        const alt = Fuzzy.normalize(Fuzzy.swapLayout(raw));
        const scored = [];
        for (const i of all) {
            if (f ? !i.ancestors.includes(f.key) : i.ancestors.some(a => a.startsWith("menu:"))) continue;
            const fields = [[i.nTitle, 1], [i.nKeywords, 0.7, 700]];   // descriptions: word starts only
            let s = Fuzzy.scoreFields(q, fields);
            if (alt !== q) s = Math.max(s, 0.97 * Fuzzy.scoreFields(alt, fields));
            if (s <= 0) continue;
            s += History.frecency(i.key) + History.memory(i.key, q);
            scored.push({ item: i, score: s });
        }
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

    function setQuery(q) {
        query = q;
        confirmKey = "";
        refresh(false);
        if (!prompt && !folder && looksLikeMath(q.trim())) calcTimer.restart();
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

    function activate(item, alt) {
        if (prompt) return answerPrompt();
        item = item ?? current;
        if (!item) return;
        if (item.folder) { History.record(item.key, Fuzzy.normalize(query)); enter(item); return; }
        if (item.action === "back") { back(); return; }
        if (item.confirm && confirmKey !== item.key) { confirmKey = item.key; return; }

        History.record(item.key, Fuzzy.normalize(query));
        switch (item.kind) {
        case "app":
            if ((Settings.s.launchPrefix ?? []).length) launch([item.entry.id + ".desktop"]);
            else item.entry.execute();
            break;
        case "power":
            Quickshell.execDetached(item.command);
            break;
        case "web":
            launch(["xdg-open", item.url]);
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
