using Gtk;

// Your own module from config.ini, no Vala needed:
//
//   [custom.weather]
//   key = e
//   icon = 
//   exec = curl -s 'wttr.in/?format=%c+%t'
//   interval = 900
//   on-enter = xdg-open https://wttr.in
//
// then list `weather` in a [bar] section. The chip shows the first line of exec's output,
// the panel shows all of it, Enter runs on-enter.
class Custom : Module {
    string exec;
    string? on_enter;
    Label output = label ("", "sub");

    public Custom (string name) {
        base (Config.str ("custom." + name, "key", name.substring (0, 1)),
              Config.str ("custom." + name, "icon", ""));
        var g = "custom." + name;
        exec = Config.str (g, "exec", "echo 'set exec in [%s]'".printf (g));
        on_enter = Config.maybe (g, "on-enter");
        every = Config.num (g, "interval", 5).clamp (1, 86400);
        output.wrap = true;
        output.max_width_chars = 60;
        output.selectable = false;
        panel.append (label (Config.str (g, "title", name), "status"));
        panel.append (output);
        if (on_enter != null) panel.append (label ("enter  " + on_enter, "dim"));
    }

    public override async void refresh () {
        var out = yield sh ("sh -c " + Shell.quote (exec));
        var lines = out.split ("\n");
        value.label = lines[0];
        output.label = out;
    }

    public override bool on_key (string k) {
        if (k != "Return" || on_enter == null) return false;
        if (Config.flag ("custom." + name, "close-on-enter", true)) dismiss ();
        launch ("sh -c " + Shell.quote (on_enter));
        Timeout.add (400, () => { refresh.begin (); return Source.REMOVE; });
        return true;
    }
}
