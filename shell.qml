// quickseek: one search box for apps, settings, plugins, math and the web.
// Runs as a daemon; the window exists only while it is open.
//   qs -p <this dir> -n                       start the daemon
//   qs -p <this dir> ipc call quickseek toggle
//   Hyprland: bind a key to the global shortcut "quickseek:toggle"
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    GlobalShortcut {
        // A second copy (development) needs another id: Hyprland rejects a taken shortcut
        appid: Quickshell.env("QUICKSEEK_APPID") || "quickseek"
        name: "toggle"
        description: "Open or close quickseek"
        onPressed: Engine.toggle()
    }

    IpcHandler {
        target: "quickseek"
        function toggle(): void { Engine.toggle(); }
        function open(): void { Engine.open(); }
        function close(): void { Engine.close(); }
        // Open straight into a folder, e.g. "plugin:cc" or "plugin:cc:wifi"
        function folder(key: string): void { Engine.open(key); }
        function search(text: string): void { Engine.open(); Engine.setQuery(text); }
        // A key as if pressed in the window: "esc", "down", "ctrl+o"… (scripts and tests)
        function key(name: string): bool { return Engine.pressKey(name); }
        // Replace the text of the open window's field, as if typed
        function type(text: string): void { Engine.typeRequested(text); }
        // What the search field shows
        function field(): string { return Engine.fieldText; }
        // What the window shows, for scripts and tests: folder, query, then one row per line
        function rows(): string {
            return [`${Engine.folder?.key ?? ""}\t${Engine.query}`].concat(Engine.rows.map((r, n) =>
                r.header ? "# " + r.header : `${n === Engine.sel ? ">" : " "} ${r.item.title}\t${r.item.status ?? ""}`)).join("\n");
        }
    }

    LazyLoader {
        active: Engine.mapped
        SeekWindow {}
    }

    Component.onCompleted: History.items
}
