import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable via `swift run`.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MacSpaceManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Space Manager") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 700)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan Home Folder") { model.scan(.home) }
                    .keyboardShortcut("r")
                Button("Scan Entire Disk") { model.scan(.disk) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Scan Folder…") { model.chooseFolder() }
                    .keyboardShortcut("o")
            }
        }
    }
}
