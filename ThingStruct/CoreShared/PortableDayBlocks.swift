import Foundation

enum PortableDayBlocksError: Error, Equatable, Sendable {
    case yamlParse(line: Int, message: String)
    case invalidDocument(String)
}

extension PortableDayBlocksError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .yamlParse(line, message):
            return "YAML line \(line): \(message)"
        case let .invalidDocument(message):
            return message
        }
    }
}

struct PortableDayBlocksSummary: Equatable, Sendable {
    let sourceDate: LocalDay
    let baseBlockCount: Int
    let totalBlockCount: Int
    let taskCount: Int
}

enum ThingStructPortableDayBlocks {
    static let supportedVersion = 1
    static let supportedKind = "day_blocks"

    static func exportYAML(from dayPlan: DayPlan) throws -> String {
        let document = try portableDocument(from: dayPlan)
        return PortableYAMLRenderer.render(document)
    }

    static func summary(fromYAML yaml: String) throws -> PortableDayBlocksSummary {
        summary(from: try document(fromYAML: yaml))
    }

    static func importedBlocks(fromYAML yaml: String, dayPlanID: UUID? = nil) throws -> [TimeBlock] {
        try blocks(from: document(fromYAML: yaml), dayPlanID: dayPlanID)
    }

    static func dayPlanForImport(
        fromYAML yaml: String,
        on date: LocalDay,
        dayPlanID: UUID = UUID(),
        lastGeneratedAt: Date? = nil
    ) throws -> DayPlan {
        var plan = DayPlan(
            id: dayPlanID,
            date: date,
            sourceSavedTemplateID: nil,
            lastGeneratedAt: lastGeneratedAt,
            hasUserEdits: true,
            blocks: try importedBlocks(fromYAML: yaml, dayPlanID: dayPlanID)
        )
        plan = try DayPlanEngine.resolved(plan)
        plan.sourceSavedTemplateID = nil
        plan.hasUserEdits = true
        return plan
    }

    private static func portableDocument(from dayPlan: DayPlan) throws -> PortableDayBlocksDocument {
        let resolvedPlan = try DayPlanEngine.resolved(dayPlan)
        let exportableBlocks = resolvedPlan.blocks
            .filter { !$0.isCancelled && !$0.isBlankBaseBlock && $0.kind == .userDefined }
        let blocksByID = Dictionary(uniqueKeysWithValues: exportableBlocks.map { ($0.id, $0) })
        let childrenByParent = Dictionary(grouping: exportableBlocks, by: \.parentBlockID)

        return PortableDayBlocksDocument(
            version: supportedVersion,
            kind: supportedKind,
            sourceDate: resolvedPlan.date,
            blocks: childrenByParent[nil, default: []]
                .sorted(by: exportSort)
                .map { block in
                    portableBlock(
                        from: block,
                        blocksByID: blocksByID,
                        childrenByParent: childrenByParent
                    )
                }
        )
    }

    private static func portableBlock(
        from block: TimeBlock,
        blocksByID: [UUID: TimeBlock],
        childrenByParent: [UUID?: [TimeBlock]]
    ) -> PortableDayBlock {
        PortableDayBlock(
            title: block.title,
            note: block.note?.nilIfBlank,
            timing: portableTiming(from: block.timing),
            reminders: block.reminders.map(portableReminder(from:)),
            tasks: block.tasks
                .sorted(by: exportTaskSort)
                .map { PortableDayTask(title: $0.title, completed: $0.isCompleted) },
            children: childrenByParent[block.id, default: []]
                .filter { blocksByID[$0.id] != nil }
                .sorted(by: exportSort)
                .map {
                    portableBlock(
                        from: $0,
                        blocksByID: blocksByID,
                        childrenByParent: childrenByParent
                    )
                }
        )
    }

    private static func summary(from document: PortableDayBlocksDocument) -> PortableDayBlocksSummary {
        PortableDayBlocksSummary(
            sourceDate: document.sourceDate,
            baseBlockCount: document.blocks.count,
            totalBlockCount: document.blocks.reduce(0) { $0 + $1.totalBlockCount },
            taskCount: document.blocks.reduce(0) { $0 + $1.totalTaskCount }
        )
    }

