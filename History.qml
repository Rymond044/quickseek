// Frecency (how often and how recently an item was picked), query memory (which item was
// picked for a query) and pins. Stored in ~/.local/state/quickseek/history.json.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var items: ({})    // key -> { n: count, t: last pick (ms) }
    property var queries: ({})  // query -> { key: count }
    property var pins: []       // keys, in pin order

    function pinned(key) {
        return pins.includes(key);
    }

    function togglePin(key) {
        pins = pinned(key) ? pins.filter(k => k !== key) : pins.concat([key]);
        saveTimer.restart();
    }

    function unpinAll() {
        pins = [];
        saveTimer.restart();
    }

    // Keys, most recently / most often picked first
    function recent() {
        return Object.keys(items).sort((a, b) => items[b].t - items[a].t);
    }

    function popular() {
        return Object.keys(items).sort((a, b) => items[b].n - items[a].n || items[b].t - items[a].t);
    }

    function clear() {
        items = {};
        queries = {};
        saveTimer.restart();
    }

    function frecency(key) {
        const e = items[key];
        if (!e) return 0;
        const days = (Date.now() - e.t) / 86400000;
        const w = days < 4 ? 1 : days < 14 ? 0.7 : days < 31 ? 0.5 : 0.3;
        return Math.min(220, 60 * Math.log2(1 + e.n) * w);
    }

    // Bonus when this item was picked for the same query or for one this query starts.
    function memory(key, q) {
        if (!q) return 0;
        let best = 0;
        for (const past in queries) {
            if (!past.startsWith(q)) continue;
            const n = queries[past][key];
            if (n) best = Math.max(best, (past === q ? 300 : 150) * Math.min(1, n / 3));
        }
        return best;
    }

    function record(key, q) {
        const e = items[key] ?? { n: 0, t: 0 };
        items[key] = { n: e.n + 1, t: Date.now() };
        if (q) {
            const m = queries[q] ?? {};
            m[key] = (m[key] ?? 0) + 1;
            queries[q] = m;
        }
        saveTimer.restart();
    }

    function prune() {
        const keys = Object.keys(queries);
        if (keys.length > 2000)
            for (const k of keys.slice(0, keys.length - 2000)) delete queries[k];
    }

    Timer {
        id: saveTimer
        interval: 800
        onTriggered: {
            root.prune();
            file.setText(JSON.stringify({ items: root.items, queries: root.queries, pins: root.pins }));
        }
    }

    FileView {
        id: file
        path: Settings.stateDir + "/history.json"
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                const j = JSON.parse(text());
                root.items = j.items ?? {};
                root.queries = j.queries ?? {};
                root.pins = j.pins ?? [];
            } catch (e) {
                console.warn("quickseek: history", e);
            }
        }
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", Settings.stateDir, Settings.cacheDir])
}
