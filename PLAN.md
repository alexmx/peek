# Peek — Future Features Plan

Tool purpose: Enable AI agents to debug and interact with native macOS apps.

## Completed

1. **Window enumeration** — `peek list` shows real windows across all desktops
2. **Screenshot capture** — `peek capture <id>` saves a Retina PNG
3. **Accessibility tree inspection** — `peek inspect <id>` walks the full UI hierarchy with roles, values, descriptions, and frames

## Planned Features

### Priority 1: JSON output
- Add `--json` flag to all commands
- Agents need parseable structured output, not formatted tables
- Enables chaining commands and programmatic consumption

### Priority 2: Query specific elements
- `peek find <window-id> --role AXButton --value "Submit"` — search for elements by role/title/value instead of dumping the whole tree
- `peek element-at <window-id> <x> <y>` — what element is at this point?

### Priority 3: Perform actions (interact with UI elements)
- `peek click <window-id> <x> <y>` — click at coordinates
- `peek type <window-id> <text>` — type text into the focused element
- `peek action <window-id> <element-path> <action>` — trigger AX actions (press, confirm, cancel, expand, etc.)

### Priority 4: Watch/diff (monitor changes)
- `peek watch <window-id>` — subscribe to AX notifications (value changed, element created/destroyed) and stream changes in real-time
- `peek diff <window-id>` — snapshot the tree, wait, snapshot again, show what changed

### Priority 5: App-level info
- `peek apps` — list running apps with bundle IDs, PIDs, active state
- `peek logs <pid>` — capture os_log output from the target app
- `peek menu <pid>` — dump the menu bar structure (useful for finding actions)