    private static func blocks(
        from document: PortableDayBlocksDocument,
        dayPlanID: UUID?
    ) throws -> [TimeBlock] {
        var flattened: [TimeBlock] = []
        try appendBlocks(
            from: document.blocks,
            dayPlanID: dayPlanID,
            parentBlockID: nil,
            layerIndex: 0,
            into: &flattened
        )
        return flattened
    }

    private static func appendBlocks(
        from portableBlocks: [PortableDayBlock],
        dayPlanID: UUID?,
        parentBlockID: UUID?,
        layerIndex: Int,
        into blocks: inout [TimeBlock]
    ) throws {
        for portableBlock in portableBlocks {
            let blockID = UUID()
            let timing = blockTiming(from: portableBlock.timing)
            let tasks = portableBlock.tasks.enumerated().map { index, task in
                TaskItem(
                    title: task.title,
                    order: index,
                    isCompleted: task.completed,
                    completedAt: nil
                )
            }

            blocks.append(
                TimeBlock(
                    id: blockID,
                    dayPlanID: dayPlanID,
                    parentBlockID: parentBlockID,
                    layerIndex: layerIndex,
                    kind: .userDefined,
                    title: portableBlock.title,
                    note: portableBlock.note?.nilIfBlank,
                    reminders: portableBlock.reminders.map(reminderRule(from:)),
                    tasks: tasks,
                    timing: timing
                )
            )

            try appendBlocks(
                from: portableBlock.children,
                dayPlanID: dayPlanID,
                parentBlockID: blockID,
                layerIndex: layerIndex + 1,
                into: &blocks
            )
        }
    }

    private static func document(fromYAML yaml: String) throws -> PortableDayBlocksDocument {
        let rootNode = try PortableYAMLParser.parse(yaml)
        let root = try mapping(rootNode, path: "root")
        let version = try intValue(for: "version", in: root, path: "version")
        let kind = try stringValue(for: "kind", in: root, path: "kind")
        let sourceDateString = try stringValue(for: "source_date", in: root, path: "source_date")
        guard let sourceDate = LocalDay(isoDateString: sourceDateString) else {
            throw PortableDayBlocksError.invalidDocument(
                "Invalid `source_date` value `\(sourceDateString)`. Expected YYYY-MM-DD."
            )
        }
        guard version == supportedVersion else {
            throw PortableDayBlocksError.invalidDocument(
                "Unsupported portable day-blocks version \(version)."
            )
        }
        guard kind == supportedKind else {
            throw PortableDayBlocksError.invalidDocument(
                "Unsupported `kind` value `\(kind)`. Expected `\(supportedKind)`."
            )
        }

        let blocksNode = try requiredNode(for: "blocks", in: root, path: "blocks")
        let blocks = try sequence(blocksNode, path: "blocks").enumerated().map { index, node in
            try decodeBlock(node, path: "blocks[\(index)]")
        }

        return PortableDayBlocksDocument(
            version: version,
            kind: kind,
            sourceDate: sourceDate,
            blocks: blocks
        )
    }

    private static func decodeBlock(_ node: PortableYAMLNode, path: String) throws -> PortableDayBlock {
        let mapping = try mapping(node, path: path)
        let title = try stringValue(for: "title", in: mapping, path: "\(path).title").trimmed()
        guard !title.isEmpty else {
            throw PortableDayBlocksError.invalidDocument("`\(path).title` cannot be empty.")
        }

        let note = try optionalStringValue(for: "note", in: mapping, path: "\(path).note")?.nilIfBlank
        let timingNode = try requiredNode(for: "timing", in: mapping, path: "\(path).timing")
        let timing = try decodeTiming(timingNode, path: "\(path).timing")
        let reminders = try optionalSequence(for: "reminders", in: mapping, path: "\(path).reminders")?
            .enumerated()
            .map { index, node in
                try decodeReminder(node, path: "\(path).reminders[\(index)]")
            } ?? []
        let tasks = try optionalSequence(for: "tasks", in: mapping, path: "\(path).tasks")?
            .enumerated()
            .map { index, node in
                try decodeTask(node, path: "\(path).tasks[\(index)]")
            } ?? []
        let children = try optionalSequence(for: "children", in: mapping, path: "\(path).children")?
            .enumerated()
            .map { index, node in
                try decodeBlock(node, path: "\(path).children[\(index)]")
            } ?? []

        return PortableDayBlock(
            title: title,
            note: note,
            timing: timing,
            reminders: reminders,
            tasks: tasks,
            children: children
        )
    }

