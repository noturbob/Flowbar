// The stylesheet. Every color, the font, the radius and every duration are CSS variables
// set from config.ini (see Theme.css_vars); ~/.config/flowbar/style.css is layered on top
// and can use the same variables.
const string CSS = """
window { background: transparent; }

.flow {
    padding-bottom: 40px; /* room for the shadow; the bar's own margins place it */
    font-family: var(--font);
    font-size: var(--font-size);
    color: var(--foreground);
}

.bar, .card {
    background: alpha(var(--background), var(--opacity));
    border: 1px solid alpha(var(--foreground), 0.08);
    box-shadow: 0 14px 36px alpha(black, 0.5), inset 0 1px alpha(white, 0.05);
}

/* summon: the bar drops in and unfolds from the middle out to both corners,
   then the chips ripple outwards after it (delays are generated per chip) */
/* sized like a waybar: chips fill its height edge to edge */
.bar {
    min-height: calc(var(--bar-height) - 2px); /* height includes the 1px border */
    padding: 0;
    border-radius: var(--radius);
    transition: opacity var(--t-fade) ease-out, transform var(--t-drop) cubic-bezier(0.16, 1, 0.3, 1);
}
.flow.hidden .bar {
    opacity: 0;
    transform: translateY(-22px) scale(0.35, 0.85);
    transition: opacity var(--t-quick) ease-in, transform var(--t-leave) ease-in;
}

.chip {
    padding: 0 12px;
    border-radius: var(--radius);
    transition: opacity var(--t-fade) ease-out, transform var(--t-chip) cubic-bezier(0.16, 1, 0.3, 1), background-color var(--t-quick) ease;
}
.flow.hidden .chip {
    opacity: 0;
    transform: translateY(-8px);
    transition: opacity 120ms ease-in, transform 120ms ease-in, background-color 0ms;
}

.chip.active { background: alpha(var(--accent), 0.18); }
.chip .key {
    font-size: 10px;
    font-weight: bold;
    color: var(--background);
    background: alpha(var(--accent), 0.85);
    border-radius: 6px;
    padding: 1px 5px;
}
.chip.active .key { background: var(--accent-2); }
.chip .icon { color: var(--accent); }

.card {
    margin-top: var(--gap);
    padding: 18px 22px;
    border-radius: var(--radius);
}

/* --peek: one module in a small pill at the top, e.g. on a volume key */
.osd {
    padding: 0 16px;
    min-height: calc(var(--bar-height) - 2px);
    border-radius: var(--radius);
    background: alpha(var(--background), var(--opacity));
    border: 1px solid alpha(var(--foreground), 0.08);
    box-shadow: 0 10px 28px alpha(black, 0.45);
    transition: opacity var(--t-fade) ease-out, transform var(--t-chip) cubic-bezier(0.16, 1, 0.3, 1);
}
.peek.hidden .osd {
    opacity: 0;
    transform: translateY(-14px) scale(0.92);
    transition: opacity var(--t-quick) ease-in, transform var(--t-leave) ease-in;
}
.osd .icon { color: var(--accent); }
.osd levelbar { min-width: 160px; }
.osd levelbar trough, .osd levelbar block { min-height: 6px; }

.big { font-size: 44px; font-weight: bold; letter-spacing: 2px; }
.sub { font-size: var(--font-size); }
.dim { font-size: 12px; color: alpha(var(--foreground), 0.5); }
.accent { color: var(--accent); }

.row { padding: 5px 10px; border-radius: 10px; }
.row.cursor { background: alpha(var(--accent), 0.2); }
.status { font-size: var(--font-size); font-weight: bold; margin-bottom: 4px; }

levelbar trough { background: alpha(var(--foreground), 0.08); border: none; border-radius: 99px; min-height: 8px; }
levelbar block { border: none; border-radius: 99px; min-height: 8px; }
levelbar block.filled, levelbar block.low, levelbar block.high, levelbar block.full { background: var(--accent); }
levelbar block.empty { background: transparent; }
levelbar.muted block.filled { background: alpha(var(--foreground), 0.25); }

calendar { background: transparent; border: none; color: var(--foreground); }
calendar > header { border: none; padding-bottom: 6px; }
calendar > header button { background: none; border: none; color: var(--accent); }
calendar > grid { padding: 2px; }
calendar > grid > label { padding: 4px 6px; border-radius: 8px; }
calendar > grid > label.day-name { color: var(--accent); font-weight: bold; }
calendar > grid > label.week-number { color: alpha(var(--foreground), 0.35); }
calendar > grid > label.other-month { color: alpha(var(--foreground), 0.25); }
calendar > grid > label.today { color: var(--accent-2); font-weight: bold; box-shadow: inset 0 -2px var(--accent-2); }
calendar > grid > label:selected { background: var(--accent); color: var(--background); }
""";
