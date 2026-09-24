using Gtk;

// Replaces screenshot.sh, whose window mode only knew Hyprland and Sway. niri's own
// screenshot actions do area, screen and window, save the file and copy it to the clipboard.
class Shot : Module {
    const string[] KEYS = { "a", "s", "w" };
    const string[] NAMES = { "area", "screen", "window" };
    const string[] ACTIONS = { "screenshot", "screenshot-screen", "screenshot-window" };

    public Shot () {
        base ("g", "");
        value.visible = false;
        every = 3600;
        panel.width_request = 260;
        panel.append (label ("Screenshot", "status"));
        for (int i = 0; i < KEYS.length; i++) panel.append (key_row (KEYS[i], NAMES[i]));
        panel.append (key_row ("o", "open folder"));
        panel.append (label ("saved to %s and copied".printf (dir ()), "dim"));
    }

    // Match niri's screenshot-path.
    static string dir () {
        return Config.str ("screenshot", "dir", "~/Pictures/Screenshots");
    }

    public override async void refresh () {}

    public override bool on_key (string k) {
        if (k == "o") {
            dismiss ();
            launch ("xdg-open " + Shell.quote (dir ().replace ("~", Environment.get_home_dir ())));
            return true;
        }
        int i = 0;
        while (i < KEYS.length && KEYS[i] != k) i++;
        if (i == KEYS.length) return false;
        // Wait until the bar has left and the windows have slid back, or they'd be in the shot.
        dismiss ();
        var action = ACTIONS[i];
        Timeout.add (450, () => {
            launch ("niri msg action " + action);
            return Source.REMOVE;
        });
        return true;
    }
}
