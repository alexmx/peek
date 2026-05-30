# Peek

## What is Peek?

Peek is a macOS CLI tool and MCP server for inspecting and automating native application windows. It provides accessibility tree inspection, element search, UI interaction (click, type, actions), menu bar control, screenshots, and app lifecycle control (launch/quit).

## Project Structure

```
peek/
├── Package.swift                    # SPM manifest (macOS 15+, Swift 6.2)
├── Sources/Peek/
│   ├── Peek.swift                   # @main entry point, registers all subcommands
│   ├── Commands/                    # One file per CLI command
│   ├── Managers/                    # Core business logic (stateless enum singletons)
│   ├── Models/                      # Data types (AXNode, WindowInfo, PeekError, etc.)
│   ├── MCP/
│   │   └── PeekTools.swift          # MCP tool definitions, mirrors CLI 1:1
│   └── Utilities/                   # AX helpers, key mapping, output formatting
```

## Build & Run

```bash
swift build
swift run peek <command> [options]
```

**Requirements:** macOS 15+, Swift 6.2, Xcode toolchain.

**Dependencies:**
- `swift-argument-parser` — CLI argument parsing
- `swift-cli-mcp` — MCP server framework

## Version Management & Releases

**Version Source:** `.peek-version` file in repository root

- Single source of truth for version number (e.g., `1.0.0` or `dev`)
- `Sources/Peek/Version.swift` defines `peekVersion` constant (defaults to "dev" for local builds)
- GitHub Actions reads `.peek-version`, generates `Version.swift` with actual version, then builds release binary
- CLI exposes version via `peek --version`

**Release Process:**

1. Update `.peek-version` with new version (e.g., `1.0.0`)
2. Commit and push to main
3. Manually trigger "Release" workflow from GitHub Actions (or enable auto-trigger in `.github/workflows/release.yml`)
4. Workflow creates git tag, builds universal binary, publishes GitHub release
5. Update Homebrew formula in `homebrew-tools` repository with new SHA256

**Homebrew Distribution:**

Users install via:
```bash
brew tap alexmx/tools
brew install peek
```

Formula location: `alexmx/homebrew-tools/Formula/peek.rb`

## Commands

All commands support `--format json` for JSON output (default: text). Most commands accept window targeting via `--app <name>`, `--pid <pid>`, or positional `<window-id>`.

### Discovery
- **apps** — List running apps and windows. `--app` to filter by name.

### Inspection
- **tree** — Accessibility tree of a window. `--depth` to limit traversal (default: full tree from CLI).
- **find** — Search elements by `--role`, `--title`, `--value`, `--desc`, `--enabled`, or hit-test with `--x`/`--y`. The `--title` filter matches AXTitle OR AXDescription; `--enabled true|false` narrows by state.
- **menu** — Menu bar structure. `--find` searches items, `--click` triggers an item, `--path` returns just a scoped submenu (e.g. `--path Debug`) to avoid dumping the full menu tree on large apps.

### Interaction
- **click** — Click at `--x`/`--y` screen coordinates.
- **scroll** — Scroll at `--x`/`--y` screen coordinates with `--delta-y` (required) and `--delta-x` (optional). `--drag` for touch-based apps like iOS Simulator.
- **type** — Type `--text` via keyboard events.
- **action** — Perform an AX action (`--do Press|Confirm|Cancel|ShowMenu`) on elements matched by `--role`/`--title`/`--value`/`--desc`. `--all` for all matches. `--verify tree|diff|none` (default `none`) atomically captures the post-action state — `diff` returns just what changed (best for "did this update?" checks), `tree` returns the full post-action tree. Tune via `--depth` and `--delay`.
- **activate** — Bring app to foreground.
- **launch** — Launch an app by `--bundle-id`, `--name`, or `--path`. `--wait-for-window` blocks until at least one AX-visible window appears (10s budget).
- **quit** — Terminate a running app by `--pid`, `--bundle-id`, or `--name`. `--force` uses forceTerminate.

### Monitoring
- **capture** — Screenshot to PNG. `--output` path, `--x`/`--y`/`--width`/`--height` to crop (window-relative pixels).

### System
- **doctor** — Check Accessibility/Screen Recording permissions. `--prompt` to open System Settings.
- **mcp** — Start MCP server. `--setup` for integration instructions.

## Swift Style

- Swift 6.2 with modern concurrency

## Adding a New Command

1. Create `Sources/Peek/Commands/NewCommand.swift` implementing `AsyncParsableCommand`
2. Add it as a subcommand in `Peek.swift`
3. Put business logic in an existing or new manager under `Managers/`
4. Add the corresponding MCP tool in `MCP/PeekTools.swift`
5. Add any new model types under `Models/`

## Formatting

```bash
swiftformat .
```
