// One external plugin, see docs/plugins.md for the protocol.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: plugin

    required property var config    // { id, name, icon, command: [...] }
    readonly property string pid: config.id ?? config.name
    readonly property var command: (config.command ?? []).map(Settings.expand)

    property var items: []
    property bool loading: lister.running
    property bool stale: false

    function parseLines(text) {
        const out = [];
        for (const line of text.split("\n")) {
            if (!line.trim()) continue;
            try {
                out.push(JSON.parse(line));
            } catch (e) {
                console.warn("quickseek:", pid, "bad line:", line);
            }
        }
        return out;
    }

    function list() {
        if (lister.running) { stale = true; return; }
        lister.running = true;
    }

    // done(lines) gets the parsed output of `run`.
    function run(id, input, done) {
        const env = input === undefined ? {} : { QUICKSEEK_INPUT: input };
        runner.createObject(plugin, { command: command.concat(["run", id]), environment: env, done: done });
    }

    Process {
        id: lister
        command: plugin.command.concat(["list"])
        stdout: StdioCollector {
            onStreamFinished: {
                plugin.items = plugin.parseLines(text);
                if (plugin.stale) { plugin.stale = false; plugin.list(); }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) console.warn("quickseek:", plugin.pid, text.trim())
        }
    }

    Component {
        id: runner
        Process {
            id: proc
            property var done
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    proc.done?.(plugin.parseLines(text));
                    proc.destroy();
                }
            }
        }
    }
}
