import QtQuick

Item {
    id: bar

    readonly property var chips: {
        const out = Engine.stack.map(k => Engine.byKey[k]?.title).filter(t => t);
        if (Engine.prompt) out.push(Engine.prompt.title);
        return out;
    }

    Text {
        id: glass
        anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
        text: Engine.busyKey ? "󰔟" : "󰍉"
        color: Theme.dim
        font { family: Settings.s.fonts.icons; pointSize: Settings.s.fonts.size + 7 }
    }

    Row {
        id: chipRow
        anchors { left: glass.right; leftMargin: bar.chips.length ? 12 : 0; verticalCenter: parent.verticalCenter }
        spacing: 6
        Repeater {
            model: bar.chips
            Rectangle {
                required property string modelData
                height: 28
                width: chipText.implicitWidth + 22
                radius: 14
                color: Qt.alpha(Theme.accent, Theme.light ? 0.14 : 0.22)
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: modelData + "  ›"
                    color: Theme.foreground
                    font { family: Settings.textFont; pointSize: Settings.s.fonts.size }
                }
            }
        }
    }

    TextInput {
        id: input
        anchors { left: chipRow.right; leftMargin: 12; right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
        focus: true
        color: Theme.foreground
        selectionColor: Theme.selection
        selectedTextColor: Theme.onSelection
        font { family: Settings.textFont; pointSize: Settings.s.fonts.size + 7 }
        echoMode: Engine.prompt?.password ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"
        clip: true
        Component.onCompleted: { text = Engine.query; forceActiveFocus(); }

        onTextEdited: Engine.setQuery(text)
        onTextChanged: Engine.fieldText = text
        Connections {
            target: Engine
            function onQueryChanged() { if (input.text !== Engine.query) input.text = Engine.query; }
            function onQueryReplaced() { if (input.text !== Engine.query) input.text = Engine.query; }
            function onTypeRequested(t) { input.text = t; Engine.setQuery(t); }
        }

        Keys.onReleased: e => Engine.keyUp(e.key)
        Keys.onPressed: e => {
            if (!e.isAutoRepeat) Engine.keyDown(e.key);
            e.accepted = Engine.onKey(e.key, e.modifiers, cursorPosition === text.length, !text);
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !input.text
            text: Engine.prompt ? (Engine.prompt.message || Engine.prompt.title) : Engine.folder ? "Search in " + Engine.folder.title + "…" : "Search…"
            color: Theme.faint
            font: input.font
            elide: Text.ElideRight
            width: input.width
        }
    }
}
