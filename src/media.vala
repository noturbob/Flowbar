using Gtk;

class Media : Module {
    Label title = label ("", "status");
    Label artist = label ("", "sub");
    Label state = label ("", "dim");

    public Media () {
        base ("m", "");
        panel.width_request = 320;
        title.max_width_chars = artist.max_width_chars = 36;
        title.ellipsize = artist.ellipsize = Pango.EllipsizeMode.END;
        panel.append (title);
        panel.append (artist);
        panel.append (state);
        panel.append (label ("space play/pause · h/l prev/next", "dim"));
    }

    public override async void refresh () {
        // One field per line; title last so it can't shift the others.
        var fmt = Shell.quote ("{{playerName}}\n{{status}}\n{{artist}}\n{{title}}");
        var f = (yield sh ("playerctl metadata --format " + fmt)).split ("\n", 4);
        if (f.length < 4) {
            value.label = "—";
            title.label = "Nothing playing";
            artist.visible = state.visible = false;
            return;
        }
        value.label = (f[1] == "Playing" ? "" : " ") + f[3];
        title.label = f[3];
        artist.label = f[2];
        artist.visible = f[2] != "";
        state.visible = true;
        state.label = "%s · %s".printf (f[1].down (), f[0]);
    }

    public override bool on_key (string k) {
        switch (k) {
        case "space": act.begin ("playerctl play-pause"); return true;
        case "h": act.begin ("playerctl previous"); return true;
        case "l": act.begin ("playerctl next"); return true;
        }
        return false;
    }
}
