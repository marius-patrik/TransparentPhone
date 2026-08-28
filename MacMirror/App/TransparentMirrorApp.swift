import SwiftUI
import AppKit

@main
struct TransparentMirrorApp: App {
    @StateObject private var model = MirrorModel()

    var body: some Scene {
        WindowGroup {
            MirrorView(model: model)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Transparent Mirror") { }
            }
        }
    }
}
