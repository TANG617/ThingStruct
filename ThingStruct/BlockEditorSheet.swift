import SwiftUI

// The editor does not write directly into domain models while the user types.
// Instead it edits a `BlockDraft`, which acts like a temporary form state object.
//
// This pattern is very common in UI code because a partially typed form may be
// invalid or incomplete, while domain models usually want stronger invariants.
enum BlockDraftMode: Equatable {
    case createBase
    case createOverlay(parentBlockID: UUID, layerIndex: Int)
    case edit(blockID: UUID)
}

enum BlockTimingDraftMode: String, CaseIterable, Identifiable {
    case absolute
    case relative

    var id: String { rawValue }
}

enum ReminderPreset: String, CaseIterable, Identifiable {
    case atStart
    case fiveMinutesBefore
    case tenMinutesBefore
    case fifteenMinutesBefore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .atStart:
            return "At start"
        case .fiveMinutesBefore:
            return "5 min before"
        case .tenMinutesBefore:
            return "10 min before"
        case .fifteenMinutesBefore:
            return "15 min before"
        }
    }

    var rule: ReminderRule {
        switch self {
        case .atStart:
            return ReminderRule(triggerMode: .atStart, offsetMinutes: 0)
        case .fiveMinutesBefore:
            return ReminderRule(triggerMode: .beforeStart, offsetMinutes: 5)
        case .tenMinutesBefore:
            return ReminderRule(triggerMode: .beforeStart, offsetMinutes: 10)
        case .fifteenMinutesBefore:
            return ReminderRule(triggerMode: .beforeStart, offsetMinutes: 15)
        }
    }

    init?(rule: ReminderRule) {
        switch (rule.triggerMode, rule.offsetMinutes) {
        case (.atStart, _):
            self = .atStart
        case (.beforeStart, 5):
            self = .fiveMinutesBefore
        case (.beforeStart, 10):
            self = .tenMinutesBefore
        case (.beforeStart, 15):
            self = .fifteenMinutesBefore
        default:
            return nil
        }
    }
}

struct BlockDraft: Equatable {
    var mode: BlockDraftMode
    var title: String
    var note: String
    var timingMode: BlockTimingDraftMode
    var absoluteStartMinuteOfDay: Int
    var hasExplicitAbsoluteEnd: Bool
    var absoluteEndMinuteOfDay: Int
    var relativeOffsetMinutes: Int
    var hasRelativeDuration: Bool
    var relativeDurationMinutes: Int
    var relativeParentStartMinuteOfDay: Int?
    var relativeParentEndMinuteOfDay: Int?
    var reminders: [ReminderRule]
    var tasks: [TaskItem]

    private var snappedAbsoluteStartMinuteOfDay: Int {
        // The draft can temporarily hold arbitrary values from UI controls;
        // these computed properties normalize the values before we build a real block.
        absoluteStartMinuteOfDay.snapped(toStep: 5, within: 0 ... (24 * 60 - 5))
    }

    private var snappedAbsoluteEndMinuteOfDay: Int {
        let minimumEnd = min(snappedAbsoluteStartMinuteOfDay + 5, 24 * 60)
        return max(
            absoluteEndMinuteOfDay.snapped(toStep: 5, within: minimumEnd ... (24 * 60)),
            minimumEnd
        )
    }

    private var snappedRelativeOffsetMinutes: Int {
        relativeOffsetMinutes.snapped(toStep: 5, within: 0 ... 720)
    }

    private var snappedRelativeDurationMinutes: Int {
        relativeDurationMinutes.snapped(toStep: 5, within: 5 ... 720)
    }

    var hasRelativeParentRange: Bool {
        guard
            let relativeParentStartMinuteOfDay,
            let relativeParentEndMinuteOfDay
        else {
            return false
        }

        return relativeParentEndMinuteOfDay > relativeParentStartMinuteOfDay
    }

