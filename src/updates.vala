using Gtk;

// Pending package updates from the repos (checkupdates) and the AUR (yay -Qua).
class Updates : Module {
    const int64 STALE = 30 * 60 * TimeSpan.SECOND; // both checks hit the network
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
        panel.append (label ("enter update in kitty · r check now", "dim"));
    }

    public override async void refresh () {
        if (busy || get_monotonic_time () - checked < STALE && checked != 0) return;
        busy = true;
        status.label = "Checking…";
        if (checked == 0) value.label = "…";

        // "name old -> new" per line, from both sources.
        string[] lines = {};
        int aur = 0;
        foreach (var l in (yield sh ("checkupdates")).split ("\n")) {
            if (l.strip () != "") lines += l;
        }
        if (Environment.find_program_in_path ("yay") != null) {
            foreach (var l in (yield sh ("yay -Qua")).split ("\n")) {
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

    public override bool on_key (string k) {
        switch (k) {
        case "Return":
            dismiss ();
            launch ("kitty --hold -e yay"); // yay alone runs a full -Syu
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
