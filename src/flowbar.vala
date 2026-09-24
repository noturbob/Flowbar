// flowbar — a bar that isn't there until you summon it.
//
// Run `flowbar` to toggle it: the first run starts the daemon and shows the bar,
// every later run tells the running instance to show or hide it.
// `flowbar --daemon` starts it hidden (for login), so even the first summon is instant.
// `flowbar --peek volume` flashes one module in a small pill (for media keys), see peek.vala.
// While it's up, one key opens a module's panel, Esc backs out.
// Everything is configured in ~/.config/flowbar/config.ini (see config.vala), which is
// watched: saving it rebuilds the bar in place.

using Gtk;

delegate void Step (double eased);

public class Flowbar : Gtk.Application {
    Window win;
    Window? catcher = null; // full-screen and invisible behind the bar: a click on it closes the bar
    Peek peek;
    Module[] loose = {}; // modules made just for peeks, when they aren't on the bar
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
    uint reload_id = 0;
    FileMonitor monitor;
    CssProvider? css_main = null;
    CssProvider? css_user = null;
    int zone = 0;
    int ticks = 0;

    public Flowbar () {
        // Every `flowbar` run hands its arguments to the one already running.
        Object (application_id: "io.github.noturbob.flowbar", flags: ApplicationFlags.HANDLES_COMMAND_LINE);
    }

    public override int command_line (ApplicationCommandLine cmd) {
        var args = cmd.get_arguments ();
        bool daemon = false;
        string? glance_at = null;
        string? open_at = null;
        for (int i = 1; i < args.length; i++) {
            if (args[i] == "--daemon") {
                daemon = true;
            } else if (args[i] == "--peek" && i + 1 < args.length) {
                glance_at = args[++i];
            } else if (args[i] == "--open" && i + 1 < args.length) {
                open_at = args[++i];
            } else {
                cmd.printerr ("usage: flowbar [--daemon] [--peek MODULE] [--open MODULE]\n");
                return 1;
            }
        }
        if (win == null) {
            hold ();
            Config.load ();
            watch_config ();
            build ();
            peek = new Peek (this);
            if (daemon) {
                prewarm ();
                peek.prewarm ();
            }
        } else if (daemon) {
            return 0; // already running
        }
        if (glance_at != null) {
            glance.begin (glance_at);
        } else if (open_at != null) {
            // Straight to one panel, e.g. a bind for the launcher.
            foreach (var m in modules) {
                if (m.name != open_at) continue;
                if (!shown) show_bar ();
                if (active != m) open_panel (m);
            }
        } else if (!daemon) {
            if (shown) hide_bar (); else show_bar ();
        }
        return 0;
    }

    // --peek: a quick look at one module. With the bar open the chip is already on screen,
    // so it just refreshes; otherwise the peek pill shows it.
    async void glance (string name) {
        Module? m = null;
        foreach (var x in modules) {
            if (x.name == name) m = x;
        }
        if (m != null && shown) {
            yield m.refresh ();
            return;
        }
        if (m == null) {
            foreach (var x in loose) {
                if (x.name == name) m = x;
            }
        }
        if (m == null) {
            m = make_module (name);
            if (m == null) return;
            m.name = name;
            loose += m;
        }
        yield peek.show (m);
    }

