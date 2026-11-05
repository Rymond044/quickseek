import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

PanelWindow {
    id: win

    readonly property int barHeight: 54
    readonly property int headerHeight: 26
    readonly property int rowHeight: 40
    readonly property int maxListHeight: Settings.s.maxRows * rowHeight + 2 * headerHeight + 8

    screen: Quickshell.screens.find(s => s.name === Engine.screenName) ?? Quickshell.screens[0]
    anchors.top: true
    margins.top: Math.round((screen?.height ?? 900) * 0.2)
    implicitWidth: Math.min(Settings.s.width, (screen?.width ?? 1000) - 32)
    implicitHeight: barHeight + maxListHeight + 2
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickseek"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    mask: Region { item: plate }

    HyprlandFocusGrab {
        windows: [win]
        active: Engine.shown
        onCleared: Engine.close()
    }

    function listHeight() {
        let h = 0;
        for (const r of Engine.rows) h += r.header ? headerHeight : rowHeight;
        return h ? Math.min(h + 8, maxListHeight) : 0;
    }

    Rectangle {
        id: plate
        width: parent.width
        height: win.barHeight + win.listHeight()
        radius: 16
        color: Qt.alpha(Theme.background, Settings.s.opacity)
        border.width: 1
        border.color: Theme.border
        clip: true
        transformOrigin: Item.Top

        opacity: 0
        scale: 0.96
        Behavior on height { SpringAnimation { spring: 5; damping: 0.42; epsilon: 0.5 } }

        states: State {
            name: "open"
            when: Engine.shown && win.ready
            PropertyChanges { plate.opacity: 1; plate.scale: 1 }
        }
        transitions: [
            Transition {
                to: "open"
                NumberAnimation { properties: "opacity,scale"; duration: 150; easing.type: Easing.OutCubic }
            },
            Transition {
                from: "open"
                SequentialAnimation {
                    NumberAnimation { properties: "opacity,scale"; duration: 100; easing.type: Easing.InCubic }
                    ScriptAction { script: Engine.mapped = false }
                }
            }
        ]

        SearchBar {
            id: bar
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: win.barHeight
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: bar.bottom }
            height: 1
            color: Theme.border
            visible: Engine.rows.length > 0
        }

        Results {
            anchors { left: parent.left; right: parent.right; top: bar.bottom; bottom: parent.bottom; topMargin: 4 }
            headerHeight: win.headerHeight
            rowHeight: win.rowHeight
        }
    }

    // The first frame shows the start state, then animates to "open"
    property bool ready: false
    Component.onCompleted: Qt.callLater(() => ready = true)
    Connections {
        target: Engine
        function onShownChanged() { if (!Engine.shown && !win.ready) Engine.mapped = false; }
    }
}
