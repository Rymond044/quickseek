// Preview of the selected file or clipboard entry (Space): a picture, the beginning of a text,
// a PDF page or a video frame, else the file's icon and details.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

Rectangle {
    id: panel

    readonly property var item: Engine.previewItem
    readonly property var entry: item?.kind === "clip" ? item.entry : null
    readonly property string path: item?.kind === "file" ? item.path : ""

    // From bin/quickseek-preview, or straight from the clipboard entry
    property string kind: ""
    property string mime: ""
    property real size: 0
    property real mtime: 0
    property string image: ""
    property string text: ""
    property bool loading: false

    radius: 22
    color: Qt.alpha(Theme.background, Settings.s.opacity)
    border.width: 1
    border.color: Theme.border
    clip: true

    // After the bindings that depend on `item` have caught up
    onItemChanged: Qt.callLater(load)
    Component.onCompleted: load()

    function load() {
        loadTimer.stop();
        proc.running = false;
        if (entry) {
            kind = entry.image ? "image" : "text";
            image = entry.image;
            text = entry.text;
            mime = "";
            size = 0;
            mtime = 0;
            loading = false;
        } else if (path) {
            loading = true;
            loadTimer.restart();
        }
    }

    // Holding a key down the list should not start a helper per row
    Timer {
        id: loadTimer
        interval: 60
        onTriggered: {
            proc.target = panel.path;
            proc.command = [Quickshell.shellPath("bin/quickseek-preview"), panel.path];
            proc.running = true;
        }
    }

    Process {
        id: proc
        property string target
        stdout: StdioCollector {
            onStreamFinished: {
                if (proc.target !== panel.path) return;
                const nl = text.indexOf("\n");
                const head = (nl < 0 ? text : text.slice(0, nl)).split("\t");
                panel.kind = head[0] ?? "other";
                panel.mime = head[1] ?? "";
                panel.size = Number(head[2] ?? 0);
                panel.mtime = Number(head[3] ?? 0);
                panel.image = head[4] ?? "";
                panel.text = nl < 0 ? "" : text.slice(nl + 1);
                panel.loading = false;
            }
        }
    }

    function humanSize(b) {
        const u = ["B", "KB", "MB", "GB", "TB"];
        let n = 0;
        while (b >= 1024 && n < u.length - 1) { b /= 1024; n++; }
        return (n ? b.toFixed(b < 10 ? 1 : 0) : b) + " " + u[n];
    }

    readonly property string details: {
        if (entry) return entry.image ? "Image · " + Clipboard.age(entry.time) : entry.text.length + " characters · " + Clipboard.age(entry.time);
        if (!path || loading) return "";
        const d = new Date(mtime * 1000).toLocaleString(Qt.locale("en_GB"), "d MMM yyyy, HH:mm");
        return [humanSize(size), d, mime].filter(x => x).join(" · ");
    }

    readonly property bool showImage: !!image && ["image", "pdf", "video"].includes(kind)
    readonly property bool showText: kind === "text" && !showImage

    Column {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
        spacing: 4

        Text {
            width: parent.width
            text: panel.entry ? "Clipboard" : panel.item?.title ?? ""
            color: Theme.foreground
            font { family: Settings.textFont; pointSize: Settings.s.fonts.size + 2; weight: Font.DemiBold }
            elide: Text.ElideMiddle
        }
        Text {
            width: parent.width
            text: panel.details
            color: Theme.dim
            font { family: Settings.textFont; pointSize: Settings.s.fonts.size - 1 }
            elide: Text.ElideRight
        }
    }

    Item {
        id: body
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom; margins: 18; topMargin: 14 }

        Image {
            anchors.fill: parent
            visible: panel.showImage
            source: panel.showImage ? "file://" + panel.image : ""
            sourceSize { width: body.width * 2; height: body.height * 2 }
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
        }

        Flickable {
            id: flick
            anchors.fill: parent
            visible: panel.showText
            contentHeight: textView.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Text {
                id: textView
                width: flick.width
                text: panel.showText ? panel.text : ""
                textFormat: Text.PlainText
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                color: Theme.foreground
                font {
                    family: panel.entry ? Settings.textFont : "monospace"
                    pointSize: Settings.s.fonts.size - (panel.entry ? 0 : 1)
                }
            }
        }

        // Nothing to show: the icon and a word on the type
        Column {
            anchors.centerIn: parent
            visible: !panel.loading && !panel.showImage && !panel.showText
            spacing: 12
            IconImage {
                anchors.horizontalCenter: parent.horizontalCenter
                implicitSize: 96
                source: panel.item?.iconType === "theme" && panel.item.icon ? Quickshell.iconPath(panel.item.icon, true) : ""
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No preview"
                color: Theme.faint
                font { family: Settings.textFont; pointSize: Settings.s.fonts.size }
            }
        }
    }
}
