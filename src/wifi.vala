using Gtk;

class Wifi : Module {
    Label status = label ("", "status");
    Label radio;
    Picker list = new Picker ();
    string[] ssids = {};
    string[] secure = {};
    int active = -1;

    public Wifi () {
        base ("w", "");
        every = 5;
        panel.width_request = 340;
        radio = key_row ("space", "", this);
        panel.append (status);
        panel.append (radio);
        panel.append (list);
        list.activated.connect (() => on_key ("Return")); // a clicked row acts like Enter
        panel.append (label ("j/k move · enter connect · space radio · r rescan", "dim"));
    }

    public override async void refresh () {
        bool on = (yield sh ("nmcli radio wifi")) == "enabled";
        radio.label = keyed ("space", "Wi‑Fi   " + onoff (on));
        if (!on) {
            value.label = "off";
            status.label = "Wi-Fi off";
            ssids = secure = {};
            list.set_rows ({});
            return;
        }

        // Chip first, from the device state: instant, where a scan can take seconds.
        value.label = "—";
        status.label = "Not connected";
        foreach (var line in (yield sh ("nmcli -t -f TYPE,STATE,CONNECTION device")).split ("\n")) {
            var d = line.split (":", 3);
            if (d.length < 3 || d[0] != "wifi" || d[1] != "connected") continue;
            value.label = d[2];
            status.label = "Connected to " + d[2];
        }

        // SSID goes last so colons inside it survive the split.
        var out = yield sh ("nmcli -t --escape no -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan auto");
        string[] names = {};
        string[] locks = {};
        int[] signal = {};
        active = -1;
        foreach (var line in out.split ("\n")) {
            var f = line.split (":", 4);
            if (f.length < 4 || f[3] == "") continue;
            // One row per SSID, even when several access points broadcast it.
            int i = 0;
            while (i < names.length && names[i] != f[3]) i++;
            if (i == names.length) {
                if (names.length == 8) continue;
                names += f[3];
                locks += f[2];
                signal += int.parse (f[1]);
            }
            if (f[0] == "*") active = i;
        }
        string[] rows = {};
        for (int i = 0; i < names.length; i++) {
            var name = Markup.escape_text (names[i]);
            rows += "%s  %s%s".printf (
                bars (signal[i]),
                i == active ? "<b>%s</b>".printf (name) : name,
                locks[i] == "" ? "" : "  <span alpha='40%'>\uf023</span>");
        }
        ssids = names;
        secure = locks;
        list.set_rows (rows);
    }

    static string bars (int signal) {
        string[] b = { "▂", "▄", "▆", "█" };
        int n = signal > 75 ? 4 : signal > 50 ? 3 : signal > 25 ? 2 : 1;
        var s = "<span foreground='%s'>".printf (Theme.accent ());
        for (int i = 0; i < 4; i++) s += (i == n ? "</span><span alpha='25%'>" : "") + b[i];
        return s + "</span>";
    }

    public override bool on_key (string k) {
        if (list.move (k)) return true;
        switch (k) {
        case "space":
            launch ("nmcli radio wifi " + (value.label == "off" ? "on" : "off"));
            break;
        case "r":
            status.label = "Scanning…";
            launch ("nmcli device wifi rescan");
            break;
        case "Return":
            if (ssids.length == 0) return true;
            connect.begin (list.pos);
            return true;
        default:
            return false;
        }
        Timeout.add (2500, () => { refresh.begin (); return false; });
        return true;
    }

    async void connect (int i) {
        var ssid = ssids[i];
        var q = Shell.quote (ssid);
        if (i == active) {
            status.label = "Disconnecting…";
            yield sh ("nmcli connection down id " + q);
        } else if (ssid in (yield sh ("nmcli -g NAME connection show")).split ("\n")) {
            status.label = "Connecting to %s…".printf (ssid);
            yield sh ("nmcli connection up id " + q);
        } else if (secure[i] == "") {
            status.label = "Connecting to %s…".printf (ssid);
            yield sh ("nmcli device wifi connect " + q);
        } else {
            // New secured network: nmcli asks for the password in a terminal.
            dismiss ();
            in_terminal ("nmcli --ask device wifi connect " + q);
            return;
        }
        yield refresh ();
    }
}
