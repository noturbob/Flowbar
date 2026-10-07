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
    Lifted root;
    CenterBox bar;
    Box card;
    Revealer drawer;
    Stack panels;
    Module[] modules;
    Module? active = null;
    bool shown = false;
    uint tick_id = 0;
    uint slide_tick = 0;
    uint card_tick = 0;
    uint reload_id = 0;
    FileMonitor monitor;
    CssProvider? css_main = null;
    CssProvider? css_user = null;
    int zone = 0;
    double pos = 0; // 0 hidden, 1 fully slid in
    int ticks = 0;
    public bool igpu = false; // see prefer_igpu()

    public Flowbar () {
        // Every `flowbar` run hands its arguments to the one already running.
        Object (application_id: "io.github.noturbob.flowbar", flags: ApplicationFlags.HANDLES_COMMAND_LINE);
    }

    public override void startup () {
        base.startup ();
        if (!igpu) return;
        // GL is set up now, on the iGPU; apps launched from the bar should pick their own GPU.
        try {
            Gdk.Display.get_default ().prepare_gl ();
        } catch (Error e) {
            warning ("GL: %s", e.message);
        }
        Environment.unset_variable ("__EGL_VENDOR_LIBRARY_FILENAMES");
        Environment.unset_variable ("GDK_DISABLE");
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
                // One quiet refresh so the first summon already has everything, updates too
                // (it hits the network, so wait until that's likely up after login).
                Timeout.add_seconds (20, () => {
                    if (!shown) refresh (true);
                    return Source.REMOVE;
                });
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
        // No size tweening between panels: GtkStack squeezes the incoming panel below its
        // minimum while it interpolates, and GTK warns about it. The crossfade covers the jump.
        panels.interpolate_size = false;
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

        root = new Lifted ();
        root.add_css_class ("flow");
        if (!shown) root.lift = 10000; // off the top edge until it slides in
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
            slide (true); // windows only move if the bar's height or margin changed
            tick ();
        }
        message ("reloaded %s", Config.dir ());
    }

    // The first map of the surface costs 250ms+ (renderer setup). Pay it at login instead:
    // map once fully transparent, without grabbing the keyboard, and unmap on the first frame.
    void prewarm () {
        GtkLayerShell.set_keyboard_mode (win, GtkLayerShell.KeyboardMode.NONE);
        if (mouse ()) catch_clicks ().present ();
        win.present ();
        root.add_tick_callback (() => {
            win.visible = false;
            if (catcher != null) catcher.visible = false;
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
        shown = true;
        refresh (true);
        if (mouse ()) catch_clicks ().present (); // under the bar, so it goes first
        win.present ();
        slide (true);
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
        slide (false);
        if (tick_id != 0) {
            Source.remove (tick_id);
            tick_id = 0;
        }
    }

    // Slide the bar down out of the top edge, or back up into it, and claim its strip of that
    // edge so niri moves every window down to make room (panels still float over the top).
    // The strip changes once, right away, not a little every frame: every change resizes every
    // window, and apps re-flow their text a beat after the last resize (kitty waits up to
    // 0.5s), so a strip that grew with the bar left the text settling after the bar had landed.
    // In one step the windows re-flow while the bar is still sliding.
    void slide (bool on) {
        // Just the bar's footprint: niri adds its own `gaps` between this strip and the windows.
        // measure() counts the top margin and the CSS border; get_height() leaves the border out.
        int a, b, footprint;
        bar.measure (Orientation.VERTICAL, -1, out a, out footprint, out a, out b);
        int z = on && Config.flag ("bar", "push-windows", true) ? footprint : 0;
        if (z != zone) GtkLayerShell.set_exclusive_zone (win, zone = z);
        double from = pos, to = on ? 1 : 0;
        if (slide_tick != 0) win.remove_tick_callback (slide_tick);
        slide_tick = spring ((e) => {
            pos = from + (to - from) * e;
            root.lift = (1 - pos) * footprint;
            root.queue_draw ();
            if (e == 1 && !on) win.visible = false;
        });
    }

    // Call step with 0..1 progress every frame, on niri's default spring (damping-ratio 1,
    // stiffness 800): x = 1 - (1 + wt)e^(-wt), w = sqrt(800). The same curve both ways.
    // It's within niri's epsilon (0.0001) at wt = 11.8, about 420ms before [motion] speed.
    uint spring (owned Step step) {
        double settled = 11.8;
        double ms = Config.ms (settled / Math.sqrt (800) * 1000);
        if (ms <= 0) {
            step (1); // [motion] speed = 0: no animation
            return 0;
        }
        int64 start = -1;
        return win.add_tick_callback ((w, clock) => {
            int64 now = clock.get_frame_time ();
            if (start < 0) start = now;
            double wt = (now - start) / 1000.0 / ms * settled;
            if (wt >= settled) {
                step (1);
                return Source.REMOVE;
            }
            step (1 - (1 + wt) * Math.exp (-wt));
            return Source.CONTINUE;
        });
    }

    // Center the card under its chip, kept on screen. Glide there if a card is already open.
    void place_card (Module m) {
        // Measure against the bar, not the screen: the bar is shifted while it slides.
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
        card_tick = spring ((e) => {
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

// The bar and its panel, drawn lift px higher than laid out: how the bar slides in and out
// of the top edge (a layer surface can't move itself).
class Lifted : Box {
    public double lift = 0;

    public Lifted () {
        Object (orientation: Orientation.VERTICAL, spacing: 0);
    }

    public override void snapshot (Snapshot s) {
        Graphene.Point p = { 0, (float) (-lift) };
        s.translate (p);
        base.snapshot (s);
    }
}

// One letter on the bar: a chip that's always visible and a panel that opens under it.
public abstract class Module {
    public string name = "";
    public string key;
    public Label key_label;
    public Label icon_label;
    public Box chip = new Box (Orientation.HORIZONTAL, 7);
    public Marquee value = new Marquee ();
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
        value.max_width_chars = 14; // fifteen chips have to share one screen width; longer text scrolls
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

// A vertical list with a keyboard cursor; the wifi, bluetooth and notification panels use it.
class Picker : Box {
    public int pos = 0;
    public int count = 0;
    public bool moved = false; // the user has moved the cursor since the panel last reset it
    public signal void activated (); // a row was clicked; pos is that row

    public Picker () {
        Object (orientation: Orientation.VERTICAL, spacing: 2);
    }

    public void set_rows (string[] markup) {
        Widget[] rows = {};
        foreach (var m in markup) {
            var l = label ("", "row");
            l.use_markup = true;
            l.label = m;
            rows += l;
        }
        set_widgets (rows);
    }

    // Any widgets as rows; give them the "row" class for the cursor highlight.
    public void set_widgets (Widget[] rows) {
        Widget? c;
        while ((c = get_first_child ()) != null) remove (c);
        for (int i = 0; i < rows.length; i++) {
            append (rows[i]);
            if (Config.flag ("bar", "mouse", true)) pointable (rows[i], i);
        }
        count = rows.length;
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
    void pointable (Widget row, int i) {
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

// slurp, but read on a worker thread, for files that are slow to read.
async string slurp_async (string path) {
    try {
        uint8[] data;
        yield File.new_for_path (path).load_contents_async (null, out data, null);
        return ((string) data).strip (); // load_contents always nul-terminates
    } catch (Error e) {
        return "";
    }
}

Label label (string text, string? css = null) {
    var l = new Label (text);
    l.xalign = 0;
    if (css != null) l.add_css_class (css);
    return l;
}

// On a hybrid-GPU laptop GTK renders on the NVIDIA card, which powers down when idle and
// takes ~2s to wake: that was a pause before the bar appeared after a while unused. Draw on
// the integrated GPU instead, over GL (the Vulkan loader would pick NVIDIA again).
// Returns whether it set anything, so startup() can clear it for the apps we launch.
bool prefer_igpu () {
    const string MESA = "/usr/share/glvnd/egl_vendor.d/50_mesa.json";
    if (Environment.get_variable ("__EGL_VENDOR_LIBRARY_FILENAMES") != null) return false;
    if (Environment.get_variable ("GDK_DISABLE") != null) return false;
    if (!FileUtils.test (MESA, FileTest.EXISTS)) return false;
    bool nvidia = false, other = false;
    try {
        var drm = Dir.open ("/sys/class/drm");
        string? n;
        while ((n = drm.read_name ()) != null) {
            if (!n.has_prefix ("renderD")) continue;
            var driver = FileUtils.read_link ("/sys/class/drm/%s/device/driver".printf (n));
            if (Path.get_basename (driver) == "nvidia") nvidia = true; else other = true;
        }
    } catch (Error e) {
        return false;
    }
    if (!nvidia || !other) return false;
    Environment.set_variable ("__EGL_VENDOR_LIBRARY_FILENAMES", MESA, true);
    Environment.set_variable ("GDK_DISABLE", "vulkan", true);
    return true;
}

int main (string[] args) {
    var app = new Flowbar ();
    app.igpu = prefer_igpu ();
    return app.run (args);
}