    var relativeStartMinuteOfDay: Int {
        guard
            let relativeParentStartMinuteOfDay,
            let relativeParentEndMinuteOfDay
        else {
            return 0
        }

        let upperBound = max(relativeParentStartMinuteOfDay, relativeParentEndMinuteOfDay - 5)
        return (relativeParentStartMinuteOfDay + snappedRelativeOffsetMinutes)
            .snapped(toStep: 5, within: relativeParentStartMinuteOfDay ... upperBound)
    }

    var relativeEndMinuteOfDay: Int {
        guard let relativeParentEndMinuteOfDay else {
            return 0
        }

        if hasRelativeDuration {
            let minimumEnd = min(relativeStartMinuteOfDay + 5, relativeParentEndMinuteOfDay)
            return max(
                min(relativeStartMinuteOfDay + snappedRelativeDurationMinutes, relativeParentEndMinuteOfDay),
                minimumEnd
            )
        }

        return relativeParentEndMinuteOfDay
    }

    var relativeStartValidRange: ClosedRange<Int>? {
        guard
            let relativeParentStartMinuteOfDay,
            let relativeParentEndMinuteOfDay,
            relativeParentEndMinuteOfDay > relativeParentStartMinuteOfDay
        else {
            return nil
        }

        return relativeParentStartMinuteOfDay ... max(relativeParentStartMinuteOfDay, relativeParentEndMinuteOfDay - 5)
    }

    var relativeEndValidRange: ClosedRange<Int>? {
        guard let relativeParentEndMinuteOfDay else {
            return nil
        }

        let minimumEnd = min(relativeStartMinuteOfDay + 5, relativeParentEndMinuteOfDay)
        return minimumEnd ... relativeParentEndMinuteOfDay
    }

    var reminderPreset: ReminderPreset? {
        get {
            reminders.first.flatMap(ReminderPreset.init(rule:))
        }
        set {
            reminders = newValue.map { [$0.rule] } ?? []
        }
    }

    func makeBlock(dayPlanID: UUID) -> TimeBlock {
        // This is the "commit" boundary from form state into domain state.
        TimeBlock(
            dayPlanID: dayPlanID,
            layerIndex: 0,
            title: title.isEmpty ? "Untitled" : title,
            note: note.isEmpty ? nil : note,
            reminders: reminders,
            tasks: normalizedTasks,
            timing: timing
        )
    }

    var normalizedTasks: [TaskItem] {
        tasks.enumerated().map { index, task in
            var updated = task
            updated.order = index
            return updated
        }
    }

    var timing: TimeBlockTiming {
        switch timingMode {
        case .absolute:
            return .absolute(
                startMinuteOfDay: snappedAbsoluteStartMinuteOfDay,
                requestedEndMinuteOfDay: hasExplicitAbsoluteEnd ? snappedAbsoluteEndMinuteOfDay : nil
            )

        case .relative:
            return .relative(
                startOffsetMinutes: snappedRelativeOffsetMinutes,
                requestedDurationMinutes: hasRelativeDuration ? snappedRelativeDurationMinutes : nil
            )
        }
    }

    mutating func setRelativeStartMinuteOfDay(_ minuteOfDay: Int) {
        guard
            let relativeParentStartMinuteOfDay,
            let relativeStartValidRange
        else {
            return
        }

        let snappedStart = minuteOfDay.snapped(toStep: 5, within: relativeStartValidRange)
        relativeOffsetMinutes = snappedStart - relativeParentStartMinuteOfDay

        if hasRelativeDuration {
            clampRelativeEndIfNeeded()
        }
    }

    mutating func setRelativeEndMinuteOfDay(_ minuteOfDay: Int) {
        guard let relativeEndValidRange else {
            return
        }

        let snappedEnd = minuteOfDay.snapped(toStep: 5, within: relativeEndValidRange)
        hasRelativeDuration = true
        relativeDurationMinutes = max(snappedEnd - relativeStartMinuteOfDay, 5)
    }

    mutating func clampRelativeEndIfNeeded() {
        guard hasRelativeDuration else { return }
        setRelativeEndMinuteOfDay(relativeEndMinuteOfDay)
    }
}

