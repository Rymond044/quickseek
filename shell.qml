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
        appid: "quickseek"
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
    }

    LazyLoader {
        active: Engine.mapped
        SeekWindow {}
    }

    Component.onCompleted: History.items
}
