using Gtk;

class Bluetooth : Module {
    Label status = label ("", "status");
    Label power;
    Picker list = new Picker ();
    string[] macs = {};
    string[] linked = {};
    bool powered = false;

    public Bluetooth () {
        base ("b", "");
        every = 5;
        panel.width_request = 300;
        power = key_row ("space", "", this);
        panel.append (status);
        panel.append (power);
        panel.append (list);
        list.activated.connect (() => on_key ("Return")); // a clicked row acts like Enter
        panel.append (label ("j/k move · enter (dis)connect · space power", "dim"));
    }

    public override async void refresh () {
        powered = "Powered: yes" in (yield sh ("bluetoothctl show"));
        power.label = keyed ("space", "Bluetooth   " + onoff (powered));
        if (!powered) {
            value.label = "off";
            status.label = "Bluetooth off";
            macs = {};
            list.set_rows ({});
            return;
        }

        linked = {};
        foreach (var line in (yield sh ("bluetoothctl devices Connected")).split ("\n")) {
            var f = line.split (" ", 3);
            if (f.length == 3) linked += f[1];
        }

        // "Device <mac> <name>"
        string[] rows = {};
        string[] found = {};
        string? first = null;
        foreach (var line in (yield sh ("bluetoothctl devices Paired")).split ("\n")) {
            var f = line.split (" ", 3);
            if (f.length < 3) continue;
            found += f[1];
            var name = Markup.escape_text (f[2]);
            if (f[1] in linked) {
                first = first ?? f[2];
                rows += "<span foreground='%s'>●</span>  <b>%s</b>".printf (Theme.accent (), name);
            } else {
                rows += "<span alpha='35%'>○</span>  %s".printf (name);
            }
        }
        macs = found;
        list.set_rows (rows);
        value.label = first ?? "on";
        status.label = first != null ? "Connected to " + first : "No device connected";
        if (macs.length == 0) status.label = "No paired devices";
    }

    public override bool on_key (string k) {
        if (list.move (k)) return true;
        switch (k) {
        case "space":
            launch ("bluetoothctl power " + (powered ? "off" : "on"));
            break;
        case "Return":
            if (macs.length == 0) return true;
            var mac = macs[list.pos];
            bool on = mac in linked;
            status.label = on ? "Disconnecting…" : "Connecting…";
            launch ("bluetoothctl %s %s".printf (on ? "disconnect" : "connect", mac));
            break;
        default:
            return false;
        }
        // Connecting takes a few seconds; check back rather than block.
        Timeout.add (1500, () => { refresh.begin (); return false; });
        Timeout.add (5000, () => { refresh.begin (); return false; });
        return true;
    }
}
