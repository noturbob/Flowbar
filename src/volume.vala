using Gtk;

// Volume for the default output (or input, after `i`), plus picking which device is default.
class Volume : Module {
    Label big = label ("", "big");
    LevelBar meter = new LevelBar.for_interval (0, 100);
    Label heading = label ("", "dim");
    Picker list = new Picker ();
    string[] names = {};
    bool input = false; // false: speakers/headphones, true: microphones

    public Volume () {
        base ("v", "");
        panel.width_request = 340;
        panel.append (big);
        panel.append (meter);
        panel.append (heading);
        panel.append (list);
        panel.append (label ("h/l −/+%d%% · m mute · j/k pick · enter use · i inputs/outputs".printf (step ()), "dim"));
    }

    // Always open on outputs, with the cursor on the current default.
    public override void opened () {
        input = false;
        list.moved = false;
    }

    public override double level () {
        return meter.value;
    }

    string target () {
        return input ? "@DEFAULT_AUDIO_SOURCE@" : "@DEFAULT_AUDIO_SINK@";
    }

    public override async void refresh () {
        // "Volume: 0.80" or "Volume: 0.80 [MUTED]"
        var sink = yield sh ("wpctl get-volume @DEFAULT_AUDIO_SINK@");
        value.label = percent (sink);
        var shown = sink;
        if (input) shown = yield sh ("wpctl get-volume " + target ());
        big.label = percent (shown);
        var f = shown.split (" ");
        meter.value = f.length > 1 ? ((int) (double.parse (f[1]) * 100 + 0.5)).clamp (0, 100) : 0;
        if ("MUTED" in shown) meter.add_css_class ("muted"); else meter.remove_css_class ("muted");

        // `pactl list` blocks start with "Name:" then "Description:". Sources include a
        // ".monitor" loopback of every output; those aren't microphones, so skip them.
        var kind = input ? "source" : "sink";
        var current = yield sh ("pactl get-default-" + kind);
        string[] found = {};
        string[] rows = {};
        string name = "";
        foreach (var line in (yield sh ("pactl list %ss".printf (kind))).split ("\n")) {
            var l = line.strip ();
            if (l.has_prefix ("Name: ")) name = l.substring (6);
            if (!l.has_prefix ("Description: ") || name.has_suffix (".monitor")) continue;
            var desc = Markup.escape_text (l.substring (13));
            if (name == current) {
                if (!list.moved) list.pos = found.length;
                rows += "<span foreground='%s'>●</span>  <b>%s</b>".printf (Theme.accent (), desc);
            } else {
                rows += "<span alpha='35%'>○</span>  %s".printf (desc);
            }
            found += name;
        }
        names = found;
        list.set_rows (rows);
        heading.label = input ? "inputs" : "outputs";
    }

    static int step () {
        return Config.num ("volume", "step", 5);
    }

    static string percent (string wpctl) {
        var f = wpctl.split (" ");
        if (f.length < 2) return "—";
        if ("MUTED" in wpctl) return "muted";
        return "%d%%".printf ((int) (double.parse (f[1]) * 100 + 0.5));
    }

    public override bool on_key (string k) {
        if (list.move (k)) return true;
        switch (k) {
        case "h": act.begin ("wpctl set-volume %s %d%%-".printf (target (), step ())); return true;
        case "l": act.begin ("wpctl set-volume -l 1.0 %s %d%%+".printf (target (), step ())); return true;
        case "m": act.begin ("wpctl set-mute %s toggle".printf (target ())); return true;
        case "i":
            input = !input;
            list.moved = false;
            refresh.begin ();
            return true;
        case "Return":
            if (names.length == 0) return true;
            list.moved = false;
            act.begin ("pactl set-default-%s %s".printf (input ? "source" : "sink", Shell.quote (names[list.pos])));
            return true;
        }
        return false;
    }
}
