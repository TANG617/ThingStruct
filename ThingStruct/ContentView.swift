import SwiftUI

struct ContentView: View {
    @State private var store = ThingStructStore()

    var body: some View {
        AppShellView()
            .environment(store)
            .task {
                store.loadIfNeeded()
            }
    }
}

#Preview {
    ContentView()
}
