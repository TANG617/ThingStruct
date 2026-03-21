import Foundation

// `ThingStructDocumentStore` is the persistence adapter for the entire app document.
// The core model stays in memory as `ThingStructDocument`; this type is responsible
// for converting that model to and from bytes on disk.
//
// If you come from C++, think of this as a tiny repository / serialization layer.
struct ThingStructDocumentStore {
    let fileURL: URL

    func load() throws -> ThingStructDocument? {
        // Returning `nil` here means "no document has been saved yet", not "an error happened".
        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ThingStructDocument.self, from: data)
    }

    func save(_ document: ThingStructDocument) throws {
        // iOS apps commonly store app-private files under Application Support.
        // We create the directory lazily so first launch works with no manual setup.
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try JSONEncoder.pretty.encode(document)
        // `.atomic` writes via a temporary file and then swaps it into place.
        // This reduces the chance of leaving a half-written document if the app is interrupted.
        try data.write(to: fileURL, options: .atomic)
    }

    nonisolated static var live: ThingStructDocumentStore {
        // `Application Support` is the standard sandbox location for structured app data.
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return ThingStructDocumentStore(
            fileURL: baseURL.appending(path: "ThingStruct/document.json")
        )
    }
}