    private static func decodeTask(_ node: PortableYAMLNode, path: String) throws -> PortableDayTask {
        let mapping = try mapping(node, path: path)
        let title = try stringValue(for: "title", in: mapping, path: "\(path).title").trimmed()
        guard !title.isEmpty else {
            throw PortableDayBlocksError.invalidDocument("`\(path).title` cannot be empty.")
        }

        return PortableDayTask(
            title: title,
            completed: try optionalBoolValue(for: "completed", in: mapping, path: "\(path).completed") ?? false
        )
    }

    private static func decodeTiming(_ node: PortableYAMLNode, path: String) throws -> PortableBlockTiming {
        let mapping = try mapping(node, path: path)
        let type = try stringValue(for: "type", in: mapping, path: "\(path).type")

        switch type {
        case "absolute":
            let startText = try stringValue(for: "start", in: mapping, path: "\(path).start")
            let endText = try optionalStringValue(for: "end", in: mapping, path: "\(path).end")
            return .absolute(
                startMinuteOfDay: try parseTime(startText, allow24Hour: false, path: "\(path).start"),
                endMinuteOfDay: try endText.map {
                    try parseTime($0, allow24Hour: true, path: "\(path).end")
                }
            )

        case "relative":
            let offsetText = try stringValue(for: "offset", in: mapping, path: "\(path).offset")
            let durationText = try optionalStringValue(for: "duration", in: mapping, path: "\(path).duration")
            return .relative(
                offsetMinutes: try parseMinutes(offsetText, path: "\(path).offset"),
                durationMinutes: try durationText.map {
                    try parseMinutes($0, path: "\(path).duration")
                }
            )

        default:
            throw PortableDayBlocksError.invalidDocument(
                "Invalid `\(path).type` value `\(type)`. Expected `absolute` or `relative`."
            )
        }
    }

    private static func decodeReminder(_ node: PortableYAMLNode, path: String) throws -> PortableReminder {
        let text = try scalar(node, path: path)
        if text == "at_start" {
            return .atStart
        }

        guard
            text.hasSuffix("m_before"),
            let minutes = Int(text.dropLast("m_before".count))
        else {
            throw PortableDayBlocksError.invalidDocument(
                "Invalid reminder `\(text)` at `\(path)`. Use `at_start` or `<minutes>m_before`."
            )
        }

        return .beforeStart(minutes: minutes)
    }

    private static func portableTiming(from timing: TimeBlockTiming) -> PortableBlockTiming {
        switch timing {
        case let .absolute(startMinuteOfDay, requestedEndMinuteOfDay):
            return .absolute(
                startMinuteOfDay: startMinuteOfDay,
                endMinuteOfDay: requestedEndMinuteOfDay
            )

        case let .relative(startOffsetMinutes, requestedDurationMinutes):
            return .relative(
                offsetMinutes: startOffsetMinutes,
                durationMinutes: requestedDurationMinutes
            )
        }
    }

    private static func blockTiming(from timing: PortableBlockTiming) -> TimeBlockTiming {
        switch timing {
        case let .absolute(startMinuteOfDay, endMinuteOfDay):
            return .absolute(
                startMinuteOfDay: startMinuteOfDay,
                requestedEndMinuteOfDay: endMinuteOfDay
            )

        case let .relative(offsetMinutes, durationMinutes):
            return .relative(
                startOffsetMinutes: offsetMinutes,
                requestedDurationMinutes: durationMinutes
            )
        }
    }

    private static func portableReminder(from reminder: ReminderRule) -> PortableReminder {
        switch reminder.triggerMode {
        case .atStart:
            return .atStart

        case .beforeStart:
            return .beforeStart(minutes: reminder.offsetMinutes)
        }
    }

    private static func reminderRule(from reminder: PortableReminder) -> ReminderRule {
        switch reminder {
        case .atStart:
            return ReminderRule(triggerMode: .atStart, offsetMinutes: 0)

        case let .beforeStart(minutes):
            return ReminderRule(triggerMode: .beforeStart, offsetMinutes: minutes)
        }
    }

