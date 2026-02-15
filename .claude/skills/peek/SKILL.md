---
name: peek
description: Use the peek CLI to inspect, debug, and interact with native macOS app windows. Use when the user asks to debug a macOS app, inspect UI elements, take screenshots, click buttons, or automate interactions with native apps.
argument-hint: [command]
---

# peek — macOS Window Inspector CLI

Use `peek` to inspect and interact with native macOS application windows. It provides accessibility tree inspection, screenshots, element search, UI automation, and real-time monitoring.

## Prerequisites

- macOS 15+
- Accessibility permission must be granted in System Settings > Privacy & Security > Accessibility
- Screen Recording permission for `peek capture`
- Run `peek doctor` to check permissions, or `peek doctor --prompt` to trigger system dialogs

## Quick Workflow

```bash
# 1. List apps and their windows to find window IDs and PIDs
peek apps

# 2. Inspect the UI tree of a window (by ID or app name)
peek tree --app Xcode --depth 3

# 3. Search for a specific element
peek find --app Xcode --role Button --desc "Run"

# 4. Hit-test at coordinates
peek find --app Xcode --at 280 50

# 5. Interact with it
peek action --app Xcode --do Press --role Button --desc "Run"

# 6. Click a menu item
peek menu --app Xcode --click "Paste"

# 7. Bring an app to the foreground
peek activate --app Claude
```

## Window Targeting

Most commands accept a window target. You can specify it three ways:

| Method | Example | Description |
|--------|---------|-------------|
| Window ID | `peek tree 21121` | Direct window ID (from `peek apps`) |
| `--app` | `peek tree --app Xcode` | First window matching app name (case-insensitive substring) |
| `--pid` | `peek tree --pid 53051` | First window for the given process ID |

Applies to: `tree`, `find`, `action`, `activate`, `capture`, `watch`, `menu`.

## Commands Reference

### `peek apps` — List running applications

```bash
$ peek apps
Finder (21162)  com.apple.finder
  (no windows)

Xcode (53051)  com.apple.dt.Xcode
  21121   peek — MenuBarManager.swift    (0, 33) 1512x882

9 app(s), 17 window(s).
```

```bash
$ peek apps --format json
```
```json
[
  {
    "bundleID" : "com.apple.dt.Xcode",
    "isActive" : false,
    "isHidden" : false,
    "name" : "Xcode",
    "pid" : 53051,
    "windows" : [
      {
        "frame" : { "height" : 882, "width" : 1512, "x" : 0, "y" : 33 },
        "isOnScreen" : true,
        "title" : "peek — MenuBarManager.swift",
        "windowID" : 21121
      }
    ]
  }
]
```

### `peek tree` — Inspect the accessibility tree

Options: `--depth <n>` to limit tree depth.

```bash
$ peek tree --app Xcode --depth 3
Window  "peek — MenuBarManager.swift"  (0, 33) 1512x882
├── SplitGroup  "peek"  desc="/Users/alexmx/Projects/peek"  (0, 33) 1512x882
│   ├── Group  desc="navigator"  (8, 41) 300x866
│   │   ├── RadioGroup  (15, 84) 286x30
│   │   ├── ScrollArea  (8, 113) 300x750
│   │   ├── TextField  desc="Project navigator filter"  (43, 870) 258x30
│   │   └── MenuButton  (23, 876) 17x18
│   ├── Splitter  value="308"  (308, 85) 0x830
│   └── Group  desc="editor area"  (0, 33) 1512x882
│       ├── SplitGroup  (0, 33) 1512x882
│       └── Group  desc="debug bar"  (308, 879) 1204x36
├── Toolbar  (0, 33) 1512x52
│   └── ...
└── Button  (18, 51) 16x16
```

```bash
$ peek tree 21121 --depth 1 --format json
```
```json
{
  "role" : "Window",
  "title" : "peek — MenuBarManager.swift",
  "frame" : { "x" : 0, "y" : 33, "width" : 1512, "height" : 882 },
  "children" : [
    { "role" : "SplitGroup", "title" : "peek", "description" : "/Users/alexmx/Projects/peek", "frame" : { ... }, "children" : [] },
    { "role" : "Toolbar", "frame" : { ... }, "children" : [] }
  ]
}
```

### `peek find` — Search for UI elements

Two modes: **attribute search** or **hit-test**.

**Attribute search** — filter by `--role`, `--title`, `--value`, `--desc` (at least one required):

```bash
$ peek find --app Xcode --role Button --desc "Run"
Button  desc="Run"  (276, 45) 28x28

1 element(s) found.
```

```bash
$ peek find --app Xcode --role Button --desc "Run" --format json
```
```json
[
  {
    "description" : "Run",
    "frame" : { "height" : 28, "width" : 28, "x" : 276, "y" : 45 },
    "role" : "Button",
    "children" : []
  }
]
```

**Hit-test** — find the deepest element at screen coordinates with `--at <x> <y>`:

```bash
$ peek find --app Xcode --at 280 50
Group  desc="navigator"  (8, 41) 300x866
```

```bash
$ peek find --app Xcode --at 280 50 --format json
```
```json
{
  "description" : "navigator",
  "frame" : { "height" : 866, "width" : 300, "x" : 8, "y" : 41 },
  "role" : "Group",
  "children" : []
}
```

### `peek menu` — Inspect the menu bar structure

Without `--click`: shows the full menu bar structure.
With `--click <title>`: finds and presses a menu item by title (case-insensitive substring).

```bash
$ peek menu --app Xcode
Apple
  About This Mac
  System Information
  ---
  System Settings…, 1 update
  App Store
  ---
  Recent Items  >
    ...
File
  New  >
    File…  ⌘N
    Target…
    ...
  Open…  ⌘O
  Open Recent  >
  Close Window  ⇧⌘W
  ...
```

