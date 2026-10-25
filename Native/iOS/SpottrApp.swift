import SwiftUI

@main
struct SpottrApp: App {
    @State private var store = TrainingStore()
    @State private var profileStore = NativeProfileStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            SpottrRoot(store: store, profileStore: profileStore).preferredColorScheme(.light).tint(Palette.blue)
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
                .onChange(of: scenePhase, initial: true) { _, phase in
                    store.setAppActive(phase == .active)
                    if phase == .active { store.refreshRewards() }
                    if store.sessionPhase == .active,
                       phase == .background || (phase == .inactive && store.configured != nil) { store.pause() }
                }
        }
    }
}
