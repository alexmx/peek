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

The typical workflow is: **discover → act → verify** — in as few calls as possible.

```bash
# 1. Discover the app and its window frame
peek apps --app Simulator --format toon

# 2. Inspect the UI tree to understand the layout
peek tree --app Simulator --depth 3 --format toon

# 3. Act on an element and verify the result in one call
peek action --app Simulator --do Press --role StaticText --desc "Settings" --result-tree --depth 3 --delay 2 --format toon
```

For menu items, use `peek menu --click` instead of `peek action`:
```bash
peek menu --app Xcode --click "Paste"
```

## Window Targeting

All commands accept a window target. Use `--app` by default — it's the simplest and works everywhere.

| Method | Example | Description |
|--------|---------|-------------|
| `--app` | `peek tree --app Xcode` | First window matching app name (case-insensitive substring) |
| `--pid` | `peek tree --pid 53051` | First window for the given process ID |
| Window ID | `peek tree 21121` | Direct window ID (from `peek apps`) |

Applies to: `tree`, `find`, `action`, `activate`, `capture`, `watch`, `menu`.

## Commands Reference

### `peek apps` — List running applications

Options: `--app <name>` to filter by app name. Always filter when you know the app name.

```bash
$ peek apps --app Xcode --format toon
[1]:
  - name: Xcode
    bundleID: com.apple.dt.Xcode
    pid: 53051
    windows[1]:
      - windowID: 21121
        title: peek — MenuBarManager.swift
        frame:
          x: 0
          y: 33
          width: 1512
          height: 882
```

The `frame` values are needed for `peek capture` crop coordinate conversion (see capture section).


### `peek tree` — Inspect the accessibility tree

Options: `--depth <n>` to limit tree depth. Always use `--depth` to control output size.

```bash
$ peek tree --app Xcode --depth 2 --format toon
role: Window
title: peek — MenuBarManager.swift
frame:
  x: 0
  y: 33
  width: 1512
  height: 882
children[3]:
  - role: SplitGroup
    title: peek
    description: /Users/alexmx/Projects/peek
    frame:
      x: 0
      y: 33
      width: 1512
      height: 882
  - role: Toolbar
    frame:
      x: 0
      y: 33
      width: 1512
      height: 52
  - role: Button
    frame:
      x: 18
      y: 51
      width: 16
      height: 16
```


### `peek find` — Search for UI elements

Read-only search. To interact with found elements, use `peek action` directly with the same filters — no need to find first.

Two modes: **attribute search** or **hit-test**.

**Attribute search** — filter by `--role`, `--title`, `--value`, `--desc` (at least one required):

```bash
$ peek find --app Xcode --role Button --desc "Run" --format toon
[1]:
  - role: Button
    description: Run
    frame:
      x: 276
      y: 45
      width: 28
      height: 28
```

**Hit-test** — find the deepest element at screen coordinates with `--x` and `--y`:

```bash
$ peek find --app Xcode --x 280 --y 50 --format toon
role: Button
description: Run
frame:
  x: 276
  y: 45
  width: 28
  height: 28
```


### `peek action` — Perform accessibility actions

The primary interaction tool. Finds an element and acts on it in one step — no need to `peek find` first.

Filters: `--role`, `--title`, `--value`, `--desc` (at least one required).
Use `--all` to act on every matching element (default: first match only).
Use `--result-tree` to also return the post-action accessibility tree (saves a separate `peek tree` call). Combine with `--depth` and `--delay` (seconds to wait before capturing the tree, default: 1).

**Basic action:**

```bash
$ peek action --app Xcode --do Press --role Button --desc "Run" --format toon
role: Button
description: Run
frame:
  x: 276
  y: 45
  width: 28
  height: 28
```

**Action with result tree** (recommended — act and verify in one call):

```bash
$ peek action --app Simulator --do Press --role StaticText --desc "General" --result-tree --depth 2 --delay 2 --format toon
action[1]:
  - role: StaticText
    value: General
    frame:
      x: 164
      y: 326
      width: 63
      height: 20
resultTree:
  role: Window
  title: Settings
  children[1]:
    - role: Group
      children[2]:
        - role: NavigationBar
          title: General
        - role: ScrollArea
          ...
```

Common actions by element role:
- **Button, MenuItem, CheckBox, RadioButton:** `Press`
- **TextField, TextArea:** `Confirm` (to submit), or use `peek click` to focus
- **Slider, Stepper:** `Increment`, `Decrement`
- **PopUpButton, MenuButton:** `ShowMenu`
- **Window:** `Raise`


### `peek menu` — Search and click menu items

Use `--find <title>` to search or `--click <title>` to trigger. Avoid calling without either flag — the full menu tree can be very large.

```bash
$ peek menu --app Xcode --find "Run" --format toon
[4]:
  - title: Run
    shortcut: ⌘R
    path: Product > Run
  - title: Run…
    shortcut: ⌥⌘R
    path: Product > Run…
  - title: Running
    shortcut: ⇧⌘R
    path: Product > Build For > Running
  - title: Run Without Building
    shortcut: ⌃⌘R
    path: Product > Perform Action > Run Without Building
```

