import SwiftUI

@main
struct SpottrApp: App {
    var body: some Scene {
        WindowGroup {
            AccountRootView().preferredColorScheme(.light).tint(Palette.blue)
        }
    }
}
