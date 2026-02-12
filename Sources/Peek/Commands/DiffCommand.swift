import ArgumentParser
import CoreGraphics
import Foundation

struct DiffCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff",
        abstract: "Snapshot the accessibility tree, wait, then show changes"
    )

    @Argument(help: "The window ID to diff")
    var windowID: UInt32

    @Option(name: .shortAndLong, help: "Seconds to wait between snapshots (default: 3)")
    var delay: Double = 3.0

    @Option(name: .long, help: "Output format")
    var format: OutputFormat = .default

    func run() throws {
        guard let pid = WindowManager.pid(forWindowID: windowID) else {
            throw PeekError.windowNotFound(windowID)
        }

        if format != .json {
            print("Taking first snapshot...")
            print("Waiting \(String(format: "%.1f", delay))s...")
        }

        let diff = try MonitorManager.diff(pid: pid, windowID: windowID, delay: delay)

        if format == .json {
            try printJSON(diff)
        } else {
            printDiff(diff)
        }
    }

    private func printDiff(_ diff: TreeDiff) {
        let total = diff.added.count + diff.removed.count + diff.changed.count
        if total == 0 {
            print("No changes detected.")
            return
        }

        if !diff.added.isEmpty {
            print("\n+ Added (\(diff.added.count)):")
            for node in diff.added {
                print("  + \(formatNode(node))")
            }
        }

        if !diff.removed.isEmpty {
            print("\n- Removed (\(diff.removed.count)):")
            for node in diff.removed {
                print("  - \(formatNode(node))")
            }
        }

        if !diff.changed.isEmpty {
            print("\n~ Changed (\(diff.changed.count)):")
            for change in diff.changed {
                print("  ~ \(change.role) [\(change.identity)]")
                if change.before.value != change.after.value {
                    print("    value: \"\(change.before.value ?? "")\" -> \"\(change.after.value ?? "")\"")
                }
                if change.before.title != change.after.title {
                    print("    title: \"\(change.before.title ?? "")\" -> \"\(change.after.title ?? "")\"")
                }
                if change.before.frame != change.after.frame {
                    if let bf = change.before.frame, let af = change.after.frame {
                        print("    frame: (\(bf.x), \(bf.y)) \(bf.width)x\(bf.height) -> (\(af.x), \(af.y)) \(af.width)x\(af.height)")
                    }
                }
            }
        }

        print("\n\(total) change(s) detected.")
    }

    private func formatNode(_ node: AXNode) -> String {
        var line = node.role
        if let t = node.title, !t.isEmpty { line += "  \"\(t)\"" }
        if let v = node.value, !v.isEmpty { line += "  value=\"\(v)\"" }
        if let d = node.description, !d.isEmpty { line += "  desc=\"\(d)\"" }
        if let f = node.frame {
            line += "  (\(f.x), \(f.y)) \(f.width)x\(f.height)"
        }
        return line
    }
}
