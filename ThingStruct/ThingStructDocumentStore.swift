import Foundation

// `ThingStructDocumentStore` is the persistence adapter for the entire app document.
// The core model stays in memory as `ThingStructDocument`; this type is responsible
// for converting that model to and from bytes on disk.
//
// If you come from C++, think of this as a tiny repository / serialization layer.
struct ThingStructDocumentStore {
    private let loadDocument: () throws -> ThingStructDocument?
    private let saveDocument: (ThingStructDocument) throws -> Void

    init(fileURL: URL) {
        loadDocument = {
            try Self.load(from: fileURL)
        }
        saveDocument = { document in
            try Self.save(document, to: fileURL)
        }
    }

    init(
        load: @escaping () throws -> ThingStructDocument?,
        save: @escaping (ThingStructDocument) throws -> Void
    ) {
        loadDocument = load
        saveDocument = save
    }

    func load() throws -> ThingStructDocument? {
        try loadDocument()
    }

    func save(_ document: ThingStructDocument) throws {
        try saveDocument(document)
    }

    private static func load(from fileURL: URL) throws -> ThingStructDocument? {
        // Returning `nil` here means "no document has been saved yet", not "an error happened".
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ThingStructDocument.self, from: data)
    }

    private static func save(
        _ document: ThingStructDocument,
        to fileURL: URL
    ) throws {
        // iOS apps commonly store app-private files under Application Support.
        // We create the directory lazily so first launch works with no manual setup.
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        // `.atomic` writes via a temporary file and then swaps it into place.
        // This reduces the chance of leaving a half-written document if the app is interrupted.
        try data.write(to: fileURL, options: .atomic)
    }

    nonisolated static var live: ThingStructDocumentStore {
        let client = ThingStructSharedDocumentClient.appLive
        return ThingStructDocumentStore(
            load: {
                try client.load()
            },
            save: { document in
                try client.save(document)
            }
        )
    }
}
