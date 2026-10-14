---
name: use-peek
description: Use the peek CLI to inspect, debug, and interact with native macOS app windows. Use when the user asks to debug a macOS app, inspect UI elements, take screenshots, click buttons, or automate interactions with native apps.
argument-hint: [command]
---

# peek — macOS Window Inspector CLI

`peek` inspects and drives native macOS app windows via Accessibility: tree inspection, element search, UI automation, screenshots, app lifecycle, menu bar.

Requirements: macOS 15+, Accessibility permission (and Screen Recording for `peek capture`). Run `peek doctor --prompt` to grant.

Always pass `--format toon` for LLM workflows (30-50% fewer tokens than JSON).

## Workflow

**Discover → act → verify** in as few calls as possible.

```bash
peek launch --name Calculator --wait-for-window        # → returns pid + windowID + windowTitle
peek find --app Calculator --role Button --title 5 --limit 1
peek action --app Calculator --do Press --role Button --title 5 --verify diff
```

- **Discover** with `peek launch --wait-for-window` (returns windowID) or `peek apps --app X`. Skip `peek apps` after launch — it's already in the result.
- **Inspect** structure with `peek tree` (unfamiliar UI) or `peek find` (known labels, much cheaper — `--limit 1` for existence checks).
- **Act+verify** in one call: `peek action --verify diff` returns just the delta — usually 10x smaller than `--verify tree`.
- **Shortcuts** (⌘S, Esc, arrows, F-keys): use `peek key`, not menu navigation.
- **Menu items**: `peek menu --click "Save"` for menu BAR; `peek action --do Press` only works for items in an already-open menu.

## Window targeting

All UI commands accept one of: `--app NAME` (case-insensitive substring), `--pid PID`, or a positional `<window-id>`. `--app` is simplest. Doesn't apply to `launch` / `quit` (use `--bundle-id` / `--name`).

For coordinate ops (`click`/`drag`/`scroll`) with a target set, peek verifies the point lands on that app/window — it raises an occluded target window, or errors `(x, y) is over '<OtherApp>'` if the coordinates are stale or over another window. On that error, re-read frames with `peek find` (windows move/resize) or pass a specific `<window-id>` for multi-window apps.

**Window-less apps** (Dock, Control Center, status-menu helpers): `--app NAME` or `--pid` scopes `find`/`tree`/`action` to the AXApplication root. Not in plain `peek apps` — go straight to `peek find --app Dock --role AXDockItem` (`peek apps --include-panels` does list the ones owning panels/status items).

## Commands

### `peek apps` — list running apps + windows

`--app NAME` filters. Always pass it when you know the name (no-arg form lists every running app).

`--include-panels` adds non-standard windows — menu-bar panels, status items, small utility windows — and the accessory apps that own them (menu-bar apps are otherwise invisible here). Each window gets a `layer`: 0 = normal, 25 = status item, 101 = menu/panel. Use it to get the window ID of a MenuBarExtra panel for `peek capture`.

### `peek tree` — accessibility tree

`--depth N` to limit output. Bump for deep apps (Xcode, System Settings). Prefer `peek find` for labeled elements.

### `peek find` — search elements (read-only)

Filters: `--role` (exact, without AX prefix), `--title` (case-insensitive substring, matches AXTitle OR AXDescription), `--value`, `--desc`, `--enabled true|false`. Hit-test mode: `--x N --y N` returns the deepest element at coordinates.

Pass `--limit N` to stop after N matches (`--limit 1` for existence checks — big speedup on deep trees).

To interact with a match, call `peek action` with the same filters — don't `peek find` then `peek click`.

### `peek text` — read an element's full text content

Reads text behind parameterized AX attributes (AXStringForRange), so it returns content `peek find`/`peek tree` show as empty or a 2000-char capped preview (SwiftUI / NavigableStaticText — watch for `valueTruncated`/`valueLength` in their output). Selects the first match by `--role`/`--title`/`--value`/`--desc`.