extension BlockDraft {
    static func base(startMinute: Int = 540, endMinute: Int = 600) -> BlockDraft {
        // Factory helpers keep view code from having to know all draft defaults.
        BlockDraft(
            mode: .createBase,
            title: "",
            note: "",
            timingMode: .absolute,
            absoluteStartMinuteOfDay: startMinute.snapped(toStep: 5, within: 0 ... (24 * 60 - 5)),
            hasExplicitAbsoluteEnd: true,
            absoluteEndMinuteOfDay: max(
                endMinute.snapped(toStep: 5, within: 5 ... (24 * 60)),
                startMinute.snapped(toStep: 5, within: 0 ... (24 * 60 - 5)) + 5
            ),
            relativeOffsetMinutes: 0,
            hasRelativeDuration: false,
            relativeDurationMinutes: 60,
            relativeParentStartMinuteOfDay: nil,
            relativeParentEndMinuteOfDay: nil,
            reminders: [],
            tasks: []
        )
    }

    static func overlay(
        parentBlockID: UUID,
        layerIndex: Int,
        parentResolvedRange: (start: Int, end: Int)? = nil
    ) -> BlockDraft {
        BlockDraft(
            mode: .createOverlay(parentBlockID: parentBlockID, layerIndex: layerIndex),
            title: "",
            note: "",
            timingMode: .relative,
            absoluteStartMinuteOfDay: 540,
            hasExplicitAbsoluteEnd: false,
            absoluteEndMinuteOfDay: 600,
            relativeOffsetMinutes: 0,
            hasRelativeDuration: true,
            relativeDurationMinutes: 60,
            relativeParentStartMinuteOfDay: parentResolvedRange?.start,
            relativeParentEndMinuteOfDay: parentResolvedRange?.end,
            reminders: [],
            tasks: []
        )
    }

    static func editing(
        detail: BlockDetailModel,
        sourceBlock: TimeBlock,
        parentResolvedRange: (start: Int, end: Int)? = nil
    ) -> BlockDraft {
        // Converting a stored block into a mutable draft is the inverse of `makeBlock`.
        let timingMode: BlockTimingDraftMode
        let absoluteStart: Int
        let absoluteEnd: Int
        let relativeOffset: Int
        let relativeDuration: Int
        let hasAbsoluteEnd: Bool
        let hasDuration: Bool

        switch sourceBlock.timing {
        case let .absolute(startMinuteOfDay, requestedEndMinuteOfDay):
            timingMode = .absolute
            absoluteStart = startMinuteOfDay.snapped(toStep: 5, within: 0 ... (24 * 60 - 5))
            absoluteEnd = (requestedEndMinuteOfDay ?? detail.endMinuteOfDay)
                .snapped(toStep: 5, within: 5 ... (24 * 60))
            relativeOffset = 0
            relativeDuration = max(
                (detail.endMinuteOfDay - detail.startMinuteOfDay).snapped(toStep: 5, within: 5 ... 720),
                30
            )
            hasAbsoluteEnd = requestedEndMinuteOfDay != nil
            hasDuration = false

        case let .relative(startOffsetMinutes, requestedDurationMinutes):
            timingMode = .relative
            absoluteStart = detail.startMinuteOfDay.snapped(toStep: 5, within: 0 ... (24 * 60 - 5))
            absoluteEnd = detail.endMinuteOfDay.snapped(toStep: 5, within: 5 ... (24 * 60))
            relativeOffset = startOffsetMinutes.snapped(toStep: 5, within: 0 ... 720)
            relativeDuration = (requestedDurationMinutes ?? max(detail.endMinuteOfDay - detail.startMinuteOfDay, 30))
                .snapped(toStep: 5, within: 5 ... 720)
            hasAbsoluteEnd = false
            hasDuration = requestedDurationMinutes != nil
        }

        return BlockDraft(
            mode: .edit(blockID: detail.id),
            title: detail.title,
            note: detail.note ?? "",
            timingMode: timingMode,
            absoluteStartMinuteOfDay: absoluteStart,
            hasExplicitAbsoluteEnd: hasAbsoluteEnd,
            absoluteEndMinuteOfDay: absoluteEnd,
            relativeOffsetMinutes: relativeOffset,
            hasRelativeDuration: hasDuration,
            relativeDurationMinutes: relativeDuration,
            relativeParentStartMinuteOfDay: parentResolvedRange?.start,
            relativeParentEndMinuteOfDay: parentResolvedRange?.end,
            reminders: sourceBlock.reminders,
            tasks: detail.tasks
        )
    }

