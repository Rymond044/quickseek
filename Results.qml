import QtQuick
import Quickshell
import Quickshell.Widgets

ListView {
    id: list

    required property int headerHeight
    required property int rowHeight

    model: Engine.rows
    currentIndex: Engine.sel
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

    // Hover selects only when the pointer really moves, not when rows slide under a still cursor
    property point lastMouse: Qt.point(-1, -1)

    delegate: Item {
        id: row
        required property var modelData
        required property int index
        readonly property var item: modelData.item ?? null
        readonly property bool selected: index === Engine.sel

        width: list.width
        height: item ? list.rowHeight : list.headerHeight

        Text {
            visible: !row.item
            anchors { left: parent.left; leftMargin: 20; bottom: parent.bottom; bottomMargin: 4 }
            text: row.modelData.header ?? ""
            color: Theme.faint
            font { family: Settings.s.fonts.text; pointSize: Settings.s.fonts.size - 2; weight: Font.DemiBold }
        }

        Rectangle {
            visible: !!row.item
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            radius: 10
            color: row.selected ? Theme.selection : hover.containsMouse ? Theme.surface : "transparent"

            readonly property color fg: row.selected ? Theme.onSelection : Theme.foreground
            readonly property color fgDim: row.selected ? Qt.alpha(Theme.onSelection, 0.7) : Theme.dim

            Item {
                id: icon
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                width: 24
                height: 24
                IconImage {
                    anchors.fill: parent
                    visible: row.item?.iconType === "theme"
                    source: visible ? Quickshell.iconPath(row.item.icon ?? "", "application-x-executable") : ""
                    asynchronous: true
                }
                Text {
                    anchors.centerIn: parent
                    visible: row.item?.iconType !== "theme"
                    text: row.item?.icon ?? ""
                    color: parent.parent.fg
                    font { family: Settings.s.fonts.icons; pointSize: Settings.s.fonts.size + 4 }
                }
            }

            Text {
                id: status
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                width: Math.min(implicitWidth, parent.width * 0.4)
                elide: Text.ElideRight
                text: Engine.busyKey && row.item?.key === Engine.busyKey ? "…"
                    : Engine.confirmKey && row.item?.key === Engine.confirmKey ? "press ↵ again"
                    : row.item?.folder ? (row.item.status ? row.item.status + "  ›" : "›")
                    : row.item?.status ?? ""
                color: parent.fgDim
                font { family: Settings.s.fonts.text; pointSize: Settings.s.fonts.size }
            }

            Text {
                anchors { left: icon.right; leftMargin: 12; right: status.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: (row.modelData.crumb ? `<font color="${parent.fgDim}">${esc(row.modelData.crumb)}  ›  </font>` : "")
                    + esc(row.item?.title ?? "")
                color: parent.fg
                font { family: Settings.s.fonts.text; pointSize: Settings.s.fonts.size + 1 }

                function esc(s) {
                    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
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
