using Gtk;

class Cal : Module {
    Calendar cal = new Calendar ();

    public Cal () {
        base ("c", "");
        every = 60;
        cal.show_week_numbers = true;
        panel.append (cal);
        panel.append (label ("h/l day · j/k week · H/L month · g today", "dim"));
    }

    public override async void refresh () {
        value.label = new DateTime.now_local ().format ("%a %-d");
    }

    public override bool on_key (string k) {
        var d = cal.get_date ();
        switch (k) {
        case "h": d = d.add_days (-1); break;
        case "l": d = d.add_days (1); break;
        case "k": d = d.add_days (-7); break;
        case "j": d = d.add_days (7); break;
        case "H": d = d.add_months (-1); break;
        case "L": d = d.add_months (1); break;
        case "g": d = new DateTime.now_local (); break;
        default: return false;
        }
        cal.set_date (d);
        return true;
    }
}
