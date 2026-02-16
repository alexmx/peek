# Peek

A macOS CLI tool and MCP server for inspecting and automating native applications.

Peek provides deep access to macOS accessibility APIs, enabling you to inspect UI hierarchies, search for elements, interact with windows, control menu bars, capture screenshots, and monitor real-time UI changes—all from the command line or through AI agents via MCP.

## Features

- **🔍 Discovery** — List running apps and their windows
- **🌳 Inspection** — Explore accessibility trees, search UI elements, inspect menu bars
- **⚡️ Interaction** — Click, type, and trigger actions on UI elements programmatically
- **📸 Monitoring** — Capture screenshots and watch for real-time UI changes
- **🤖 MCP Integration** — Use Peek tools directly in AI agents for automated workflows
- **📋 Flexible Output** — Human-readable text or JSON for scripting

## Installation

### Homebrew (Recommended)

```bash
brew tap alexmx/tools
brew install peek
```

### From Source

```bash
git clone https://github.com/alexmx/peek.git
cd peek
swift build -c release
cp .build/release/peek /usr/local/bin/
```

## Requirements

- macOS 15.0 or later
- Swift 6.2 (for building from source)
- **Accessibility permissions** (required for most commands)
- **Screen Recording permissions** (required for screenshots)

Run `peek doctor` to check and request permissions.

## Quick Start

### List all running applications and windows

```bash
peek apps
```

### Inspect a window's accessibility tree

```bash
# By app name
peek tree --app Xcode

# By window ID (from apps command)
peek tree 12345
```

### Search for UI elements

```bash
# Find all buttons in Xcode
peek find --app Xcode --role Button

# Find element by title
peek find --app Xcode --title "Run"

# Hit-test at screen coordinates
peek find --app Simulator --x 500 --y 300
```

### Interact with UI elements

```bash
# Click at coordinates
peek click --app Simulator --x 100 --y 200

# Type text
peek type --app Simulator --text "test@example.com"

# Press a button
peek action --app Xcode --role Button --title "Build" --do Press
```

### Work with menu bars

```bash
# Search menu items
peek menu --app Xcode --find "Run"

# Click a menu item
peek menu --app Xcode --click "Build"
```

### Capture screenshots

```bash
# Full window screenshot
peek capture --app Simulator --output simulator.png

# Crop region
peek capture --app Simulator --x 0 --y 0 --width 800 --height 600 --output screenshot.png
```

### Monitor UI changes

```bash
# Watch for changes (3 second delay between snapshots)
peek watch --app Xcode --snapshot --delay 3
```

## Command Reference

All commands support `--format json` for JSON output. Most accept window targeting via `--app <name>`, `--pid <pid>`, or positional `<window-id>`.

### Discovery

#### `apps`
List running applications and their windows.

```bash
peek apps [--app <name>] [--format json]
```

**Options:**
- `--app` — Filter by app name (case-insensitive substring)
- `--format` — Output format: `text` (default) or `json`

**Example:**
```bash
peek apps --app Xcode
```

### Inspection

#### `tree`
Display the accessibility tree of a window.

```bash
peek tree [<window-id>] [--app <name>] [--pid <pid>] [--depth <n>] [--format json]
```

**Options:**
- `--app` — Target app by name
- `--pid` — Target app by process ID
- `--depth` — Maximum tree depth to traverse
- `--format` — Output format: `text` (default) or `json`

**Example:**
```bash
peek tree --app Xcode --depth 5
```

#### `find`
Search for UI elements by attributes or coordinates.

```bash
peek find [<window-id>] [--app <name>] [--role <role>] [--title <title>]
          [--value <value>] [--desc <description>] [--x <x> --y <y>] [--format json]
```

**Options:**
- `--role` — Filter by accessibility role (e.g., `Button`, `TextField`)
- `--title` — Filter by title (case-insensitive substring)
- `--value` — Filter by value (case-insensitive substring)
- `--desc` — Filter by description (case-insensitive substring)
- `--x`, `--y` — Hit-test at screen coordinates

**Example:**
```bash
peek find --app Xcode --role Button --title "Run"
```

#### `menu`
Inspect or interact with application menu bars.

