---
name: peek
description: Use the peek CLI to inspect, debug, and interact with native macOS app windows. Use when the user asks to debug a macOS app, inspect UI elements, take screenshots, click buttons, or automate interactions with native apps.
argument-hint: [command]
---

# peek — macOS Window Inspector CLI

Use `peek` to inspect and interact with native macOS application windows. It provides accessibility tree inspection, screenshots, element search, UI automation, and app lifecycle control (launch/quit).

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

# 3. Act on an element and verify what changed in one call
peek action --app Simulator --do Press --role StaticText --desc "Settings" --verify diff --delay 2 --format toon
```

`--verify diff` is usually what you want — it returns just the delta between before and after, much smaller than the full tree. Use `--verify tree` if you specifically need the post-action structure.

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

Applies to: `tree`, `find`, `action`, `activate`, `capture`, `menu`. (`launch` and `quit` resolve by bundle ID / name / path instead.)

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

**Attribute search** — filter by `--role`, `--title`, `--value`, `--desc`, `--enabled` (at least one required):

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

`--title` matches AXTitle OR AXDescription (most controls expose their label via one or the other). `--enabled true|false` narrows by state — useful for "find all disabled buttons":

```bash
$ peek find --app Xcode --role Button --enabled false --format toon
```

Each match comes back as a flat node (no child subtree). To inspect what's inside a matched element, follow up with `peek tree` on that subtree.

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
Use `--verify tree|diff|none` to atomically capture post-action state in the same call (default `none`). Tune the capture with `--depth` and `--delay` (seconds to wait before snapshot, default: 1).

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

**Action with diff verification** (recommended — act and see just what changed):

```bash
$ peek action --app Simulator --do Press --role StaticText --desc "General" --verify diff --delay 1 --format toon
action[1]:
  - role: StaticText
    value: General
diff:
  added[1]:
    - role: NavigationBar
      title: General
  changed[1]:
    - role: StaticText
      before:
        value: Settings
      after:
        value: General
  removed: []
```

**Action with full tree** (when you need the post-action structure):

```bash
$ peek action --app Simulator --do Press --role StaticText --desc "General" --verify tree --depth 3 --delay 2 --format toon
```

Common actions by element role:
- **Button, PopUpButton, MenuItem, CheckBox, RadioButton:** `Press` (works without activating the app)
- **TextField, TextArea:** `Confirm` (to submit), or use `peek click` to focus
- **Slider, Stepper:** `Increment`, `Decrement`
- **Window:** `Raise`
- **ShowMenu** is for the narrow set of widgets that explicitly advertise AXShowMenu — most "popup" buttons take Press. If unsure, try Press first; the `unsupportedAction` error lists what's actually supported.

Note: for menu BAR items, use `peek menu --click` instead of `peek action --do Press`. `peek action`'s Press only works for menu items in an already-open menu.


### `peek menu` — Inspect and click menu items

Three modes:
- `--find <title>` — search across all menus, returns each match with its full path
- `--click <title>` — trigger a menu item (activates the target app)
- `--path <path>` — return just the subtree at a path (e.g. `Debug` or `Edit > Find`), to avoid dumping the entire menu bar on large apps

Avoid calling without any of these — the full menu tree on a large app can be hundreds of KB.

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
# Scoped read — return only the Debug menu's tree (much smaller than the full menu bar)
$ peek menu --app Xcode --path Debug --format toon

# Click a menu item by its leaf title
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

Activates the app and raises the target window. Most read-only commands (`tree`, `find`, `capture`, `menu --find`) and `peek action --do Press` work on backgrounded apps without activation. Use `activate` when you need keyboard focus before `peek type`, or when surfacing UI that requires the app's event loop (popovers, sheets).

```bash
$ peek activate --app Claude
Activated Claude (pid 84720, window 22325)
```


### `peek launch` — Launch a macOS application

Resolves the app by `--bundle-id` (preferred), `--name`, or `--path`. Pass `--wait-for-window` when your next command needs a window ID — the call blocks until at least one AX-visible window appears (10s budget).

```bash
$ peek launch --bundle-id com.apple.calculator --wait-for-window
Launched Calculator (pid 12345, bundle com.apple.calculator)
```

Note: many apps persist view mode, expression, or document state across runs. `peek quit` + `peek launch` won't necessarily reset that — plan an explicit reset (clear button, mode menu, fresh document) when you need a known starting state.


### `peek quit` — Terminate a running application

Resolves by `--pid` (preferred when known), `--bundle-id`, or `--name`. Graceful by default; `--force` uses forceTerminate.

```bash
$ peek quit --bundle-id com.apple.calculator
Quit Calculator (pid 12345)
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
