// Clipboard history kept by clipse (https://github.com/savedra1/clipse): read when the folder
// opens, copied back with wl-copy. Nothing runs while the window is closed.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool enabled: Settings.s.clipboard?.enabled ?? true
    readonly property string prefix: Settings.s.clipboard?.prefix ?? "v"
    readonly property string file: Settings.expand(Settings.s.clipboard?.file ?? "~/.config/clipse/clipboard_history.json")
    readonly property bool available: enabled && exists

    property bool exists: false
    property var entries: []     // { text, image, time, pinned }

    signal updated()

    function load() {
        if (enabled) view.reload();
    }

    function parse(text) {
        let list = [];
        try {
            list = JSON.parse(text).clipboardHistory ?? [];
        } catch (e) {
            console.warn("quickseek: clipboard:", e);
        }
        entries = list.map(e => {
            const image = e.filePath && e.filePath !== "null" ? e.filePath : "";
            return {
                text: image ? "" : e.value ?? "",
                image,
                // "2026-11-13 14:09:55.187053232" -> ms
                time: Date.parse((e.recorded ?? "").slice(0, 23).replace(" ", "T")) || 0,
                pinned: !!e.pinned,
                recorded: e.recorded ?? ""
            };
        });
        updated();
    }

    // Edits go straight into clipse's file; clipse reads it anew on every copy
    function edit(entry, change) {
        let d;
        view.reload();   // clipse may have written since the folder opened
        try {
            d = JSON.parse(view.text());
        } catch (e) {
            return;
        }
        const list = d.clipboardHistory ?? [];
        const n = list.findIndex(e => (e.recorded ?? "") === entry.recorded);
        if (n < 0) return;
        if (change === "delete") list.splice(n, 1);
        else list[n].pinned = !list[n].pinned;
        const text = JSON.stringify(d);
        view.setText(text);
        parse(text);
    }

    function copy(entry) {
        if (entry.image)
            Quickshell.execDetached(["sh", "-c", 'exec wl-copy --type image/png < "$1"', "sh", entry.image]);
        else
            Quickshell.execDetached(["wl-copy", "--", entry.text]);
    }

    // "now", "5 min", "3 h", "yesterday", "12 Nov"
    function age(t) {
        const s = (Date.now() - t) / 1000;
        if (s < 60) return "now";
        if (s < 3600) return Math.floor(s / 60) + " min";
        if (s < 86400) return Math.floor(s / 3600) + " h";
        if (s < 2 * 86400) return "yesterday";
        return new Date(t).toLocaleDateString(Qt.locale("en_GB"), "d MMM");
    }

    FileView {
        id: view
        path: root.enabled ? root.file : ""
        printErrors: false
        blockLoading: true
        atomicWrites: true
        onLoaded: { root.exists = true; root.parse(text()); }
        onLoadFailed: { root.exists = false; root.entries = []; root.updated(); }
    }
}
