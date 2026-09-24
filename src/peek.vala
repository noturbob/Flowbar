using Gtk;

// A glance at one module without opening the bar: `flowbar --peek volume` shows a small pill
// at the top with that module's icon, value and level, then lets it fade. Meant for media
// keys: niri changes the volume, flowbar just shows the result.
class Peek {
    const uint LINGER = 1500; // ms after the last peek before it fades
    Window win;
    Box root;
    Label icon = label ("", "icon");
    Label text = label ("", "osd-text");
    LevelBar meter = new LevelBar.for_interval (0, 100);
    uint linger_id = 0;
    uint unmap_id = 0;

    public Peek (Gtk.Application app) {
        win = new Window ();
        win.application = app;
        GtkLayerShell.init_for_window (win);
        GtkLayerShell.set_namespace (win, "flowbar-peek");
        GtkLayerShell.set_layer (win, GtkLayerShell.Layer.OVERLAY);
        GtkLayerShell.set_anchor (win, GtkLayerShell.Edge.TOP, true); // centered: top edge only
        GtkLayerShell.set_keyboard_mode (win, GtkLayerShell.KeyboardMode.NONE);

        var pill = new Box (Orientation.HORIZONTAL, 10);
        pill.add_css_class ("osd");
        pill.margin_top = Config.gap ();
        meter.valign = Align.CENTER;
        pill.append (icon);
        pill.append (text);
        pill.append (meter);

        root = new Box (Orientation.VERTICAL, 0);
        root.add_css_class ("flow");
        root.add_css_class ("peek");
        root.add_css_class ("hidden");
        root.append (pill);
        win.child = root;
    }

    // Map once, invisibly, so the first real peek doesn't pay for renderer setup.
    public void prewarm () {
        win.present ();
        root.add_tick_callback (() => {
            win.visible = false;
            return Source.REMOVE;
        });
    }

    public async void show (Module m) {
        yield m.refresh ();
        icon.label = m.icon_label.label;
        text.label = m.value.label;
        double level = m.level ();
        meter.visible = level >= 0;
        if (level >= 0) meter.value = level.clamp (0, 100);
        if ("muted" in m.value.label) meter.add_css_class ("muted"); else meter.remove_css_class ("muted");

        if (unmap_id != 0) {
            Source.remove (unmap_id);
            unmap_id = 0;
        }
        if (!win.visible) {
            win.present ();
            // Drop .hidden once the hidden style has been painted, so the transition runs.
            int frames = 0;
            root.add_tick_callback (() => {
                if (++frames < 2) return Source.CONTINUE;
                root.remove_css_class ("hidden");
                return Source.REMOVE;
            });
        } else {
            root.remove_css_class ("hidden");
        }

        // Every peek restarts the clock, so holding a volume key keeps it up.
        if (linger_id != 0) Source.remove (linger_id);
        linger_id = Timeout.add (LINGER, () => {
            linger_id = 0;
            root.add_css_class ("hidden");
            unmap_id = Timeout.add ((uint) Config.ms (260), () => {
                unmap_id = 0;
                win.visible = false;
                return Source.REMOVE;
            });
            return Source.REMOVE;
        });
    }
}
