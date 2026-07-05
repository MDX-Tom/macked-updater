import AppKit
import SwiftUI

@main
struct MackedUpdaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.centerOffscreenWindows()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func centerOffscreenWindows() {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        for window in NSApp.windows where window.isVisible {
            let isVisibleOnAnyScreen = visibleFrames.contains { screenFrame in
                screenFrame.intersects(window.frame)
            }
            if !isVisibleOnAnyScreen {
                window.center()
            }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
