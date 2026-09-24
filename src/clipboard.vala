using Gtk;

// Clipboard history, replacing clipboard.sh without needing cliphist: wl-paste watches the
// clipboard for as long as flowbar runs and hands every new text copy to us.
class Clip : Module {
    const int KEEP = 30;
    // Skip copies a password manager marks as secret; end each entry with a NUL.
    const string WATCH = "[ \"$CLIPBOARD_STATE\" = data ] || exit 0; cat; printf '\\0'";
    Picker list = new Picker ();
    Label empty = label ("Nothing copied yet", "dim");
    string[] items = {}; // newest first
    // ponytail: history lives in memory and is gone after logout; persist it if that bites.

    public Clip () {
        base ("y", "");
        every = 3600;
        panel.width_request = 420;
        panel.append (empty);
        panel.append (list);
        panel.append (label ("j/k pick · enter copy · x delete · X clear all", "dim"));
        watch.begin ();
    }

    async void watch () {
        try {
            // pdeathsig: the watcher dies with us instead of lingering after a restart.
            var p = new Subprocess (SubprocessFlags.STDOUT_PIPE, "setpriv", "--pdeathsig", "TERM", "--",
                "wl-paste", "--type", "text", "--watch", "sh", "-c", WATCH);
            var input = new DataInputStream (p.get_stdout_pipe ());
            while (true) {
                size_t len;
                var text = yield input.read_upto_async ("\0", 1, Priority.DEFAULT, null, out len);
                if (text == null) break; // wl-paste went away
                input.read_byte (); // the NUL itself
                if (text.strip () != "") remember (text);
            }
        } catch (Error e) {
            warning ("clipboard watch: %s", e.message);
        }
    }

    void remember (string text) {
        string[] next = { text };
        foreach (var t in items) {
            if (t != text && next.length < KEEP) next += t;
        }
        items = next;
        paint ();
    }

    public override void opened () {
        list.pos = 0;
    }

    public override async void refresh () {
        paint ();
    }

    void paint () {
        string[] rows = {};
        foreach (var t in items) rows += Markup.escape_text (preview (t, 56));
        list.set_rows (rows);
        empty.visible = items.length == 0;
        value.label = items.length > 0 ? preview (items[0], 16) : "—";
    }

    // One line: collapse whitespace so multi-line copies stay readable.
    static string preview (string text, int max) {
        var s = string.joinv (" ", text.strip ().split_set (" \t\r\n"));
        while ("  " in s) s = s.replace ("  ", " ");
        return s.char_count () > max ? s.substring (0, s.index_of_nth_char (max - 1)) + "…" : s;
    }

    public override bool on_key (string k) {
        if (list.move (k)) return true;
        switch (k) {
        case "Return":
            if (items.length == 0) return true;
            copy.begin (items[list.pos]);
            dismiss (); // straight back to where you paste
            return true;
        case "x":
            if (items.length == 0) return true;
            string[] next = {};
            for (int i = 0; i < items.length; i++) {
                if (i != list.pos) next += items[i];
            }
            items = next;
            paint ();
            return true;
        case "X":
            items = {};
            paint ();
            return true;
        }
        return false;
    }

    static async void copy (string text) {
        try {
            var p = new Subprocess (SubprocessFlags.STDIN_PIPE, "wl-copy");
            yield p.communicate_utf8_async (text, null, null, null);
        } catch (Error e) {
            warning ("wl-copy: %s", e.message);
        }
    }
}