- `--offset N` / `--length N` — page large text. Result is `{length, offset, text, truncated}`; when `truncated`, advance `--offset` by what you read.
- `--bounds` — add the screen rect of the read range. Pair with a small `--offset`/`--length` to get a clickable rect for `peek click` / `peek drag`.
- `--selection` — add the live caret/selection range (`length 0` = caret position).
- `--substring "text"` — locate the first occurrence at/after `--offset` (case-sensitive); advance `--offset` past a match to page occurrences. Combine with `--bounds` to click a specific word. Excludes `--length`.

```bash
peek text --app Notes --role TextArea --substring "Reminder" --bounds   # → offset + clickable rect
```

### `peek action` — perform AX actions

Finds + acts in one call. Filters: `--role`, `--title`, `--value`, `--desc`. `--all` to act on every match.

Actions:
- **Press** — buttons, popup buttons, checkboxes, items in an already-open menu
- **Confirm** — text fields
- **Cancel** — dialogs/sheets exposing AXCancel (Esc equivalent)
- **ShowMenu** — rare; try Press first and read `unsupportedAction` errors
- **Increment / Decrement** — sliders, steppers
- **Raise** — windows
- **Select** — rows/items in NSOutlineView/NSTableView/source lists (sidebars) that expose no Press. Sets AXSelected; match the row's **label** (e.g. `--value "History"`) and it climbs to the selectable row. Prefer this over coordinate clicks for sidebar/list selection, and `--verify diff` to confirm.

Verification: `--verify diff` (default delay 0.15s) returns just what changed — the recommended check for "did this update?". `--verify tree` returns the full post-action tree. `--depth N` and `--delay N` tune the snapshot; bump delay for apps that lazy-paint values.

For menu BAR items, use `peek menu --click` instead.

### `peek menu` — read or click menu items

Modes:
- `--find TITLE` — search across all menus, returns matches with paths
- `--path "Menu > Submenu"` — return just that submenu
- `--click TITLE` — trigger an item (activates the app). Presses the first enabled match, preferring an exact title; prints the clicked item's full path. When a title repeats across menus (`Clear Menu` under Apple › Recent Items and File › Open Recent), pass the full path as `find` returns it (`--click "File > Open Recent > Clear Menu"`) or scope with `--path "File > Open Recent" --click "Clear Menu"`
- `--extras` — operate on the status-item bar (NSStatusItem / SwiftUI MenuBarExtra `.menu` style) instead of the main menu. Combine with any mode: no-arg lists the status items, `--click "Sync"` presses one to open its menu (read the opened menu with a follow-up `--extras` call). This is the fix for "peek can't see the menu bar status item" — it lives on a separate AX bar the tree/find don't cover. Clicking a `.window`-style extra opens a panel instead of a menu — inspect it with `find`/`tree` on the app, screenshot it via the panel flow under `peek capture`.

