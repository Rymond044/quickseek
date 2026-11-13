// Emoji with English and Russian names (data/emoji.tsv, from emojibase / Unicode CLDR).
// Read the first time the folder opens.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string prefix: Settings.s.emoji?.prefix ?? ":"
    readonly property bool enabled: !!prefix
    property var items: []       // { char, name, keywords, ru }
    property bool wanted: false

    signal updated()

    function load() {
        wanted = true;
    }

    FileView {
        path: root.wanted ? Quickshell.shellPath("data/emoji.tsv") : ""
        blockLoading: true
        onLoaded: {
            root.items = text().split("\n").filter(l => l).map(l => {
                const [char, name, tags, ru, ruTags] = l.split("\t");
                return { char, name, keywords: [tags, ru, ruTags].join(" "), ru };
            });
            root.updated();
        }
    }
}
