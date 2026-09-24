using Gtk;

// Type to find an app, Enter to start it. Apps come from GIO's desktop-file index, the same
// list every launcher reads. While this panel is open, printable keys type into the search.
class Launcher : Module {
    const int SHOW = 8;
    Label query_label = label ("", "status");
    Picker list = new Picker ();
    Label empty = label ("No match", "dim");
    AppInfo[] apps = {};
    AppInfo[] shown = {};
    string query = "";

    public Launcher () {
        base ("space", "");
        typing = true;
        every = 3600;
        value.visible = false;
        panel.width_request = 480;
        panel.append (query_label);
        panel.append (list);
        panel.append (empty);
        panel.append (label ("type to search · ↑/↓ pick · enter launch · esc close", "dim"));
    }

    public override void opened () {
        query = "";
        apps = {};
        foreach (var app in AppInfo.get_all ()) {
            if (app.should_show ()) apps += app;
        }
        filter ();
    }

    public override async void refresh () {}

    public override void on_text (unichar c) {
        query += c.to_string ();
        filter ();
    }

    public override bool on_key (string k) {
        switch (k) {
        case "Down": case "Tab":
            return list.move ("j");
        case "Up": case "ISO_Left_Tab":
            return list.move ("k");
        case "BackSpace":
            if (query.length > 0) query = query.substring (0, query.index_of_nth_char (query.char_count () - 1));
            filter ();
            return true;
        case "Return":
            if (shown.length == 0) return true;
            var app = shown[list.pos];
            dismiss ();
            try {
                app.launch (null, Gdk.Display.get_default ().get_app_launch_context ());
            } catch (Error e) {
                warning ("launch %s: %s", app.get_name (), e.message);
            }
            return true;
        }
        return true; // the launcher owns the keyboard while it's open
    }

    void filter () {
        var q = query.down ();
        AppInfo[] hits = {};
        int[] scores = {};
        foreach (var app in apps) {
            int s = score (app.get_name ().down (), q);
            var exe = Path.get_basename (app.get_executable () ?? "").down ();
            s = int.max (s, score (exe, q) - 100);
            if (s <= 0) continue;
            // Keep the best SHOW, best first; ties stay alphabetical.
            int i = hits.length;
            hits += app;
            scores += s;
            while (i > 0 && (scores[i - 1] < s || scores[i - 1] == s
                   && hits[i - 1].get_name ().collate (app.get_name ()) > 0)) {
                hits[i] = hits[i - 1];
                scores[i] = scores[i - 1];
                i--;
            }
            hits[i] = app;
            scores[i] = s;
        }
        if (hits.length > SHOW) hits = hits[0:SHOW];
        shown = hits;

        string[] rows = {};
        foreach (var app in shown) {
            var about = app.get_description () ?? "";
            rows += "<b>%s</b>   <span alpha='45%%'>%s</span>".printf (
                Markup.escape_text (clip (app.get_name (), 28)), Markup.escape_text (clip (about, 40)));
        }
        list.pos = 0;
        list.set_rows (rows);
        empty.visible = rows.length == 0;
        query_label.use_markup = true;
        query_label.label = query == ""
            ? "<span alpha='45%'>Search apps</span>"
            : "<span foreground='%s'>›</span> %s<span foreground='%s'>▏</span>".printf (
                Theme.accent (), Markup.escape_text (query), Theme.accent ());
    }

    // Higher is better, 0 is no match: prefix, then a word start, then anywhere, then the
    // letters in order (fewer gaps first).
    static int score (string name, string q) {
        if (q == "") return 1;
        if (name.has_prefix (q)) return 1000 - name.length;
        int at = name.index_of (" " + q);
        if (at >= 0) return 800 - at;
        at = name.index_of (q);
        if (at >= 0) return 600 - at;
        int pos = 0, gaps = 0;
        unichar c;
        int i = 0;
        while (q.get_next_char (ref i, out c)) {
            int found = name.index_of_char (c, pos);
            if (found < 0) return 0;
            gaps += found - pos;
            pos = found + 1;
        }
        return int.max (1, 400 - gaps);
    }
}
