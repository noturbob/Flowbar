// Catppuccin Mocha. Override anything in ~/.config/flowbar/style.css.
const string CSS = """
window { background: transparent; }

.flow {
    padding: 10px 32px 40px;
    font-family: "CommitMono Nerd Font";
    font-size: 14px;
    color: #cdd6f4;
}

.bar, .card {
    background: alpha(#11111b, 0.88);
    border: 1px solid alpha(#cdd6f4, 0.08);
    box-shadow: 0 14px 36px alpha(black, 0.5), inset 0 1px alpha(white, 0.05);
}

/* summon: the pill drops in and settles, chips cascade in after it */
.bar {
    padding: 5px;
    border-radius: 20px;
    transition: opacity 360ms ease-out, transform 560ms cubic-bezier(0.16, 1, 0.3, 1);
}
.flow.hidden .bar {
    opacity: 0;
    transform: translateY(-22px) scale(0.9);
    transition: opacity 200ms ease-in, transform 240ms ease-in;
}

.chip {
    padding: 6px 12px;
    border-radius: 15px;
    transition: opacity 420ms ease-out, transform 560ms cubic-bezier(0.16, 1, 0.3, 1), background-color 180ms ease;
}
.flow.hidden .chip {
    opacity: 0;
    transform: translateY(-8px);
    transition: opacity 120ms ease-in, transform 120ms ease-in, background-color 0ms;
}
.chip:nth-child(1)  { transition-delay: 60ms,  60ms,  0ms; }
.chip:nth-child(2)  { transition-delay: 95ms,  95ms,  0ms; }
.chip:nth-child(3)  { transition-delay: 130ms, 130ms, 0ms; }
.chip:nth-child(4)  { transition-delay: 165ms, 165ms, 0ms; }
.chip:nth-child(5)  { transition-delay: 200ms, 200ms, 0ms; }
.chip:nth-child(6)  { transition-delay: 235ms, 235ms, 0ms; }
.chip:nth-child(7)  { transition-delay: 270ms, 270ms, 0ms; }
.chip:nth-child(8)  { transition-delay: 305ms, 305ms, 0ms; }
.chip:nth-child(9)  { transition-delay: 340ms, 340ms, 0ms; }
.chip:nth-child(10) { transition-delay: 375ms, 375ms, 0ms; }
.flow.hidden .chip  { transition-delay: 0ms; }

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
""";
