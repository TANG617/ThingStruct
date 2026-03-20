import Foundation

public enum TemplateEngine {
    public static func previewDayPlan(
        from savedTemplate: SavedDayTemplate,
        on date: LocalDay = LocalDay(year: 2001, month: 1, day: 1)
    ) throws -> DayPlan {
        try instantiateDayPlan(
            from: savedTemplate,
            for: date,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    public static func suggestedTemplates(
        referenceDay: LocalDay,
        from dayPlans: [DayPlan]
    ) throws -> [SuggestedDayTemplate] {
        var dayPlansByDate: [LocalDay: DayPlan] = [:]

        for dayPlan in dayPlans {
            if dayPlansByDate.updateValue(dayPlan, forKey: dayPlan.date) != nil {
                throw ThingStructCoreError.duplicateDayPlanForDate(dayPlan.date)
            }
        }

        let windowDates = [
            referenceDay.adding(days: -2),
            referenceDay.adding(days: -1),
            referenceDay
        ]

        return try windowDates.compactMap { date in
            guard let dayPlan = dayPlansByDate[date] else { return nil }
            return try suggestedTemplate(from: dayPlan)
        }
    }

    public static func saveSuggestedTemplate(
        _ suggestedTemplate: SuggestedDayTemplate,
        title: String,
        createdAt: Date = Date()
    ) -> SavedDayTemplate {
        let copiedBlocks = deepCopy(blocks: suggestedTemplate.blocks)
        return SavedDayTemplate(
            title: title,
            sourceSuggestedTemplateID: suggestedTemplate.id,
            blocks: copiedBlocks,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    public static func selectedSavedTemplate(
        for date: LocalDay,
        savedTemplates: [SavedDayTemplate],
        weekdayRules: [WeekdayTemplateRule],
        overrides: [DateTemplateOverride]
    ) throws -> SavedDayTemplate? {
        let templateByID = Dictionary(uniqueKeysWithValues: savedTemplates.map { ($0.id, $0) })

        var overrideByDate: [LocalDay: UUID] = [:]
        for override in overrides {
            if overrideByDate.updateValue(override.savedTemplateID, forKey: override.date) != nil {
                throw ThingStructCoreError.duplicateDateOverride(override.date)
            }
        }

        if let overrideTemplateID = overrideByDate[date] {
            guard let template = templateByID[overrideTemplateID] else {
                throw ThingStructCoreError.missingSavedTemplate(overrideTemplateID)
            }
            return template
        }

        var ruleByWeekday: [Weekday: UUID] = [:]
        for rule in weekdayRules {
            if ruleByWeekday.updateValue(rule.savedTemplateID, forKey: rule.weekday) != nil {
                throw ThingStructCoreError.duplicateWeekdayRule(rule.weekday)
            }
        }

        guard let ruleTemplateID = ruleByWeekday[date.weekday] else {
            return nil
        }

        guard let template = templateByID[ruleTemplateID] else {
            throw ThingStructCoreError.missingSavedTemplate(ruleTemplateID)
        }
        return template
    }

    public static func instantiateDayPlan(
        from savedTemplate: SavedDayTemplate,
        for date: LocalDay,
        dayPlanID: UUID = UUID(),
        generatedAt: Date = Date()
    ) throws -> DayPlan {
        var blockIDMap: [UUID: UUID] = [:]

        for block in savedTemplate.blocks {
            blockIDMap[block.id] = UUID()
        }

        let instantiatedBlocks = try savedTemplate.blocks.map { blockTemplate -> TimeBlock in
            guard let blockID = blockIDMap[blockTemplate.id] else {
                throw ThingStructCoreError.missingBlock(blockTemplate.id)
            }

            let parentBlockID: UUID?
            if let parentTemplateBlockID = blockTemplate.parentTemplateBlockID {
                guard let mappedParentID = blockIDMap[parentTemplateBlockID] else {
                    throw ThingStructCoreError.missingTemplateParent(
                        blockID: blockTemplate.id,
                        parentID: parentTemplateBlockID
                    )
                }
                parentBlockID = mappedParentID
            } else {
                parentBlockID = nil
            }

            let tasks = blockTemplate.taskBlueprints
                .sorted { lhs, rhs in
                    if lhs.order != rhs.order {
                        return lhs.order < rhs.order
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .map { blueprint in
                    TaskItem(
                        title: blueprint.title,
                        order: blueprint.order,
                        isCompleted: false,
                        completedAt: nil
                    )
                }

            return TimeBlock(
                id: blockID,
                dayPlanID: dayPlanID,
                parentBlockID: parentBlockID,
                layerIndex: blockTemplate.layerIndex,
                title: blockTemplate.title,
                note: blockTemplate.note,
                tasks: tasks,
                timing: blockTemplate.timing
            )
        }

        let plan = DayPlan(
            id: dayPlanID,
            date: date,
            sourceSavedTemplateID: savedTemplate.id,
            lastGeneratedAt: generatedAt,
            hasUserEdits: false,
            blocks: instantiatedBlocks
        )
        return try DayPlanEngine.resolved(plan)
    }

    public static func ensureMaterializedDayPlan(
        for date: LocalDay,
        existingDayPlans: [DayPlan],
        savedTemplates: [SavedDayTemplate],
        weekdayRules: [WeekdayTemplateRule],
        overrides: [DateTemplateOverride],
        generatedAt: Date = Date()
    ) throws -> DayPlan {
        if let existingPlan = try uniqueDayPlan(for: date, in: existingDayPlans) {
            return existingPlan
        }

        guard let selectedTemplate = try selectedSavedTemplate(
            for: date,
            savedTemplates: savedTemplates,
            weekdayRules: weekdayRules,
            overrides: overrides
        ) else {
            return DayPlan(
                date: date,
                sourceSavedTemplateID: nil,
                lastGeneratedAt: generatedAt,
                hasUserEdits: false,
                blocks: []
            )
        }

        return try instantiateDayPlan(
            from: selectedTemplate,
            for: date,
            generatedAt: generatedAt
        )
    }

    public static func regenerateFutureDayPlan(
        for date: LocalDay,
        today: LocalDay,
        existingDayPlans: [DayPlan],
        savedTemplates: [SavedDayTemplate],
        weekdayRules: [WeekdayTemplateRule],
        overrides: [DateTemplateOverride],
        generatedAt: Date = Date()
    ) throws -> DayPlan {
        guard date > today else {
            throw ThingStructCoreError.regenerationNotAllowedForNonFutureDate(date)
        }

        guard let existingPlan = try uniqueDayPlan(for: date, in: existingDayPlans) else {
            throw ThingStructCoreError.missingDayPlanForDate(date)
        }

        if existingPlan.hasUserEdits {
            throw ThingStructCoreError.regenerationBlockedByUserEdits(date)
        }

        if existingPlan.containsCompletedTasks {
            throw ThingStructCoreError.regenerationBlockedByCompletedTasks(date)
        }

        guard let selectedTemplate = try selectedSavedTemplate(
            for: date,
            savedTemplates: savedTemplates,
            weekdayRules: weekdayRules,
            overrides: overrides
        ) else {
            return DayPlan(
                id: existingPlan.id,
                date: date,
                sourceSavedTemplateID: nil,
                lastGeneratedAt: generatedAt,
                hasUserEdits: false,
                blocks: []
            )
        }

        return try instantiateDayPlan(
            from: selectedTemplate,
            for: date,
            dayPlanID: existingPlan.id,
            generatedAt: generatedAt
        )
    }

    public static func updateSavedTemplate(
        _ templateID: UUID,
        title: String,
        blocks: [BlockTemplate],
        assignedWeekdays: Set<Weekday>,
        in document: ThingStructDocument,
        updatedAt: Date = Date()
    ) throws -> ThingStructDocument {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw ThingStructCoreError.emptyTemplateTitle
        }

        guard let templateIndex = document.savedTemplates.firstIndex(where: { $0.id == templateID }) else {
            throw ThingStructCoreError.missingSavedTemplate(templateID)
        }

        var updatedDocument = document
        var updatedTemplate = updatedDocument.savedTemplates[templateIndex]
        updatedTemplate.title = trimmedTitle
        updatedTemplate.blocks = normalized(blocks: blocks)
        updatedTemplate.updatedAt = updatedAt

        _ = try previewDayPlan(from: updatedTemplate)

        updatedDocument.savedTemplates[templateIndex] = updatedTemplate
        updatedDocument.weekdayRules.removeAll {
            $0.savedTemplateID == templateID || assignedWeekdays.contains($0.weekday)
        }
        updatedDocument.weekdayRules.append(
            contentsOf: assignedWeekdays.sorted { $0.rawValue < $1.rawValue }.map {
                WeekdayTemplateRule(weekday: $0, savedTemplateID: templateID)
            }
        )
        updatedDocument.weekdayRules.sort { $0.weekday.rawValue < $1.weekday.rawValue }
        return updatedDocument
    }

    public static func deleteSavedTemplate(
        _ templateID: UUID,
        from document: ThingStructDocument
    ) -> ThingStructDocument {
        var updatedDocument = document
        updatedDocument.savedTemplates.removeAll { $0.id == templateID }
        updatedDocument.weekdayRules.removeAll { $0.savedTemplateID == templateID }
        updatedDocument.overrides.removeAll { $0.savedTemplateID == templateID }
        updatedDocument.dayPlans = updatedDocument.dayPlans.map { dayPlan in
            guard dayPlan.sourceSavedTemplateID == templateID else { return dayPlan }
            var updatedDayPlan = dayPlan
            updatedDayPlan.sourceSavedTemplateID = nil
            return updatedDayPlan
        }
        return updatedDocument
    }

    private static func suggestedTemplate(from dayPlan: DayPlan) throws -> SuggestedDayTemplate? {
        let resolvedPlan = try DayPlanEngine.resolved(dayPlan)
        let activeBlocks = resolvedPlan.blocks.filter { !$0.isCancelled && !$0.isBlankBaseBlock }

        guard !activeBlocks.isEmpty else {
            return nil
        }

        let blockTemplates = deepCopy(blocks: activeBlocks.map { block in
            BlockTemplate(
                id: block.id,
                parentTemplateBlockID: block.parentBlockID,
                layerIndex: block.layerIndex,
                title: block.title,
                note: block.note,
                taskBlueprints: block.tasks.map {
                    TaskBlueprint(id: $0.id, title: $0.title, order: $0.order)
                },
                timing: block.timing
            )
        })

        return SuggestedDayTemplate(
            sourceDate: resolvedPlan.date,
            sourceDayPlanID: resolvedPlan.id,
            blocks: blockTemplates
        )
    }

    private static func uniqueDayPlan(
        for date: LocalDay,
        in dayPlans: [DayPlan]
    ) throws -> DayPlan? {
        let matchingPlans = dayPlans.filter { $0.date == date }

        if matchingPlans.count > 1 {
            throw ThingStructCoreError.duplicateDayPlanForDate(date)
        }

        return matchingPlans.first
    }

    private static func deepCopy(blocks: [BlockTemplate]) -> [BlockTemplate] {
        var blockIDMap: [UUID: UUID] = [:]
        for block in blocks {
            blockIDMap[block.id] = UUID()
        }

        return blocks.map { block in
            let copiedTaskBlueprints = block.taskBlueprints.map { blueprint in
                TaskBlueprint(title: blueprint.title, order: blueprint.order)
            }

            return BlockTemplate(
                id: blockIDMap[block.id] ?? UUID(),
                parentTemplateBlockID: block.parentTemplateBlockID.flatMap { blockIDMap[$0] },
                layerIndex: block.layerIndex,
                title: block.title,
                note: block.note,
                taskBlueprints: copiedTaskBlueprints,
                timing: block.timing
            )
        }
    }

    private static func normalized(blocks: [BlockTemplate]) -> [BlockTemplate] {
        blocks.map { block in
            var updatedBlock = block
            updatedBlock.taskBlueprints = block.taskBlueprints.enumerated().map { index, blueprint in
                var updatedBlueprint = blueprint
                updatedBlueprint.order = index
                return updatedBlueprint
            }
            return updatedBlock
        }
    }
}
