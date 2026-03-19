import Foundation

public enum DayPlanEngine {
    public static func validate(_ plan: DayPlan) throws {
        _ = try resolved(plan)
    }

    public static func resolved(_ plan: DayPlan) throws -> DayPlan {
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

        var resolvedPlan = plan
        resolvedPlan.blocks = plan.blocks.map { block in
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
        let directChildren = childrenByParent[blockID] ?? []
        let descendantIDs = collectDescendants(startingAt: blockID, childrenByParent: childrenByParent)

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

        return try resolved(updatedPlan)
    }

    public static func activeSelection(in plan: DayPlan, at minuteOfDay: Int) throws -> ActiveSelection {
        let resolvedPlan = try resolved(plan)
        let activeBlocks = resolvedPlan.blocks
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
