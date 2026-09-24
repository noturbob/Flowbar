# flowbar

A bar that isn't there. No dock, no reserved pixels, all your screen goes to windows. Hit
`Super+/` and flowbar drops in from the top edge. Drive it with single keys, then hit
`Super+/` again (or `Esc`) and it's gone.

Written in [Vala](https://vala.dev) on GTK4 and
[gtk4-layer-shell](https://github.com/wmww/gtk4-layer-shell). It's native code with no
runtime to ship, and GTK's CSS engine handles the animation.

## Install (Arch)

```sh
sudo pacman -S --needed vala gtk4 gtk4-layer-shell
make install          # -> ~/.local/bin/flowbar
```

Runtime tools it calls: `nmcli`, `bluetoothctl`, `wpctl`, `brightnessctl`, `playerctl`,
`kitty` (for Wi‑Fi passwords), and `swaylock`.

## Summon it (niri)

In `~/.config/niri/config.kdl`, under `binds`:

```kdl
Mod+Slash hotkey-overlay-title="Toggle flowbar" { spawn "flowbar"; }
```

The first press starts flowbar and shows it. Later presses toggle the running instance.
Add `spawn-at-startup "flowbar"` if you want the first summon to be instant too (it will
show once at login, so press `Esc`).

## Keys

| key | module     | inside the panel                                   |
|-----|------------|----------------------------------------------------|
| `t` | time       | clock, date, week, uptime                          |
| `c` | calendar   | `h/l` day · `j/k` week · `H/L` month · `g` today   |
| `w` | wifi       | `j/k` pick · `Enter` connect/disconnect · `space` radio · `r` rescan |
| `b` | bluetooth  | `j/k` pick · `Enter` connect/disconnect · `space` power |
| `v` | volume     | `h/l` −/+5% · `m` mute                             |
| `d` | display    | `h/l` brightness −/+5%                             |
| `m` | media      | `space` play/pause · `h/l` prev/next               |
| `s` | system     | cpu, memory, temperature, battery                  |
| `p` | power      | `l` lock · `s` suspend · `e` log out · `r` reboot · `o` power off (press twice) |

Arrow keys work anywhere `h/j/k/l` do. An open panel gets first pick of keys; `Esc` closes
the panel, a second `Esc` hides the bar. Pressing a module's key again closes its panel.

## Theming

Catppuccin Mocha by default. Anything in `~/.config/flowbar/style.css` is layered on top,
for example:

```css
.chip .icon, .accent { color: #89b4fa; }
.chip .key { background: #89b4fa; }
```

Style classes: `.flow` (root, `.hidden` while away), `.bar`, `.chip` (`.active`), `.key`,
`.icon`, `.card`, `.row` (`.cursor`), `.big`, `.sub`, `.dim`, `.status`.
