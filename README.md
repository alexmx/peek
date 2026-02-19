# Peek

See and control any Mac app from your terminal.

<p align="center">
  <img width="1011" height="611" alt="peek tree output showing Xcode's accessibility hierarchy" src="https://github.com/user-attachments/assets/242b793f-9995-4d32-ab22-8e1859e8a002" />
</p>

A macOS CLI tool and MCP server for inspecting and automating native applications. Peek provides deep access to macOS accessibility APIs, enabling you to inspect UI hierarchies, search for elements, interact with windows, control menu bars, capture screenshots, and monitor real-time UI changes—all from the command line or through a lightweight MCP server optimized for AI agents with token-efficient output formats.

## Features

- **Discovery** — List running apps and their windows
- **Inspection** — Explore accessibility trees, search UI elements, inspect menu bars
- **Interaction** — Click, type, and trigger actions on UI elements programmatically
- **Monitoring** — Capture screenshots and watch for real-time UI changes
- **MCP Integration** — Use Peek tools directly in AI agents for automated workflows
- **Flexible Output** — Human-readable text, JSON, or TOON format (token-optimized for LLMs)

## Installation

### Homebrew

```bash
brew tap alexmx/tools
brew install peek
```

## Requirements

- macOS 15.0 or later
- **Accessibility permissions** (required for most commands)
- **Screen Recording permissions** (required for screenshots)

Run `peek doctor --prompt` to check and request permissions.

## Quick Start

### List all running applications and windows

```bash
peek apps
```
```
Xcode (9450)  com.apple.dt.Xcode
  956   peek — PeekTools.swift    (-7, 44) 1512x882

Simulator (11673)  com.apple.iphonesimulator
  1067   iPhone 16e    (901, 52) 408x862

2 app(s), 2 window(s).
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
peek action --app Xcode --role Button --desc "Build" --do Press --format toon
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

### Capture screenshots

```bash
# Full window screenshot
peek capture --app Simulator --output simulator.png

# Capture a specific region
peek capture --app Xcode --output toolbar.png --x 0 --y 0 --width 400 --height 50
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
| `find` | Search for UI elements by attributes or coordinates | `--role <role>` Filter by role<br>`--desc <text>` Filter by description<br>`--x <x> --y <y>` Hit-test at coordinates | `peek find --app Xcode --role Button --desc "Run"` |
| `menu` | Inspect or interact with application menu bars | `--find <query>` Search menu items<br>`--click <item>` Click a menu item | `peek menu --app Xcode --find "Build"` |

### Interaction

| Command | Description | Key Options | Example |
|---------|-------------|-------------|---------|
| `click` | Click at screen coordinates | `--x <x> --y <y>` Coordinates (required)<br>`--app <name>` Auto-activate app | `peek click --app Simulator --x 500 --y 300` |
| `scroll` | Scroll at screen coordinates | `--x <x> --y <y>` Coordinates (required)<br>`--delta-y <px>` Vertical scroll (required)<br>`--delta-x <px>` Horizontal scroll<br>`--drag` Drag gesture for touch apps | `peek scroll --app Simulator --x 200 --y 500 --delta-y 300 --drag` |
| `type` | Type text via keyboard events | `--text <text>` Text to type (required)<br>`--app <name>` Auto-activate app | `peek type --app Simulator --text "test@example.com"` |
| `action` | Perform accessibility actions on UI elements | `--do <action>` Action: Press, Confirm, etc.<br>`--role <role>` Filter by role<br>`--all` Act on all matches<br>`--result-tree` Return post-action tree<br>`--depth <n>` Tree depth (with result-tree)<br>`--delay <sec>` Wait before tree (default: 1) | `peek action --app Xcode --role Button --desc "Run" --do Press` |
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

- **`default`** — Human-readable output with formatting
- **`json`** — Standard JSON for programmatic use and scripting
- **`toon`** — Token-Optimized Object Notation for LLM consumption. YAML-like syntax that reduces token usage by 30-50% compared to JSON. Ideal for AI agents processing large outputs.

## MCP Server Integration

Peek can run as an MCP server, making all commands available to AI agents for automated workflows.

### Setup

1. Install Peek via Homebrew
2. Run `peek mcp --setup` for configuration instructions
3. If your AI agent is not listed, configure manually:

```json
{
  "mcpServers": {
    "peek": {
      "command": "peek",
      "args": ["mcp"]
    }
  }
}
```

4. Restart your MCP client

### Available Tools

All Peek commands are exposed as MCP tools with the `peek_` prefix:
- `peek_apps`, `peek_tree`, `peek_find`, `peek_menu`
- `peek_click`, `peek_scroll`, `peek_type`, `peek_action`, `peek_activate`
- `peek_watch`, `peek_capture`, `peek_doctor`

MCP tools return JSON format by default. `peek_capture` returns the screenshot image inline when no output path is specified. For token-optimized output, use the CLI with `--format toon`.

### AI Agent Skill

A comprehensive skill guide is available in `skills/peek/SKILL.md` that teaches AI agents how to use Peek effectively. The skill includes detailed command examples with TOON format output, common workflows, and best practices optimized for AI agent usage.

## License

MIT License - see [LICENSE](LICENSE) for details.
