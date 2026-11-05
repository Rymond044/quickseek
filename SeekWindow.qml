import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick.Effects

PanelWindow {
    id: win

    readonly property int barHeight: 60
    readonly property int headerHeight: 28
    readonly property int rowHeight: 44
    readonly property int bigRowHeight: 56
    readonly property int maxListHeight: Settings.s.maxRows * rowHeight + 2 * headerHeight + 12
    // Room around the plate for the shadow
    readonly property int pad: Settings.s.shadow ? 28 : 0

    screen: Quickshell.screens.find(s => s.name === Engine.screenName) ?? Quickshell.screens[0]
    anchors.top: true
    margins.top: Math.round((screen?.height ?? 900) * 0.2) - pad
    implicitWidth: Math.min(Settings.s.width, (screen?.width ?? 1000) - 32) + 2 * pad
    implicitHeight: barHeight + maxListHeight + 2 + 2 * pad
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
        for (const r of Engine.rows) h += r.header ? headerHeight : r.big ? bigRowHeight : rowHeight;
        return h ? Math.min(h + 12, maxListHeight) : 0;
    }

    RectangularShadow {
        visible: Settings.s.shadow
        anchors.fill: plate
        radius: plate.radius
        offset.y: 8
        blur: 24
        spread: -2
        color: Theme.shadow
        opacity: plate.opacity
        scale: plate.scale
        transformOrigin: Item.Top
    }

    Rectangle {
        id: plate
        x: win.pad
        y: win.pad
        width: parent.width - 2 * win.pad
        height: win.barHeight + win.listHeight()
        // A pill while there is only the search field, like Spotlight
        radius: Engine.rows.length ? 22 : win.barHeight / 2
        Behavior on radius { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
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
            anchors { left: parent.left; right: parent.right; top: bar.bottom; leftMargin: 16; rightMargin: 16 }
            height: 1
            color: Theme.border
            visible: Engine.rows.length > 0
        }

        Results {
            anchors { left: parent.left; right: parent.right; top: bar.bottom; bottom: parent.bottom; topMargin: 2; bottomMargin: 8 }
            headerHeight: win.headerHeight
            rowHeight: win.rowHeight
            bigRowHeight: win.bigRowHeight
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
