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
peek apps --format toon

# 2. Inspect the UI tree of a window (by ID or app name)
peek tree --app Xcode --depth 3 --format toon

# 3. Search for a specific element
peek find --app Xcode --role Button --desc "Run" --format toon

# 4. Hit-test at coordinates
peek find --app Xcode --x 280 --y 50 --format toon

# 5. Interact with it
peek action --app Xcode --do Press --role Button --desc "Run" --format toon

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

Options: `--app <name>` to filter by app name.

```bash
$ peek apps --format toon
[2]:
  - name: Finder
    bundleID: com.apple.finder
    pid: 21162
    windows[0]: []
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


### `peek tree` — Inspect the accessibility tree

Options: `--depth <n>` to limit tree depth.

```bash
$ peek tree --app Xcode --depth 3 --format toon
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
    children[3]:
      - role: Group
        description: navigator
        frame:
          x: 8
          y: 41
          width: 300
          height: 866
        children[4]:
          - role: RadioGroup
            frame:
              x: 15
              y: 84
              width: 286
              height: 30
          - role: ScrollArea
            frame:
              x: 8
              y: 113
              width: 300
              height: 750
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


### `peek menu` — Inspect the menu bar structure

Without options: shows the full menu bar structure (can be very large for apps like Xcode).
With `--find <title>`: searches for menu items matching a title and returns matches with their full menu path.
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


**Search** for menu items with `--find` (preferred over dumping the full tree):

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

Accepts optional `--app`/`--pid` to auto-activate the target app before clicking.

```bash
$ peek click --app Xcode --x 276 --y 50
Clicked at (276, 50)
```


### `peek type` — Type text via keyboard events

Accepts optional `--app`/`--pid` to auto-activate the target app before typing.

```bash
$ peek type --app Xcode --text "hello world"
Typed 11 character(s)
```


### `peek action` — Perform accessibility actions

Filters: `--role`, `--title`, `--value`, `--desc` (at least one required).
Use `--all` to act on every matching element (default: first match only).

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


Common actions by element role:
- **Button, MenuItem, CheckBox, RadioButton:** `Press`
- **TextField, TextArea:** `Confirm` (to submit), or use `peek click` to focus
- **Slider, Stepper:** `Increment`, `Decrement`
- **PopUpButton, MenuButton:** `ShowMenu`
- **Window:** `Raise`

### `peek activate` — Bring an app to the foreground

Activates the app and raises the target window.

```bash
$ peek activate --app Claude
Activated Claude (pid 84720, window 22325)
```


### `peek watch` — Monitor accessibility changes

Two modes: **streaming** (CLI only) or **snapshot** (CLI and MCP).

**Streaming** — real-time notifications until Ctrl+C (CLI only):

```bash
$ peek watch --app Xcode
[0.000s] ValueChanged StaticText "Build Succeeded"
[0.120s] LayoutChanged Group
[1.500s] ValueChanged StaticText "Indexing..."
^C
```

**Snapshot** — take two snapshots and show differences with `--snapshot`. This is the mode used by the MCP tool (`peek_watch`). Use it to monitor the effect of actions (e.g. check build status after triggering a build, verify UI updates after a click).

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

Options: `-o <path>` for output file, `--x`, `--y`, `--width`, `--height` to crop a region (window-relative points).

```bash
$ peek capture --app Xcode -o screenshot.png
Saved screenshot.png (3024x1764 pixels)
```

Crop a specific region within the window:

```bash
$ peek capture --app Xcode -o toolbar.png --x 0 --y 0 --width 400 --height 50
Saved toolbar.png (800x100 pixels)
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


## Output Formats

All commands support structured output formats via `--format`:
- `json` — Standard JSON format for programmatic use
- `toon` — Token-optimized format for LLM consumption (recommended for AI agents, uses 30-50% fewer tokens than JSON)

**Always use `--format toon` for AI agent workflows.** All examples in this guide use toon format.

## Tips

- Prefer `--format toon` for AI agent workflows to reduce token usage.
- Use `--app` or `--pid` to target windows by name instead of looking up IDs manually.
- Commands that need the accessibility tree (`tree`, `find`, `action`, `watch`, `menu`) will **auto-activate** apps on other Spaces — no need to manually run `peek activate` first.
- **Prefer `peek action --do Press`** over `peek find` + `peek click` for clicking UI elements — it finds and acts in one step, no coordinates needed.
- `peek click` and `peek type` now accept `--app`/`--pid` to auto-activate the target app before interacting. Always provide a target to ensure the window is in the foreground.
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
- `peek click` and `peek type` operate at the system level (posting CGEvents, not via accessibility).
- Use `peek find` to narrow down elements before using `peek action` — combine `--role` with `--title` or `--desc` for precise targeting.
- Use `peek find --x <x> --y <y>` for coordinate-based hit-testing — it returns the single deepest element at that point.
- Use `peek watch` (MCP: `peek_watch`) to detect UI changes after triggering an action — it takes two snapshots with a configurable delay and returns added, removed, and changed elements.