No-arg form dumps the full menu bar — avoid on large apps. Items hidden via `NSMenuItem.isHidden=true` (e.g. Safari's per-tab ⌘1-9) aren't visible to AX — send the shortcut via `peek key`. If `--extras` reports no status menu, the app's item uses a custom view with no accessibility — locate it visually and click its coordinates.

### `peek key` — send a key chord

`--key NAME` is a single character (`'1'`, `'/'`) or a named key (escape, tab, return, delete, up/down/left/right, home, end, pageup, pagedown, f1-f12, space). `--modifiers cmd,shift,option,control,fn` (comma-separated). Pass `--app`/`--pid` to auto-activate.

```bash
peek key --key s --modifiers cmd --app TextEdit       # ⌘S
peek key --key escape --app Calculator
```

### `peek type` — type literal text

`--text "..."`. Pass `--app`/`--pid` to auto-activate. `--delay-ms N` per-character delay (default 5) — bump to 10-20 if a lazy text field drops or duplicates characters. Use `peek key` for chords / non-character keys.

### `peek click` — click at screen coordinates

`--x N --y N`. `--count 2`/`3` for double/triple click (word/line selection in text views). `--button right` opens context menus on canvases / web views. `--modifiers cmd shift option control fn` (space/comma-separated) holds keys during the click — shift-click extends a selection (range select), cmd-click toggles / opens in background. For labeled elements, use `peek action --do Press` instead. For drag gestures, use `peek drag`.

### `peek move` — move the cursor without clicking

`--x N --y N`. Drives hover state, tooltips, Dock magnification. `--from-x --from-y --steps N` interpolates for apps needing continuous motion. `--dwell-ms N` holds the cursor so hover renders. Returns `cursor` (OS-reported position — verifies the event landed) and `element` (system-wide hit-test under cursor; null over empty desktop) — use these to verify hover without a follow-up `peek find` / `peek capture`.

### `peek drag` — drag between two screen points

`--from-x --from-y --to-x --to-y`. For drag-reorder, drag-and-drop, marquee selection.

### `peek scroll` — scroll at screen coordinates

`--x --y --delta-y N` (positive scrolls **DOWN**, negative UP). `--delta-x` for horizontal. Default is an instant jump; `--steps N` (and/or `--duration-ms`) gives smooth animated motion (total delta unchanged). `--drag` for touch-based apps like iOS Simulator (swipe gesture).

Pass a negative delta with the `=` form so it isn't read as a flag: `peek scroll --x 700 --y 400 --delta-y=-600 --steps 30`.

### `peek activate` — bring an app to the foreground

Most read-only commands and `peek action --do Press` work on backgrounded apps. Use `activate` before `peek type` or for UI requiring the app's event loop (popovers, sheets).

### `peek launch` / `peek quit` — app lifecycle

`peek launch` resolves by `--bundle-id` (preferred), `--name`, or `--path`. Pass `--wait-for-window` when the next call needs a window ID (10s timeout) — the result then includes `windowID` and `windowTitle`, so you can skip a follow-up `peek apps`. Pass `--documents <path-or-url> ...` to open files in the launched app via `application:openURLs:` — single deterministic call instead of launch → File → Open dialog → navigate → click.

`peek quit` resolves by `--pid` (preferred), `--bundle-id`, or `--name`. `--force` for forceTerminate.

Many apps persist state across launches — plan an explicit reset (clear button, fresh document) when you need a known starting state.

### `peek capture` — screenshot a window

`-o PATH` for output (default `/tmp/peek/window_<id>.png`). Crop with `--x --y --width --height` in **window-relative** points (subtract the window's frame origin from screen coords).

**Menu-bar panels (MenuBarExtra):** don't capture by `--app` — open the panel once, get its window ID from `peek apps --include-panels` (layer 101), and capture by that explicit ID. The panel's backing store persists after it dismisses, so the capture works even once it's closed (no racing the dismiss; content reflects the last open state). A `noCapturableWindow` error on `--app`/`--pid` means the app has no standard windows — this panel flow is the fix.

### `peek doctor` — check permissions

`peek doctor` checks Accessibility + Screen Recording. `--prompt` opens System Settings for missing ones.

## Element discovery tips

- **Don't dump the tree** when you can `peek find` by role/title/desc.
- **`--title` matches AXTitle OR AXDescription** — start with that, fall back to `--value` (System Settings stores labels in `value`).
- **Wrong role guesses**: tabs are often `RadioButton`, toggles are `CheckBox`, "popup" buttons usually take `Press` not `ShowMenu`.
- **Hit-test** with `peek find --x --y` when you know coordinates but not role/title.

Common roles (no AX prefix): `Window`, `Group`, `SplitGroup`, `ScrollArea`, `TabGroup`, `Sheet`, `Toolbar`, `Button`, `CheckBox`, `RadioButton`, `PopUpButton`, `MenuButton`, `Slider`, `Stepper`, `StaticText`, `TextField`, `TextArea`, `Link`, `Table`, `Row`, `Cell`, `Outline`, `OutlineRow`, `MenuBar`, `MenuBarItem`, `Menu`, `MenuItem`, `Image`, `WebArea`.
