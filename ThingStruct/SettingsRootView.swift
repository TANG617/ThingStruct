import SwiftUI

enum SettingsDestination: Hashable {
    case templates
}

struct SettingsRootView: View {
    @Environment(ThingStructStore.self) private var store

    var body: some View {
        @Bindable var store = store

        NavigationStack(path: $store.settingsNavigationPath) {
            List {
                Section("Planning") {
                    NavigationLink(value: SettingsDestination.templates) {
                        SettingsEntryRow(
                            title: "Templates",
                            systemImage: "square.stack.3d.up",
                            subtitle: "Manage saved templates, weekday rules, and tomorrow overrides."
                        )
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .templates:
                    TemplatesRootView()
                }
            }
        }
    }
}

private struct SettingsEntryRow: View {
    let title: String
    let systemImage: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        }
    }
}

#Preview("Settings Root") {
    SettingsRootView()
        .environment(PreviewSupport.store(tab: .settings))
}

#Preview("Settings Root - Templates") {
    SettingsRootView()
        .environment(
            PreviewSupport.store(
                tab: .settings,
                settingsNavigationPath: [.templates]
            )
        )
}