```bash
$ peek menu --app Xcode --click "Paste"
Clicked menu item: Paste
```


### `peek click` — Click at screen coordinates

Low-level click at screen coordinates. Only use for raw coordinate clicks (e.g. on images or canvas areas). For UI elements like buttons, use `peek action --do Press` instead. Accepts optional `--app`/`--pid` to auto-activate the target app before clicking.

```bash
$ peek click --app Xcode --x 276 --y 50
Clicked at (276, 50)
```


### `peek scroll` — Scroll at screen coordinates

Scroll using scroll wheel events (works on native macOS apps). Use `--drag` for touch-based apps like iOS Simulator, which simulates a finger swipe instead. Accepts optional `--app`/`--pid` to auto-activate the target app.

`--delta-y`: use **positive** values to scroll **DOWN** (reveal content below), **negative** to scroll **UP**.

```bash
# Scroll down in a native macOS app
$ peek scroll --app Safari --x 756 --y 500 --delta-y 300
Scrolled at (756, 500) by dx=0, dy=300

# Scroll down in iOS Simulator (requires --drag)
$ peek scroll --app Simulator --x 200 --y 500 --delta-y 300 --drag
Scrolled at (200, 500) by dx=0, dy=300
```


### `peek type` — Type text via keyboard events

Types text via keyboard events into the focused element. Focus a text field first with `peek click` or `peek action`. Accepts optional `--app`/`--pid` to auto-activate the target app before typing.

```bash
$ peek type --app Xcode --text "hello world"
Typed 11 character(s)
```


### `peek activate` — Bring an app to the foreground

Activates the app and raises the target window. Rarely needed — most commands (`tree`, `find`, `action`, `watch`, `menu`) auto-activate apps.

```bash
$ peek activate --app Claude
Activated Claude (pid 84720, window 22325)
```


### `peek watch` — Monitor async UI changes

Takes two accessibility snapshots separated by a delay and returns differences. Best for monitoring async/delayed changes (build progress, loading spinners, animations). Do NOT use after `peek action` to verify immediate results — use `peek action` with `--result-tree` or `peek tree` instead.

Options: `--snapshot` (required for diff mode), `--delay <seconds>` (default: 3).

```bash
$ peek watch --app Xcode --snapshot -d 5 --format toon
changed[1]:
  - role: StaticText
    before:
      value: Build Succeeded
    after:
      value: Indexing
    frame:
      x: 608
      y: 47
      width: 100
      height: 20
```


### `peek capture` — Screenshot a window

Options: `-o <path>` for output file, `--x`, `--y`, `--width`, `--height` to crop a region in window-relative points.

**Important:** `peek tree`/`peek find` return screen coordinates. To crop, subtract the window's frame origin (from `peek apps`) to get window-relative offsets.

```bash
# Full window screenshot
$ peek capture --app Xcode -o screenshot.png
Saved screenshot.png (3024x1764 pixels)

# Crop a specific region (window-relative coordinates)
$ peek capture --app Xcode -o toolbar.png --x 0 --y 0 --width 400 --height 50
Saved toolbar.png (800x100 pixels)
```


### `peek doctor` — Check permissions

Run `peek doctor` to check, or `peek doctor --prompt` to trigger system permission dialogs.

```bash
$ peek doctor --prompt
Accessibility:    granted
Screen Recording: not granted

Opening System Settings for missing permissions...
```


## Output Formats

All commands support `--format`:
- `json` — Standard JSON for programmatic use
- `toon` — Token-optimized for LLM consumption (30-50% fewer tokens than JSON)

**Always use `--format toon` for AI agent workflows.**


## Element Discovery Tips

- **Start with `peek tree --depth 2-3`** to understand the UI layout, then use `peek action` directly with role + desc/title filters.
- **Combine role + description** for precise targeting: `peek action --role Button --desc "Run" --do Press`
- **Use the right role** — don't assume `Button` for everything. Tabs are often `RadioButton`, toggles are `CheckBox`.
- **Use `peek menu --find`** for menu items instead of searching the accessibility tree.
- **Hit-test with `peek find --x --y`** when you know screen coordinates but not the element's role or title.

Common roles:
- **Containers:** `Window`, `Group`, `SplitGroup`, `ScrollArea`, `TabGroup`, `Sheet`, `Drawer`
- **Controls:** `Button`, `CheckBox`, `RadioButton`, `PopUpButton`, `MenuButton`, `Slider`, `Stepper`, `ColorWell`
- **Text:** `StaticText`, `TextField`, `TextArea`, `Link`
- **Tables:** `Table`, `Row`, `Cell`, `Column`, `Outline`, `OutlineRow`
- **Menus:** `MenuBar`, `MenuBarItem`, `Menu`, `MenuItem`
- **Toolbars:** `Toolbar`, `ToolbarButton`
- **Other:** `Image`, `ProgressIndicator`, `Splitter`, `ValueIndicator`, `WebArea`

Filters (`--title`, `--value`, `--desc`) are case-insensitive substring matches. `--role` is an exact match (without the `AX` prefix).
