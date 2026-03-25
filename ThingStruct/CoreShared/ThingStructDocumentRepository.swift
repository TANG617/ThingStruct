import Foundation

// `ThingStructDocumentRepository` 是共享文档的唯一 concrete 存储入口。
//
// 这层只负责三件事：
// 1. 找到 document.json 在哪里
// 2. 原子地读/写这份 JSON
// 3. 在需要时做带文件协调(file coordination)的 mutate
//
// 它刻意“不知道” screen model、widget snapshot、页面状态这些上层概念。
// 这是为了避免“存储层顺便懂 UI”，导致维护时认知边界越来越糊。
struct ThingStructDocumentRepository {
    // `MutationOutcome` 是 mutate 的返回包装：
    // - `value`：调用方真正想拿到的业务结果
    // - `changed`：这次 mutate 是否真的改了 document
    // - `document`：变更后的最新 document
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
        // 这个初始化器主要给 preview / test 使用，
        // 允许直接指定一个临时 JSON 文件路径。
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
        // 这个初始化器主要给真实 app / widget 使用：
        // 默认从 app group 容器里找共享文档。
        documentURLOverride = nil
        self.appGroupID = appGroupID
        self.legacyDocumentURL = legacyDocumentURL
        self.fallbackStorageRootURL = fallbackStorageRootURL
        self.fileManager = fileManager
    }

    static var appLive: ThingStructDocumentRepository {
        // app 版本额外带 legacy 迁移信息，兼容旧存储位置。
        let legacyRoot = legacyStorageRootURL()
        return ThingStructDocumentRepository(
            legacyDocumentURL: legacyRoot.appending(path: ThingStructSharedConfig.documentFileName),
            fallbackStorageRootURL: legacyRoot
        )
    }

    static var widgetLive: ThingStructDocumentRepository {
        // widget 和主 app 共享同一份 document，只是入口不同。
        ThingStructDocumentRepository()
    }

    func load() throws -> ThingStructDocument? {
        // “文件不存在”在这里不是异常，而是“尚未初始化”的正常状态。
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
        // save 不做业务级校验，只负责写盘。
        let url = try documentURL()
        try migrateLegacyDocumentIfNeeded(to: url)
        try coordinateWriting(url) { coordinatedURL in
            try writeDocument(document, to: coordinatedURL)
        }
    }

    func mutate<Value>(
        _ body: (inout ThingStructDocument) throws -> Value
    ) throws -> MutationOutcome<Value> {
        // `mutate` 是这里最值得学习的方法：
        // 它把“读当前文档 -> 在内存里修改 -> 如果有变化则原子写回”封装成一个模板。
        // 这样调用者只需要关心“我要怎么改 document”，不用重复写存储样板代码。
        let url = try documentURL()
        try migrateLegacyDocumentIfNeeded(to: url)

        return try coordinateWriting(url) { coordinatedURL in
            let current = try readDocumentIfPresent(from: coordinatedURL) ?? ThingStructDocument()
            var updated = current
            let value = try body(&updated)

            // 只有 document 真变了才写盘，避免无意义 I/O。
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
            // app group 是 iOS 里 app 与 extension 共享文件的标准方式。
            rootURL = sharedContainerURL.appending(path: ThingStructSharedConfig.sharedDirectoryName)
        } else if let fallbackStorageRootURL {
            rootURL = fallbackStorageRootURL
        } else {
            throw RepositoryError.missingSharedContainer(appGroupID)
        }

        return rootURL.appending(path: ThingStructSharedConfig.documentFileName)
    }

    private func migrateLegacyDocumentIfNeeded(to destinationURL: URL) throws {
        // 首次访问新路径时，如果旧路径里有数据，就复制过去完成懒迁移。
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
        // `NSFileCoordinator` 用于 app / widget / extension 间共享文件访问协调。
        // 不用它也可能“看起来能跑”，但并发访问时更容易出数据竞争问题。
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
        // 写前先确保目录存在，这是文件存储层最常见的防御式步骤。
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
        // `.atomic` 会先写临时文件，再替换正式文件，能减少半写入损坏风险。
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
