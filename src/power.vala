using Gtk;

class Power : Module {
    const string[] KEYS = { "l", "s", "e", "r", "o" };
    const string[] NAMES = { "lock", "suspend", "log out", "reboot", "power off" };
    const string[] CMDS = {
        "swaylock",
        "systemctl suspend",
        "niri msg action quit --skip-confirmation",
        "systemctl reboot",
        "systemctl poweroff",
    };
    Label status = label ("", "status");
    Label[] rows = {};
    int armed = -1;

    public Power () {
        base ("p", "");
        value.visible = false;
        every = 3600;
        panel.width_request = 260;
        panel.append (status);
        for (int i = 0; i < KEYS.length; i++) {
            var row = key_row (KEYS[i], NAMES[i]);
            panel.append (row);
            rows += row;
        }
    }

    public override async void refresh () {
        armed = -1;
        paint ();
    }

    // First press arms an action, pressing the same key again runs it.
    public override bool on_key (string k) {
        int i = 0;
        while (i < KEYS.length && KEYS[i] != k) i++;
        if (i == KEYS.length) return false;
        if (armed == i) {
            dismiss ();
            launch (CMDS[i]);
            i = -1;
        }
        armed = i;
        paint ();
        return true;
    }

    void paint () {
        status.label = armed < 0 ? "Session" : "Press %s again to %s".printf (KEYS[armed], NAMES[armed]);
        for (int i = 0; i < rows.length; i++) {
            if (i == armed) rows[i].add_css_class ("cursor"); else rows[i].remove_css_class ("cursor");
        }
    }
}
