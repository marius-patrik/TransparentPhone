import SwiftUI

@main
struct TransparentPhoneApp: App {
    @StateObject private var model = TransparencyModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}
