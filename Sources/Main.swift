import AppKit

@main
enum Main {
    @MainActor static func main() {
        let hasCLICommand = CommandLine.arguments.contains(where: { $0.hasPrefix("--") })
        if !hasCLICommand,
           let identifier = Bundle.main.bundleIdentifier {
            let otherApps = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
            if let existing = otherApps.first {
                // When relaunching from an in-place updater or Settings relaunch,
                // the previous instance may still be in the process of terminating.
                // Poll briefly (up to 1.0s) for it to exit rather than immediately quitting.
                var isOldInstanceTerminated = false
                for _ in 0..<20 {
                    if existing.isTerminated || kill(existing.processIdentifier, 0) != 0 {
                        isOldInstanceTerminated = true
                        break
                    }
                    usleep(50_000) // 50ms
                }
                if !isOldInstanceTerminated {
                    existing.activate(options: [])
                    return
                }
            }
        }
        let application = NSApplication.shared
        let delegate = APIBarApp()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
