# quickseek

One search box for Hyprland, built on [Quickshell](https://quickshell.org): apps, files, clipboard
history, emoji, shell commands, your own settings menus (as plugins), a calculator, session actions and
web search, in a small animated window.

<p align="center"><img src="docs/media/demo.webp" width="736" alt="quickseek: apps, calculator, wrong layout, web, a plugin folder"></p>

- Results grouped like a desktop spotlight: top hit, then Applications, plugin groups, Web.
- Files and folders in your home after the `f` prefix (`f report`), from a private `plocate` index
  plus a live look at Downloads, Desktop and Documents.
- Learns what you pick (frecency) and which item you pick for a query. Ctrl+P pins anything to the top.
- Typed in the wrong keyboard layout? `цфддзфзук` finds the same as `wallpaper` (ЙЦУКЕН ↔ QWERTY).
- Calculator and unit conversion through `qalc`: `2^10`, `5 km to mi`, `=sqrt(2)`, `100 usd to eur`
  (exchange rates older than a day are refreshed in the background). Enter copies the result.
- Clipboard history from [clipse](https://github.com/savedra1/clipse) after `v `, emoji with English
  and Russian names after `:` (`:fire`, `:огонь`), a shell command in a terminal after `>`.
- → or Ctrl+O on any result: what else can be done with it (open with, copy path, trash, hide, unpin…).
- Space after moving through the list previews the selected file or clipboard entry: text, images,
  a PDF's first page, a video frame. Beside the window when the screen has room, else in its place.
- Web: the last row is always "Search Google for …"; prefixes `g`, `yt`, `aw` (Arch Wiki).
- Plugins are plain executables speaking JSON Lines, see [docs/plugins.md](docs/plugins.md).
- Runs as a daemon with no timers or polling: idle means zero CPU and no wakeups. The window is
  created on open and destroyed after it closes. See [Cost](#cost).

## Screenshots

| | |
|:-:|:-:|
| ![Applications](docs/media/apps.webp) | ![Plugins next to apps and system actions](docs/media/power.webp) |
| Applications | Plugins next to apps and system actions |
| ![Calculator](docs/media/calculator.webp) | ![Wrong keyboard layout](docs/media/layout.webp) |
| Calculator and unit conversion | Wrong keyboard layout |
| ![Plugin folder](docs/media/plugin-folder.webp) | |
| A plugin opened as a folder (Tab) | |

## Requirements

Hyprland, Quickshell ≥ 0.3, a Nerd Font for glyph icons. Optional: `fd` and `plocate` (files),
`qalc` (libqalculate), `wl-copy`, `clipse` (clipboard history), `file` (preview; `pdftoppm`,
`ffmpeg`, `vipsthumbnail` for PDF pages, video frames and other image formats), an emoji font.

Icons come from the Qt icon theme. If file and folder icons show up as plain glyphs, Qt has no
theme: set `QT_QPA_PLATFORMTHEME` (e.g. `kde`, `gtk3`) or `QS_ICON_THEME=Adwaita` for the daemon.

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
`… folder files|clipboard|command|emoji|session`, `… search <text>`. For scripts and tests: `… rows`
prints what the window shows, `… key esc|down|ctrl+o|…` presses a key, `… type <text>` sets the query.

Under uwsm, start the daemon with `uwsm app -s b -- qs -p ~/Apps/quickseek -n` and set
`"launchPrefix": ["uwsm", "app", "--"]`, so apps get their own scope instead of living in quickseek's.

## Keys

| key                           | action                                      |
|-------------------------------|---------------------------------------------|
| ↑ ↓, Ctrl+K Ctrl+J            | move                                        |
| Enter                         | run / open folder                           |
| Alt+Enter                     | show a file in its folder                   |
| → at the end of the query, Ctrl+O | actions for the selected result         |
| Space after ↑ ↓               | preview the selected file or clipboard entry |
| Ctrl+P                        | pin / unpin                                 |
| Tab                           | open folder; in `>` complete the command    |
| `f` + space, `v` + space      | search files / clipboard history only       |
| `:` / `>`                     | emoji / run a command in a terminal         |
| Backspace on an empty query   | leave the folder                            |
| Esc                           | close the preview, leave the folder, menu or prompt; close from the top |

The window stays mapped until every key pressed in it is released, so nothing typed into quickseek
ends up in the window below.

Restart, Shut down and Log out ask for a second Enter.

## Files

Files are searched only after the prefix: type `f`, a space and the name (`f invoice`). The prefix turns
into a "Find files ›" chip; Backspace on an empty query leaves it. `а` (the same key in the Russian
layout) works too. Until you type a name the folder shows pinned and recently opened files. Pinned
files also show up in the normal search. Set `"files": { "inline": true }` to mix files into every
search instead (that runs `plocate` on every keystroke and lists the live folders on every open).

`bin/quickseek-files` keeps a [plocate](https://plocate.sesse.net) index of `$HOME` in
`~/.cache/quickseek/` (about half a second of CPU for 75 000 files). It skips hidden paths, `.cache`,
Trash, Steam, `node_modules`, `.git` and whatever `~/.config/quickseek/ignore` lists (gitignore
syntax). A query that starts with a dot also searches hidden files up to three levels deep:
`.zshrc`, `.config`.

The index is rebuilt when the window opens and the index is older than two hours, and from
"quickseek settings › Rebuild file index". Downloads, Desktop and Documents are listed live on every
open, so new downloads show up right away. To keep the index fresh without opening the window, enable
the timer (every 30 min; on battery only when the index is older than 2 h):

```sh
# edit the path in systemd/quickseek-index.service if quickseek is not in ~/Apps/quickseek
systemctl --user link ~/Apps/quickseek/systemd/quickseek-index.{service,timer}
systemctl --user enable --now quickseek-index.timer
```

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
| `launchPrefix` | `[]`                            | prepended to app launches and the opener            |
| `opener`       | `["gio", "open"]`               | opens files, folders and URLs; unlike `xdg-open`, gio starts terminal apps such as nvim in a terminal |
| `emptyView`    | `[]`                            | what an empty query shows: `"pinned"`, `"recent"`, `"popular"` |
| `files`        | `{ "enabled": true, "prefix": "f", "inline": false }` | file search, see [Files](#files)  |
| `plugins`      | `[]`                            | see [docs/plugins.md](docs/plugins.md); `"refresh": 120` lists a slow plugin at most every 2 min on open |
| `web`          | Google, YouTube, Arch Wiki      | `{ "default": "g", "engines": { "g": { "name", "url": "…%s" } } }` |
| `clipboard`    | `{ "enabled": true, "prefix": "v", "file": "~/.config/clipse/clipboard_history.json" }` | clipse history |
| `emoji`        | `{ "prefix": ":" }`             | `""` turns emoji off                                |
| `command`      | `{ "prefix": ">" }`             | `""` turns commands off                             |
| `terminal`     | `["kitty", "-e"]`               | runs a command in a terminal (the command is appended) |
| `hidden`       | `[]`                            | apps hidden with the actions menu (`"app:<desktop id>"`) |
| `power`        | systemctl / loginctl            | the Session folder: `lock`, `suspend`, `reboot`, `shutdown`, `logout` → a command; `null` hides one; a new id with `{ "title", "icon", "command", "order", "confirm" }` adds one |
| `include`      | `[]`                            | more JSON files merged on top (watched too)         |

Search for `quickseek settings` to change the empty screen and file search, rebuild the index,
unpin everything or clear the history from the window itself. That rewrites `settings.json`
(formatting is lost, the content is kept; symlinks are followed).

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

## Cost

Measured on a Core Ultra 5 125H laptop (Quickshell 0.3.2, Hyprland 0.57) with one plugin that shells
out about a hundred times to list a control center. CPU includes child processes.

| state                                | CPU per open                 | wakeups per open | memory                              |
|--------------------------------------|------------------------------|------------------|-------------------------------------|
| idle, 60 s                           | 0 %                          | 0 /s             | RSS 125 MB after start, ~165 MB after the first open (PSS ~90 MB) |
| open and close, nothing typed        | ~75 ms + ~10 ms children     | ~370             | +10 MB while open, freed on close   |
| open, type an app name, close        | ~140 ms                      | ~850             |                                     |
| open, `f report`, close              | ~125 ms + ~105 ms (`fd`, `plocate`) | ~670      |                                     |
| the plugin's `list`, when it runs    | +1.2 s                       |                  |                                     |

A plugin's `list` runs in parallel with the window and is what costs the most; give slow plugins a
`refresh` interval. Most of the memory is Qt and the Wayland/EGL stack that any Quickshell
process carries.

To measure on your machine: sum `voluntary_ctxt_switches` + `nonvoluntary_ctxt_switches` over
`/proc/<pid>/task/*/status` (wakeups) and `utime`, `stime`, `cutime`, `cstime` from `/proc/<pid>/stat`
(CPU, children included) before and after.

## License

MIT. `data/emoji.tsv` is built by `tools/emoji.py` from [emojibase-data](https://emojibase.dev) (MIT),
whose names and keywords come from [Unicode CLDR](https://cldr.unicode.org)
([Unicode License v3](https://www.unicode.org/license.txt)).
