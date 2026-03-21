import Foundation

// Centralized domain errors for the core layer.
//
// The app intentionally throws typed errors from the engines instead of returning
// ad-hoc booleans, because the failure modes carry useful product semantics:
// "duplicate weekday rule" is very different from "block overlaps parent".
public enum ThingStructCoreError: Error, Equatable, Sendable {
    case duplicateBlockID(UUID)
    case missingBlock(UUID)
    case invalidRootBlock(UUID)
    case missingParent(blockID: UUID, parentID: UUID)
    case invalidLayerIndex(blockID: UUID, expected: Int, actual: Int)
    case cycleDetected(UUID)
    case baseBlockMustUseAbsoluteTiming(UUID)
    case invalidAbsoluteStart(blockID: UUID, minuteOfDay: Int)
    case invalidAbsoluteEnd(blockID: UUID, minuteOfDay: Int)
    case invalidRelativeDuration(blockID: UUID, durationMinutes: Int)
    case invalidResolvedRange(blockID: UUID, start: Int, end: Int)
    case blockOutsideParent(blockID: UUID, parentID: UUID)
    case cancelIntroducesSiblingOverlap(firstBlockID: UUID, secondBlockID: UUID)
    case cancelChangesResolvedRange(blockID: UUID, expectedStart: Int, expectedEnd: Int, actualStart: Int, actualEnd: Int)
    case activeBlocksDoNotFormUniqueChain(atMinuteOfDay: Int)
    case duplicateDayPlanForDate(LocalDay)
    case missingDayPlanForDate(LocalDay)
    case duplicateWeekdayRule(Weekday)
    case duplicateDateOverride(LocalDay)
    case missingSavedTemplate(UUID)
    case missingTemplateParent(blockID: UUID, parentID: UUID)
    case emptyTemplateTitle
    case regenerationNotAllowedForNonFutureDate(LocalDay)
    case regenerationBlockedByUserEdits(LocalDay)
    case regenerationBlockedByCompletedTasks(LocalDay)
}

extension ThingStructCoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .duplicateBlockID:
            return "Two blocks share the same identifier."
        case .missingBlock:
            return "The requested block could not be found."
        case .invalidRootBlock:
            return "A layer 0 block must not have a parent, and overlay blocks must have one."
        case .missingParent:
            return "An overlay block references a missing parent block."
        case .invalidLayerIndex:
            return "A block’s layer index does not match its parent relationship."
        case .cycleDetected:
            return "The block hierarchy contains a cycle."
        case .baseBlockMustUseAbsoluteTiming:
            return "Base blocks must use absolute timing."
        case .invalidAbsoluteStart:
            return "A block has an invalid absolute start minute."
        case .invalidAbsoluteEnd:
            return "A block has an invalid absolute end minute."
        case .invalidRelativeDuration:
            return "A relative block has an invalid duration."
        case .invalidResolvedRange:
            return "A block resolves to an empty or inverted time range."
        case .blockOutsideParent:
            return "A block extends outside its parent block."
        case .cancelIntroducesSiblingOverlap:
            return "Cancelling this block would make sibling blocks overlap."
        case .cancelChangesResolvedRange:
            return "Cancelling this block would unexpectedly change a descendant’s resolved range."
        case .activeBlocksDoNotFormUniqueChain:
            return "The active blocks at this time do not form a unique chain."
        case .duplicateDayPlanForDate:
            return "More than one day plan exists for the same date."
        case .missingDayPlanForDate:
            return "No day plan exists for that date."
        case .duplicateWeekdayRule:
            return "More than one weekday rule targets the same weekday."
        case .duplicateDateOverride:
            return "More than one override targets the same date."
        case .missingSavedTemplate:
            return "The saved template could not be found."
        case .missingTemplateParent:
            return "A template block references a missing parent block."
        case .emptyTemplateTitle:
            return "Template title cannot be empty."
        case .regenerationNotAllowedForNonFutureDate:
            return "Only future day plans can be regenerated."
        case .regenerationBlockedByUserEdits:
            return "This future day plan has user edits and cannot be regenerated."
        case .regenerationBlockedByCompletedTasks:
            return "This future day plan has completed tasks and cannot be regenerated."
        }
    }
}
