import SwiftUI

@main
struct SpottrApp: App {
    @State private var workspace = PreviewWorkspace()
    private var store: TrainingStore { workspace.store }
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            SpottrRoot(store: store, profileStore: workspace.profileStore, workspace: workspace)
                .id(workspace.isPreview).preferredColorScheme(.light).tint(Palette.blue)
                .task(id: ObjectIdentifier(store)) {
                    let store = workspace.store
                    store.setAppActive(scenePhase == .active)
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
