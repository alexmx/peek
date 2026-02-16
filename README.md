# Peek

A macOS CLI tool and MCP server for inspecting and automating native applications.

Peek provides deep access to macOS accessibility APIs, enabling you to inspect UI hierarchies, search for elements, interact with windows, control menu bars, capture screenshots, and monitor real-time UI changes—all from the command line or through a lightweight MCP server optimized for AI agents with token-efficient output formats.

## Features

- **🔍 Discovery** — List running apps and their windows
- **🌳 Inspection** — Explore accessibility trees, search UI elements, inspect menu bars
- **⚡️ Interaction** — Click, type, and trigger actions on UI elements programmatically
- **📸 Monitoring** — Capture screenshots and watch for real-time UI changes
- **🤖 MCP Integration** — Use Peek tools directly in AI agents for automated workflows
- **📋 Flexible Output** — Human-readable text, JSON, or TOON format (token-optimized for LLMs)

## Installation

```bash
brew tap alexmx/tools
brew install peek
```

## Requirements

- macOS 15.0 or later
- **Accessibility permissions** (required for most commands)
- **Screen Recording permissions** (required for screenshots)

Run `peek doctor` to check and request permissions.

## Quick Start

### List all running applications and windows

```bash
peek apps --format toon
```
```yaml
[2]:
  - name: Xcode
    bundleID: com.apple.dt.Xcode
    pid: 9450
    windows[1]:
      - windowID: 956
        title: peek — PeekTools.swift
        frame:
          x: -7
          y: 44
          width: 1512
          height: 882
        isOnScreen: true
  - name: Simulator
    bundleID: com.apple.iphonesimulator
    pid: 11673
    windows[1]:
      - windowID: 1067
        title: iPhone 16e
        frame:
          x: 901
          y: 52
          width: 408
          height: 862
        isOnScreen: true
```

### Inspect a window's accessibility tree

```bash
peek tree --app Xcode --depth 3
```
```
Window  "peek — PeekTools.swift"  (0, 33) 1512x882
├── SplitGroup  "peek"  (0, 33) 1512x882
│   ├── Group  desc="navigator"  (8, 41) 300x866
│   │   ├── RadioGroup  (15, 84) 286x30
│   │   ├── ScrollArea  (8, 113) 300x750
│   │   └── TextField  desc="filter"  (43, 870) 258x30
│   ├── Splitter  value="308"  (308, 85) 0x830
│   └── Group  desc="editor"  (308, 85) 1204x830
│       ├── TabGroup  (308, 85) 1204x830
│       └── ScrollArea  (308, 115) 1204x800
├── Toolbar  (0, 33) 1512x52
│   ├── Button  desc="Run"  (276, 45) 28x28
│   └── Button  desc="Stop"  (304, 45) 28x28
└── Button  (18, 51) 16x16
```

### Search for UI elements

```bash
# Find all buttons in Xcode
peek find --app Xcode --role Button --format toon
```
```yaml
[2]:
  - role: Button
    frame:
      x: 365
      y: 76
      width: 16
      height: 16
  - role: Button
    description: Run
    frame:
      x: 276
      y: 45
      width: 28
      height: 28
```

```bash
# Hit-test at screen coordinates
peek find --app Simulator --x 500 --y 300 --format toon
```
```yaml
role: StaticText
value: Settings
frame:
  x: 450
  y: 280
  width: 100
  height: 20
```

### Interact with UI elements

```bash
# Click at coordinates
peek click --app Simulator --x 100 --y 200
```

```bash
# Press a button
peek action --app Xcode --role Button --title "Build" --do Press --format toon
```
```yaml
role: Button
description: Build
frame:
  x: 276
  y: 45
  width: 28
  height: 28
```

### Work with menu bars

```bash
# Search menu items
peek menu --app Xcode --find "Run" --format toon
```
```yaml
[2]:
  - title: Run
    shortcut: ⌘R
    path: Product > Run
  - title: Run Without Building
    shortcut: ⌃⌘R
    path: Product > Perform Action > Run Without Building
```

```bash
# Click a menu item
peek menu --app Xcode --click "Build"
```

### Capture screenshots

