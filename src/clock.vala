using Gtk;

class Clock : Module {
    Label time = label ("", "big");
    Label date = label ("", "sub");
    Label meta = label ("", "dim");

    public Clock () {
        base ("t", "");
        panel.append (time);
        panel.append (date);
        panel.append (meta);
    }

    public override async void refresh () {
        var now = new DateTime.now_local ();
        value.label = now.format ("%H:%M");
        time.label = now.format ("%H:%M:%S");
        date.label = now.format ("%A, %-d %B %Y");
        int up = (int) double.parse (slurp ("/proc/uptime").split (" ")[0]);
        meta.label = "week %s · day %s · up %dh %02dm".printf (
            now.format ("%V"), now.format ("%j"), up / 3600, up / 60 % 60);
    }
}
