import Foundation

public enum DayPlanEngine {
    public static func validate(_ plan: DayPlan) throws {
        _ = try resolved(plan)
    }

    public static func resolved(_ plan: DayPlan) throws -> DayPlan {
        let persistedPlan = strippedRuntimeBlocks(from: plan)
        let resolvedRanges = try resolveRanges(in: persistedPlan)

        var resolvedPlan = persistedPlan
        resolvedPlan.blocks = persistedPlan.blocks.map { block in
            var updatedBlock = block
            if let range = resolvedRanges[block.id] {
                updatedBlock.resolvedStartMinuteOfDay = range.start
                updatedBlock.resolvedEndMinuteOfDay = range.end
            } else {
                updatedBlock.resolvedStartMinuteOfDay = nil
                updatedBlock.resolvedEndMinuteOfDay = nil
            }
            return updatedBlock
        }

        return resolvedPlan
    }

    public static func runtimeResolved(_ plan: DayPlan) throws -> DayPlan {
        let resolvedPlan = try resolved(plan)
        var runtimePlan = resolvedPlan
        runtimePlan.blocks.append(contentsOf: makeBlankBaseBlocks(in: resolvedPlan))
        return runtimePlan
    }

    public static func cancelBlock(_ blockID: UUID, in plan: DayPlan) throws -> DayPlan {
        let resolvedPlan = try resolved(plan)
        guard let target = resolvedPlan.blocks.first(where: { $0.id == blockID }) else {
            throw ThingStructCoreError.missingBlock(blockID)
        }

        if target.isCancelled {
            return resolvedPlan
        }

        let activeBlocks = resolvedPlan.blocks.filter { !$0.isCancelled }
        let activeBlocksByID = Dictionary(uniqueKeysWithValues: activeBlocks.map { ($0.id, $0) })
        let childrenByParent = buildChildrenMap(from: activeBlocks)
        let directChildren = Set(childrenByParent[blockID] ?? [])
        let descendantIDs = collectDescendants(startingAt: blockID, childrenByParent: childrenByParent)
        let originalRanges = try resolvedRangeMap(from: activeBlocks)

        var updatedPlan = resolvedPlan

        for index in updatedPlan.blocks.indices {
            let currentID = updatedPlan.blocks[index].id

            if currentID == blockID {
                updatedPlan.blocks[index].isCancelled = true
                updatedPlan.blocks[index].resolvedStartMinuteOfDay = nil
                updatedPlan.blocks[index].resolvedEndMinuteOfDay = nil
                continue
            }

            if directChildren.contains(currentID) {
                guard let resolvedChild = activeBlocksByID[currentID] else {
                    throw ThingStructCoreError.missingBlock(currentID)
                }

                guard
                    let resolvedStart = resolvedChild.resolvedStartMinuteOfDay,
                    let resolvedEnd = resolvedChild.resolvedEndMinuteOfDay
                else {
                    throw ThingStructCoreError.invalidResolvedRange(blockID: currentID, start: -1, end: -1)
                }

                updatedPlan.blocks[index].parentBlockID = target.parentBlockID
                updatedPlan.blocks[index].layerIndex -= 1
                updatedPlan.blocks[index].timing = .absolute(
                    startMinuteOfDay: resolvedStart,
                    requestedEndMinuteOfDay: resolvedEnd
                )
                updatedPlan.blocks[index].resolvedStartMinuteOfDay = nil
                updatedPlan.blocks[index].resolvedEndMinuteOfDay = nil
                continue
            }

            if descendantIDs.contains(currentID) {
                updatedPlan.blocks[index].layerIndex -= 1
                updatedPlan.blocks[index].resolvedStartMinuteOfDay = nil
                updatedPlan.blocks[index].resolvedEndMinuteOfDay = nil
            }
        }

        try validateCancelOverlapRisk(in: updatedPlan, originalRanges: originalRanges)

        let reparsedPlan = try resolved(updatedPlan)
        try validatePreservedRanges(after: reparsedPlan, against: originalRanges, excluding: [blockID])
        return reparsedPlan
    }