    // The window (a layer surface) is made once; its contents are rebuilt on every reload,
    // so the space it reserves, and the windows niri pushed down, stay put.
    void build () {
        if (win == null) {
            win = new ApplicationWindow (this);
            GtkLayerShell.init_for_window (win);
            GtkLayerShell.set_namespace (win, "flowbar");
            GtkLayerShell.set_layer (win, GtkLayerShell.Layer.OVERLAY);
            // Anchored to both sides: the bar runs corner to corner.
            GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.TOP, true);
            GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.LEFT, true);
            GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.RIGHT, true);
            GtkLayerShell.set_keyboard_mode (win, GtkLayerShell.KeyboardMode.EXCLUSIVE);

            // Capture phase: our keys win over whatever widget has focus in a panel.
            var keys = new EventControllerKey ();
            keys.propagation_phase = PropagationPhase.CAPTURE;
            keys.key_pressed.connect (on_key);
            ((Widget) win).add_controller (keys);
        }

        bar = new CenterBox ();
        bar.add_css_class ("bar");
        bar.margin_top = bar.margin_start = bar.margin_end = Config.gap ();
        bar.start_widget = section ("left", "workspaces time calendar media");
        bar.center_widget = section ("center", "launcher clipboard screenshot notifications night updates");
        bar.end_widget = section ("right", "wifi bluetooth volume display system power");

        panels = new Stack ();
        panels.transition_type = StackTransitionType.CROSSFADE;
        panels.transition_duration = (uint) Config.ms (220);
        panels.interpolate_size = true;
        panels.hhomogeneous = panels.vhomogeneous = false;
        foreach (var m in modules) panels.add_named (m.panel, m.key);

        card = new Box (Orientation.VERTICAL, 0);
        card.add_css_class ("card");
        card.halign = Align.START; // x is set per panel, under its chip
        card.append (panels);
        drawer = new Revealer ();
        drawer.transition_type = RevealerTransitionType.SLIDE_DOWN;
        drawer.transition_duration = (uint) Config.ms (320);
        drawer.child = card;

        root = new Box (Orientation.VERTICAL, 0);
        root.add_css_class ("flow");
        if (!shown) root.add_css_class ("hidden"); // a reload while open restyles in place
        root.append (bar);
        root.append (drawer);
        win.child = root;

        // Clicks that land on nothing (the clear space around the bar and panel) close it.
        if (mouse ()) {
            var outside = new GestureClick ();
            outside.released.connect ((n, x, y) => {
                var hit = root.pick (x, y, PickFlags.DEFAULT);
                if (hit == root || hit == drawer) hide_bar ();
            });
            root.add_controller (outside);
        }

        load_css ();
    }

    // One group of chips, from a `[bar]` line like `left = time calendar media`.
    Box section (string side, string fallback) {
        var box = new Box (Orientation.HORIZONTAL, 2);
        foreach (var name in Config.list ("bar", side, fallback)) {
            var m = make_module (name);
            if (m == null) continue;
            m.name = name;
            var key = Config.maybe ("keys", name);
            if (key != null) m.rekey (key);
            var icon = Config.maybe ("icons", name);
            if (icon != null) m.icon_label.label = icon;
            foreach (var other in modules) {
                if (other.key == m.key) warning ("config.ini: %s and %s both use key '%s'", other.name, name, m.key);
            }
            modules += m;
            box.append (m.chip);
            if (mouse ()) clickable (m);
        }
        return box;
    }

    static bool mouse () {
        return Config.flag ("bar", "mouse", true);
    }

    // Click a chip to open or close its panel; scroll on it for modules that take it.
    void clickable (Module m) {
        m.chip.cursor = new Gdk.Cursor.from_name ("pointer", null);
        var click = new GestureClick ();
        click.released.connect (() => {
            if (active == m) close_panel (); else open_panel (m);
        });
        m.chip.add_controller (click);
        var scroll = new EventControllerScroll (EventControllerScrollFlags.VERTICAL | EventControllerScrollFlags.DISCRETE);
        scroll.scroll.connect ((dx, dy) => m.on_scroll (dy));
        m.chip.add_controller (scroll);
    }

    static Module? make_module (string name) {
        switch (name) {
        case "workspaces": return new Workspaces ();
        case "launcher": return new Launcher ();
        case "time": return new Clock ();
        case "calendar": return new Cal ();
        case "media": return new Media ();
        case "clipboard": return new Clip ();
        case "screenshot": return new Shot ();
        case "notifications": return new Notifications ();
        case "night": return new Night ();
        case "updates": return new Updates ();
        case "wifi": return new Wifi ();
        case "bluetooth": return new Bluetooth ();
        case "volume": return new Volume ();
        case "display": return new Brightness ();
        case "system": return new Sys ();
        case "power": return new Power ();
        }
        if (("custom." + name) in Config.groups ()) return new Custom (name);
        warning ("config.ini: unknown module '%s'", name);
        return null;
    }

    // Save config.ini or style.css and the bar rebuilds itself.
    void watch_config () {
        DirUtils.create_with_parents (Config.dir (), 0755);
        try {
            monitor = File.new_for_path (Config.dir ()).monitor_directory (FileMonitorFlags.NONE);
            monitor.changed.connect ((file) => {
                var n = file.get_basename ();
                if (n != "config.ini" && n != "style.css") return;
                // Editors often write a file in several steps; act once they're done.
                if (reload_id != 0) Source.remove (reload_id);
                reload_id = Timeout.add (150, () => {
                    reload_id = 0;
                    reload ();
                    return Source.REMOVE;
                });
            });
        } catch (Error e) {
            warning ("can't watch %s: %s", Config.dir (), e.message);
        }
    }

    void reload () {
        Config.load ();
        if (tick_id != 0) Source.remove (tick_id);
        if (card_tick != 0) win.remove_tick_callback (card_tick);
        tick_id = card_tick = 0;
        modules = {};
        active = null;
        build ();
        if (shown) {
            refresh (true);
            reserve (true); // windows only move if the bar's height or margin changed
            tick ();
        }
        message ("reloaded %s", Config.dir ());
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
        if (css_main != null) StyleContext.remove_provider_for_display (display, css_main);
        if (css_user != null) StyleContext.remove_provider_for_display (display, css_user);

        var sb = new StringBuilder (Theme.css_vars ());
        sb.append (CSS);
        // Chips cascade in from the middle of the bar outwards to both corners.
        double mid = (modules.length - 1) / 2.0;
        for (int i = 0; i < modules.length; i++) {
            modules[i].chip.add_css_class ("n%d".printf (i));
            int ms = (int) Config.ms (90 + (i - mid).abs () * 40);
            sb.append (".chip.n%d { transition-delay: %dms, %dms, 0ms; }\n".printf (i, ms, ms));
        }
        sb.append (".flow.hidden .chip { transition-delay: 0ms; }\n");
        css_main = provider ("flowbar", display, STYLE_PROVIDER_PRIORITY_APPLICATION);
        css_main.load_from_string (sb.str);

        var user = Path.build_filename (Config.dir (), "style.css");
        css_user = null;
        if (FileUtils.test (user, FileTest.EXISTS)) {
            css_user = provider (user, display, STYLE_PROVIDER_PRIORITY_USER);
            css_user.load_from_path (user);
        }
    }

    // CSS mistakes are reported with a line number instead of being silently dropped.
    static CssProvider provider (string name, Gdk.Display display, uint priority) {
        var css = new CssProvider ();
        css.parsing_error.connect ((section, err) => {
            warning ("%s:%d: %s", name, (int) section.get_start_location ().lines + 1, err.message);
        });
        StyleContext.add_provider_for_display (display, css, priority);
        return css;
    }

    void show_bar () {
        if (hide_id != 0) {
            Source.remove (hide_id);
            hide_id = 0;
        }
        shown = true;
        refresh (true);
        if (mouse ()) catch_clicks ().present (); // under the bar, so it goes first
        win.present ();
        reveal ();
        tick ();
    }

    // A clear layer over the whole screen, just below the bar, while the bar is open: clicking
    // anywhere outside the bar or its panel lands here and closes it, like any popover.
    Window catch_clicks () {
        if (catcher != null) return catcher;
        catcher = new Window ();
        catcher.application = this;
        GtkLayerShell.init_for_window (catcher);
        GtkLayerShell.set_namespace (catcher, "flowbar-backdrop");
        GtkLayerShell.set_layer (catcher, GtkLayerShell.Layer.TOP);
        foreach (var edge in new GtkLayerShell.Edge[] { TOP, BOTTOM, LEFT, RIGHT }) {
            GtkLayerShell.set_anchor (catcher, edge, true);
        }
        GtkLayerShell.set_exclusive_zone (catcher, -1); // the whole screen, reserved strips included
        GtkLayerShell.set_keyboard_mode (catcher, GtkLayerShell.KeyboardMode.NONE);
        var backdrop = new Box (Orientation.VERTICAL, 0);
        var click = new GestureClick ();
        click.released.connect (() => hide_bar ());
        backdrop.add_controller (click);
        catcher.child = backdrop;
        return catcher;
    }

    // Drop .hidden only once the hidden style has been painted, so the CSS transitions run.
    void reveal () {
        int frames = 0;
        root.add_tick_callback (() => {
            if (++frames < 2) return Source.CONTINUE;
            root.remove_css_class ("hidden");
            reserve (true);
            return Source.REMOVE;
        });
    }

    void tick () {
        tick_id = Timeout.add_seconds (1, () => {
            refresh (false);
            return Source.CONTINUE;
        });
    }

    public void hide_bar () {
        shown = false;
        if (catcher != null) catcher.visible = false;
        close_panel ();
        root.add_css_class ("hidden");
        reserve (false);
        if (tick_id != 0) {
            Source.remove (tick_id);
            tick_id = 0;
        }
        hide_id = Timeout.add ((uint) Config.ms (280), () => {
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
        if (!Config.flag ("bar", "push-windows", true)) return;
        int from = zone;
        // Just the bar's footprint: niri adds its own `gaps` between this strip and the windows.
        // measure() counts the top margin and the CSS border; get_height() leaves the border out.
        int a, b, footprint;
        bar.measure (Orientation.VERTICAL, -1, out a, out footprint, out a, out b);
        int to = on ? footprint : 0;
        if (zone_tick != 0) win.remove_tick_callback (zone_tick);
        // settle in on show, fall away on hide
        zone_tick = tween (Config.ms (on ? 520 : 240), on, (e) => {
            int z = from + (int) ((to - from) * e);
            if (z != zone) GtkLayerShell.set_exclusive_zone (win, zone = z);
        });
    }

    // Call step with 0..1 eased progress every frame for ms; ease-out or ease-in.
    uint tween (double ms, bool ease_out, owned Step step) {
        if (ms <= 0) {
            step (1); // [motion] speed = 0: no animation
            return 0;
        }
        int64 start = -1;
        return win.add_tick_callback ((w, clock) => {
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
        // The panel plus the card's padding and border. measure() counts margins too, and the
        // card's margin is its current x, so take that back out.
        int w = panel_w + card_w - card.margin_start - card.margin_end - stack_w;
        int x = bar.margin_start + (int) p.x + m.chip.get_width () / 2 - w / 2;
        x = int.max (bar.margin_start, int.min (x, root.get_width () - bar.margin_end - w));

        if (card_tick != 0) win.remove_tick_callback (card_tick);
        card_tick = 0;
        if (!drawer.reveal_child) {
            card.margin_start = x;
            return;
        }
        int from = card.margin_start;
        card_tick = tween (Config.ms (320), true, (e) => {
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

        // A panel that takes text (the launcher) gets typed characters, not module keys.
        if (active != null && active.typing && k != "Escape") {
            unichar c = Gdk.keyval_to_unicode (keyval);
            bool plain = (state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) == 0;
            if (c >= 32 && c != 127 && plain) {
                active.on_text (c);
                return true;
            }
            return active.on_key (k == "KP_Enter" ? "Return" : k);
        }

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
    public string name = "";
    public string key;
    public Label key_label;
    public Label icon_label;
    public Box chip = new Box (Orientation.HORIZONTAL, 7);
    public Label value = new Label ("");
    public Box panel = new Box (Orientation.VERTICAL, 6);
    public int every = 1; // refresh interval in seconds while visible
    public bool typing = false; // takes typed text while its panel is open (see on_text)

    protected Module (string key, string icon) {
        this.key = key;
        key_label = label (badge (key), "key");
        icon_label = label (icon, "icon");
        chip.add_css_class ("chip");
        chip.append (key_label);
        chip.append (icon_label);
        value.max_width_chars = 14; // fifteen chips have to share one screen width
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

    // Keys are Gdk key names: a letter, or e.g. F1, comma, slash.
    public void rekey (string k) {
        key = k;
        key_label.label = badge (k);
    }

    static string badge (string k) {
        if (k == "space") return "␣";
        return k.char_count () == 1 ? k.up () : k;
    }

    // Typed characters, for modules with typing = true.
    public virtual void on_text (unichar c) {}

    // Scrolling on the chip: dy is +1 per step down, -1 per step up. Return true if used.
    public virtual bool on_scroll (double dy) {
        return false;
    }

    // 0-100 for modules that have a level (volume, brightness), shown by --peek; -1 if not.
    public virtual double level () {
        return -1;
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
    public signal void activated (); // a row was clicked; pos is that row

    public Picker () {
        Object (orientation: Orientation.VERTICAL, spacing: 2);
    }

    public void set_rows (string[] markup) {
        Widget? c;
        while ((c = get_first_child ()) != null) remove (c);
        for (int i = 0; i < markup.length; i++) {
            var l = label ("", "row");
            l.use_markup = true;
            l.label = markup[i];
            append (l);
            if (Config.flag ("bar", "mouse", true)) pointable (l, i);
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

    // Hovering a row moves the cursor to it, clicking it acts on it.
    void pointable (Label row, int i) {
        row.cursor = new Gdk.Cursor.from_name ("pointer", null);
        var hover = new EventControllerMotion ();
        hover.enter.connect (() => {
            pos = i;
            moved = true;
            paint ();
        });
        row.add_controller (hover);
        var click = new GestureClick ();
        click.released.connect (() => {
            pos = i;
            moved = true;
            paint ();
            activated ();
        });
        row.add_controller (click);
    }

    void paint () {
        int i = 0;
        for (var c = get_first_child (); c != null; c = c.get_next_sibling ()) {
            if (i++ == pos) c.add_css_class ("cursor"); else c.remove_css_class ("cursor");
        }
    }
}

// At most max characters, with an ellipsis if it was cut.
string clip (string s, int max) {
    return s.char_count () > max ? s.substring (0, s.index_of_nth_char (max - 1)) + "…" : s;
}

// "k   name" rows for panels that are a menu of single-key actions. With an owner, clicking
// the row is the same as pressing its key.
Label key_row (string key, string text, Module? owner = null) {
    var row = label ("", "row");
    row.use_markup = true;
    row.label = keyed (key, text);
    if (owner != null && Config.flag ("bar", "mouse", true)) {
        row.add_css_class ("key-row");
        row.cursor = new Gdk.Cursor.from_name ("pointer", null);
        var click = new GestureClick ();
        click.released.connect (() => owner.on_key (key));
        row.add_controller (click);
    }
    return row;
}

string keyed (string key, string text) {
    var shown = key == "Return" ? "enter" : key;
    return "<b><span foreground='%s'>%s</span></b>   %s".printf (Theme.accent (), shown, text);
}

// "on" in the theme's good color, or a dimmed "off", for toggle rows.
string onoff (bool on) {
    return on ? "<span foreground='%s'>on</span>".printf (Theme.color ("good")) : "<span alpha='45%'>off</span>";
}

delegate void SetLevel (int percent);

// Click anywhere along a meter to jump to that level.
void settable (LevelBar meter, owned SetLevel set) {
    if (!Config.flag ("bar", "mouse", true)) return;
    meter.cursor = new Gdk.Cursor.from_name ("pointer", null);
    var click = new GestureClick ();
    click.released.connect ((n, x, y) => {
        int width = meter.get_width ();
        if (width > 0) set (((int) (x / width * 100 + 0.5)).clamp (0, 100));
    });
    meter.add_controller (click);
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

// Run an interactive command in the configured terminal, kept open until you press Enter.
void in_terminal (string cmd) {
    var term = Config.str ("commands", "terminal", "kitty -e");
    launch (term + " sh -c " + Shell.quote (cmd + "; echo; read -rp 'Press Enter to close ' _"));
}

void launch (string cmd) {
    try {
        Process.spawn_command_line_async (cmd);
    } catch (Error e) {
        warning ("%s: %s", cmd, e.message);
    }
}

// A file's contents, or "" if it can't be read.
string slurp (string path) {
    try {
        string s;
        FileUtils.get_contents (path, out s);
        return s.strip ();
    } catch (Error e) {
        return ""; // get_contents nulls its out param on failure
    }
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
