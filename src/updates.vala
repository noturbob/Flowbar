using Gtk;

// Pending package updates from the repos (checkupdates) and the AUR (yay -Qua).
class Updates : Module {
    const int SHOW = 10;
    Label status = label ("", "status");
    Label pkgs = label ("", "sub");
    int64 checked = 0;
    bool busy = false;

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
        if (busy || get_monotonic_time () - checked < stale && checked != 0) return;
        busy = true;
        status.label = "Checking…";
        if (checked == 0) value.label = "…";

        // "name old -> new" per line, from both sources.
        string[] lines = {};
        int aur = 0;
        foreach (var l in (yield sh ("checkupdates")).split ("\n")) {
            if (l.strip () != "") lines += l;
        }
        // AUR updates, if the update command is an AUR helper that can list them.
        var helper = updater ().split (" ")[0];
        if ((helper == "yay" || helper == "paru") && Environment.find_program_in_path (helper) != null) {
            foreach (var l in (yield sh (helper + " -Qua")).split ("\n")) {
                if (l.strip () == "") continue;
                lines += l;
                aur++;
            }
        }
        checked = get_monotonic_time ();
        busy = false;

        value.label = lines.length == 0 ? "" : "%d".printf (lines.length);
        status.label = lines.length == 0 ? "Up to date"
            : "%d updates%s".printf (lines.length, aur > 0 ? " · %d from AUR".printf (aur) : "");
        var sb = new StringBuilder ();
        for (int i = 0; i < lines.length && i < SHOW; i++) {
            var f = lines[i].split (" ");
            if (f.length < 4) continue;
            sb.append ("%s<b>%s</b>  <span alpha='45%'>%s →</span> %s".printf (
                i > 0 ? "\n" : "", Markup.escape_text (f[0]), Markup.escape_text (f[1]), Markup.escape_text (f[3])));
        }
        if (lines.length > SHOW) sb.append ("\n<span alpha='45%'>and %d more</span>".printf (lines.length - SHOW));
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
