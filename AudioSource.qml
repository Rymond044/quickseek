// Sound: outputs, inputs, default device, mute. PipeWire through Quickshell.Services.Pipewire.
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

NativeSource {
    id: src
    name: "audio"

    readonly property var nodes: Pipewire.nodes.values.filter(n => !n.isStream && n.audio)
    readonly property var sinks: nodes.filter(n => n.isSink)
    readonly property var sources: nodes.filter(n => !n.isSink)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    // Bound nodes report volume and properties
    PwObjectTracker { objects: src.nodes.concat([src.sink, src.source].filter(n => n)) }

    function label(n) {
        return n.nickname || n.description || n.name;
    }

    function percent(n) {
        return n?.audio ? Math.round(n.audio.volume * 100) + "%" : "";
    }

    function build() {
        const out = [];
        const dev = (n, def, glyph) => out.push({
            id: (n.isSink ? "sink:" : "source:") + n.name,
            title: label(n),
            status: n === def ? "default" : "",
            icon: glyph,
            keywords: [n.description, n.name].join(" "),
            run: () => { if (n.isSink) Pipewire.preferredDefaultAudioSink = n; else Pipewire.preferredDefaultAudioSource = n; }
        });
        // The default first: it is what the window opens on
        for (const n of sinks.slice().sort((a, b) => (b === sink) - (a === sink))) dev(n, sink, "󰓃");
        for (const n of sources.slice().sort((a, b) => (b === source) - (a === source))) dev(n, source, "󰍬");
        if (sink?.audio)
            out.push({ id: "volume", title: "Volume", icon: sink.audio.muted ? "󰝟" : "󰕾", keywords: "mute speakers output",
                status: sink.audio.muted ? "muted" : percent(sink), run: () => { sink.audio.muted = !sink.audio.muted; } });
        if (source?.audio)
            out.push({ id: "mic", title: "Microphone", icon: source.audio.muted ? "󰍭" : "󰍬", keywords: "mute input",
                status: source.audio.muted ? "muted" : "on", run: () => { source.audio.muted = !source.audio.muted; } });
        out.push({ id: "mixer", title: "Open wiremix", icon: "󰕾", keywords: "pipewire mixer volume", close: true,
            run: () => Engine.runInTerminal(["wiremix"]) });
        return out;
    }

    items: build()
    status: label(sink ?? { nickname: "", description: "", name: "" })
}
