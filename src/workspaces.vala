using Gtk;

// niri's workspaces and windows, read over its IPC (`niri msg --json`).
// The chip is waybar-style: workspace numbers with the focused one lit, then the focused
// window's title. The panel lists every window by workspace, in niri's column order.
class Workspaces : Module {
    Label status = label ("", "status");
    Picker list = new Picker ();
    int64[] window_ids = {};

    public Workspaces () {
        base ("o", "");
        value.use_markup = true;
        value.max_width_chars = 26;
        panel.width_request = 480;
        panel.append (status);
        panel.append (list);
        list.activated.connect (() => on_key ("Return")); // a clicked row acts like Enter
        panel.append (label ("j/k pick · enter focus · 1–9 go to workspace", "dim"));
    }

    // The parsed reply, or null if niri isn't answering.
    static async Json.Node? query (string what) {
        var reply = yield sh ("niri msg --json " + what);
        try {
            var parser = new Json.Parser ();
            parser.load_from_data (reply);
            return parser.steal_root ();
        } catch (Error e) {
            return null;
        }
    }

    // Scroll on the chip to move between workspaces, like niri's own workspace scrolling.
    public override bool on_scroll (double dy) {
        launch ("niri msg action focus-workspace-" + (dy > 0 ? "down" : "up"));
        Timeout.add (150, () => { refresh.begin (); return Source.REMOVE; });
        return true;
    }

    public override void opened () {
        list.moved = false; // start on the focused window
    }

    public override async void refresh () {
        var ws_node = yield query ("workspaces");
        var win_node = yield query ("windows");
        if (ws_node == null || win_node == null || ws_node.get_node_type () != Json.NodeType.ARRAY) {
            value.label = "—";
            status.label = "Can't reach niri (niri msg --json)";
            return;
        }

        // Workspaces by output, then position.
        var ws = objects (ws_node.get_array ());
        sort (ws, (a, b) => {
            int o = strcmp (a.get_string_member_with_default ("output", ""), b.get_string_member_with_default ("output", ""));
            return o != 0 ? o : (int) (a.get_int_member ("idx") - b.get_int_member ("idx"));
        });

        // Windows by workspace, then column and row; floating windows last on their workspace.
        var wins = objects (win_node.get_array ());
        sort (wins, (a, b) => {
            int64 d = idx_of (ws, a.get_int_member ("workspace_id")) - idx_of (ws, b.get_int_member ("workspace_id"));
            if (d != 0) return (int) d;
            return column (a) - column (b);
        });

        var accent = Theme.accent ();
        var chip = new StringBuilder ();
        string title = "";
        int focused_ws = 0;
        foreach (var w in ws) {
            int idx = (int) w.get_int_member ("idx");
            if (w.get_boolean_member ("is_focused")) {
                focused_ws = idx;
                chip.append ("<span foreground='%s'><b>%d</b></span> ".printf (accent, idx));
            } else {
                chip.append ("<span alpha='45%%'>%d</span> ".printf (idx));
            }
        }

        string[] rows = {};
        int64[] ids = {};
        int focused_row = 0;
        foreach (var w in wins) {
            var t = w.get_string_member_with_default ("title", "");
            var app = w.get_string_member_with_default ("app_id", "");
            int idx = (int) idx_of (ws, w.get_int_member ("workspace_id"));
            bool focused = w.get_boolean_member ("is_focused");
            if (focused) {
                focused_row = rows.length;
                title = t;
            }
            // The font is monospace, so padding the app name lines the titles up.
            rows += "<span foreground='%s'><b>%d</b></span>   %s%s%s  <span alpha='50%%'>%s</span>".printf (
                accent, idx, focused ? "<b>" : "", Markup.escape_text ("%-15s".printf (clip (app, 15))),
                focused ? "</b>" : "", Markup.escape_text (clip (t, 48)));
            ids += w.get_int_member ("id");
        }
        window_ids = ids;
        if (!list.moved) list.pos = focused_row;
        list.set_rows (rows);

        chip.append (Markup.escape_text (clip (title, 18)));
        value.label = chip.str.strip ();
        status.label = "Workspace %d · %d window%s".printf (focused_ws, rows.length, rows.length == 1 ? "" : "s");
    }

    public override bool on_key (string k) {
        if (list.move (k)) return true;
        if (k == "Return") {
            if (window_ids.length == 0) return true;
            dismiss ();
            launch ("niri msg action focus-window --id %lld".printf (window_ids[list.pos]));
            return true;
        }
        if (k.length == 1 && k[0] >= '1' && k[0] <= '9') {
            dismiss ();
            launch ("niri msg action focus-workspace " + k);
            return true;
        }
        return false;
    }

    // ---- small helpers over json-glib ----

    delegate int Compare (Json.Object a, Json.Object b);

    static Json.Object[] objects (Json.Array arr) {
        Json.Object[] out = {};
        foreach (var n in arr.get_elements ()) out += n.get_object ();
        return out;
    }

    // Insertion sort: a handful of workspaces and windows.
    static void sort (Json.Object[] items, Compare cmp) {
        for (int i = 1; i < items.length; i++) {
            var cur = items[i];
            int j = i - 1;
            while (j >= 0 && cmp (items[j], cur) > 0) {
                items[j + 1] = items[j];
                j--;
            }
            items[j + 1] = cur;
        }
    }

    // A workspace's number from its id.
    static int64 idx_of (Json.Object[] ws, int64 id) {
        foreach (var w in ws) {
            if (w.get_int_member ("id") == id) return w.get_int_member ("idx");
        }
        return 99;
    }

    // Column * 100 + row in the scrolling layout; floating windows sort after tiled ones.
    static int column (Json.Object w) {
        if (!w.has_member ("layout")) return 10000;
        var layout = w.get_object_member ("layout");
        if (layout == null || !layout.has_member ("pos_in_scrolling_layout")
            || layout.get_null_member ("pos_in_scrolling_layout")) return 10000;
        var pos = layout.get_array_member ("pos_in_scrolling_layout");
        return (int) (pos.get_int_element (0) * 100 + pos.get_int_element (1));
    }
}
