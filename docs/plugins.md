# Plugins

A plugin is any executable. quickseek calls it with a verb and reads [JSON Lines](https://jsonlines.org)
from stdout: one JSON object per line. Anything on stderr ends up in the quickseek log.

```json
"plugins": [
  { "id": "cc", "name": "Control center", "icon": "󰒓", "keywords": "settings", "command": ["~/bin/cc", "quickseek"] }
]
```

Every plugin gets a folder named after it. Its items are searchable from the top level, but items
nested inside the plugin's own folders show up only when they match the query or when you enter
that folder (Enter or Tab on it, Backspace on an empty query to leave).

## `list`

Called when the window opens, when one of the plugin's folders is entered and after every action.
A slow `list` (many shell-outs) costs CPU on every open; `"refresh": 120` in the plugin's settings
skips the call on open while the last list is younger than that many seconds. Entering the plugin's
folders and running its items still re-list, so statuses there stay current.
Prints the whole tree:

```json
{"id": "wifi", "title": "Wi-Fi", "status": "HomeNet", "icon": "󰖩", "folder": true, "keywords": "wireless network"}
{"id": "net-1", "parent": "wifi", "title": "HomeNet", "status": "connected", "icon": "󰤨"}
{"id": "scan", "parent": "wifi", "title": "Rescan"}
```

| field      | meaning                                                                        |
|------------|--------------------------------------------------------------------------------|
| `id`       | string, unique within the plugin, passed back to `run`                         |
| `title`    | the text that is searched and shown                                            |
| `status`   | short state on the right (`on`, `connected`, `72 %`). Keep it short            |
| `icon`     | a glyph (Nerd Font) or, with `"iconType": "theme"`, an icon theme name         |
| `keywords` | extra words to match (string or array)                                         |
| `parent`   | id of a folder item; without it the item lives in the plugin's root folder     |
| `folder`   | the item is a folder: Enter opens it instead of running it                     |
| `close`    | close the window right away when the item is run                               |

## `run <id>`

Runs the item. By default the window stays open and the plugin is listed again, so a toggle
shows its new state. The output may change that:

```json
{"type": "close"}
```
Close the window (the action started an app, a terminal, a screenshot…).

```json
{"type": "menu", "title": "HomeNet"}
{"id": "disconnect", "title": "Disconnect"}
{"id": "forget", "title": "Forget network"}
```
Show a submenu. Its items are run like any other; afterwards the submenu closes. An item with
`"action": "back"` just leaves the submenu (a "No" button).

```json
{"type": "prompt", "title": "Password", "message": "Network “HomeNet”", "password": true, "id": "net-1"}
```
Ask for text. The answer is passed to `run <id>` in the `QUICKSEEK_INPUT` environment variable
(not in argv, so it doesn't show up in the process list).
