import AppKit
import Foundation

/// Launch and terminate macOS applications.
enum AppLifecycleManager {
    struct LaunchResult: Encodable {
        let pid: Int32
        let bundleID: String?
        let name: String
        let path: String
    }

    struct QuitResult: Encodable {
        let pid: Int32
        let name: String
        let forced: Bool
    }

    /// Resolve an app to launch by bundle ID, absolute path, or name.
    /// Name search looks under /Applications and /System/Applications (depth 1).
    static func resolveAppURL(bundleID: String?, name: String?, path: String?) throws -> URL {
        if let path {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw PeekError.appNotFound(path)
            }
            return url
        }
        if let bundleID {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                throw PeekError.appNotFound(bundleID)
            }
            return url
        }
        if let name {
            let normalized = name.hasSuffix(".app") ? name : "\(name).app"
            for parent in ["/Applications", "/System/Applications", "/System/Applications/Utilities"] {
                let candidate = URL(fileURLWithPath: parent).appendingPathComponent(normalized)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            throw PeekError.appNotFound(name)
        }
        throw PeekError.appNotFound("(no bundle_id, name, or path)")
    }

    /// Launch an application. Returns once the app has begun running (and, when
    /// `waitForWindow` is true, once at least one AX-visible window appears).
    static func launch(url: URL, waitForWindow: Bool) async throws -> LaunchResult {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        let app: NSRunningApplication = try await withCheckedThrowingContinuation { cont in
            NSWorkspace.shared.openApplication(at: url, configuration: config) { running, error in
                if let error {
                    cont.resume(throwing: PeekError.launchFailed(url.lastPathComponent, error.localizedDescription))
                } else if let running {
                    cont.resume(returning: running)
                } else {
                    cont.resume(throwing: PeekError.launchFailed(url.lastPathComponent, "openApplication returned no running app"))
                }
            }
        }

        if waitForWindow {
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                let windows = try? await WindowManager.listWindows()
                if windows?.contains(where: { $0.pid == app.processIdentifier }) == true {
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        return LaunchResult(
            pid: app.processIdentifier,
            bundleID: app.bundleIdentifier,
            name: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
            path: url.path
        )
    }

    /// Quit a running app by PID, bundle ID, or name. Graceful by default;
    /// `force=true` uses SIGKILL-equivalent forceTerminate().
    static func quit(pid: pid_t?, bundleID: String?, name: String?, force: Bool) throws -> QuitResult {
        let app = try resolveRunningApp(pid: pid, bundleID: bundleID, name: name)
        let appName = app.localizedName ?? "Unknown"
        let appPid = app.processIdentifier

        let success = force ? app.forceTerminate() : app.terminate()
        if !success {
            throw PeekError.launchFailed(appName, force ? "forceTerminate returned false" : "terminate returned false")
        }
        return QuitResult(pid: appPid, name: appName, forced: force)
    }

    private static func resolveRunningApp(pid: pid_t?, bundleID: String?, name: String?) throws -> NSRunningApplication {
        if let pid {
            guard let app = NSRunningApplication(processIdentifier: pid) else {
                throw PeekError.appNotFound("pid \(pid)")
            }
            return app
        }
        if let bundleID {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
                throw PeekError.appNotFound(bundleID)
            }
            return app
        }
        if let name {
            let lower = name.lowercased()
            for app in NSWorkspace.shared.runningApplications {
                if app.localizedName?.lowercased().contains(lower) == true {
                    return app
                }
            }
            throw PeekError.appNotFound(name)
        }
        throw PeekError.appNotFound("(no pid, bundle_id, or name)")
    }
}
