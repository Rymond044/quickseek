// Bluetooth: adapter power, paired devices, connect, pair and forget. BlueZ through Quickshell.Bluetooth.
import QtQuick
import Quickshell
import Quickshell.Bluetooth

NativeSource {
    id: src
    name: "bluetooth"

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: (adapter?.devices?.values ?? []).filter(d => d.name || d.deviceName)
    readonly property var paired: devices.filter(d => d.paired).sort((a, b) => (b.connected - a.connected) || label(a).localeCompare(label(b)))
    readonly property var fresh: devices.filter(d => !d.paired).sort((a, b) => label(a).localeCompare(label(b)))
    property var pairing: null   // device being paired, connected when done

    function label(d) {
        return d.name || d.deviceName || d.address;
    }

    function icon(d) {
        const i = d.icon ?? "";
        if (i.startsWith("audio-head")) return "󰋋";
        if (i.startsWith("audio")) return "󰓃";
        if (i === "input-mouse") return "󰍽";
        if (i === "input-keyboard") return "󰌌";
        if (i === "input-gaming") return "󰊴";
        if (i === "phone") return "󰏲";
        return "󰂯";
    }

    function setPower(on) {
        if (on) Quickshell.execDetached(["rfkill", "unblock", "bluetooth"]);
        adapter.enabled = on;
    }

    function scan() {
        adapter.discovering = true;
        scanTimer.restart();
    }

    function pair(d) {
        d.trusted = true;
        d.pair();
        pairing = d;
        pairTimer.restart();
    }

    function build() {
        const out = [];
        const tui = () => out.push({ id: "tui", title: "Open bluetui", icon: "󰂳", keywords: "terminal", close: true,
            run: () => Engine.runInTerminal(["bluetui"]) });
        if (!adapter) {
            tui();
            return out;
        }
        if (!adapter.enabled) {
            out.push({ id: "on", title: "Turn Bluetooth on", icon: "󰂯", run: () => setPower(true) });
            tui();
            return out;
        }
        for (const d of paired)
            out.push({ id: "dev:" + d.address, title: label(d), icon: icon(d), keywords: d.address,
                status: d.connected ? "connected" : d.state === BluetoothDeviceState.Connecting ? "connecting…" : "",
                run: () => { if (d.connected) d.disconnect(); else d.connect(); } });
        out.push({ id: "scan", title: "Pair new device", icon: "󰐕", keywords: "add search scan discover",
            status: adapter.discovering ? "scanning…" : "", run: () => scan() });
        if (adapter.discovering)
            for (const d of fresh)
                out.push({ id: "new:" + d.address, title: label(d), icon: icon(d), keywords: d.address, status: "pair",
                    run: () => pair(d) });
        if (paired.length)
            out.push({ id: "forget", title: "Forget device", icon: "󰆴", folder: true, keywords: "remove unpair" });
        for (const d of paired)
            out.push({ id: "forget:" + d.address, parent: "forget", title: label(d), icon: icon(d), confirm: true,
                nosearch: true, run: () => d.forget() });
        tui();
        out.push({ id: "off", title: "Turn Bluetooth off", icon: "󰂲", run: () => setPower(false) });
        return out;
    }

    items: build()
    status: {
        if (!adapter) return "no adapter";
        if (!adapter.enabled) return "off";
        const names = paired.filter(d => d.connected).map(label).join(", ");
        return names || "on";
    }

    // Discovery is short and stops with the window
    Timer { id: scanTimer; interval: 8000; onTriggered: if (src.adapter) src.adapter.discovering = false }

    // Connect once the pairing went through, give up after 30 s
    Timer {
        id: pairTimer
        interval: 1000
        repeat: true
        property int ticks: 0
        onTriggered: {
            ticks++;
            if (src.pairing?.paired) { src.pairing.connect(); src.pairing = null; }
            if (!src.pairing || ticks > 30) { stop(); ticks = 0; src.pairing = null; }
        }
        onRunningChanged: if (running) ticks = 0
    }

    QtObject {
        Component.onDestruction: if (src.adapter?.discovering) src.adapter.discovering = false
    }
}
