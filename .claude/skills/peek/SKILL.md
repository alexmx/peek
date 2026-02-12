---
name: peek
description: Use the peek CLI to inspect, debug, and interact with native macOS app windows. Use when the user asks to debug a macOS app, inspect UI elements, take screenshots, click buttons, or automate interactions with native apps.
argument-hint: [command]
---

# peek — macOS Window Inspector CLI

Use `peek` to inspect and interact with native macOS application windows. It provides accessibility tree inspection, screenshots, element search, UI automation, and real-time monitoring.

## Prerequisites

- macOS 14+
- Accessibility permission must be granted in System Settings > Privacy & Security > Accessibility
- Screen Recording permission for `peek capture`

## Quick Workflow

```bash
# 1. Find the target window
peek list

# 2. Get the PID for a window ID
peek apps

# 3. Inspect the UI tree
peek inspect <window-id>

# 4. Search for a specific element
peek find <window-id> --role AXButton --title "Submit"

# 5. Interact with it
peek action <window-id> AXPress --role AXButton --title "Submit"
```

## Commands Reference

### Discovery

| Command | Description |
|---------|-------------|
| `peek list [--json]` | List all open windows with IDs, PIDs, app names, and frames |
| `peek apps [--json]` | List running apps with bundle IDs, PIDs, and active/hidden state |

### Inspection

| Command | Description |
|---------|-------------|
| `peek inspect <window-id> [--json]` | Dump the full accessibility tree of a window |
| `peek find <window-id> [--json]` | Search for elements by `--role`, `--title`, `--value`, `--desc` (at least one required) |
| `peek element-at <window-id> <x> <y> [--json]` | Find the deepest element at screen coordinates |
| `peek menu <pid> [--json]` | Dump the menu bar structure with keyboard shortcuts |

### Interaction

| Command | Description |
|---------|-------------|
| `peek click <x> <y>` | Click at screen coordinates |
| `peek type <text>` | Type text via keyboard events |
| `peek action <window-id> <action> [--json]` | Perform an AX action on a matched element. Filters: `--role`, `--title`, `--value`, `--desc` |

Common AX actions: `AXPress`, `AXConfirm`, `AXCancel`, `AXShowMenu`, `AXIncrement`, `AXDecrement`, `AXRaise`.

### Capture

| Command | Description |
|---------|-------------|
| `peek capture <window-id> [-o path] [--json]` | Screenshot a window to PNG |

### Monitoring

| Command | Description |
|---------|-------------|
| `peek watch <window-id> [--json]` | Stream real-time accessibility change notifications (Ctrl+C to stop) |
| `peek diff <window-id> [-d seconds] [--json]` | Snapshot tree, wait, snapshot again, show what changed |

## Tips

- All commands support `--json` for structured output — prefer this for programmatic use.
- Filters (`--title`, `--value`, `--desc`) are case-insensitive substring matches.
- `--role` is an exact match. Common roles: `AXButton`, `AXStaticText`, `AXTextField`, `AXCheckBox`, `AXRadioButton`, `AXPopUpButton`, `AXMenuItem`, `AXTable`, `AXRow`, `AXCell`.
- `peek action` tolerates SwiftUI error codes that occur when elements are recreated during state changes.
- `peek click` and `peek type` operate at the system level (not window-scoped).
- Use `peek list` to get window IDs, then `peek apps` or the PID column from `peek list` to get PIDs for `peek menu`.
- Use `peek find` to narrow down elements before using `peek action` — combine `--role` with `--title` or `--desc` for precise targeting.
