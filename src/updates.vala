using Gtk;

// Pending package updates from the repos (checkupdates) and the AUR (yay -Qua).
class Updates : Module {
    const int SHOW = 10;
    Label status = label ("", "status");
    Label pkgs = label ("", "sub");
    // The last result lives on the class, so a config reload doesn't re-check.
    static string[] lines = {};
    static int aur = 0;
    static int64 checked = 0;
    static bool busy = false;

    public Updates () {
        base ("u", "");
        every = 60;
        panel.width_request = 380;
        pkgs.use_markup = true;
        panel.append (status);
        panel.append (pkgs);
        panel.append (label ("enter update · r check now", "dim"));
    }

    public override async void refresh () {
        // Both checks hit the network, so only every [updates] interval minutes.
        int64 stale = Config.num ("updates", "interval", 30) * TimeSpan.MINUTE;
        if (busy || checked != 0 && get_monotonic_time () - checked < stale) {
            paint ();
            return;
        }
        busy = true;
        status.label = "Checking…";
        if (checked == 0) value.label = "…";

        // "name old -> new" per line, from both sources.
        string[] found = {};
        int from_aur = 0;
        foreach (var l in (yield sh ("checkupdates")).split ("\n")) {
            if (l.strip () != "") found += l;
        }
        // AUR updates, if the update command is an AUR helper that can list them.
        var words = updater ().split (" ");
        var helper = words[0];
        if ((helper == "yay" || helper == "paru") && Environment.find_program_in_path (helper) != null) {
            foreach (var l in (yield sh (helper + " -Qua")).split ("\n")) {
                if (l.strip () == "") continue;
                found += l;
                from_aur++;
            }
        }
        lines = found;
        aur = from_aur;
        checked = get_monotonic_time ();
        busy = false;
        paint ();
    }

    void paint () {
        if (checked == 0) return;
        value.label = lines.length == 0 ? "\uf00c" : "%d".printf (lines.length);
        status.label = lines.length == 0 ? "Up to date"
            : "%d updates%s".printf (lines.length, aur > 0 ? " · %d from AUR".printf (aur) : "");
        var sb = new StringBuilder ();
        for (int i = 0; i < lines.length && i < SHOW; i++) {
            var f = lines[i].split (" ");
            if (f.length < 4) continue;
            sb.append ("%s<b>%s</b>  <span alpha='45%%'>%s →</span> %s".printf (
                i > 0 ? "\n" : "", Markup.escape_text (f[0]), Markup.escape_text (f[1]), Markup.escape_text (f[3])));
        }
        if (lines.length > SHOW) sb.append ("\n<span alpha='45%%'>and %d more</span>".printf (lines.length - SHOW));
        pkgs.label = sb.str;
        pkgs.visible = lines.length > 0;
    }

    // yay or paru alone run a full -Syu.
    static string updater () {
        return Config.str ("commands", "update", "yay");
    }

    public override bool on_key (string k) {
        switch (k) {
        case "Return":
            dismiss ();
            in_terminal (updater ());
            checked = 0; // recheck next time the bar opens
            return true;
        case "r":
            checked = 0;
            refresh.begin ();
            return true;
        }
        return false;
    }
}
