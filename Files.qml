// Files and folders: bin/quickseek-files searches a private plocate index of $HOME as you type,
// and lists Downloads, Desktop and Documents live on every open.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool enabled: Settings.s.files?.enabled ?? true
    // Files show up after the prefix ("f report"); `inline` mixes them into every search
    readonly property string prefix: Settings.s.files?.prefix ?? "f"
    readonly property bool inline: enabled && !!Settings.s.files?.inline
    readonly property string tool: Quickshell.shellPath("bin/quickseek-files")

    property var live: []        // [{ path, dir }]
    property var found: []
    property string foundFor: ""  // query `found` belongs to
    property string pending: ""

    signal updated()

    function open() {
        pending = "";
        if (!enabled) return;
        recentProc.running = false;
        recentProc.running = true;
    }

    // `queries`: the query and its wrong-layout twin
    function search(queries) {
        const key = queries.join("\n");
        if (!enabled || key === pending) return;
        pending = key;
        if (!queries.some(q => q.replace(/^\./, "").length >= 2)) {
            searchTimer.stop();
            searchProc.running = false;
            found = [];
            foundFor = key;
            return;
        }
        searchTimer.restart();
    }

    readonly property bool indexing: indexProc.running
    function rebuild() {
        indexProc.running = true;
    }

    Process {
        id: indexProc
        command: [root.tool, "index"]
        onExited: root.updated()
    }

    function parse(text) {
        const out = [];
        for (const line of text.split("\n")) {
            if (line[1] !== "\t") continue;
            out.push({ dir: line[0] === "d", path: line.slice(2) });
        }
        return out;
    }

    Timer {
        id: searchTimer
        interval: 60
        onTriggered: {
            searchProc.running = false;
            searchProc.key = root.pending;
            searchProc.command = [root.tool, "search"].concat(root.pending.split("\n"));
            searchProc.running = true;
        }
    }

    Process {
        id: searchProc
        property string key
        stdout: StdioCollector {
            onStreamFinished: {
                if (searchProc.key !== root.pending) return;
                root.found = root.parse(text);
                root.foundFor = searchProc.key;
                root.updated();
            }
        }
    }

    Process {
        id: recentProc
        command: [root.tool, "recent"]
        stdout: StdioCollector {
            onStreamFinished: { root.live = root.parse(text); root.updated(); }
        }
    }
}
