import Foundation

public enum TemplateEngine {
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
        for date: LocalDay
    ) throws -> DayPlan {
        let dayPlanID = UUID()
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
                reminders: blockTemplate.reminders,
                tasks: tasks,
                timing: blockTemplate.timing
            )
        }

        let plan = DayPlan(id: dayPlanID, date: date, blocks: instantiatedBlocks)
        return try DayPlanEngine.resolved(plan)
    }

    private static func suggestedTemplate(from dayPlan: DayPlan) throws -> SuggestedDayTemplate {
        let resolvedPlan = try DayPlanEngine.resolved(dayPlan)
        let activeBlocks = resolvedPlan.blocks.filter { !$0.isCancelled }
        let blockTemplates = deepCopy(blocks: activeBlocks.map { block in
            BlockTemplate(
                id: block.id,
                parentTemplateBlockID: block.parentBlockID,
                layerIndex: block.layerIndex,
                title: block.title,
                note: block.note,
                reminders: block.reminders,
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
                reminders: block.reminders,
                taskBlueprints: copiedTaskBlueprints,
                timing: block.timing
            )
        }
    }
}
