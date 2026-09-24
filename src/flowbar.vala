// flowbar — a bar that isn't there until you summon it.
//
// Run `flowbar` to toggle it: the first run starts the daemon and shows the bar,
// every later run tells the running instance to show or hide it.
// While it's up, one key opens a module's panel, Esc backs out.

using Gtk;

public class Flowbar : Gtk.Application {
    Window win;
    Box root;
    Revealer drawer;
    Stack panels;
    Module[] modules;
    Module? active = null;
    bool shown = false;
    uint tick_id = 0;
    uint hide_id = 0;
    int ticks = 0;

    public Flowbar () {
        Object (application_id: "io.github.noturbob.flowbar");
    }

    public override void activate () {
        if (win == null) build ();
        if (shown) hide_bar (); else show_bar ();
    }

    void build () {
        hold ();
        win = new ApplicationWindow (this);
        GtkLayerShell.init_for_window (win);
        GtkLayerShell.set_namespace (win, "flowbar");
        GtkLayerShell.set_layer (win, GtkLayerShell.Layer.OVERLAY);
        GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.TOP, true);
        GtkLayerShell.set_keyboard_mode (win, GtkLayerShell.KeyboardMode.EXCLUSIVE);

        modules = { new Clock (), new Cal (), new Wifi (), new Bluetooth (), new Volume (), new Brightness (), new Media (), new Sys (), new Power () };

        var bar = new Box (Orientation.HORIZONTAL, 2);
        bar.add_css_class ("bar");
        bar.halign = Align.CENTER;
        panels = new Stack ();
        panels.transition_type = StackTransitionType.CROSSFADE;
        panels.transition_duration = 220;
        panels.interpolate_size = true;
        panels.hhomogeneous = panels.vhomogeneous = false;
        foreach (var m in modules) {
            bar.append (m.chip);
            panels.add_named (m.panel, m.key);
        }

        var card = new Box (Orientation.VERTICAL, 0);
        card.add_css_class ("card");
        card.halign = Align.CENTER;
        card.append (panels);
        drawer = new Revealer ();
        drawer.transition_type = RevealerTransitionType.SLIDE_DOWN;
        drawer.transition_duration = 320;
        drawer.child = card;

        root = new Box (Orientation.VERTICAL, 0);
        root.add_css_class ("flow");
        root.add_css_class ("hidden");
        root.append (bar);
        root.append (drawer);
        win.child = root;

        // Capture phase: our keys win over whatever widget has focus in a panel.
        var keys = new EventControllerKey ();
        keys.propagation_phase = PropagationPhase.CAPTURE;
        keys.key_pressed.connect (on_key);
        ((Widget) win).add_controller (keys);

        load_css ();
    }

    void load_css () {
        var display = Gdk.Display.get_default ();
        var css = new CssProvider ();
        css.load_from_string (CSS);
        StyleContext.add_provider_for_display (display, css, STYLE_PROVIDER_PRIORITY_APPLICATION);

        var user = Path.build_filename (Environment.get_user_config_dir (), "flowbar", "style.css");
        if (FileUtils.test (user, FileTest.EXISTS)) {
            var over = new CssProvider ();
            over.load_from_path (user);
            StyleContext.add_provider_for_display (display, over, STYLE_PROVIDER_PRIORITY_USER);
        }
    }

    void show_bar () {
        if (hide_id != 0) {
            Source.remove (hide_id);
            hide_id = 0;
        }
        shown = true;
        refresh (true);
        win.present ();
        // Drop .hidden only once the hidden style has been painted, so the CSS transitions run.
        int frames = 0;
        root.add_tick_callback (() => {
            if (++frames < 2) return Source.CONTINUE;
            root.remove_css_class ("hidden");
            return Source.REMOVE;
        });
        tick_id = Timeout.add_seconds (1, () => {
            refresh (false);
            return Source.CONTINUE;
        });
    }

    public void hide_bar () {
        shown = false;
        close_panel ();
        root.add_css_class ("hidden");
        if (tick_id != 0) {
            Source.remove (tick_id);
            tick_id = 0;
        }
        hide_id = Timeout.add (280, () => {
            win.visible = false;
            hide_id = 0;
            return Source.REMOVE;
        });
    }

    // Modules only poll while the bar is visible.
    void refresh (bool all) {
        ticks++;
        foreach (var m in modules) {
            if (all || ticks % m.every == 0) m.refresh.begin ();
        }
    }

    bool on_key (uint keyval, uint keycode, Gdk.ModifierType state) {
        string k = Gdk.keyval_name (keyval) ?? "";
        switch (k) {
        case "Left": k = "h"; break;
        case "Down": k = "j"; break;
        case "Up": k = "k"; break;
        case "Right": k = "l"; break;
        case "KP_Enter": k = "Return"; break;
        }

        if (k == "Escape") {
            if (active != null) close_panel (); else hide_bar ();
            return true;
        }
        // The open panel gets first dibs, so it can reuse letters (h/j/k/l, etc).
        if (active != null && active.on_key (k)) return true;
        foreach (var m in modules) {
            if (m.key != k) continue;
            if (active == m) close_panel (); else open_panel (m);
            return true;
        }
        return false;
    }

    void open_panel (Module m) {
        if (active != null) active.chip.remove_css_class ("active");
        active = m;
        m.chip.add_css_class ("active");
        m.refresh.begin ();
        panels.visible_child = m.panel;
        drawer.reveal_child = true;
    }

    void close_panel () {
        if (active == null) return;
        active.chip.remove_css_class ("active");
        active = null;
        drawer.reveal_child = false;
    }
}

