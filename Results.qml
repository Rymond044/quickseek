import QtQuick
import Quickshell
import Quickshell.Widgets

ListView {
    id: list

    required property int headerHeight
    required property int rowHeight
    required property int bigRowHeight

    model: Engine.rows
    currentIndex: Engine.sel
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

    // Hover selects only when the pointer really moves, not when rows slide under a still cursor
    property point lastMouse: Qt.point(-1, -1)

    function esc(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // All items of one top-level section share a tile color
    function tintKey(i) {
        const a = i.ancestors ?? [];
        if (a.length >= 2) return a[a.length - 2];
        if (a.length === 1 || i.kind === "folder") return i.key;
        return i.kind;
    }

    // "" when the theme has no such icon: the row then falls back to a glyph tile
    function iconSource(name) {
        if (!name) return "";
        if (name.startsWith("/")) return "file://" + name;
        return Quickshell.iconPath(name, true);
    }

    delegate: Item {
        id: row
        required property var modelData
        required property int index
        readonly property var item: modelData.item ?? null
        readonly property bool big: !!modelData.big
        readonly property bool selected: index === Engine.sel

        width: list.width
        height: !item ? list.headerHeight : big ? list.bigRowHeight : list.rowHeight

        Text {
            visible: !row.item
            anchors { left: parent.left; leftMargin: 22; bottom: parent.bottom; bottomMargin: 5 }
            text: row.modelData.header ?? ""
            color: Theme.dim
            font { family: Settings.textFont; pointSize: Settings.s.fonts.size - 1.5; weight: Font.DemiBold }
        }

        Rectangle {
            id: bg
            visible: !!row.item
            anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 1; bottomMargin: 1 }
            radius: 12
            color: row.selected ? Theme.selection : hover.containsMouse ? Theme.surface : "transparent"
            Behavior on color { ColorAnimation { duration: 90 } }

            Item {
                id: icon
                readonly property int size: row.big ? 40 : 32
                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                width: size
                height: size

                IconImage {
                    id: image
                    readonly property bool ok: !!source.toString() && status !== Image.Error
                    anchors.fill: parent
                    visible: ok
                    source: row.item?.iconType === "theme" ? list.iconSource(row.item.icon) : ""
                    asynchronous: true
                }

                // Glyph icons sit on a tinted rounded tile, like settings icons
                Rectangle {
                    id: tile
                    visible: !image.ok
                    readonly property color tint: row.item ? Theme.tint(list.tintKey(row.item)) : Theme.accent
                    anchors.fill: parent
                    radius: Math.round(parent.size * 0.26)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(tile.tint, 1.3) }
                        GradientStop { position: 1; color: tile.tint }
                    }
                    border.width: 1
                    border.color: Qt.alpha("#ffffff", 0.12)
                    Text {
                        anchors.centerIn: parent
                        text: row.item?.iconType === "theme" ? "󰣆" : row.item?.icon ?? ""
                        color: "#ffffff"
                        font { family: Settings.s.fonts.icons; pixelSize: Math.round(icon.size * 0.5) }
                    }
                }
            }

            Text {
                id: status
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                width: Math.min(implicitWidth, parent.width * 0.4)
                elide: Text.ElideRight
                text: Engine.busyKey && row.item?.key === Engine.busyKey ? "…"
                    : Engine.confirmKey && row.item?.key === Engine.confirmKey ? "press ↵ again"
                    : row.item?.folder ? (row.item.status ? row.item.status + "  ›" : "›")
                    : row.item?.status ?? ""
                color: Engine.confirmKey && row.item?.key === Engine.confirmKey ? Theme.accent : Theme.dim
                font { family: Settings.textFont; pointSize: Settings.s.fonts.size }
            }

            Text {
                anchors { left: icon.right; leftMargin: 12; right: status.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: (row.modelData.crumb ? `<font color="${Theme.dim}">${list.esc(row.modelData.crumb)}  ›  </font>` : "")
                    + list.esc(row.item?.title ?? "")
                color: Theme.foreground
                font {
                    family: Settings.textFont
                    pointSize: Settings.s.fonts.size + (row.big ? 3 : 1)
                    weight: row.big ? Font.DemiBold : Font.Normal
                }
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            enabled: !!row.item
            hoverEnabled: true
            onPositionChanged: mouse => {
                const m = mapToItem(null, mouse.x, mouse.y);
                const p = Qt.point(Math.round(m.x / 4), Math.round(m.y / 4));   // ignore jitter from the open animation
                if (p.x === list.lastMouse.x && p.y === list.lastMouse.y) return;
                const first = list.lastMouse.x < 0;
                list.lastMouse = p;
                if (!first) Engine.select(row.index);
            }
            onClicked: Engine.activate(row.item)
        }
    }
}