    public static func resizeBounds(for blockID: UUID, in plan: DayPlan) throws -> BlockResizeBounds {
        let resolvedPlan = try resolved(plan)
        let activeBlocks = resolvedPlan.blocks.filter { !$0.isCancelled }

        guard let target = activeBlocks.first(where: { $0.id == blockID }) else {
            throw ThingStructCoreError.missingBlock(blockID)
        }

        guard
            let resolvedStart = target.resolvedStartMinuteOfDay,
            let resolvedEnd = target.resolvedEndMinuteOfDay
        else {
            throw ThingStructCoreError.invalidResolvedRange(blockID: blockID, start: -1, end: -1)
        }

        let nextSiblingStart = activeBlocks
            .filter { $0.parentBlockID == target.parentBlockID && $0.id != blockID }
            .compactMap { sibling -> Int? in
                guard let siblingStart = sibling.resolvedStartMinuteOfDay else {
                    return nil
                }

                return siblingStart > resolvedStart ? siblingStart : nil
            }
            .min()

        let parentEnd: Int
        if let parentBlockID = target.parentBlockID {
            guard
                let parent = activeBlocks.first(where: { $0.id == parentBlockID }),
                let resolvedParentEnd = parent.resolvedEndMinuteOfDay
            else {
                throw ThingStructCoreError.missingParent(blockID: blockID, parentID: parentBlockID)
            }

            parentEnd = resolvedParentEnd
        } else {
            parentEnd = 24 * 60
        }

        let childrenByParent = buildChildrenMap(from: activeBlocks)
        let descendantIDs = collectDescendants(startingAt: blockID, childrenByParent: childrenByParent)
        let deepestDescendantEnd = activeBlocks
            .filter { descendantIDs.contains($0.id) }
            .compactMap(\.resolvedEndMinuteOfDay)
            .max() ?? (resolvedStart + 5)

        let rawMinimumEnd = max(resolvedStart + 5, deepestDescendantEnd)
        let rawMaximumEnd = min(parentEnd, nextSiblingStart ?? parentEnd)
        let minimumEnd = rawMinimumEnd.roundedUp(toStep: 5)
        let maximumEnd = rawMaximumEnd.roundedDown(toStep: 5)

        guard minimumEnd <= maximumEnd else {
            throw ThingStructCoreError.invalidResolvedRange(
                blockID: blockID,
                start: resolvedStart,
                end: rawMaximumEnd
            )
        }

        return BlockResizeBounds(
            blockID: blockID,
            startMinuteOfDay: resolvedStart,
            endMinuteOfDay: resolvedEnd.aligned(toStep: 5, within: minimumEnd ... maximumEnd) ?? minimumEnd,
            minimumEndMinuteOfDay: minimumEnd,
            maximumEndMinuteOfDay: maximumEnd
        )
    }

    public static func resizeBlockEnd(
        _ blockID: UUID,
        in plan: DayPlan,
        proposedEndMinuteOfDay: Int
    ) throws -> DayPlan {
        let bounds = try resizeBounds(for: blockID, in: plan)
        let alignedEnd = proposedEndMinuteOfDay.aligned(
            toStep: 5,
            within: bounds.minimumEndMinuteOfDay ... bounds.maximumEndMinuteOfDay
        ) ?? bounds.endMinuteOfDay
        var updatedPlan = try resolved(plan)

        guard let blockIndex = updatedPlan.blocks.firstIndex(where: { $0.id == blockID }) else {
            throw ThingStructCoreError.missingBlock(blockID)
        }

        switch updatedPlan.blocks[blockIndex].timing {
        case let .absolute(startMinuteOfDay, _):
            updatedPlan.blocks[blockIndex].timing = .absolute(
                startMinuteOfDay: startMinuteOfDay,
                requestedEndMinuteOfDay: alignedEnd
            )

        case let .relative(startOffsetMinutes, _):
            updatedPlan.blocks[blockIndex].timing = .relative(
                startOffsetMinutes: startOffsetMinutes,
                requestedDurationMinutes: max(alignedEnd - bounds.startMinuteOfDay, 5)
            )
        }

        updatedPlan.blocks[blockIndex].resolvedStartMinuteOfDay = nil
        updatedPlan.blocks[blockIndex].resolvedEndMinuteOfDay = nil

        return try resolved(updatedPlan)
    }

