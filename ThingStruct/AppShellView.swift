import SwiftUI

struct AppShellView: View {
    @Environment(ThingStructStore.self) private var store

    var body: some View {
        @Bindable var store = store

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
        .alert(
            "Unable to Complete Action",
            isPresented: Binding(
                get: { store.lastErrorMessage != nil },
                set: { if !$0 { store.lastErrorMessage = nil } }
            )
        ) {
            Button("OK") {
                store.lastErrorMessage = nil
            }
        } message: {
            Text(store.lastErrorMessage ?? "")
        }
    }
}
