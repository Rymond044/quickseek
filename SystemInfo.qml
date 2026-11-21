pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var sample: null
    property real sampledAt: 0
    property real now: Date.now()
    property bool active: false
    onActiveChanged: if (active) load()
    signal updated()

    function load() {
        if (!reader.running) reader.running = true;
    }
    function duration(seconds) {
        const n = Math.max(0, Math.floor(seconds));
        return (n >= 86400 ? Math.floor(n / 86400) + "d " : "")
            + Math.floor(n % 86400 / 3600) + "h " + Math.floor(n % 3600 / 60) + "m";
    }
    function values() {
        const delta = Math.max(0, (now - sampledAt) / 1000);
        return [
            ["elapsed", "Time since boot", sample ? duration(sample.elapsed + delta) : "Loading…", "uptime boot including sleep"],
            ["boot", "Boot time", sample ? new Date(sample.bootTime * 1000).toLocaleString(Qt.locale(), "yyyy-MM-dd HH:mm:ss") : "Loading…", "boot date started"],
            ["awake", "Awake time", sample ? duration(sample.awake + delta) : "Loading…", "awake active excluding sleep"],
            ["session", "Session duration", !sample ? "Loading…" : sample.session === null ? "Unavailable" : duration(sample.session + delta), "graphical session login duration including sleep"]
        ];
    }
    Timer {
        interval: 60000
        repeat: true
        running: root.active
        onTriggered: root.load()
    }
    Process {
        id: reader
        command: ["python3", Qt.resolvedUrl("bin/quickseek-system-info").toString().replace(/^file:\/\//, "")]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.sample = JSON.parse(text); } catch (e) { root.sample = null; }
                root.sampledAt = Date.now();
                root.now = root.sampledAt;
                root.updated();
            }
        }
    }
}
