import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
#if DEBUG
        NSLog("DockShelf launched with arguments: %@", CommandLine.arguments.description)
#endif
    }
}
