import SwiftUI

@main
struct SpottrApp: App {
    @State private var store = TrainingStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            SpottrRoot(store: store).preferredColorScheme(.light).tint(.black)
                .task {
                    defer { store.cancelCoaching() }
                    var publishSnapshot = true
                    while !Task.isCancelled {
                        store.coachingTick()
                        if publishSnapshot { store.publish() }
                        publishSnapshot.toggle()
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if store.sessionPhase == .active,
                       phase == .background || (phase == .inactive && store.configured != nil) { store.pause() }
                }
        }
    }
}