```bash
# Full window screenshot
peek capture --app Simulator --output simulator.png --format toon
```
```yaml
path: simulator.png
width: 816
height: 1724
```

### Monitor UI changes

```bash
# Watch for changes (3 second delay between snapshots)
peek watch --app Xcode --snapshot --delay 3 --format toon
```
```yaml
changed[1]:
  - role: StaticText
    before:
      value: Build Succeeded
    after:
      value: Indexing
    frame:
      x: 608
      y: 47
```

## Command Reference

All commands support `--format` for structured output: `json` (standard JSON) or `toon` (token-optimized for LLMs). Most accept window targeting via `--app <name>`, `--pid <pid>`, or positional `<window-id>`.

### Discovery

| Command | Description | Key Options | Example |
|---------|-------------|-------------|---------|
| `apps` | List running applications and their windows | `--app <name>` Filter by app name<br>`--format` Output format | `peek apps --app Xcode` |

### Inspection

| Command | Description | Key Options | Example |
|---------|-------------|-------------|---------|
| `tree` | Display the accessibility tree of a window | `--app <name>` Target app<br>`--depth <n>` Max tree depth<br>`--format` Output format | `peek tree --app Xcode --depth 5` |
| `find` | Search for UI elements by attributes or coordinates | `--role <role>` Filter by role<br>`--title <text>` Filter by title<br>`--x <x> --y <y>` Hit-test at coordinates | `peek find --app Xcode --role Button --title "Run"` |
| `menu` | Inspect or interact with application menu bars | `--find <query>` Search menu items<br>`--click <item>` Click a menu item | `peek menu --app Xcode --find "Build"` |

### Interaction

| Command | Description | Key Options | Example |
|---------|-------------|-------------|---------|
| `click` | Click at screen coordinates | `--x <x> --y <y>` Coordinates (required)<br>`--app <name>` Auto-activate app | `peek click --app Simulator --x 500 --y 300` |
| `type` | Type text via keyboard events | `--text <text>` Text to type (required)<br>`--app <name>` Auto-activate app | `peek type --app Simulator --text "test@example.com"` |
| `action` | Perform accessibility actions on UI elements | `--do <action>` Action: Press, Confirm, etc.<br>`--role <role>` Filter by role<br>`--all` Act on all matches | `peek action --app Xcode --role Button --title "Run" --do Press` |
| `activate` | Bring an application window to the foreground | `--app <name>` Target app<br>`--pid <pid>` Target by PID | `peek activate --app Xcode` |

### Monitoring

| Command | Description | Key Options | Example |
|---------|-------------|-------------|---------|
| `watch` | Monitor UI changes in a window | `--snapshot` Compare snapshots<br>`--delay <sec>` Wait time (default: 3) | `peek watch --app Xcode --snapshot --delay 5` |
| `capture` | Capture a window screenshot | `--output <path>` Output file<br>`--x --y --width --height` Crop region | `peek capture --app Simulator --output screenshot.png` |

### System

| Command | Description | Key Options | Example |
|---------|-------------|-------------|---------|
| `doctor` | Check system permissions | `--prompt` Open System Settings | `peek doctor --prompt` |
| `mcp` | Start the MCP server for AI agent integration | `--setup` Show integration instructions | `peek mcp --setup` |

## Output Formats

All commands support structured output via the `--format` flag:

- **`text` (default)** — Human-readable output with formatting and colors
- **`json`** — Standard JSON for programmatic use and scripting
- **`toon`** — Token-Optimized Object Notation, a specialized format designed for LLM consumption that reduces token usage by 30-50% compared to JSON while maintaining full structure. Uses YAML-like syntax with compact array notation (`[count]:`) and inline frames. Ideal for AI agents processing large accessibility trees or search results. Recommended for all MCP workflows via CLI.

## MCP Server Integration

Peek can run as an MCP server, making all commands available to AI agents for automated workflows.

### Setup

1. Install Peek via Homebrew
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

MCP tools return JSON format by default (as required by the MCP protocol). For token-optimized output, use the CLI with `--format toon`.

AI agents can now inspect, interact with, and automate any native macOS application.

## License

MIT License - see [LICENSE](LICENSE) for details.
