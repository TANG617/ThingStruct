import SwiftUI

// `AppShellView` is the global frame around the three feature screens.
// It owns navigation between tabs and shows app-wide errors.
//
// Architecturally, this is close to a "shell" or "frame window" in desktop UI.
struct AppShellView: View {
    // `@Environment(ThingStructStore.self)` asks SwiftUI to inject the shared store.
    // This avoids manually threading the store through every initializer.
    @Environment(ThingStructStore.self) private var store

    var body: some View {
        // `@Bindable` creates bindings into an `@Observable` object.
        // In C++ terms, this is a bit like getting mutable references to fields
        // while still letting the framework observe changes and trigger re-rendering.
        @Bindable var store = store

        // `TabView` is the iOS equivalent of a bottom tab bar controller.
        TabView(selection: $store.selectedTab) {
            NowRootView()
                .tabItem {
                    Label("Now", systemImage: "bolt.circle")
                }
                .tag(RootTab.now)

            TodayRootView()
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }
                .tag(RootTab.today)

            TemplatesRootView()
                .tabItem {
                    Label("Templates", systemImage: "square.stack.3d.up")
                }
                .tag(RootTab.templates)
        }
        // Global error presentation lives here so feature screens can report errors
        // without each screen reinventing its own alert state.
        .alert(
            "Unable to Complete Action",
            isPresented: Binding(
                get: { store.lastErrorMessage != nil },
                set: { if !$0 { store.dismissError() } }
            )
        ) {
            Button("OK") {
                store.dismissError()
            }
        } message: {
            Text(store.lastErrorMessage ?? "")
        }
    }
}

#Preview("App Shell - Now") {
    AppShellView()
        .environment(PreviewSupport.store(tab: .now))
}

#Preview("App Shell - Today") {
    AppShellView()
        .environment(PreviewSupport.store(tab: .today))
}

#Preview("App Shell - Templates") {
    AppShellView()
        .environment(PreviewSupport.store(tab: .templates))
}

#Preview("App Shell - Error Alert") {
    AppShellView()
        .environment(
            PreviewSupport.store(
                tab: .now,
                lastErrorMessage: "This is a preview alert message."
            )
        )
}
