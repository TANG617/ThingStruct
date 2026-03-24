import Foundation

struct ThingStructSharedDocumentClient {
    struct MutationOutcome<Value> {
        let value: Value
        let changed: Bool
        let document: ThingStructDocument
    }

    enum ClientError: LocalizedError {
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

    let appGroupID: String
    let legacyMigrationSourceURL: URL?
    let fallbackStorageRootURL: URL?
    let fileManager: FileManager

    init(
        appGroupID: String = ThingStructSharedConfig.appGroupID,
        legacyMigrationSourceURL: URL? = nil,
        fallbackStorageRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.appGroupID = appGroupID
        self.legacyMigrationSourceURL = legacyMigrationSourceURL
        self.fallbackStorageRootURL = fallbackStorageRootURL
        self.fileManager = fileManager
    }

    static var appLive: ThingStructSharedDocumentClient {
        let legacyRoot = legacyStorageRootURL()
        return ThingStructSharedDocumentClient(
            legacyMigrationSourceURL: legacyRoot.appending(path: ThingStructSharedConfig.documentFileName),
            fallbackStorageRootURL: legacyRoot
        )
    }

    static var widgetLive: ThingStructSharedDocumentClient {
        ThingStructSharedDocumentClient()
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

    func nowScreenModel(at date: Date) throws -> NowScreenModel {
        let localDay = LocalDay(date: date)
        let document = try documentPreparedForNow(at: date)
        return try ThingStructPresentation.nowScreenModel(
            document: document,
            date: localDay,
            minuteOfDay: date.minuteOfDay
        )
    }

    func widgetSnapshot(
        at date: Date,
        maxTaskCount: Int
    ) throws -> ThingStructWidgetSnapshot {
        let now = try nowScreenModel(at: date)
        return ThingStructWidgetSnapshotBuilder.makeSnapshot(
            from: now,
            maxTaskCount: maxTaskCount
        )
    }

    @discardableResult
    func toggleTask(
        on date: LocalDay,
        blockID: UUID,
        taskID: UUID,
        completedAt: Date = .now
    ) throws -> Bool {
        guard try load() != nil else {
            return false
        }

        let outcome = try mutate { document in
            let prepared = try ensureMaterializedDocument(
                from: document,
                for: date,
                generatedAt: completedAt
            )
            document = prepared.document

            guard let planIndex = document.dayPlans.firstIndex(where: { $0.date == date }) else {
                return false
            }
            guard let blockIndex = document.dayPlans[planIndex].blocks.firstIndex(where: { $0.id == blockID }) else {
                return false
            }
            guard let taskIndex = document.dayPlans[planIndex].blocks[blockIndex].tasks.firstIndex(where: { $0.id == taskID }) else {
                return false
            }

            document.dayPlans[planIndex].blocks[blockIndex].tasks[taskIndex].isCompleted.toggle()
            document.dayPlans[planIndex].blocks[blockIndex].tasks[taskIndex].completedAt =
                document.dayPlans[planIndex].blocks[blockIndex].tasks[taskIndex].isCompleted ? completedAt : nil
            document.dayPlans[planIndex].hasUserEdits = true
            return true
        }

        return outcome.value
    }

    @discardableResult
    func completeTask(
        on date: LocalDay,
        blockID: UUID,
        taskID: UUID,
        completedAt: Date = .now
    ) throws -> Bool {
        guard try load() != nil else {
            return false
        }

        let outcome = try mutate { document in
            try completeTask(
                on: date,
                blockID: blockID,
                taskID: taskID,
                completedAt: completedAt,
                in: &document
            )
        }

        return outcome.value
    }

    @discardableResult
    func completeTask(
        on date: LocalDay,
        blockID: UUID,
        taskID: UUID,
        completedAt: Date = .now,
        in document: inout ThingStructDocument
    ) throws -> Bool {
        let prepared = try ensureMaterializedDocument(
            from: document,
            for: date,
            generatedAt: completedAt
        )
        document = prepared.document

        guard let planIndex = document.dayPlans.firstIndex(where: { $0.date == date }) else {
            return false
        }
        guard let blockIndex = document.dayPlans[planIndex].blocks.firstIndex(where: { $0.id == blockID }) else {
            return false
        }
        guard let taskIndex = document.dayPlans[planIndex].blocks[blockIndex].tasks.firstIndex(where: { $0.id == taskID }) else {
            return false
        }

        guard !document.dayPlans[planIndex].blocks[blockIndex].tasks[taskIndex].isCompleted else {
            return false
        }

        document.dayPlans[planIndex].blocks[blockIndex].tasks[taskIndex].isCompleted = true
        document.dayPlans[planIndex].blocks[blockIndex].tasks[taskIndex].completedAt = completedAt
        document.dayPlans[planIndex].hasUserEdits = true
        return true
    }

    func documentPreparedForNow(at date: Date) throws -> ThingStructDocument {
        let localDay = LocalDay(date: date)

        guard try load() != nil else {
            return try ensureMaterializedDocument(
                from: ThingStructDocument(),
                for: localDay,
                generatedAt: date
            ).document
        }

        let outcome = try mutate { document in
            let prepared = try ensureMaterializedDocument(
                from: document,
                for: localDay,
                generatedAt: date
            )
            document = prepared.document
            return prepared.didMaterialize
        }

        return outcome.document
    }

    private func ensureMaterializedDocument(
        from document: ThingStructDocument,
        for date: LocalDay,
        generatedAt: Date
    ) throws -> (document: ThingStructDocument, didMaterialize: Bool) {
        guard document.dayPlan(for: date) == nil else {
            return (document, false)
        }

        let dayPlan = try TemplateEngine.ensureMaterializedDayPlan(
            for: date,
            existingDayPlans: document.dayPlans,
            savedTemplates: document.savedTemplates,
            weekdayRules: document.weekdayRules,
            overrides: document.overrides,
            generatedAt: generatedAt
        )

        var updated = document
        if let existingIndex = updated.dayPlans.firstIndex(where: { $0.date == dayPlan.date }) {
            updated.dayPlans[existingIndex] = dayPlan
        } else {
            updated.dayPlans.append(dayPlan)
            updated.dayPlans.sort { $0.date < $1.date }
        }

        return (updated, true)
    }

    private func documentURL() throws -> URL {
        let rootURL: URL
        if let sharedContainerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            rootURL = sharedContainerURL.appending(path: ThingStructSharedConfig.sharedDirectoryName)
        } else if let fallbackStorageRootURL {
            rootURL = fallbackStorageRootURL
        } else {
            throw ClientError.missingSharedContainer(appGroupID)
        }

        return rootURL.appending(path: ThingStructSharedConfig.documentFileName)
    }

    private func migrateLegacyDocumentIfNeeded(to destinationURL: URL) throws {
        guard
            let legacyMigrationSourceURL,
            legacyMigrationSourceURL.standardizedFileURL != destinationURL.standardizedFileURL,
            fileManager.fileExists(atPath: legacyMigrationSourceURL.path()),
            !fileManager.fileExists(atPath: destinationURL.path())
        else {
            return
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: legacyMigrationSourceURL, to: destinationURL)
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
        throw ClientError.coordinationFailed(operation: "read")
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
        throw ClientError.coordinationFailed(operation: "write")
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