    static func editing(
        templateBlock: BlockTemplate,
        parentResolvedRange: (start: Int, end: Int)? = nil
    ) -> BlockDraft {
        let timingMode: BlockTimingDraftMode
        let absoluteStart: Int
        let absoluteEnd: Int
        let relativeOffset: Int
        let relativeDuration: Int
        let hasAbsoluteEnd: Bool
        let hasDuration: Bool

        switch templateBlock.timing {
        case let .absolute(startMinuteOfDay, requestedEndMinuteOfDay):
            timingMode = .absolute
            absoluteStart = startMinuteOfDay.snapped(toStep: 5, within: 0 ... (24 * 60 - 5))
            absoluteEnd = (requestedEndMinuteOfDay ?? startMinuteOfDay + 60)
                .snapped(toStep: 5, within: 5 ... (24 * 60))
            relativeOffset = 0
            relativeDuration = 60
            hasAbsoluteEnd = requestedEndMinuteOfDay != nil
            hasDuration = false

        case let .relative(startOffsetMinutes, requestedDurationMinutes):
            timingMode = .relative
            absoluteStart = 0
            absoluteEnd = 60
            relativeOffset = startOffsetMinutes.snapped(toStep: 5, within: 0 ... 720)
            relativeDuration = (requestedDurationMinutes ?? 60).snapped(toStep: 5, within: 5 ... 720)
            hasAbsoluteEnd = false
            hasDuration = requestedDurationMinutes != nil
        }

        return BlockDraft(
            mode: .edit(blockID: templateBlock.id),
            title: templateBlock.title,
            note: templateBlock.note ?? "",
            timingMode: timingMode,
            absoluteStartMinuteOfDay: absoluteStart,
            hasExplicitAbsoluteEnd: hasAbsoluteEnd,
            absoluteEndMinuteOfDay: absoluteEnd,
            relativeOffsetMinutes: relativeOffset,
            hasRelativeDuration: hasDuration,
            relativeDurationMinutes: relativeDuration,
            relativeParentStartMinuteOfDay: parentResolvedRange?.start,
            relativeParentEndMinuteOfDay: parentResolvedRange?.end,
            reminders: templateBlock.reminders,
            tasks: templateBlock.taskBlueprints
                .sorted { lhs, rhs in
                    if lhs.order != rhs.order {
                        return lhs.order < rhs.order
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .map { TaskItem(title: $0.title, order: $0.order) }
        )
    }
}

struct BlockEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    // The sheet owns a temporary draft so text entry can be incomplete/invalid
    // without mutating the persisted block immediately.
    @State var draft: BlockDraft
    let onSave: (BlockDraft) -> Bool
    var onCancelBlock: (() -> Void)? = nil

    @State private var isShowingCancelConfirmation = false
    @FocusState private var focusedTaskID: UUID?

    var body: some View {
        NavigationStack {
            // `Form` provides the standard grouped editor appearance on iOS.
            Form {
                Section("Details") {
                    TextField("Title", text: $draft.title)
                    TextField("Note", text: $draft.note, axis: .vertical)
                        .lineLimit(2 ... 4)
                }
                
                Section("Tasks") {
                    if draft.tasks.isEmpty {
                        Text("No tasks")
                            .foregroundStyle(.secondary)
                    }

                    ForEach($draft.tasks, editActions: [.move, .delete]) { $task in
                        let taskID = $task.wrappedValue.id

                        HStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.tertiary)

                            // Each field binds directly into the matching task draft row.
                            TextField("Task", text: $task.title)
                                .focused($focusedTaskID, equals: taskID)
                        }
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.tertiary)

                        Text("Tap to add task")
                            .foregroundStyle(.tertiary)

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        beginAddingTask()
                    }
                }

                Section("Timing") {
                    // A segmented picker works well for small enums like timing mode.
                    Picker("Mode", selection: $draft.timingMode) {
                        ForEach(BlockTimingDraftMode.allCases) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if draft.timingMode == .absolute {
                        // The storage format is `Int` minutes, but the native control is a
                        // `DatePicker`, so `MinutePickerRow` handles that conversion.
                        MinutePickerRow(
                            title: "Start",
                            minuteOfDay: $draft.absoluteStartMinuteOfDay,
                            validRange: 0 ... (24 * 60 - 5)
                        )
                        Toggle("Explicit End", isOn: $draft.hasExplicitAbsoluteEnd)
                        if draft.hasExplicitAbsoluteEnd {
                            MinutePickerRow(
                                title: "End",
                                minuteOfDay: $draft.absoluteEndMinuteOfDay,
                                validRange: absoluteEndValidRange
                            )
                        }
                    } else {
                        if let relativeStartValidRange = draft.relativeStartValidRange {
                            MinutePickerRow(
                                title: "Start",
                                minuteOfDay: relativeStartMinuteBinding,
                                validRange: relativeStartValidRange
                            )

                            Toggle("Explicit End", isOn: $draft.hasRelativeDuration)
                            if draft.hasRelativeDuration, let relativeEndValidRange = draft.relativeEndValidRange {
                                MinutePickerRow(
                                    title: "End",
                                    minuteOfDay: relativeEndMinuteBinding,
                                    validRange: relativeEndValidRange
                                )
                            }
                        } else {
                            Text("Relative timing becomes editable after the parent block resolves to a valid time range.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Reminder") {
                    Toggle(
                        "Enable reminder",
                        isOn: Binding(
                            get: { draft.reminderPreset != nil },
                            set: { draft.reminderPreset = $0 ? (draft.reminderPreset ?? .atStart) : nil }
                        )
                    )

                    if draft.reminderPreset != nil {
                        Picker(
                            "When",
                            selection: Binding(
                                get: { draft.reminderPreset ?? .atStart },
                                set: { draft.reminderPreset = $0 }
                            )
                        ) {
                            ForEach(ReminderPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                    }
                }



                if onCancelBlock != nil {
                    Section {
                        Button("Cancel Block", role: .destructive) {
                            isShowingCancelConfirmation = true
                        }
                    } footer: {
                        Text("This keeps history but removes the block from the active plan and collapses its descendants.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: draft.absoluteStartMinuteOfDay) { _, _ in
                clampAbsoluteEndIfNeeded()
            }
            .onChange(of: draft.hasExplicitAbsoluteEnd) { _, isEnabled in
                if isEnabled {
                    clampAbsoluteEndIfNeeded()
                }
            }
            .onChange(of: draft.hasRelativeDuration) { _, isEnabled in
                if isEnabled {
                    draft.clampRelativeEndIfNeeded()
                }
            }
            .onChange(of: focusedTaskID) { previousTaskID, currentTaskID in
                guard previousTaskID != currentTaskID else { return }
                removeTaskIfBlank(previousTaskID)
            }
            .onChange(of: draft.tasks.map(\.id)) { _, _ in
                normalizeTaskOrder()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        commitTaskEdits()
                        if onSave(draft) {
                            dismiss()
                        }
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .confirmationDialog(
            "Cancel this block?",
            isPresented: $isShowingCancelConfirmation,
            titleVisibility: .visible
        ) {
            if let onCancelBlock {
                Button("Cancel Block", role: .destructive) {
                    onCancelBlock()
                    dismiss()
                }
            }
        }
    }

    private var absoluteEndValidRange: ClosedRange<Int> {
        let snappedStart = draft.absoluteStartMinuteOfDay.snapped(toStep: 5, within: 0 ... (24 * 60 - 5))
        let minimumEnd = min(snappedStart + 5, 24 * 60)
        return minimumEnd ... (24 * 60)
    }

    private var relativeStartMinuteBinding: Binding<Int> {
        Binding(
            get: { draft.relativeStartMinuteOfDay },
            set: { draft.setRelativeStartMinuteOfDay($0) }
        )
    }

    private var relativeEndMinuteBinding: Binding<Int> {
        Binding(
            get: { draft.relativeEndMinuteOfDay },
            set: { draft.setRelativeEndMinuteOfDay($0) }
        )
    }

    private func clampAbsoluteEndIfNeeded() {
        guard draft.hasExplicitAbsoluteEnd else { return }

        draft.absoluteEndMinuteOfDay = max(
            draft.absoluteEndMinuteOfDay.snapped(toStep: 5, within: absoluteEndValidRange),
            absoluteEndValidRange.lowerBound
        )
    }

    private func beginAddingTask() {
        if let existingBlankTaskID = draft.tasks.first(where: isTaskBlank)?.id {
            focusedTaskID = existingBlankTaskID
            return
        }

        let newTask = TaskItem(title: "", order: draft.tasks.count)
        draft.tasks.append(newTask)
        focusedTaskID = newTask.id
    }

    private func removeTaskIfBlank(_ taskID: UUID?) {
        guard
            let taskID,
            let index = draft.tasks.firstIndex(where: { $0.id == taskID }),
            isTaskBlank(draft.tasks[index])
        else {
            return
        }

        draft.tasks.remove(at: index)
    }

    private func commitTaskEdits() {
        focusedTaskID = nil
        draft.tasks.removeAll(where: isTaskBlank)
        normalizeTaskOrder()
    }

    private func normalizeTaskOrder() {
        for index in draft.tasks.indices {
            draft.tasks[index].order = index
        }
    }

    private func isTaskBlank(_ task: TaskItem) -> Bool {
        task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct MinutePickerRow: View {
    let title: String
    // `@Binding` means this row edits state owned by its parent view.
    @Binding var minuteOfDay: Int
    let validRange: ClosedRange<Int>

    var body: some View {
        DatePicker(
            title,
            selection: Binding(
                // Adapt `Binding<Int>` to the `Binding<Date>` API expected by `DatePicker`.
                get: { date(for: minuteOfDay) },
                set: { minuteOfDay = minuteOfDay(from: $0).snapped(toStep: 5, within: validRange) }
            ),
            displayedComponents: .hourAndMinute
        )
    }

    private func date(for minuteOfDay: Int) -> Date {
        // The concrete day is arbitrary; we only need a stable same-day reference point.
        Calendar.current.date(
            byAdding: .minute,
            value: minuteOfDay,
            to: referenceDate
        ) ?? referenceDate
    }

    private func minuteOfDay(from date: Date) -> Int {
        // Convert the picker output back into the engine's simpler minute-of-day format.
        Calendar.current.dateComponents([.minute], from: referenceDate, to: date).minute ?? 0
    }

    private var referenceDate: Date {
        Calendar.current.startOfDay(for: Calendar.current.date(
            from: DateComponents(year: 2001, month: 1, day: 1)
        ) ?? .now)
    }
}

#Preview("Block Editor - Base") {
    BlockEditorSheet(
        title: "New Base Block",
        draft: PreviewSupport.sampleBlockDraftBase()
    ) { _ in
        true
    }
}

#Preview("Block Editor - Overlay") {
    BlockEditorSheet(
        title: "New L2",
        draft: PreviewSupport.sampleBlockDraftOverlay()
    ) { _ in
        true
    }
}

#Preview("Block Editor - Edit") {
    BlockEditorSheet(
        title: "Edit Block",
        draft: PreviewSupport.sampleBlockDraftEdit()
    ) { _ in
        true
    }
}

#Preview("Block Editor - Edit With Cancel") {
    BlockEditorSheet(
        title: "Edit Block",
        draft: PreviewSupport.sampleBlockDraftEdit()
    ) { _ in
        true
    } onCancelBlock: {
    }
}

#Preview("Minute Picker Row") {
    struct MinutePickerPreview: View {
        @State private var minuteOfDay = 9 * 60 + 45

        var body: some View {
            Form {
                MinutePickerRow(
                    title: "Start",
                    minuteOfDay: $minuteOfDay,
                    validRange: 0 ... (24 * 60 - 5)
                )
            }
        }
    }

    return MinutePickerPreview()
}