```bash
$ peek menu --app Xcode --format json
```
```json
{
  "role" : "MenuBar",
  "title" : "",
  "enabled" : true,
  "children" : [
    {
      "role" : "MenuBarItem",
      "title" : "File",
      "enabled" : true,
      "children" : [
        { "role" : "MenuItem", "title" : "New File…", "enabled" : true, "shortcut" : "⌘N", "children" : [] },
        { "role" : "MenuItem", "title" : "Open…", "enabled" : true, "shortcut" : "⌘O", "children" : [] }
      ]
    }
  ]
}
```

```bash
$ peek menu --app Xcode --click "Paste"
Clicked menu item: Paste
```

### `peek click` — Click at screen coordinates

```bash
$ peek click 276 50
Clicked at (276, 50)
```

```bash
$ peek click 276 50 --format json
```
```json
{ "x" : 276, "y" : 50 }
```

### `peek type` — Type text via keyboard events

```bash
$ peek type "hello world"
Typed 11 character(s)
```

```bash
$ peek type "hello" --format json
```
```json
{ "characters" : 5 }
```

### `peek action` — Perform accessibility actions

Filters: `--role`, `--title`, `--value`, `--desc` (at least one required).
Use `--all` to act on every matching element (default: first match only).

```bash
$ peek action --app Xcode --do Press --role Button --desc "Run"
Performed 'Press' on: Button  desc="Run"
```

```bash
$ peek action --app Xcode --do Press --role Button --desc "Run" --format json
```
```json
{
  "description" : "Run",
  "frame" : { "height" : 28, "width" : 28, "x" : 276, "y" : 45 },
  "role" : "Button",
  "children" : []
}
```

Common actions: `Press`, `Confirm`, `Cancel`, `ShowMenu`, `Increment`, `Decrement`, `Raise`.

### `peek activate` — Bring an app to the foreground

Activates the app and raises the target window.

```bash
$ peek activate --app Claude
Activated Claude (pid 84720, window 22325)
```

```bash
$ peek activate --app Claude --format json
```
```json
{ "app" : "Claude", "pid" : 84720, "windowID" : 22325 }
```

### `peek watch` — Monitor accessibility changes

Two modes: **streaming** (default) or **snapshot**.

**Streaming** — real-time notifications until Ctrl+C:

```bash
$ peek watch --app Xcode
[0.000s] ValueChanged StaticText "Build Succeeded"
[0.120s] LayoutChanged Group
[1.500s] ValueChanged StaticText "Indexing..."
^C
```

**Snapshot** — take two snapshots and show differences with `--snapshot`:

```bash
$ peek watch --app Xcode --snapshot -d 5
Taking first snapshot...
Waiting 5.0s...

~ Changed (1):
  ~ StaticText [StaticText|Build Succeeded||608,47]
    value: "Build Succeeded" -> "Indexing"

1 change(s) detected.
```

```bash
$ peek watch --app Xcode --snapshot --format json
```
```json
{
  "added" : [],
  "changed" : [
    {
      "after" : { "frame" : { ... }, "title" : null, "value" : "Indexing" },
      "before" : { "frame" : { ... }, "title" : null, "value" : "Build Succeeded" },
      "identity" : "StaticText|||608,47",
      "role" : "StaticText"
    }
  ],
  "removed" : []
}
```

### `peek capture` — Screenshot a window

```bash
$ peek capture --app Xcode -o screenshot.png
Saved screenshot to screenshot.png
Size: 3024x1764 pixels
```

```bash
$ peek capture --app Xcode -o screenshot.png --format json
```
```json
{ "path" : "screenshot.png", "width" : 3024, "height" : 1764 }
```

### `peek doctor` — Check permissions

```bash
$ peek doctor
Accessibility:    granted
Screen Recording: not granted

Run 'peek doctor --prompt' to request missing permissions.
```

Use `--prompt` to trigger the system permission dialogs for any missing permissions.

```bash
$ peek doctor --prompt
Accessibility:    granted
Screen Recording: not granted

Opening System Settings for missing permissions...
```

```bash
$ peek doctor --format json
```
```json
{ "accessibility" : true, "screenRecording" : false }
```

## Tips

- All commands support `--format json` for structured output — prefer this for programmatic use.
- Use `--app` or `--pid` to target windows by name instead of looking up IDs manually.
- Use `peek activate --app <name>` to bring an app to the foreground before clicking or typing.
- Filters (`--title`, `--value`, `--desc`) are case-insensitive substring matches.
- `--role` is an exact match (without the `AX` prefix). Common roles:
  - **Containers:** `Window`, `Group`, `SplitGroup`, `ScrollArea`, `TabGroup`, `Sheet`, `Drawer`
  - **Controls:** `Button`, `CheckBox`, `RadioButton`, `PopUpButton`, `MenuButton`, `Slider`, `Stepper`, `ColorWell`
  - **Text:** `StaticText`, `TextField`, `TextArea`, `Link`
  - **Tables:** `Table`, `Row`, `Cell`, `Column`, `Outline`, `OutlineRow`
  - **Menus:** `MenuBar`, `MenuBarItem`, `Menu`, `MenuItem`
  - **Toolbars:** `Toolbar`, `ToolbarButton`
  - **Other:** `Image`, `ProgressIndicator`, `Splitter`, `ValueIndicator`, `WebArea`
- `peek action` tolerates SwiftUI error codes that occur when elements are recreated during state changes.
- `peek click` and `peek type` operate at the system level (not window-scoped).
- Use `peek find` to narrow down elements before using `peek action` — combine `--role` with `--title` or `--desc` for precise targeting.
- Use `peek find --at <x> <y>` for coordinate-based hit-testing — it returns the single deepest element at that point.
