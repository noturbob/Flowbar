using Gtk;

class Sys : Module {
    Grid grid = new Grid ();
    LevelBar[] bars = {};
    Label[] vals = {};
    string temp = "";
    string battery = "";
    int64 last_idle = 0;
    int64 last_total = 0;

    public Sys () {
        base ("s", "");
        panel.width_request = 320;
        grid.column_spacing = 14;
        grid.row_spacing = 10;
        string[] names = { "cpu", "mem", "temp", "bat" };
        for (int i = 0; i < names.length; i++) {
            var bar = new LevelBar.for_interval (0, 100);
            bar.hexpand = true;
            bar.valign = Align.CENTER;
            var v = label ("", "dim");
            v.xalign = 1;
            grid.attach (label (names[i], "accent"), 0, i);
            grid.attach (bar, 1, i);
            grid.attach (v, 2, i);
            bars += bar;
            vals += v;
        }
        panel.append (grid);

        foreach (var name in dir ("/sys/class/hwmon")) {
            var d = "/sys/class/hwmon/" + name;
            if (slurp (d + "/name") in "k10temp coretemp zenpower".split (" ")) temp = d + "/temp1_input";
        }
        foreach (var name in dir ("/sys/class/power_supply")) {
            if (name.has_prefix ("BAT")) battery = "/sys/class/power_supply/" + name;
        }
    }

    public override async void refresh () {
        // cpu: busy share of jiffies since the last tick
        int64 total = 0, idle = 0;
        int i = 0;
        foreach (var n in slurp ("/proc/stat").split ("\n")[0].split (" ")) {
            if (n == "" || n == "cpu") continue;
            total += int64.parse (n);
            if (i == 3 || i == 4) idle += int64.parse (n); // idle + iowait
            i++;
        }
        int cpu = total > last_total ? (int) (100 * (1 - (double) (idle - last_idle) / (total - last_total))) : 0;
        last_idle = idle;
        last_total = total;
        set_row (0, cpu, "%d%%".printf (cpu));

        int64 mem_total = 0, mem_free = 0;
        foreach (var line in slurp ("/proc/meminfo").split ("\n")) {
            var kb = int64.parse (line.substring (line.index_of (":") + 1).replace ("kB", "").strip ());
            if (line.has_prefix ("MemTotal:")) mem_total = kb;
            if (line.has_prefix ("MemAvailable:")) mem_free = kb;
        }
        if (mem_total > 0) {
            set_row (1, (int) (100 * (mem_total - mem_free) / mem_total),
                "%.1f / %.1f G".printf ((mem_total - mem_free) / 1048576.0, mem_total / 1048576.0));
        }

        int c = int.parse (slurp (temp)) / 1000;
        set_row (2, c, temp == "" ? "—" : "%d°C".printf (c));

        if (battery == "") {
            value.label = "cpu %d%%".printf (cpu);
            set_row (3, 0, "—");
            return;
        }
        int cap = int.parse (slurp (battery + "/capacity"));
        var status = slurp (battery + "/status");
        value.label = (status == "Charging" ? " " : "") + "%d%%".printf (cap);
        set_row (3, cap, "%d%% %s".printf (cap, status.down ()));
    }

    void set_row (int i, int pct, string text) {
        bars[i].value = pct.clamp (0, 100);
        vals[i].label = text;
    }

    static string[] dir (string path) {
        string[] names = {};
        try {
            var d = Dir.open (path);
            string? n;
            while ((n = d.read_name ()) != null) names += n;
        } catch (Error e) {}
        return names;
    }
}
