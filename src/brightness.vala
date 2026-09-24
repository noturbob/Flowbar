using Gtk;

class Brightness : Module {
    const string CTL = "brightnessctl --class=backlight ";
    Label big = label ("", "big");
    LevelBar meter = new LevelBar.for_interval (0, 100);

    public Brightness () {
        base ("d", "");
        every = 2;
        panel.width_request = 300;
        panel.append (big);
        panel.append (meter);
        panel.append (label ("h/l −/+%d%%".printf (step ()), "dim"));
    }

    public override async void refresh () {
        // "amdgpu_bl2,backlight,33425,51%,65535"
        var f = (yield sh (CTL + "-m")).split (",");
        if (f.length < 4) {
            value.label = "—";
            return;
        }
        value.label = big.label = f[3];
        meter.value = int.parse (f[3]).clamp (0, 100);
    }

    static int step () {
        return Config.num ("display", "step", 5);
    }

    public override bool on_key (string k) {
        switch (k) {
        case "h": case "j": act.begin (CTL + "set %d%%-".printf (step ())); return true;
        case "l": case "k": act.begin (CTL + "set %d%%+".printf (step ())); return true;
        }
        return false;
    }
}
