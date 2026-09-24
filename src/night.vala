using Gtk;

// Night light and do-not-disturb. Night light replaces nightlight.sh, which started wlsunset
// with no location, so wlsunset followed its default day/night schedule and "on" did
// nothing during the day. Low T / high T+1 keeps the screen warm around the clock.
class Night : Module {
    const string MODE = "[mode=do-not-disturb]";
    Label night_row = key_row ("n", "");
    Label dnd_row = key_row ("f", "");
    Label note = label ("", "dim");
    bool night = false;
    bool dnd = false;

    public Night () {
        base ("n", "\uf186");
        every = 5;
        panel.width_request = 300;
        note.wrap = true;
        note.max_width_chars = 40;
        panel.append (label ("Night & quiet", "status"));
        panel.append (night_row);
        panel.append (dnd_row);
        panel.append (note);
    }

    public override async void refresh () {
        night = (yield sh ("pgrep -x wlsunset")) != "";
        dnd = "do-not-disturb" in (yield sh ("makoctl mode"));
        night_row.label = keyed ("n", "night light   " + state (night));
        dnd_row.label = keyed ("f", "do not disturb   " + state (dnd));
        value.label = night && dnd ? "night · dnd" : night ? "night" : dnd ? "dnd" : "off";

        // Say what's missing rather than toggling something that can't take effect.
        string[] missing = {};
        if (Environment.find_program_in_path ("wlsunset") == null) {
            missing += "Night light needs wlsunset: sudo pacman -S wlsunset";
        }
        var mako = Path.build_filename (Environment.get_user_config_dir (), "mako", "config");
        if (!(MODE in slurp (mako))) {
            missing += "Do not disturb needs a mode in %s:\n%s\ninvisible=1".printf (mako, MODE);
        }
        note.label = string.joinv ("\n\n", missing);
        note.visible = missing.length > 0;
    }

    static string state (bool on) {
        return on ? "<span foreground='%s'>on</span>".printf (Theme.color ("good")) : "<span alpha='45%'>off</span>";
    }

    public override bool on_key (string k) {
        switch (k) {
        case "n":
            if (night) {
                act.begin ("pkill -x wlsunset");
            } else {
                int t = Config.num ("night", "temperature", 4000);
                launch ("wlsunset -t %d -T %d".printf (t, t + 1)); // lasts until toggled off
                Timeout.add (300, () => { refresh.begin (); return Source.REMOVE; });
            }
            return true;
        case "f":
            act.begin ("makoctl mode -t do-not-disturb");
            return true;
        }
        return false;
    }
}
