using Gtk;

// A chip's text, at most max_width_chars wide. Text that doesn't fit glides left to show its
// end, holds, and glides back, over and over, but only while it's on screen.
public class Marquee : Widget {
    const double HOLD = 1.5; // seconds at each end
    const double SPEED = 30; // px per second

    public int max_width_chars = 14;
    Label text = new Label ("");
    int over = 0; // px that don't fit
    int shift = 0; // px scrolled
    int64 start = -1;
    uint glide_id = 0;

    public string label {
        get { return text.label; }
        set {
            if (text.label == value) return; // most refreshes repeat the same text
            text.label = value;
            start = -1; // a new song or network name starts from its beginning
            queue_resize ();
        }
    }

    public bool use_markup {
        get { return text.use_markup; }
        set { text.use_markup = value; }
    }

    public Marquee () {
        overflow = Overflow.HIDDEN;
        text.xalign = 0;
        text.set_parent (this);
    }

    public override void dispose () {
        text.unparent ();
        base.dispose ();
    }

    int cap () {
        int w, h;
        text.create_pango_layout (string.nfill (max_width_chars, '0')).get_pixel_size (out w, out h);
        return w;
    }

    public override void measure (Orientation o, int for_size, out int min, out int nat, out int min_base, out int nat_base) {
        text.measure (o, -1, out min, out nat, out min_base, out nat_base);
        if (o == Orientation.HORIZONTAL) min = nat = int.min (nat, cap ());
    }

    public override void size_allocate (int width, int height, int baseline) {
        int min, nat, a, b;
        text.measure (Orientation.HORIZONTAL, -1, out min, out nat, out a, out b);
        over = int.max (nat - width, 0);
        if (over > 0 && glide_id == 0) glide_id = add_tick_callback (glide);
        if (over == 0 && glide_id != 0) {
            remove_tick_callback (glide_id);
            glide_id = 0;
        }
        if (over == 0) shift = 0;
        Graphene.Point p = { -shift, 0 };
        text.allocate (int.max (nat, width), height, baseline, new Gsk.Transform ().translate (p));
    }

    // hold, glide to the end, hold, glide back
    bool glide (Widget w, Gdk.FrameClock clock) {
        int64 now = clock.get_frame_time ();
        if (start < 0) start = now;
        double move = over / SPEED;
        double t = ((now - start) % (int64) (2 * (HOLD + move) * 1e6)) / 1e6;
        double x = t < HOLD ? 0
            : t < HOLD + move ? (t - HOLD) * SPEED
            : t < 2 * HOLD + move ? over
            : over - (t - 2 * HOLD - move) * SPEED;
        if ((int) x != shift) {
            shift = (int) x;
            queue_allocate ();
        }
        return Source.CONTINUE;
    }
}
