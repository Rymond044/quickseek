# quickseek

One search box for Hyprland, built on [Quickshell](https://quickshell.org): apps, your own settings
menus (as plugins), a calculator, power actions and web search, in a small animated window.

- Results grouped like a desktop spotlight: top hit, then Applications, plugin groups, Web.
- Learns what you pick (frecency) and which item you pick for a query.
- Typed in the wrong keyboard layout? `цфддзфзук` finds the same as `wallpaper` (ЙЦУКЕН ↔ QWERTY).
- Calculator and unit conversion through `qalc`: `2^10`, `5 km to mi`, `=sqrt(2)`. Enter copies the result.
- Web: the last row is always "Search Google for …"; prefixes `g`, `yt`, `aw` (Arch Wiki).
- Plugins are plain executables speaking JSON Lines, see [docs/plugins.md](docs/plugins.md).
- Runs as a daemon with no timers or polling: idle means zero CPU and no wakeups. The window is
  created on open and destroyed after it closes.

## Requirements

Hyprland, Quickshell ≥ 0.3, a Nerd Font for glyph icons. Optional: `qalc` (libqalculate), `wl-copy`.

## Run

```sh
git clone https://github.com/… ~/Apps/quickseek
qs -p ~/Apps/quickseek -n            # start the daemon (put it in your autostart)
```

Hyprland (Lua config):

```lua
hl.bind("SUPER + ALT + Space", hl.dsp.global("quickseek:toggle"))
```

or the classic config: `bind = SUPER ALT, Space, global, quickseek:toggle`.

IPC: `qs -p ~/Apps/quickseek ipc call quickseek toggle|open|close`, `… folder plugin:<id>`,
`… search <text>`.

Under uwsm, start the daemon with `uwsm app -s b -- qs -p ~/Apps/quickseek -n` and set
`"launchPrefix": ["uwsm", "app", "--"]`, so apps get their own scope instead of living in quickseek's.

## Keys

| key                           | action                                      |
|-------------------------------|---------------------------------------------|
| ↑ ↓, Ctrl+K Ctrl+J            | move                                        |
| Enter                         | run / open folder                           |
| Tab                           | open folder                                 |
| Backspace on an empty query   | leave the folder                            |
| Esc                           | close                                       |

Restart, Shut down and Log out ask for a second Enter.

## Settings

`~/.config/quickseek/settings.json`, applied on save. Everything is optional, see
[examples/settings.json](examples/settings.json):

| key            | default                         |                                                     |
|----------------|---------------------------------|-----------------------------------------------------|
| `width`        | 680                             | logical px, shrinks on narrow monitors              |
| `maxRows`      | 9                               |                                                     |
| `opacity`      | 0.96                            | background opacity                                  |
| `fonts`        | desktop font, Symbols Nerd Font, 11 | `{ "text", "icons", "size" }`; empty `text` = gsettings `font-name`, else sans-serif |
| `shadow`       | true                            | drop shadow under the window                        |
| `colors`       |                                 | path to a colors file, see below                    |
| `launchPrefix` | `[]`                            | prepended to app launches and `xdg-open`            |
| `plugins`      | `[]`                            | see [docs/plugins.md](docs/plugins.md)              |
| `web`          | Google, YouTube, Arch Wiki      | `{ "default": "g", "engines": { "g": { "name", "url": "…%s" } } }` |
| `power`        | systemctl / loginctl            | commands for `lock`, `suspend`, `reboot`, `shutdown`, `logout` |
| `include`      | `[]`                            | more JSON files merged on top (watched too)         |

`include` lets other tools change settings without touching your file, e.g. a script that writes
`{ "opacity": 0.45, "shadow": false }` when a blur effect is on.

## Colors

The first file that exists wins:

1. `colors` from settings;
2. `~/.cache/quickseek/colors.json`: render [templates/wallust.json.j2](templates/wallust.json.j2)
   (wallust) or [templates/matugen.json](templates/matugen.json) (matugen) there;
3. `~/.cache/wal/colors.json` (pywal);
4. a built-in dark palette.

The format is pywal's (`special.background`, `special.foreground`, `colors.color0…15`) with an
optional `accent`, or flat `{ "background", "foreground", "accent" }`. Light or dark look follows the
background. Files are watched: a new wallpaper recolors an open window.

## License

MIT
