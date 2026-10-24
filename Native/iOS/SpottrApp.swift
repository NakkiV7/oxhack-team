import SwiftUI

@main
struct SpottrApp: App {
    @State private var store = TrainingStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            SpottrRoot(store: store).preferredColorScheme(.light).tint(.black)
                .task {
                    while !Task.isCancelled {
                        store.publish()
                        try? await Task.sleep(for: .seconds(2))
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background, store.session.phase == .active { store.pause() }
                }
        }
    }
}
