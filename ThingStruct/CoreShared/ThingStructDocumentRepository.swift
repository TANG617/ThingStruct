import Foundation

// The repository is the single concrete storage entry point for the shared app
// document. It knows how to locate the JSON file and coordinate atomic reads and
// writes, but it does not build screen models or widget snapshots.
struct ThingStructDocumentRepository {
    struct MutationOutcome<Value> {
        let value: Value
        let changed: Bool
        let document: ThingStructDocument
    }

    enum RepositoryError: LocalizedError {
        case missingSharedContainer(String)
        case coordinationFailed(operation: String)

        var errorDescription: String? {
            switch self {
            case let .missingSharedContainer(identifier):
                return "Unable to access the shared container for \(identifier)."
            case let .coordinationFailed(operation):
                return "Unable to coordinate a shared document \(operation)."
            }
        }
    }

    private let documentURLOverride: URL?
    private let appGroupID: String
    private let legacyDocumentURL: URL?
    private let fallbackStorageRootURL: URL?
    private let fileManager: FileManager

    init(
        fileURL: URL,
        fileManager: FileManager = .default
    ) {
        documentURLOverride = fileURL
        appGroupID = ThingStructSharedConfig.appGroupID
        legacyDocumentURL = nil
        fallbackStorageRootURL = nil
        self.fileManager = fileManager
    }

    init(
        appGroupID: String = ThingStructSharedConfig.appGroupID,
        legacyDocumentURL: URL? = nil,
        fallbackStorageRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        documentURLOverride = nil
        self.appGroupID = appGroupID
        self.legacyDocumentURL = legacyDocumentURL
        self.fallbackStorageRootURL = fallbackStorageRootURL
        self.fileManager = fileManager
    }

    static var appLive: ThingStructDocumentRepository {
        let legacyRoot = legacyStorageRootURL()
        return ThingStructDocumentRepository(
            legacyDocumentURL: legacyRoot.appending(path: ThingStructSharedConfig.documentFileName),
            fallbackStorageRootURL: legacyRoot
        )
    }

    static var widgetLive: ThingStructDocumentRepository {
        ThingStructDocumentRepository()
    }

    func load() throws -> ThingStructDocument? {
        let url = try documentURL()
        try migrateLegacyDocumentIfNeeded(to: url)

        guard fileManager.fileExists(atPath: url.path()) else {
            return nil
        }

        return try coordinateReading(url) { coordinatedURL in
            try readDocument(from: coordinatedURL)
        }
    }

    func save(_ document: ThingStructDocument) throws {
        let url = try documentURL()
        try migrateLegacyDocumentIfNeeded(to: url)
        try coordinateWriting(url) { coordinatedURL in
            try writeDocument(document, to: coordinatedURL)
        }
    }

    func mutate<Value>(
        _ body: (inout ThingStructDocument) throws -> Value
    ) throws -> MutationOutcome<Value> {
        let url = try documentURL()
        try migrateLegacyDocumentIfNeeded(to: url)

        return try coordinateWriting(url) { coordinatedURL in
            let current = try readDocumentIfPresent(from: coordinatedURL) ?? ThingStructDocument()
            var updated = current
            let value = try body(&updated)

            if updated != current {
                try writeDocument(updated, to: coordinatedURL)
            }

            return MutationOutcome(
                value: value,
                changed: updated != current,
                document: updated
            )
        }
    }

    private func documentURL() throws -> URL {
        if let documentURLOverride {
            return documentURLOverride
        }

        let rootURL: URL
        if let sharedContainerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            rootURL = sharedContainerURL.appending(path: ThingStructSharedConfig.sharedDirectoryName)
        } else if let fallbackStorageRootURL {
            rootURL = fallbackStorageRootURL
        } else {
            throw RepositoryError.missingSharedContainer(appGroupID)
        }

        return rootURL.appending(path: ThingStructSharedConfig.documentFileName)
    }

    private func migrateLegacyDocumentIfNeeded(to destinationURL: URL) throws {
        guard
            let legacyDocumentURL,
            legacyDocumentURL.standardizedFileURL != destinationURL.standardizedFileURL,
            fileManager.fileExists(atPath: legacyDocumentURL.path()),
            !fileManager.fileExists(atPath: destinationURL.path())
        else {
            return
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: legacyDocumentURL, to: destinationURL)
    }

    private func coordinateReading<T>(
        _ url: URL,
        body: (URL) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?

        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            result = Result {
                try body(coordinatedURL)
            }
        }

        if let result {
            return try result.get()
        }
        if let coordinationError {
            throw coordinationError
        }
        throw RepositoryError.coordinationFailed(operation: "read")
    }

    private func coordinateWriting<T>(
        _ url: URL,
        body: (URL) throws -> T
    ) throws -> T {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var coordinationError: NSError?
        var result: Result<T, Error>?

        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result {
                try body(coordinatedURL)
            }
        }

        if let result {
            return try result.get()
        }
        if let coordinationError {
            throw coordinationError
        }
        throw RepositoryError.coordinationFailed(operation: "write")
    }

    private func readDocumentIfPresent(from url: URL) throws -> ThingStructDocument? {
        guard fileManager.fileExists(atPath: url.path()) else {
            return nil
        }

        return try readDocument(from: url)
    }

    private func readDocument(from url: URL) throws -> ThingStructDocument {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ThingStructDocument.self, from: data)
    }

    private func writeDocument(
        _ document: ThingStructDocument,
        to url: URL
    ) throws {
        let data = try prettyEncoder().encode(document)
        try data.write(to: url, options: .atomic)
    }

    private func prettyEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func legacyStorageRootURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL.appending(path: ThingStructSharedConfig.sharedDirectoryName)
    }
}
