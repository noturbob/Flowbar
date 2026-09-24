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
        panel.append (label ("h/l −/+5%", "dim"));
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

    public override bool on_key (string k) {
        switch (k) {
        case "h": case "j": act.begin (CTL + "set 5%-"); return true;
        case "l": case "k": act.begin (CTL + "set 5%+"); return true;
        }
        return false;
    }
}
