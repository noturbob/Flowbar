// Catppuccin Mocha. Override anything in ~/.config/flowbar/style.css.
const string CSS = """
window { background: transparent; }

.flow {
    padding-bottom: 40px; /* room for the shadow; the bar's own margins place it */
    font-family: "CommitMono Nerd Font";
    font-size: 15px;
    color: #cdd6f4;
}

.bar, .card {
    background: alpha(#11111b, 0.94);
    border: 1px solid alpha(#cdd6f4, 0.08);
    box-shadow: 0 14px 36px alpha(black, 0.5), inset 0 1px alpha(white, 0.05);
}

/* summon: the bar drops in and unfolds from the middle out to both corners,
   then the chips ripple outwards after it (delays are generated per chip) */
.bar {
    padding: 6px;
    border-radius: 22px;
    transition: opacity 360ms ease-out, transform 640ms cubic-bezier(0.16, 1, 0.3, 1);
}
.flow.hidden .bar {
    opacity: 0;
    transform: translateY(-22px) scale(0.35, 0.85);
    transition: opacity 200ms ease-in, transform 240ms ease-in;
}

.chip {
    padding: 7px 14px;
    border-radius: 15px;
    transition: opacity 420ms ease-out, transform 560ms cubic-bezier(0.16, 1, 0.3, 1), background-color 180ms ease;
}
.flow.hidden .chip {
    opacity: 0;
    transform: translateY(-8px);
    transition: opacity 120ms ease-in, transform 120ms ease-in, background-color 0ms;
}

.chip.active { background: alpha(#cba6f7, 0.16); }
.chip .key {
    font-size: 10px;
    font-weight: bold;
    color: #11111b;
    background: alpha(#cba6f7, 0.8);
    border-radius: 6px;
    padding: 1px 5px;
}
.chip.active .key { background: #f5c2e7; }
.chip .icon { color: #cba6f7; }

.card {
    margin-top: 10px;
    padding: 18px 22px;
    border-radius: 22px;
}

.big { font-size: 44px; font-weight: bold; letter-spacing: 2px; }
.sub { font-size: 15px; }
.dim { font-size: 12px; color: alpha(#cdd6f4, 0.5); }
.accent { color: #cba6f7; }

.row { padding: 5px 10px; border-radius: 10px; }
.row.cursor { background: alpha(#cba6f7, 0.18); }
.status { font-size: 15px; font-weight: bold; margin-bottom: 4px; }

levelbar trough { background: alpha(#cdd6f4, 0.08); border: none; border-radius: 99px; min-height: 8px; }
levelbar block { border: none; border-radius: 99px; min-height: 8px; }
levelbar block.filled, levelbar block.low, levelbar block.high, levelbar block.full { background: #cba6f7; }
levelbar block.empty { background: transparent; }
levelbar.muted block.filled { background: alpha(#cdd6f4, 0.25); }

calendar { background: transparent; border: none; color: #cdd6f4; }
calendar > header { border: none; padding-bottom: 6px; }
calendar > header button { background: none; border: none; color: #cba6f7; }
calendar > grid { padding: 2px; }
calendar > grid > label { padding: 4px 6px; border-radius: 8px; }
calendar > grid > label.day-name { color: #cba6f7; font-weight: bold; }
calendar > grid > label.week-number { color: alpha(#cdd6f4, 0.35); }
calendar > grid > label.other-month { color: alpha(#cdd6f4, 0.25); }
calendar > grid > label.today { color: #f5c2e7; font-weight: bold; box-shadow: inset 0 -2px #f5c2e7; }
calendar > grid > label:selected { background: #cba6f7; color: #11111b; }
""";