// One letter on the bar: a chip that's always visible and a panel that opens under it.
public abstract class Module {
    public string key;
    public Box chip = new Box (Orientation.HORIZONTAL, 7);
    public Label value = new Label ("");
    public Box panel = new Box (Orientation.VERTICAL, 6);
    public int every = 1; // refresh interval in seconds while visible

    protected Module (string key, string icon) {
        this.key = key;
        chip.add_css_class ("chip");
        chip.append (label (key.up (), "key"));
        chip.append (label (icon, "icon"));
        value.max_width_chars = 16;
        value.ellipsize = Pango.EllipsizeMode.END;
        chip.append (value);
        panel.add_css_class ("panel");
    }

    public abstract async void refresh ();

    // Run a command, then show its effect straight away.
    protected async void act (string cmd) {
        yield sh (cmd);
        yield refresh ();
    }

    // Keys while this module's panel is open. Return true if consumed.
    public virtual bool on_key (string k) {
        return false;
    }
}

// For actions that hand off to another window (a terminal, a lock screen).
void dismiss () {
    ((Flowbar) GLib.Application.get_default ()).hide_bar ();
}

// A vertical list with a keyboard cursor; the wifi and bluetooth panels use it.
class Picker : Box {
    public int pos = 0;
    public int count = 0;

    public Picker () {
        Object (orientation: Orientation.VERTICAL, spacing: 2);
    }

    public void set_rows (string[] markup) {
        Widget? c;
        while ((c = get_first_child ()) != null) remove (c);
        foreach (var m in markup) {
            var l = label ("", "row");
            l.use_markup = true;
            l.label = m;
            append (l);
        }
        count = markup.length;
        pos = pos.clamp (0, int.max (count - 1, 0));
        paint ();
    }

    // j/k move the cursor.
    public bool move (string k) {
        if (count == 0 || (k != "j" && k != "k")) return false;
        pos = (pos + (k == "j" ? 1 : -1) + count) % count;
        paint ();
        return true;
    }

    void paint () {
        int i = 0;
        for (var c = get_first_child (); c != null; c = c.get_next_sibling ()) {
            if (i++ == pos) c.add_css_class ("cursor"); else c.remove_css_class ("cursor");
        }
    }
}

async string sh (string cmd) {
    try {
        string[] argv;
        Shell.parse_argv (cmd, out argv);
        var p = new Subprocess.newv (argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
        string? output;
        yield p.communicate_utf8_async (null, null, out output, null);
        return (output ?? "").strip ();
    } catch (Error e) {
        return "";
    }
}

void launch (string cmd) {
    try {
        Process.spawn_command_line_async (cmd);
    } catch (Error e) {
        warning ("%s: %s", cmd, e.message);
    }
}

string slurp (string path) {
    string s = "";
    try {
        FileUtils.get_contents (path, out s);
    } catch (Error e) {}
    return s.strip ();
}

Label label (string text, string? css = null) {
    var l = new Label (text);
    l.xalign = 0;
    if (css != null) l.add_css_class (css);
    return l;
}

int main (string[] args) {
    return new Flowbar ().run (args);
}
