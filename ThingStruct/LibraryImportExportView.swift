import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

extension UTType {
    static var thingStructPortableYAML: UTType {
        UTType(exportedAs: "tang.ThingStruct.portable-yaml", conformingTo: .plainText)
    }
}

struct LibraryImportExportView: View {
    @Environment(ThingStructStore.self) private var store

    @State private var sharedExportFile: SharedExportFile?
    @State private var sharedExportCleanupURL: URL?
    @State private var isShowingImporter = false
    @State private var pendingImport: PendingTodayImport?

    var body: some View {
        List {
            Section("Today") {
                Button {
                    beginExport()
                } label: {
                    Label("Export Today's Blocks", systemImage: "square.and.arrow.up")
                }
                .disabled(!store.isLoaded)

                Button(role: .destructive) {
                    isShowingImporter = true
                } label: {
                    Label("Import to Today", systemImage: "square.and.arrow.down")
                }
                .disabled(!store.isLoaded)
            }

            Section("Format") {
                Text("The exported file is human-readable YAML with titles, notes, timing, reminders, tasks, and nested children.")
                Text("Importing replaces today's current user-defined blocks after confirmation.")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
        }
        .navigationTitle("Import & Export")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharedExportFile, onDismiss: cleanupSharedExportFile) { sharedExportFile in
            ShareSheet(activityItems: [sharedExportFile.url])
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.thingStructPortableYAML, .plainText]
        ) { result in
            handleImportSelection(result)
        }
        .alert(
            "Replace Today's Blocks?",
            isPresented: Binding(
                get: { pendingImport != nil },
                set: {
                    if !$0 {
                        pendingImport = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingImport = nil
            }

            Button("Replace", role: .destructive) {
                performPendingImport()
            }
        } message: {
            Text(pendingImportMessage)
        }
    }

    private func beginExport() {
        do {
            let yaml = try store.exportTodayBlocksYAML()
            sharedExportFile = try makeSharedExportFile(yaml: yaml)
        } catch {
            store.presentError(error)
        }
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let yaml = try loadText(from: url)
            let summary = try store.previewTodayBlocksImport(yaml)
            pendingImport = PendingTodayImport(
                sourceFilename: url.lastPathComponent,
                yaml: yaml,
                summary: summary
            )
        } catch {
            store.presentError(error)
        }
    }

    private func performPendingImport() {
        guard let pendingImport else { return }

        do {
            try store.importTodayBlocksYAML(pendingImport.yaml)
            self.pendingImport = nil
        } catch {
            store.presentError(error)
        }
    }

    private var pendingImportMessage: String {
        guard let pendingImport else { return "" }

        return """
        \(pendingImport.sourceFilename) will replace today's blocks.

        Source date: \(pendingImport.summary.sourceDate.description)
        Blocks: \(pendingImport.summary.totalBlockCount)
        Base blocks: \(pendingImport.summary.baseBlockCount)
        Tasks: \(pendingImport.summary.taskCount)
        """
    }

    private func loadText(from url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    private func makeSharedExportFile(yaml: String) throws -> SharedExportFile {
        let filename = "thingstruct-day-\(LocalDay.today().description).yml"
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ThingStructExports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let fileURL = directory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: filename)
        let exportDirectory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )
        try Data(yaml.utf8).write(to: fileURL, options: .atomic)
        sharedExportCleanupURL = exportDirectory
        return SharedExportFile(url: fileURL)
    }

    private func cleanupSharedExportFile() {
        if let sharedExportCleanupURL {
            try? FileManager.default.removeItem(at: sharedExportCleanupURL)
        }
        sharedExportCleanupURL = nil
        self.sharedExportFile = nil
    }
}

private struct PendingTodayImport {
    let sourceFilename: String
    let yaml: String
    let summary: PortableDayBlocksSummary
}

private struct SharedExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

#if canImport(UIKit)
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}
#endif

#Preview("Library Import & Export") {
    NavigationStack {
        LibraryImportExportView()
    }
    .environment(PreviewSupport.store(tab: .library))
}
