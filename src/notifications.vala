using Gtk;

// mako's notifications: the ones on screen now, then its history. Reads `makoctl list -j`
// and `makoctl history -j`; mako can only act on notifications still on screen.
class Notifications : Module {
    Label status = label ("", "status");
    Picker list = new Picker ();
    int64[] ids = {};
    bool[] live = {};

    public Notifications () {
        base ("a", "");
        every = 2;
        panel.width_request = 460;
        panel.append (status);
        panel.append (list);
        list.activated.connect (() => on_key ("Return")); // a clicked row acts like Enter
        panel.append (label ("enter act (on screen) · x dismiss · X all · r bring back last · f do not disturb", "dim"));
    }

    static async Json.Array? query (string what) {
        var reply = yield sh ("makoctl %s -j".printf (what));
        try {
            var parser = new Json.Parser ();
            parser.load_from_data (reply);
            var root = parser.steal_root ();
            // Hand back an array that owns its elements; the node goes away with this frame.
            if (root.get_node_type () != Json.NodeType.ARRAY) return null;
            return root.dup_array ();
        } catch (Error e) {
            return null;
        }
    }

    public override void opened () {
        list.pos = 0;
    }

    public override async void refresh () {
        var on_screen = yield query ("list");
        var history = yield query ("history");
        bool dnd = "do-not-disturb" in (yield sh ("makoctl mode"));
        icon_label.label = dnd ? "" : "";
        if (on_screen == null || history == null) {
            value.label = "—";
            status.label = "Can't reach mako (makoctl)";
            list.set_rows ({});
            return;
        }

        var accent = Theme.accent ();
        string[] rows = {};
        int64[] found = {};
        bool[] is_live = {};
        foreach (var arr in new Json.Array[] { on_screen, history }) {
            bool now = arr == on_screen;
            foreach (var node in arr.get_elements ()) {
                var n = node.get_object ();
                var summary = n.get_string_member_with_default ("summary", "");
                var body = n.get_string_member_with_default ("body", "").replace ("\n", " ");
                var app = n.get_string_member_with_default ("app_name", "");
                rows += "%s  <b>%s</b>  <span alpha='55%%'>%s</span>  <span alpha='35%%'>%s</span>".printf (
                    now ? "<span foreground='%s'>●</span>".printf (accent) : "<span alpha='35%'>○</span>",
                    Markup.escape_text (clip (summary, 32)), Markup.escape_text (clip (body, 44)),
                    Markup.escape_text (app));
                found += n.get_int_member ("id");
                is_live += now;
            }
        }
        ids = found;
        live = is_live;
        list.set_rows (rows);

        int count = (int) on_screen.get_length ();
        value.label = count > 0 ? "%d".printf (count) : "";
        value.visible = count > 0;
        status.label = "%d on screen · %d in history%s".printf (
            count, (int) history.get_length (), dnd ? " · do not disturb" : "");
        if (rows.length == 0) status.label = dnd ? "Nothing yet · do not disturb" : "Nothing yet";
    }

    public override bool on_key (string k) {
        if (list.move (k)) return true;
        bool picked = ids.length > 0;
        switch (k) {
        case "Return":
            if (!picked || !live[list.pos]) return true; // history can't be acted on
            dismiss ();
            launch ("makoctl invoke -n %lld default".printf (ids[list.pos]));
            return true;
        case "x":
            if (picked && live[list.pos]) act.begin ("makoctl dismiss -n %lld".printf (ids[list.pos]));
            return true;
        case "X":
            act.begin ("makoctl dismiss --all");
            return true;
        case "r":
            act.begin ("makoctl restore");
            return true;
        case "f":
            act.begin ("makoctl mode -t do-not-disturb");
            return true;
        }
        return false;
    }
}
