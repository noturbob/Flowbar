using Gtk;

// mako's notifications as cards: the ones on screen now, then its history (dimmed). Reads
// `makoctl list -j` and `makoctl history -j`; mako can only act on notifications still on screen.
class Notifications : Module {
    Label status = label ("", "status");
    Picker list = new Picker ();
    int64[] ids = {};
    bool[] live = {};
    string shown = ""; // what the cards show now, so an unchanged refresh doesn't rebuild them
    // History entries you cleared: mako can't delete history, so flowbar stops showing them.
    // ponytail: by mako's ids, kept in memory; a mako restart reuses ids, restart flowbar too then.
    GenericSet<string> cleared = new GenericSet<string> (str_hash, str_equal);

    public Notifications () {
        base ("a", "");
        every = 2;
        panel.width_request = 460;
        list.spacing = 6;
        panel.append (status);
        panel.append (list);
        list.activated.connect (() => on_key ("Return")); // a clicked row acts like Enter
        panel.append (label ("enter act (on screen) · x remove · X clear all · r bring back last · f do not disturb", "dim"));
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

    // A string member, or "" when it's missing or null (mako sends null for unset fields).
    static string field (Json.Object n, string key) {
        var node = n.get_member (key);
        return node != null && node.get_value_type () == typeof (string) ? node.get_string ().strip () : "";
    }

    // The notification's own image or icon, else the app's icon, else a generic bell.
    static Image icon_for (Json.Object n) {
        var icon = field (n, "app_icon");
        if (icon.has_prefix ("file://")) icon = File.new_for_uri (icon).get_path () ?? "";
        if (icon.has_prefix ("/") && FileUtils.test (icon, FileTest.EXISTS)) return new Image.from_file (icon);
        var theme = IconTheme.get_for_display (Gdk.Display.get_default ());
        foreach (var name in new string[] { icon, field (n, "desktop_entry"), field (n, "app_name").down () }) {
            if (name != "" && theme.has_icon (name)) return new Image.from_icon_name (name);
        }
        return new Image.from_icon_name ("preferences-system-notifications");
    }

    // Lines of at most width characters, broken at spaces (long words are split). The cards
    // break their own lines: a label that wraps itself makes the panel card ask for the whole
    // screen width once it's laid out at a fixed height (GTK's height-for-width).
    static string wrap (string text, int width) {
        var lines = new StringBuilder ();
        int col = 0;
        foreach (var w in text.split_set (" \t\n")) {
            var word = w;
            while (word.char_count () > width) { // a URL or the like: hard-split it
                if (col > 0) lines.append_c ('\n');
                lines.append (word.substring (0, word.index_of_nth_char (width)));
                word = word.substring (word.index_of_nth_char (width));
                col = width;
            }
            int n = word.char_count ();
            if (n == 0) continue;
            if (col > 0 && col + 1 + n > width) {
                lines.append_c ('\n');
                col = 0;
            } else if (col > 0) {
                lines.append_c (' ');
                col++;
            }
            lines.append (word);
            col += n;
        }
        return lines.str;
    }

    static Widget card (Json.Object n, bool now) {
        var box = new Box (Orientation.HORIZONTAL, 12);
        box.add_css_class ("row");
        box.add_css_class ("note");
        if (!now) box.add_css_class ("old");
        var icon = icon_for (n);
        icon.pixel_size = 32;
        icon.valign = Align.START;
        box.append (icon);

        var text = new Box (Orientation.VERTICAL, 2);
        text.hexpand = true;
        var head = new Box (Orientation.HORIZONTAL, 8);
        var title = label (wrap (field (n, "summary"), 30), "note-title");
        title.hexpand = true;
        head.append (title);
        var app = label (field (n, "app_name"), "dim");
        app.valign = Align.START;
        head.append (app);
        text.append (head);
        var body = field (n, "body");
        if (body != "") text.append (label (wrap (clip (body, 200), 42), "note-body"));
        box.append (text);
        return box;
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
            shown = "";
            return;
        }

        Widget[] cards = {};
        int64[] found = {};
        bool[] is_live = {};
        var seen = new StringBuilder ();
        foreach (var arr in new Json.Array[] { on_screen, history }) {
            bool now = arr == on_screen;
            foreach (var node in arr.get_elements ()) {
                var n = node.get_object ();
                var id = n.get_int_member ("id");
                if (!now && cleared.contains (id.to_string ())) continue;
                cards += card (n, now);
                found += id;
                is_live += now;
                seen.append_printf ("%lld%c ", id, now ? 'l' : 'h');
            }
        }
        int count = (int) on_screen.get_length ();
        ids = found;
        live = is_live;
        if (seen.str != shown) {
            shown = seen.str;
            list.set_widgets (cards);
        }

        value.label = count > 0 ? "%d".printf (count) : "";
        value.visible = count > 0;
        status.label = "%d on screen · %d in history%s".printf (
            count, cards.length - count, dnd ? " · do not disturb" : "");
        if (cards.length == 0) status.label = dnd ? "Nothing yet · do not disturb" : "Nothing yet";
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
        case "x": // remove this one: off the screen without going to history, or out of the history list
            if (!picked) return true;
            if (live[list.pos]) {
                act.begin ("makoctl dismiss -h -n %lld".printf (ids[list.pos]));
            } else {
                cleared.add (ids[list.pos].to_string ());
                refresh.begin ();
            }
            return true;
        case "X": // clear everything
            foreach (var id in ids) cleared.add (id.to_string ());
            act.begin ("makoctl dismiss --all -h");
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
