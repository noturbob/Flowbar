// ~/.config/flowbar/config.ini: the one file for theme, layout, keys, icons, commands
// and motion. Every setting has a default, so the file (and any line in it) is optional.
// flowbar watches the file and applies changes the moment you save.

class Config {
    static KeyFile file;

    public static string dir () {
        return Path.build_filename (Environment.get_user_config_dir (), "flowbar");
    }

    public static void load () {
        file = new KeyFile ();
        try {
            file.load_from_file (Path.build_filename (dir (), "config.ini"), KeyFileFlags.NONE);
        } catch (FileError.NOENT e) {
            // no config yet: defaults all the way down
        } catch (Error e) {
            warning ("config.ini: %s (using defaults)", e.message);
        }
    }

    public static string str (string group, string key, string fallback) {
        try {
            // Raw value: get_string would rewrite backslashes (\s, \t) inside commands.
            var v = file.get_value (group, key);
            // Allow `key = value   # comment`. A # with a space before and after it,
            // so colors (#00A2E8) and #-containing commands are left alone.
            var cut = v.index_of (" # ");
            if (cut >= 0) v = v.substring (0, cut);
            v = v.strip ();
            return v != "" ? v : fallback;
        } catch (Error e) {
            return fallback;
        }
    }

    public static string? maybe (string group, string key) {
        var v = str (group, key, "");
        return v != "" ? v : null;
    }

    public static int num (string group, string key, int fallback) {
        var v = str (group, key, "");
        return v != "" ? int.parse (v) : fallback;
    }

    public static double real (string group, string key, double fallback) {
        var v = str (group, key, "");
        return v != "" ? double.parse (v) : fallback;
    }

    public static bool flag (string group, string key, bool fallback) {
        var v = str (group, key, "").down ();
        return v == "" ? fallback : v == "true" || v == "yes" || v == "1" || v == "on";
    }

    // Space- or comma-separated names, e.g. `left = time calendar media`.
    public static string[] list (string group, string key, string fallback) {
        string[] out = {};
        foreach (var w in str (group, key, fallback).split_set (" ,;\t")) {
            if (w != "") out += w;
        }
        return out;
    }

    // Groups like [custom.weather], for user-defined modules.
    public static string[] groups () {
        return file.get_groups ();
    }

    // Animation durations scale with [motion] speed (1.5 matches niri's `slowdown 1.5`).
    public static double ms (double base_ms) {
        return base_ms * real ("motion", "speed", 1.0).clamp (0, 10);
    }
}

// Colors come from a preset, and any single color can be overridden in [theme].
namespace Theme {
    // name: accent, accent-2, background, foreground, good
    const string[] PRESETS = {
        "azure",       "#00A2E8", "#89dceb", "#11111b", "#cdd6f4", "#a6e3a1",
        "catppuccin",  "#cba6f7", "#f5c2e7", "#11111b", "#cdd6f4", "#a6e3a1",
        "tokyo-night", "#7aa2f7", "#bb9af7", "#16161e", "#c0caf5", "#9ece6a",
        "gruvbox",     "#fe8019", "#fabd2f", "#1d2021", "#ebdbb2", "#b8bb26",
        "nord",        "#88c0d0", "#81a1c1", "#2e3440", "#eceff4", "#a3be8c",
        "rose-pine",   "#c4a7e7", "#ebbcba", "#191724", "#e0def4", "#9ccfd8",
    };
    const string[] COLORS = { "accent", "accent-2", "background", "foreground", "good" };

    public string color (string name) {
        var preset = Config.str ("theme", "preset", "azure");
        int row = 0;
        for (int i = 0; i < PRESETS.length; i += 6) {
            if (PRESETS[i] == preset) row = i;
        }
        int col = 0;
        while (COLORS[col] != name) col++;
        return Config.str ("theme", name, PRESETS[row + 1 + col]);
    }

    public string accent () {
        return color ("accent");
    }

    // The :root block the stylesheet reads. Your style.css can use these too.
    public string css_vars () {
        var sb = new StringBuilder (":root {\n");
        foreach (var c in COLORS) sb.append ("    --%s: %s;\n".printf (c, color (c)));
        sb.append ("    --opacity: %s;\n".printf (Config.str ("theme", "opacity", "0.94")));
        sb.append ("    --font: \"%s\";\n".printf (Config.str ("theme", "font", "CommitMono Nerd Font")));
        sb.append ("    --font-size: %dpx;\n".printf (Config.num ("theme", "font-size", 15)));
        sb.append ("    --radius: %dpx;\n".printf (Config.num ("theme", "radius", 22)));
        // Durations, pre-scaled by [motion] speed.
        string[] names = { "drop", "fade", "chip", "leave", "quick" };
        int[] base_ms = { 640, 360, 560, 220, 180 };
        for (int i = 0; i < names.length; i++) {
            sb.append ("    --t-%s: %dms;\n".printf (names[i], (int) Config.ms (base_ms[i])));
        }
        sb.append ("}\n");
        return sb.str;
    }

    public bool known (string preset) {
        for (int i = 0; i < PRESETS.length; i += 6) {
            if (PRESETS[i] == preset) return true;
        }
        return false;
    }
}
