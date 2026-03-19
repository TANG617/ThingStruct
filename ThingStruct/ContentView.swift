import SwiftUI

struct ContentView: View {
    @State private var store: ThingStructStore

    @MainActor
    init(store: ThingStructStore? = nil) {
        _store = State(initialValue: store ?? ThingStructStore())
    }

    var body: some View {
        AppShellView()
            .environment(store)
            .task {
                store.loadIfNeeded()
            }
    }
}

#Preview("Content") {
    ContentView(store: PreviewSupport.store())
}

#Preview("Content - Templates Tab") {
    ContentView(store: PreviewSupport.store(tab: .templates))
}
