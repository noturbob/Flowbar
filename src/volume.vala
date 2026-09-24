using Gtk;

class Volume : Module {
    const string SINK = "@DEFAULT_AUDIO_SINK@";
    Label big = label ("", "big");
    LevelBar meter = new LevelBar.for_interval (0, 100);
    Label device = label ("", "dim");

    public Volume () {
        base ("v", "");
        panel.width_request = 300;
        panel.append (big);
        panel.append (meter);
        panel.append (device);
        panel.append (label ("h/l −/+5% · m mute", "dim"));
    }

    public override async void refresh () {
        // "Volume: 0.80" or "Volume: 0.80 [MUTED]"
        var out = yield sh ("wpctl get-volume " + SINK);
        var f = out.split (" ");
        if (f.length < 2) {
            value.label = "—";
            return;
        }
        int pct = (int) (double.parse (f[1]) * 100 + 0.5);
        bool muted = "MUTED" in out;
        value.label = muted ? "muted" : "%d%%".printf (pct);
        big.label = value.label;
        meter.value = pct.clamp (0, 100);
        if (muted) meter.add_css_class ("muted"); else meter.remove_css_class ("muted");

        foreach (var line in (yield sh ("wpctl inspect " + SINK)).split ("\n")) {
            var q = line.split ("\"");
            if ("node.description" in line && q.length > 1) device.label = q[1];
        }
    }

    public override bool on_key (string k) {
        switch (k) {
        case "h": case "j": act.begin ("wpctl set-volume %s 5%%-".printf (SINK)); return true;
        case "l": case "k": act.begin ("wpctl set-volume -l 1.0 %s 5%%+".printf (SINK)); return true;
        case "m": act.begin ("wpctl set-mute %s toggle".printf (SINK)); return true;
        }
        return false;
    }
}