    private static func exportSort(_ lhs: TimeBlock, _ rhs: TimeBlock) -> Bool {
        let lhsStart = lhs.resolvedStartMinuteOfDay ?? Int.max
        let rhsStart = rhs.resolvedStartMinuteOfDay ?? Int.max
        if lhsStart != rhsStart {
            return lhsStart < rhsStart
        }

        let lhsEnd = lhs.resolvedEndMinuteOfDay ?? Int.max
        let rhsEnd = rhs.resolvedEndMinuteOfDay ?? Int.max
        if lhsEnd != rhsEnd {
            return lhsEnd < rhsEnd
        }

        if lhs.layerIndex != rhs.layerIndex {
            return lhs.layerIndex < rhs.layerIndex
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func exportTaskSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func requiredNode(
        for key: String,
        in mapping: [String: PortableYAMLNode],
        path: String
    ) throws -> PortableYAMLNode {
        guard let node = mapping[key] else {
            throw PortableDayBlocksError.invalidDocument("Missing required field `\(path)`.")
        }
        return node
    }

    private static func stringValue(
        for key: String,
        in mapping: [String: PortableYAMLNode],
        path: String
    ) throws -> String {
        try scalar(requiredNode(for: key, in: mapping, path: path), path: path)
    }

    private static func optionalStringValue(
        for key: String,
        in mapping: [String: PortableYAMLNode],
        path: String
    ) throws -> String? {
        guard let node = mapping[key] else { return nil }
        if case .null = node {
            return nil
        }
        return try scalar(node, path: path)
    }

    private static func intValue(
        for key: String,
        in mapping: [String: PortableYAMLNode],
        path: String
    ) throws -> Int {
        let text = try stringValue(for: key, in: mapping, path: path)
        guard let value = Int(text) else {
            throw PortableDayBlocksError.invalidDocument("`\(path)` must be an integer.")
        }
        return value
    }

    private static func optionalBoolValue(
        for key: String,
        in mapping: [String: PortableYAMLNode],
        path: String
    ) throws -> Bool? {
        guard let node = mapping[key] else { return nil }
        if case .null = node {
            return nil
        }

        let text = try scalar(node, path: path).lowercased()
        switch text {
        case "true":
            return true
        case "false":
            return false
        default:
            throw PortableDayBlocksError.invalidDocument("`\(path)` must be `true` or `false`.")
        }
    }

    private static func optionalSequence(
        for key: String,
        in mapping: [String: PortableYAMLNode],
        path: String
    ) throws -> [PortableYAMLNode]? {
        guard let node = mapping[key] else { return nil }
        if case .null = node {
            return nil
        }
        return try sequence(node, path: path)
    }

    private static func mapping(
        _ node: PortableYAMLNode,
        path: String
    ) throws -> [String: PortableYAMLNode] {
        guard case let .mapping(mapping) = node else {
            throw PortableDayBlocksError.invalidDocument("`\(path)` must be a mapping.")
        }
        return mapping
    }

    private static func sequence(
        _ node: PortableYAMLNode,
        path: String
    ) throws -> [PortableYAMLNode] {
        guard case let .sequence(sequence) = node else {
            throw PortableDayBlocksError.invalidDocument("`\(path)` must be a list.")
        }
        return sequence
    }

    private static func scalar(_ node: PortableYAMLNode, path: String) throws -> String {
        guard case let .scalar(value) = node else {
            throw PortableDayBlocksError.invalidDocument("`\(path)` must be a scalar value.")
        }
        return value
    }

    private static func parseTime(
        _ text: String,
        allow24Hour: Bool,
        path: String
    ) throws -> Int {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard
            parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1]),
            (0 ... 59).contains(minute)
        else {
            throw PortableDayBlocksError.invalidDocument(
                "Invalid time `\(text)` at `\(path)`. Expected HH:mm."
            )
        }

        if hour == 24 && minute == 0 && allow24Hour {
            return 24 * 60
        }

        guard (0 ... 23).contains(hour) else {
            throw PortableDayBlocksError.invalidDocument(
                "Invalid time `\(text)` at `\(path)`. Expected HH:mm."
            )
        }

        return hour * 60 + minute
    }

