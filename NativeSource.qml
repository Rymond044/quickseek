// Base of the built-in sources a plugin can mount as a folder ("source": "audio"), see docs/plugins.md.
// Instances exist only while the window is open (shell.qml), so nothing listens in the background.
import QtQuick
import Quickshell

Scope {
    id: src

    required property string name
    property string status: ""
    // [{ id, title, status, icon, iconType, keywords, parent, folder, confirm, close, run }]
    property var items: []

    // Changes come in bursts (PipeWire announces nodes one by one): one update per burst
    function publish() {
        Engine.setNative(name, status, items);
    }

    onStatusChanged: burst.restart()
    onItemsChanged: burst.restart()
    Timer { id: burst; interval: 40; onTriggered: src.publish() }
    Component.onCompleted: publish()
    Component.onDestruction: Engine.setNative(name)
}
