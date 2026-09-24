# flowbar

A bar that isn't there. No dock, no reserved pixels, all your screen goes to windows. Hit
`Super+/` and flowbar drops in from the top edge and unfolds from corner to corner. Drive
it with single keys, then hit `Super+/` again (or `Esc`) and it's gone.

Written in [Vala](https://vala.dev) on GTK4 and
[gtk4-layer-shell](https://github.com/wmww/gtk4-layer-shell). It's native code with no
runtime to ship, and GTK's CSS engine handles the animation.

## Install (Arch)

```sh
sudo pacman -S --needed vala gtk4 gtk4-layer-shell
make install          # -> ~/.local/bin/flowbar
```

Runtime tools it calls: `nmcli`, `bluetoothctl`, `wpctl`, `pactl`, `brightnessctl`,
`playerctl`, `wl-clipboard`, `makoctl`, `checkupdates` (pacman-contrib), `kitty` (Wi‑Fi
passwords, updates) and `swaylock`. Optional: `wlsunset` for night light, `yay` for AUR
updates.

## Summon it (niri)

In `~/.config/niri/config.kdl`, under `binds`:

```kdl
Mod+Slash hotkey-overlay-title="Toggle flowbar" { spawn "flowbar"; }
```

and start it hidden at login so the first summon is instant too:

```kdl
spawn-at-startup "flowbar" "--daemon"
```

Without the daemon, the first press cold-starts flowbar (about 1.5s) and later presses
toggle the running instance.

While the bar is up it reserves its strip of the top edge, so niri slides your windows
down to make room and slides them back up when it leaves. Panels float over windows
without resizing them.

## Keys

The bar has three groups: time on the left, tools in the middle, system on the right.

| key | module     | inside the panel                                   |
|-----|------------|----------------------------------------------------|
| `t` | time       | clock, date, week, uptime                          |
| `c` | calendar   | `h/l` day · `j/k` week · `H/L` month · `g` today   |
| `m` | media      | `space` play/pause · `h/l` prev/next               |
| `y` | clipboard  | `j/k` pick · `Enter` copy · `x` delete · `X` clear all |
| `g` | screenshot | `a` area · `s` screen · `w` window · `o` open folder |
| `n` | night      | `n` night light · `f` do not disturb               |
| `u` | updates    | `Enter` update in kitty · `r` check now            |
| `w` | wifi       | `j/k` pick · `Enter` connect/disconnect · `space` radio · `r` rescan |
| `b` | bluetooth  | `j/k` pick · `Enter` connect/disconnect · `space` power |
| `v` | volume     | `h/l` −/+5% · `m` mute · `j/k` + `Enter` default device · `i` inputs/outputs |
| `d` | display    | `h/l` brightness −/+5%                             |
| `s` | system     | cpu, memory, temperature, battery                  |
| `p` | power      | `l` lock · `s` suspend · `e` log out · `r` reboot · `o` power off (press twice) |

Clipboard history is text only, kept in memory, and never records copies a password
manager marks as sensitive. Do not disturb needs this in `~/.config/mako/config`:

```ini
[mode=do-not-disturb]
invisible=1
```

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
# Flowbar