    private static func parseMinutes(_ text: String, path: String) throws -> Int {
        guard text.hasSuffix("m"), let minutes = Int(text.dropLast()) else {
            throw PortableDayBlocksError.invalidDocument(
                "Invalid duration `\(text)` at `\(path)`. Expected `<minutes>m`."
            )
        }
        return minutes
    }
}

private struct PortableDayBlocksDocument: Equatable {
    var version: Int
    var kind: String
    var sourceDate: LocalDay
    var blocks: [PortableDayBlock]
}

private struct PortableDayBlock: Equatable {
    var title: String
    var note: String?
    var timing: PortableBlockTiming
    var reminders: [PortableReminder]
    var tasks: [PortableDayTask]
    var children: [PortableDayBlock]

    var totalBlockCount: Int {
        1 + children.reduce(0) { $0 + $1.totalBlockCount }
    }

    var totalTaskCount: Int {
        tasks.count + children.reduce(0) { $0 + $1.totalTaskCount }
    }
}

private struct PortableDayTask: Equatable {
    var title: String
    var completed: Bool
}

private enum PortableBlockTiming: Equatable {
    case absolute(startMinuteOfDay: Int, endMinuteOfDay: Int?)
    case relative(offsetMinutes: Int, durationMinutes: Int?)
}

private enum PortableReminder: Equatable {
    case atStart
    case beforeStart(minutes: Int)

    var yamlScalar: String {
        switch self {
        case .atStart:
            return "at_start"
        case let .beforeStart(minutes):
            return "\(minutes)m_before"
        }
    }
}

private enum PortableYAMLNode: Equatable {
    case scalar(String)
    case mapping([String: PortableYAMLNode])
    case sequence([PortableYAMLNode])
    case null
}

