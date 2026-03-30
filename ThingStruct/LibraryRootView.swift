import SwiftUI

enum LibraryDestination: Hashable {
    case templates
    case importExport
    case settings
}

struct LibraryRootView: View {
    @Environment(ThingStructStore.self) private var store

    var body: some View {
        @Bindable var store = store

        NavigationStack(path: $store.libraryNavigationPath) {
            List {
                Section {
                    LibraryStatusSummaryRow(
                        todayStatus: store.isLoaded
                            ? (store.requiresTemplateSelection(for: .today()) ? "Choose today" : "Ready")
                            : "Loading",
                        templateCount: store.savedTemplates.count,
                        tintTitle: store.tintPreset.title
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section("Workspace") {
                    NavigationLink(value: LibraryDestination.templates) {
                        LibraryEntryRow(
                            title: "Templates",
                            systemImage: "square.stack.3d.up",
                            subtitle: "Choose today and manage reusable day structures.",
                            status: store.savedTemplates.isEmpty ? "Empty" : "\(store.savedTemplates.count)"
                        )
                    }
                }

                Section("Appearance") {
                    NavigationLink(value: LibraryDestination.settings) {
                        LibraryEntryRow(
                            title: "Settings",
                            systemImage: "paintpalette",
                            subtitle: "Tune tint and global visual behavior.",
                            status: store.tintPreset.title
                        )
                    }
                }

                Section("Data") {
                    NavigationLink(value: LibraryDestination.importExport) {
                        LibraryEntryRow(
                            title: "Import & Export",
                            systemImage: "arrow.up.arrow.down.doc",
                            subtitle: "Move day plans in and out through YAML.",
                            status: "YAML"
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: LibraryDestination.self) { destination in
                switch destination {
                case .templates:
                    TemplatesRootView()

                case .importExport:
                    LibraryImportExportView()

                case .settings:
                    LibrarySettingsView()
                }
            }
        }
    }
}

private struct LibraryStatusSummaryRow: View {
    let todayStatus: String
    let templateCount: Int
    let tintTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workspace Status")
                .font(.headline)

            HStack(spacing: 10) {
                summaryPill(
                    title: "Today",
                    value: todayStatus,
                    systemImage: "calendar"
                )
                summaryPill(
                    title: "Templates",
                    value: templateCount == 0 ? "None" : "\(templateCount)",
                    systemImage: "square.stack.3d.up"
                )
                summaryPill(
                    title: "Tint",
                    value: tintTitle,
                    systemImage: "paintpalette"
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 4)
    }

    private func summaryPill(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct LibrarySettingsView: View {
    @Environment(ThingStructStore.self) private var store

    var body: some View {
        List {
            Section("Tint Presets") {
                ForEach(AppTintPreset.allCases) { preset in
                    Button {
                        store.applyTintPreset(preset)
                    } label: {
                        TintPresetRow(
                            preset: preset,
                            isSelected: store.tintPreset == preset
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(store.tintPreset == preset ? [.isSelected] : [])
                }
            }

            Section("Behavior") {
                Text("The selected tint updates the global accent and regenerates the layered block palette so Now, Today, Library, widgets, and live activities keep the same depth curve.")

                Text("Blank blocks stay neutral, while active layers reuse the same saturation and brightness steps across every preset.")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TintPresetRow: View {
    let preset: AppTintPreset
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            TintPresetSwatch(preset: preset)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(preset.title)
                        .font(.body.weight(.semibold))

                    if preset == .ocean {
                        Text("Default")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                    }
                }

                Text(preset.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct TintPresetSwatch: View {
    let preset: AppTintPreset

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .leading) {
                ForEach(Array((0 ..< 4).reversed()), id: \.self) { layer in
                    let style = LayerVisualStyle.forBlock(
                        layerIndex: layer,
                        isBlank: false,
                        preset: preset
                    )

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(style.strongSurface)
                        .frame(width: 34, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(style.border, lineWidth: 1)
                        )
                        .offset(x: CGFloat(layer) * 8)
                }
            }
            .frame(width: 58, height: 28, alignment: .leading)

            Circle()
                .fill(preset.tintColor)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(Color(uiColor: .systemBackground), lineWidth: 2)
                )
        }
        .frame(width: 64, height: 36)
        .accessibilityHidden(true)
    }
}

private struct LibraryEntryRow: View {
    let title: String
    let systemImage: String
    let subtitle: String
    var status: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.body.weight(.semibold))

                    if let status {
                        Text(status)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        }
    }
}

#Preview("Library Root") {
    LibraryRootView()
        .environment(PreviewSupport.store(tab: .library))
}

#Preview("Library Root - Settings") {
    LibraryRootView()
        .environment(
            PreviewSupport.store(
                tab: .library,
                libraryNavigationPath: [.settings],
                tintPreset: .meadow
            )
        )
}

#Preview("Library Root - Templates") {
    LibraryRootView()
        .environment(
            PreviewSupport.store(
                tab: .library,
                libraryNavigationPath: [.templates]
            )
        )
}
