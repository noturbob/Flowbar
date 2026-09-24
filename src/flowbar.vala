// flowbar — a bar that isn't there until you summon it.
//
// Run `flowbar` to toggle it: the first run starts the daemon and shows the bar,
// every later run tells the running instance to show or hide it.
// `flowbar --daemon` starts it hidden (for login), so even the first summon is instant.
// While it's up, one key opens a module's panel, Esc backs out.

using Gtk;

delegate void Step (double eased);

public class Flowbar : Gtk.Application {
    public static bool start_hidden = false;
    Window win;
    Box root;
    CenterBox bar;
    Box card;
    Revealer drawer;
    Stack panels;
    Module[] modules;
    Module? active = null;
    bool shown = false;
    uint tick_id = 0;
    uint hide_id = 0;
    uint zone_tick = 0;
    uint card_tick = 0;
    int zone = 0;
    int ticks = 0;

    public Flowbar () {
        Object (application_id: "io.github.noturbob.flowbar");
    }

    public override void activate () {
        if (win == null) {
            build ();
            if (start_hidden) {
                prewarm ();
                return;
            }
        }
        if (shown) hide_bar (); else show_bar ();
    }

    void build () {
        hold ();
        win = new ApplicationWindow (this);
        GtkLayerShell.init_for_window (win);
        GtkLayerShell.set_namespace (win, "flowbar");
        GtkLayerShell.set_layer (win, GtkLayerShell.Layer.OVERLAY);
        // Anchored to both sides: the bar runs corner to corner.
        GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.TOP, true);
        GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.LEFT, true);
        GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.RIGHT, true);
        GtkLayerShell.set_keyboard_mode (win, GtkLayerShell.KeyboardMode.EXCLUSIVE);

        Module[] left = { new Clock (), new Cal (), new Media () };
        Module[] center = {};
        Module[] right = { new Wifi (), new Bluetooth (), new Volume (), new Brightness (), new Sys (), new Power () };

        bar = new CenterBox ();
        bar.add_css_class ("bar");
        bar.margin_top = bar.margin_start = bar.margin_end = 10;
        bar.start_widget = section (left);
        bar.center_widget = section (center);
        bar.end_widget = section (right);
        foreach (var m in left) modules += m;
        foreach (var m in center) modules += m;
        foreach (var m in right) modules += m;

        panels = new Stack ();
        panels.transition_type = StackTransitionType.CROSSFADE;
        panels.transition_duration = 220;
        panels.interpolate_size = true;
        panels.hhomogeneous = panels.vhomogeneous = false;
        foreach (var m in modules) panels.add_named (m.panel, m.key);

        card = new Box (Orientation.VERTICAL, 0);
        card.add_css_class ("card");
        card.halign = Align.START; // x is set per panel, under its chip
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

    static Box section (Module[] mods) {
        var box = new Box (Orientation.HORIZONTAL, 2);
        foreach (var m in mods) box.append (m.chip);
        return box;
    }

    // The first map of the surface costs 250ms+ (renderer setup). Pay it at login instead:
    // map once fully transparent, without grabbing the keyboard, and unmap on the first frame.
    void prewarm () {
        GtkLayerShell.set_keyboard_mode (win, GtkLayerShell.KeyboardMode.NONE);
        win.present ();
        root.add_tick_callback (() => {
            win.visible = false;
            GtkLayerShell.set_keyboard_mode (win, GtkLayerShell.KeyboardMode.EXCLUSIVE);
            return Source.REMOVE;
        });
    }

    void load_css () {
        var display = Gdk.Display.get_default ();
        var css = new CssProvider ();
        // Chips cascade in from the middle of the bar outwards to both corners.
        var cascade = new StringBuilder (CSS);
        double mid = (modules.length - 1) / 2.0;
        for (int i = 0; i < modules.length; i++) {
            modules[i].chip.add_css_class ("n%d".printf (i));
            int ms = 90 + (int) ((i - mid).abs () * 40);
            cascade.append (".chip.n%d { transition-delay: %dms, %dms, 0ms; }\n".printf (i, ms, ms));
        }
        cascade.append (".flow.hidden .chip { transition-delay: 0ms; }\n");
        css.load_from_string (cascade.str);
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
            reserve (true);
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
        reserve (false);
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

    // Claim the bar's strip of the top edge so niri slides every window down to make room,
    // the way it slides columns aside for a new window. Panels still float over the top.
    // niri snaps windows to a new working area without animating, so we grow the strip a
    // little every frame, eased like the bar's own drop, and the windows glide with it.
    void reserve (bool on) {
        int from = zone;
        int to = on ? bar.margin_top + bar.get_height () + 6 : 0;
        if (zone_tick != 0) root.remove_tick_callback (zone_tick);
        // settle in on show, fall away on hide
        zone_tick = tween (on ? 520 : 240, on, (e) => {
            int z = from + (int) ((to - from) * e);
            if (z != zone) GtkLayerShell.set_exclusive_zone (win, zone = z);
        });
    }

    // Call step with 0..1 eased progress every frame for ms; ease-out or ease-in.
    uint tween (double ms, bool ease_out, owned Step step) {
        int64 start = -1;
        return root.add_tick_callback ((w, clock) => {
            int64 now = clock.get_frame_time ();
            if (start < 0) start = now;
            double t = ((now - start) / 1000.0 / ms).clamp (0, 1);
            double u = 1 - t;
            step (ease_out ? 1 - u * u * u * u : t * t);
            return t < 1 ? Source.CONTINUE : Source.REMOVE;
        });
    }

    // Center the card under its chip, kept on screen. Glide there if a card is already open.
    void place_card (Module m) {
        // Measure against the bar, not the screen: the bar is scaled while it unfolds.
        Graphene.Point origin = { 0, 0 };
        Graphene.Point p;
        m.chip.compute_point (bar, origin, out p);
        int a, b, card_w, stack_w, panel_w;
        card.measure (Orientation.HORIZONTAL, -1, out a, out card_w, out a, out b);
        panels.measure (Orientation.HORIZONTAL, -1, out a, out stack_w, out a, out b);
        m.panel.measure (Orientation.HORIZONTAL, -1, out a, out panel_w, out a, out b);
        int w = panel_w + card_w - stack_w; // the panel plus the card's padding and border
        int x = bar.margin_start + (int) p.x + m.chip.get_width () / 2 - w / 2;
        x = int.max (bar.margin_start, int.min (x, root.get_width () - bar.margin_end - w));

        if (card_tick != 0) root.remove_tick_callback (card_tick);
        card_tick = 0;
        if (!drawer.reveal_child) {
            card.margin_start = x;
            return;
        }
        int from = card.margin_start;
        card_tick = tween (320, true, (e) => {
            card.margin_start = from + (int) ((x - from) * e);
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
        m.opened ();
        m.refresh.begin ();
        place_card (m);
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

    // Called as the panel opens, before its refresh.
    public virtual void opened () {}

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
    public bool moved = false; // the user has moved the cursor since the panel last reset it

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
        moved = true;
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
    Flowbar.start_hidden = "--daemon" in args;
    // Our only flag is handled above; GApplication would reject it as unknown.
    return new Flowbar ().run ({ args[0] });
}