```bash
peek menu [--app <name>] [--find <query>] [--click <item>] [--format json]
```

**Options:**
- `--find` — Search for menu items by title
- `--click` — Click a menu item by title

**Example:**
```bash
peek menu --app Xcode --find "Build"
peek menu --app Xcode --click "Build"
```

### Interaction

#### `click`
Click at screen coordinates.

```bash
peek click --x <x> --y <y> [--app <name>] [--pid <pid>] [--window-id <id>]
```

**Options:**
- `--x`, `--y` — Screen coordinates (required)
- `--app`, `--pid`, `--window-id` — Auto-activate target window

**Example:**
```bash
peek click --app Simulator --x 500 --y 300
```

#### `type`
Type text via keyboard events.

```bash
peek type --text <text> [--app <name>] [--pid <pid>] [--window-id <id>]
```

**Options:**
- `--text` — Text to type (required)
- `--app`, `--pid`, `--window-id` — Auto-activate target window

**Example:**
```bash
peek type --app Simulator --text "test@example.com"
```

#### `action`
Perform accessibility actions on UI elements.

```bash
peek action --do <action> [--role <role>] [--title <title>] [--value <value>]
            [--desc <description>] [--all] [--app <name>] [--format json]
```

**Options:**
- `--do` — Action to perform: `Press`, `Confirm`, `Cancel`, `ShowMenu`, `Increment`, `Decrement`, `Raise`
- `--role`, `--title`, `--value`, `--desc` — Element filters
- `--all` — Perform action on all matching elements (default: first only)

**Example:**
```bash
peek action --app Xcode --role Button --title "Run" --do Press
```

#### `activate`
Bring an application window to the foreground.

```bash
peek activate [<window-id>] [--app <name>] [--pid <pid>]
```

**Example:**
```bash
peek activate --app Xcode
```

### Monitoring

#### `watch`
Monitor UI changes in a window.

```bash
peek watch [<window-id>] [--app <name>] [--snapshot] [--delay <seconds>] [--format json]
```

**Options:**
- `--snapshot` — Compare two snapshots and show diff
- `--delay` — Seconds to wait between snapshots (default: 3)

**Example:**
```bash
peek watch --app Xcode --snapshot --delay 5
```

#### `capture`
Capture a window screenshot.

```bash
peek capture [<window-id>] [--app <name>] [--output <path>]
             [--x <x>] [--y <y>] [--width <w>] [--height <h>]
```

**Options:**
- `--output` — Output PNG file path (default: `window_<id>.png`)
- `--x`, `--y`, `--width`, `--height` — Crop region (window-relative coordinates)

**Example:**
```bash
peek capture --app Simulator --output screenshot.png
```

### System

#### `doctor`
Check system permissions.

```bash
peek doctor [--prompt]
```

**Options:**
- `--prompt` — Open System Settings to grant missing permissions

**Example:**
```bash
peek doctor --prompt
```

#### `mcp`
Start the MCP server for AI agent integration.

```bash
peek mcp [--setup]
```

**Options:**
- `--setup` — Display integration instructions for MCP clients

## MCP Server Integration

Peek can run as an MCP server, making all commands available to AI agents for automated workflows.

### Setup

1. Install Peek via Homebrew or build from source
2. Run `peek mcp --setup` for configuration instructions
3. Add Peek to your MCP client config:

```json
{
  "mcpServers": {
    "peek": {
      "command": "/usr/local/bin/peek",
      "args": ["mcp"]
    }
  }
}
```

4. Restart your MCP client

### Available Tools

All Peek commands are exposed as MCP tools with the `peek_` prefix:
- `peek_apps`, `peek_tree`, `peek_find`, `peek_menu`
- `peek_click`, `peek_type`, `peek_action`, `peek_activate`
- `peek_watch`, `peek_capture`, `peek_doctor`

AI agents can now inspect, interact with, and automate any native macOS application.

## Permissions

Peek requires specific macOS permissions to function:

### Accessibility Permission (Required)
Needed for inspecting UI elements, interacting with windows, and most commands.

### Screen Recording Permission (Required for Screenshots)
Needed for the `capture` command.

Run `peek doctor` to check permissions and get setup instructions.

## License

MIT License - see LICENSE file for details.