    public static func activeSelection(in plan: DayPlan, at minuteOfDay: Int) throws -> ActiveSelection {
        let runtimePlan = try runtimeResolved(plan)
        let activeBlocks = runtimePlan.blocks
            .filter { !$0.isCancelled }
            .filter { block in
                guard
                    let start = block.resolvedStartMinuteOfDay,
                    let end = block.resolvedEndMinuteOfDay
                else {
                    return false
                }

                return start <= minuteOfDay && minuteOfDay < end
            }
            .sorted { lhs, rhs in
                if lhs.layerIndex != rhs.layerIndex {
                    return lhs.layerIndex < rhs.layerIndex
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        if activeBlocks.isEmpty {
            return ActiveSelection(chain: [], taskSourceBlock: nil)
        }

        guard activeBlocks.first?.layerIndex == 0 else {
            throw ThingStructCoreError.activeBlocksDoNotFormUniqueChain(atMinuteOfDay: minuteOfDay)
        }

        for index in activeBlocks.indices.dropFirst() {
            let child = activeBlocks[index]
            let parent = activeBlocks[index - 1]

            if child.parentBlockID != parent.id || child.layerIndex != parent.layerIndex + 1 {
                throw ThingStructCoreError.activeBlocksDoNotFormUniqueChain(atMinuteOfDay: minuteOfDay)
            }
        }

        let taskSource = activeBlocks.reversed().first { $0.hasIncompleteTasks }
        return ActiveSelection(chain: activeBlocks, taskSourceBlock: taskSource)
    }

    private static func strippedRuntimeBlocks(from plan: DayPlan) -> DayPlan {
        var sanitized = plan
        sanitized.blocks = plan.blocks.filter { !$0.isBlankBaseBlock }
        return sanitized
    }

    private static func resolveRanges(in plan: DayPlan) throws -> [UUID: (start: Int, end: Int)] {
        var allBlocksByID: [UUID: TimeBlock] = [:]

        for block in plan.blocks {
            if allBlocksByID.updateValue(block, forKey: block.id) != nil {
                throw ThingStructCoreError.duplicateBlockID(block.id)
            }
        }

        let activeBlocks = plan.blocks.filter { !$0.isCancelled }
        let activeBlocksByID = Dictionary(uniqueKeysWithValues: activeBlocks.map { ($0.id, $0) })
        var childrenByParent: [UUID?: [UUID]] = [:]

        for block in activeBlocks {
            if block.layerIndex == 0, block.parentBlockID != nil {
                throw ThingStructCoreError.invalidRootBlock(block.id)
            }

            if block.layerIndex > 0, block.parentBlockID == nil {
                throw ThingStructCoreError.invalidRootBlock(block.id)
            }

            if let parentID = block.parentBlockID, activeBlocksByID[parentID] == nil {
                throw ThingStructCoreError.missingParent(blockID: block.id, parentID: parentID)
            }

            childrenByParent[block.parentBlockID, default: []].append(block.id)
        }

        try detectCycles(in: activeBlocks, activeBlocksByID: activeBlocksByID)

        for block in activeBlocks {
            if block.layerIndex == 0 {
                if case .relative = block.timing {
                    throw ThingStructCoreError.baseBlockMustUseAbsoluteTiming(block.id)
                }
            } else if let parentID = block.parentBlockID, let parent = activeBlocksByID[parentID] {
                let expectedLayer = parent.layerIndex + 1
                if block.layerIndex != expectedLayer {
                    throw ThingStructCoreError.invalidLayerIndex(
                        blockID: block.id,
                        expected: expectedLayer,
                        actual: block.layerIndex
                    )
                }
            }
        }

        var resolvedRanges: [UUID: (start: Int, end: Int)] = [:]

        try resolveChildren(
            of: nil,
            in: activeBlocksByID,
            childrenByParent: childrenByParent,
            resolvedRanges: &resolvedRanges
        )

        return resolvedRanges
    }

    private static func detectCycles(
        in activeBlocks: [TimeBlock],
        activeBlocksByID: [UUID: TimeBlock]
    ) throws {
        for block in activeBlocks {
            var visited: Set<UUID> = [block.id]
            var currentParentID = block.parentBlockID

            while let parentID = currentParentID {
                if !visited.insert(parentID).inserted {
                    throw ThingStructCoreError.cycleDetected(block.id)
                }

                currentParentID = activeBlocksByID[parentID]?.parentBlockID
            }
        }
    }

    private static func resolveChildren(
        of parentID: UUID?,
        in activeBlocksByID: [UUID: TimeBlock],
        childrenByParent: [UUID?: [UUID]],
        resolvedRanges: inout [UUID: (start: Int, end: Int)]
    ) throws {
        let childIDs = childrenByParent[parentID] ?? []
        if childIDs.isEmpty {
            return
        }

        let parentRange: (start: Int, end: Int)?
        if let parentID {
            guard let resolvedParent = resolvedRanges[parentID] else {
                throw ThingStructCoreError.missingBlock(parentID)
            }
            parentRange = resolvedParent
        } else {
            parentRange = nil
        }

        let siblings = try childIDs.map { childID -> ResolvedSibling in
            guard let block = activeBlocksByID[childID] else {
                throw ThingStructCoreError.missingBlock(childID)
            }

            return try initialSiblingState(for: block, parentID: parentID, parentRange: parentRange)
        }
        .sorted { lhs, rhs in
            if lhs.start != rhs.start {
                return lhs.start < rhs.start
            }
            return lhs.block.id.uuidString < rhs.block.id.uuidString
        }

        for index in siblings.indices {
            let sibling = siblings[index]
            let nextStart = siblings[safe: index + 1]?.start

            var upperBounds: [Int] = []
            if let parentRange {
                upperBounds.append(parentRange.end)
            } else {
                upperBounds.append(24 * 60)
            }
            if let nextStart {
                upperBounds.append(nextStart)
            }
            if let requestedEnd = sibling.requestedEnd {
                upperBounds.append(requestedEnd)
            }

            let resolvedEnd = upperBounds.min() ?? (24 * 60)
            let resolvedStart = sibling.start

            if let parentRange {
                if resolvedStart < parentRange.start || resolvedStart >= parentRange.end {
                    throw ThingStructCoreError.blockOutsideParent(
                        blockID: sibling.block.id,
                        parentID: sibling.block.parentBlockID ?? parentID ?? sibling.block.id
                    )
                }
            }

            if resolvedStart >= resolvedEnd {
                throw ThingStructCoreError.invalidResolvedRange(
                    blockID: sibling.block.id,
                    start: resolvedStart,
                    end: resolvedEnd
                )
            }

            resolvedRanges[sibling.block.id] = (resolvedStart, resolvedEnd)
        }

        for sibling in siblings {
            try resolveChildren(
                of: sibling.block.id,
                in: activeBlocksByID,
                childrenByParent: childrenByParent,
                resolvedRanges: &resolvedRanges
            )
        }
    }

    private static func initialSiblingState(
        for block: TimeBlock,
        parentID: UUID?,
        parentRange: (start: Int, end: Int)?
    ) throws -> ResolvedSibling {
        switch block.timing {
        case let .absolute(startMinuteOfDay, requestedEndMinuteOfDay):
            guard (0 ..< 24 * 60).contains(startMinuteOfDay) else {
                throw ThingStructCoreError.invalidAbsoluteStart(
                    blockID: block.id,
                    minuteOfDay: startMinuteOfDay
                )
            }

            if let requestedEndMinuteOfDay, !(0 ... 24 * 60).contains(requestedEndMinuteOfDay) {
                throw ThingStructCoreError.invalidAbsoluteEnd(
                    blockID: block.id,
                    minuteOfDay: requestedEndMinuteOfDay
                )
            }

            if parentID == nil, block.layerIndex != 0 {
                throw ThingStructCoreError.invalidRootBlock(block.id)
            }

            return ResolvedSibling(
                block: block,
                start: startMinuteOfDay,
                requestedEnd: requestedEndMinuteOfDay
            )

        case let .relative(startOffsetMinutes, requestedDurationMinutes):
            guard let parentRange else {
                throw ThingStructCoreError.baseBlockMustUseAbsoluteTiming(block.id)
            }

            if let requestedDurationMinutes, requestedDurationMinutes <= 0 {
                throw ThingStructCoreError.invalidRelativeDuration(
                    blockID: block.id,
                    durationMinutes: requestedDurationMinutes
                )
            }

            let start = parentRange.start + startOffsetMinutes
            let requestedEnd = requestedDurationMinutes.map { start + $0 }
            return ResolvedSibling(block: block, start: start, requestedEnd: requestedEnd)
        }
    }

    private static func makeBlankBaseBlocks(in plan: DayPlan) -> [TimeBlock] {
        let resolvedBaseBlocks = plan.blocks
            .filter { !$0.isCancelled && $0.layerIndex == 0 }
            .sorted { lhs, rhs in
                let lhsStart = lhs.resolvedStartMinuteOfDay ?? 0
                let rhsStart = rhs.resolvedStartMinuteOfDay ?? 0
                if lhsStart != rhsStart {
                    return lhsStart < rhsStart
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        if resolvedBaseBlocks.isEmpty {
            return [blankBaseBlock(in: plan, start: 0, end: 24 * 60)]
        }

        var blanks: [TimeBlock] = []
        var cursor = 0

        for block in resolvedBaseBlocks {
            guard
                let start = block.resolvedStartMinuteOfDay,
                let end = block.resolvedEndMinuteOfDay
            else {
                continue
            }

            if cursor < start {
                blanks.append(blankBaseBlock(in: plan, start: cursor, end: start))
            }

            cursor = max(cursor, end)
        }

        if cursor < 24 * 60 {
            blanks.append(blankBaseBlock(in: plan, start: cursor, end: 24 * 60))
        }

        return blanks
    }

    private static func blankBaseBlock(in plan: DayPlan, start: Int, end: Int) -> TimeBlock {
        TimeBlock(
            dayPlanID: plan.id,
            layerIndex: 0,
            kind: .blankBase,
            title: "Blank",
            tasks: [],
            timing: .absolute(startMinuteOfDay: start, requestedEndMinuteOfDay: end),
            resolvedStartMinuteOfDay: start,
            resolvedEndMinuteOfDay: end
        )
    }

    private static func resolvedRangeMap(from blocks: [TimeBlock]) throws -> [UUID: (start: Int, end: Int)] {
        var ranges: [UUID: (start: Int, end: Int)] = [:]

        for block in blocks where !block.isCancelled {
            guard
                let start = block.resolvedStartMinuteOfDay,
                let end = block.resolvedEndMinuteOfDay
            else {
                throw ThingStructCoreError.invalidResolvedRange(blockID: block.id, start: -1, end: -1)
            }

            ranges[block.id] = (start, end)
        }

        return ranges
    }

    private static func validateCancelOverlapRisk(
        in plan: DayPlan,
        originalRanges: [UUID: (start: Int, end: Int)]
    ) throws {
        let survivingBlocks = plan.blocks.filter { !$0.isCancelled }
        let groupedBlocks = Dictionary(grouping: survivingBlocks) { block in
            ParentLayerKey(parentID: block.parentBlockID, layerIndex: block.layerIndex)
        }

        for (_, blocks) in groupedBlocks {
            let sortedBlocks = try blocks.sorted { lhs, rhs in
                guard let lhsRange = originalRanges[lhs.id], let rhsRange = originalRanges[rhs.id] else {
                    throw ThingStructCoreError.missingBlock(lhs.id == rhs.id ? lhs.id : rhs.id)
                }

                if lhsRange.start != rhsRange.start {
                    return lhsRange.start < rhsRange.start
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

            for index in sortedBlocks.indices.dropFirst() {
                let previous = sortedBlocks[index - 1]
                let current = sortedBlocks[index]

                guard
                    let previousRange = originalRanges[previous.id],
                    let currentRange = originalRanges[current.id]
                else {
                    throw ThingStructCoreError.missingBlock(previous.id)
                }

                if currentRange.start < previousRange.end {
                    throw ThingStructCoreError.cancelIntroducesSiblingOverlap(
                        firstBlockID: previous.id,
                        secondBlockID: current.id
                    )
                }
            }
        }
    }

    private static func validatePreservedRanges(
        after plan: DayPlan,
        against originalRanges: [UUID: (start: Int, end: Int)],
        excluding excludedIDs: Set<UUID>
    ) throws {
        for block in plan.blocks where !block.isCancelled && !excludedIDs.contains(block.id) {
            guard let expectedRange = originalRanges[block.id] else {
                continue
            }

            guard
                let actualStart = block.resolvedStartMinuteOfDay,
                let actualEnd = block.resolvedEndMinuteOfDay
            else {
                throw ThingStructCoreError.invalidResolvedRange(blockID: block.id, start: -1, end: -1)
            }

            if actualStart != expectedRange.start || actualEnd != expectedRange.end {
                throw ThingStructCoreError.cancelChangesResolvedRange(
                    blockID: block.id,
                    expectedStart: expectedRange.start,
                    expectedEnd: expectedRange.end,
                    actualStart: actualStart,
                    actualEnd: actualEnd
                )
            }
        }
    }

    private static func buildChildrenMap(from blocks: [TimeBlock]) -> [UUID: [UUID]] {
        var childrenByParent: [UUID: [UUID]] = [:]

        for block in blocks where !block.isCancelled {
            if let parentID = block.parentBlockID {
                childrenByParent[parentID, default: []].append(block.id)
            }
        }

        return childrenByParent
    }

    private static func collectDescendants(
        startingAt blockID: UUID,
        childrenByParent: [UUID: [UUID]]
    ) -> Set<UUID> {
        var descendants: Set<UUID> = []
        var stack = childrenByParent[blockID] ?? []

        while let next = stack.popLast() {
            if descendants.insert(next).inserted {
                stack.append(contentsOf: childrenByParent[next] ?? [])
            }
        }

        return descendants
    }
}

private struct ResolvedSibling {
    let block: TimeBlock
    let start: Int
    let requestedEnd: Int?
}

private struct ParentLayerKey: Hashable {
    let parentID: UUID?
    let layerIndex: Int
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
