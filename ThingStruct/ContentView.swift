import SwiftUI

// `ContentView` is the composition root for the app's SwiftUI tree.
// If you come from C++, think of this file as the place where we allocate
// the long-lived "application controller" (`ThingStructStore`) and inject it
// into the rest of the UI.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    // `@State` gives this view ownership of a mutable value whose lifetime is
    // tied to the view instance rather than to a single render pass.
    //
    // This is important: SwiftUI view structs are recreated frequently.
    // Plain stored properties would be reset. `@State` keeps the store alive.
    @State private var store: ThingStructStore

    @MainActor
    init(store: ThingStructStore? = nil) {
        // Previews/tests can pass a custom store. The real app uses the default one.
        _store = State(initialValue: store ?? ThingStructStore())
    }

    var body: some View {
        AppShellView()
            // `.environment(store)` is dependency injection.
            // Any descendant view can request `ThingStructStore` with `@Environment`.
            .environment(store)
            .task {
                // `.task` is SwiftUI's way to run async/side-effect work tied to a view's life.
                // Here we bootstrap the document exactly once when the root UI appears.
                store.loadIfNeeded()
                if let pendingURL = ThingStructExternalRouteCenter.shared.consumePendingURL() {
                    store.handleDeepLink(pendingURL)
                }
                ThingStructQuickActionManager.refresh()
            }
            .onOpenURL { url in
                store.handleDeepLink(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .thingStructExternalRouteDidChange)) { notification in
                guard let url = notification.object as? URL else { return }
                store.handleDeepLink(url)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active, store.isLoaded else { return }
                store.reload()
                store.syncCurrentBlockLiveActivity()
                ThingStructQuickActionManager.refresh()
                if let pendingURL = ThingStructExternalRouteCenter.shared.consumePendingURL() {
                    store.handleDeepLink(pendingURL)
                }
            }
    }
}

#Preview("Content - Now") {
    ContentView(store: PreviewSupport.store(tab: .now))
}

#Preview("Content - Today") {
    ContentView(store: PreviewSupport.store(tab: .today))
}

#Preview("Content - Library Tab") {
    ContentView(store: PreviewSupport.store(tab: .library))
}

#Preview("Content - Templates in Library") {
    ContentView(
        store: PreviewSupport.store(
            tab: .library,
            libraryNavigationPath: [.templates]
        )
    )
}
