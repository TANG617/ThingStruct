import SwiftUI

// `@main` in SwiftUI plays a role similar to `int main()` in C++.
// The difference is that the iOS runtime owns the event loop and application lifecycle.
// We provide an `App` value describing the root scene graph, and SwiftUI/UIKit do the rest.
@main
struct ThingStructApp: App {
    var body: some Scene {
        // `WindowGroup` is the root container for one or more app windows/scenes.
        // On iPhone you can think of it as "the main app window".
        WindowGroup {
            ContentView()
        }
    }
}