private enum PortableYAMLRenderer {
    static func render(_ document: PortableDayBlocksDocument) -> String {
        var lines: [String] = [
            "version: \(document.version)",
            "kind: \(document.kind)",
            "source_date: \(document.sourceDate.description)"
        ]

        if document.blocks.isEmpty {
            lines.append("blocks: []")
        } else {
            lines.append("blocks:")
            for block in document.blocks {
                append(block, indent: 2, to: &lines)
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func append(_ block: PortableDayBlock, indent: Int, to lines: inout [String]) {
        let prefix = String(repeating: " ", count: indent)
        lines.append("\(prefix)- title: \(quoted(block.title))")

        if let note = block.note?.nilIfBlank {
            lines.append("\(prefix)  note: \(quoted(note))")
        }

        lines.append("\(prefix)  timing:")
        switch block.timing {
        case let .absolute(startMinuteOfDay, endMinuteOfDay):
            lines.append("\(prefix)    type: absolute")
            lines.append("\(prefix)    start: \(quoted(timeText(for: startMinuteOfDay)))")
            if let endMinuteOfDay {
                lines.append("\(prefix)    end: \(quoted(timeText(for: endMinuteOfDay)))")
            }

        case let .relative(offsetMinutes, durationMinutes):
            lines.append("\(prefix)    type: relative")
            lines.append("\(prefix)    offset: \(quoted("\(offsetMinutes)m"))")
            if let durationMinutes {
                lines.append("\(prefix)    duration: \(quoted("\(durationMinutes)m"))")
            }
        }

        if !block.reminders.isEmpty {
            lines.append("\(prefix)  reminders:")
            for reminder in block.reminders {
                lines.append("\(prefix)    - \(reminder.yamlScalar)")
            }
        }

        if !block.tasks.isEmpty {
            lines.append("\(prefix)  tasks:")
            for task in block.tasks {
                lines.append("\(prefix)    - title: \(quoted(task.title))")
                lines.append("\(prefix)      completed: \(task.completed ? "true" : "false")")
            }
        }

        if !block.children.isEmpty {
            lines.append("\(prefix)  children:")
            for child in block.children {
                append(child, indent: indent + 4, to: &lines)
            }
        }
    }

    private static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private static func timeText(for minuteOfDay: Int) -> String {
        if minuteOfDay == 24 * 60 {
            return "24:00"
        }

        let hour = minuteOfDay / 60
        let minute = minuteOfDay % 60
        return String(format: "%02d:%02d", hour, minute)
    }
}

private enum PortableYAMLParser {
    static func parse(_ yaml: String) throws -> PortableYAMLNode {
        let lines = try parseLines(from: yaml)
        guard !lines.isEmpty else {
            throw PortableDayBlocksError.invalidDocument("The YAML file is empty.")
        }

        var parser = Parser(lines: lines)
        let root = try parser.parseNode(expectedIndent: lines[0].indent)
        guard parser.isAtEnd else {
            throw PortableDayBlocksError.yamlParse(
                line: parser.currentLineNumber,
                message: "Unexpected trailing content."
            )
        }
        return root
    }

    private static func parseLines(from yaml: String) throws -> [ParsedLine] {
        try yaml
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .enumerated()
            .compactMap { offset, rawLine in
                let leadingWhitespace = rawLine.prefix { $0 == " " || $0 == "\t" }
                if leadingWhitespace.contains("\t") {
                    throw PortableDayBlocksError.yamlParse(
                        line: offset + 1,
                        message: "Tabs are not supported for indentation."
                    )
                }

                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed == "---" || trimmed == "..." {
                    return nil
                }

                let indent = rawLine.prefix { $0 == " " }.count
                if indent % 2 != 0 {
                    throw PortableDayBlocksError.yamlParse(
                        line: offset + 1,
                        message: "Indentation must use multiples of 2 spaces."
                    )
                }

                return ParsedLine(
                    number: offset + 1,
                    indent: indent,
                    content: String(rawLine.dropFirst(indent))
                )
            }
    }

    private struct ParsedLine {
        let number: Int
        let indent: Int
        let content: String
    }

    private struct Parser {
        let lines: [ParsedLine]
        var index = 0

        var isAtEnd: Bool {
            index >= lines.count
        }

        var currentLineNumber: Int {
            guard index < lines.count else {
                return lines.last?.number ?? 1
            }
            return lines[index].number
        }

        mutating func parseNode(expectedIndent: Int) throws -> PortableYAMLNode {
            guard index < lines.count else {
                throw PortableDayBlocksError.invalidDocument("Unexpected end of YAML.")
            }

            let line = lines[index]
            guard line.indent == expectedIndent else {
                throw PortableDayBlocksError.yamlParse(
                    line: line.number,
                    message: "Unexpected indentation."
                )
            }

            if line.content.hasPrefix("- ") {
                return try parseSequence(expectedIndent: expectedIndent)
            }

            return try parseMapping(expectedIndent: expectedIndent)
        }

        mutating func parseMapping(
            expectedIndent: Int,
            firstEntryContent: String? = nil,
            firstEntryLineNumber: Int? = nil
        ) throws -> PortableYAMLNode {
            var mapping: [String: PortableYAMLNode] = [:]

            if let firstEntryContent {
                try parseMappingEntry(
                    content: firstEntryContent,
                    lineNumber: firstEntryLineNumber ?? currentLineNumber,
                    expectedIndent: expectedIndent,
                    into: &mapping
                )
            }

            while index < lines.count {
                let line = lines[index]
                if line.indent < expectedIndent {
                    break
                }

                if line.indent > expectedIndent {
                    throw PortableDayBlocksError.yamlParse(
                        line: line.number,
                        message: "Unexpected indentation inside mapping."
                    )
                }

                if line.content.hasPrefix("- ") {
                    break
                }

                index += 1
                try parseMappingEntry(
                    content: line.content,
                    lineNumber: line.number,
                    expectedIndent: expectedIndent,
                    into: &mapping
                )
            }

            return .mapping(mapping)
        }

        mutating func parseSequence(expectedIndent: Int) throws -> PortableYAMLNode {
            var sequence: [PortableYAMLNode] = []

            while index < lines.count {
                let line = lines[index]
                if line.indent < expectedIndent {
                    break
                }

                if line.indent > expectedIndent {
                    throw PortableDayBlocksError.yamlParse(
                        line: line.number,
                        message: "Unexpected indentation inside list."
                    )
                }

                guard line.content.hasPrefix("- ") else {
                    break
                }

                index += 1
                let remainder = String(line.content.dropFirst(2)).trimmed()

                if remainder.isEmpty {
                    guard index < lines.count else {
                        throw PortableDayBlocksError.yamlParse(
                            line: line.number,
                            message: "List item is missing a value."
                        )
                    }
                    let childLine = lines[index]
                    guard childLine.indent > expectedIndent else {
                        throw PortableDayBlocksError.yamlParse(
                            line: line.number,
                            message: "List item is missing an indented value."
                        )
                    }
                    sequence.append(try parseNode(expectedIndent: childLine.indent))
                    continue
                }

                if looksLikeMappingEntry(remainder) {
                    sequence.append(
                        try parseMapping(
                            expectedIndent: expectedIndent + 2,
                            firstEntryContent: remainder,
                            firstEntryLineNumber: line.number
                        )
                    )
                } else {
                    sequence.append(try parseInlineValue(remainder, lineNumber: line.number))
                }
            }

            return .sequence(sequence)
        }

        mutating func parseMappingEntry(
            content: String,
            lineNumber: Int,
            expectedIndent: Int,
            into mapping: inout [String: PortableYAMLNode]
        ) throws {
            guard let separatorIndex = content.firstIndex(of: ":") else {
                throw PortableDayBlocksError.yamlParse(
                    line: lineNumber,
                    message: "Expected a `key: value` entry."
                )
            }

            let key = String(content[..<separatorIndex]).trimmed()
            guard !key.isEmpty else {
                throw PortableDayBlocksError.yamlParse(
                    line: lineNumber,
                    message: "Mapping key cannot be empty."
                )
            }

            let rawValue = String(content[content.index(after: separatorIndex)...]).trimmed()
            let value: PortableYAMLNode
            if rawValue.isEmpty {
                if index < lines.count, lines[index].indent > expectedIndent {
                    value = try parseNode(expectedIndent: lines[index].indent)
                } else {
                    value = .null
                }
            } else {
                value = try parseInlineValue(rawValue, lineNumber: lineNumber)
            }

            if mapping.updateValue(value, forKey: key) != nil {
                throw PortableDayBlocksError.yamlParse(
                    line: lineNumber,
                    message: "Duplicate key `\(key)`."
                )
            }
        }

        func parseInlineValue(_ rawValue: String, lineNumber: Int) throws -> PortableYAMLNode {
            switch rawValue {
            case "[]":
                return .sequence([])
            case "{}":
                return .mapping([:])
            case "null", "~":
                return .null
            default:
                return .scalar(try parseScalar(rawValue, lineNumber: lineNumber))
            }
        }

        func parseScalar(_ rawValue: String, lineNumber: Int) throws -> String {
            if rawValue.hasPrefix("\"") {
                guard rawValue.hasSuffix("\""), rawValue.count >= 2 else {
                    throw PortableDayBlocksError.yamlParse(
                        line: lineNumber,
                        message: "Unterminated double-quoted string."
                    )
                }

                let inner = rawValue.dropFirst().dropLast()
                var result = ""
                var isEscaping = false

                for character in inner {
                    if isEscaping {
                        switch character {
                        case "\\":
                            result.append("\\")
                        case "\"":
                            result.append("\"")
                        case "n":
                            result.append("\n")
                        case "r":
                            result.append("\r")
                        case "t":
                            result.append("\t")
                        default:
                            throw PortableDayBlocksError.yamlParse(
                                line: lineNumber,
                                message: "Unsupported escape sequence `\\\(character)`."
                            )
                        }
                        isEscaping = false
                    } else if character == "\\" {
                        isEscaping = true
                    } else {
                        result.append(character)
                    }
                }

                if isEscaping {
                    throw PortableDayBlocksError.yamlParse(
                        line: lineNumber,
                        message: "Unterminated escape sequence."
                    )
                }

                return result
            }

            if rawValue.hasPrefix("'") {
                guard rawValue.hasSuffix("'"), rawValue.count >= 2 else {
                    throw PortableDayBlocksError.yamlParse(
                        line: lineNumber,
                        message: "Unterminated single-quoted string."
                    )
                }

                return String(rawValue.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }

            return rawValue
        }

        func looksLikeMappingEntry(_ text: String) -> Bool {
            guard let separatorIndex = text.firstIndex(of: ":") else {
                return false
            }
            return !String(text[..<separatorIndex]).trimmed().isEmpty
        }
    }
}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        let trimmed = trimmed()
        return trimmed.isEmpty ? nil : trimmed
    }
}
