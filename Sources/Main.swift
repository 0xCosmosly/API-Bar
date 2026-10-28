import AppKit

@main
enum Main {
    @MainActor static func main() {
        let hasCLICommand = CommandLine.arguments.contains(where: { $0.hasPrefix("--") })
        if !hasCLICommand,
           let identifier = Bundle.main.bundleIdentifier,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }) {
            running.activate(options: [])
            return
        }
        let application = NSApplication.shared
        let delegate = APIBarApp()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
