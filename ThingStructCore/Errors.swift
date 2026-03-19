import Foundation

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
    case activeBlocksDoNotFormUniqueChain(atMinuteOfDay: Int)
    case duplicateDayPlanForDate(LocalDay)
    case duplicateWeekdayRule(Weekday)
    case duplicateDateOverride(LocalDay)
    case missingSavedTemplate(UUID)
    case missingTemplateParent(blockID: UUID, parentID: UUID)
}
