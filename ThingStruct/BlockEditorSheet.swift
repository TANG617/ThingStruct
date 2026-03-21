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

    func makeBlock(dayPlanID: UUID) -> TimeBlock {
        // This is the "commit" boundary from form state into domain state.
        TimeBlock(
            dayPlanID: dayPlanID,
            layerIndex: 0,
            title: title.isEmpty ? "Untitled" : title,
            note: note.isEmpty ? nil : note,
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
            tasks: []
        )
    }

    static func overlay(parentBlockID: UUID, layerIndex: Int) -> BlockDraft {
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
            tasks: []
        )
    }

    static func editing(detail: BlockDetailModel, sourceBlock: TimeBlock) -> BlockDraft {
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
            tasks: detail.tasks
        )
    }

    static func editing(templateBlock: BlockTemplate) -> BlockDraft {
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
    let onSave: (BlockDraft) -> Void
    var onCancelBlock: (() -> Void)? = nil

    @State private var isShowingCancelConfirmation = false

    var body: some View {
        NavigationStack {
            // `Form` provides the standard grouped editor appearance on iOS.
            Form {
                Section("Details") {
                    TextField("Title", text: $draft.title)
                    TextField("Note", text: $draft.note, axis: .vertical)
                        .lineLimit(2 ... 4)
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
                                validRange: 5 ... (24 * 60)
                            )
                        }
                    } else {
                        // Relative overlays are edited as offsets/durations because their
                        // actual wall-clock position depends on the parent block.
                        Stepper("Offset: \(draft.relativeOffsetMinutes) min", value: $draft.relativeOffsetMinutes, in: 0 ... 720, step: 5)
                        Toggle("Duration", isOn: $draft.hasRelativeDuration)
                        if draft.hasRelativeDuration {
                            Stepper("Duration: \(draft.relativeDurationMinutes) min", value: $draft.relativeDurationMinutes, in: 5 ... 720, step: 5)
                        }
                    }
                }

                Section("Tasks") {
                    if draft.tasks.isEmpty {
                        Text("No tasks")
                            .foregroundStyle(.secondary)
                    }

                    ForEach($draft.tasks) { $task in
                        // Iterating over bindings gives each row direct write-back access
                        // into the parent array element.
                        TextField("Task", text: $task.title)
                    }
                    .onDelete { offsets in
                        draft.tasks.remove(atOffsets: offsets)
                    }

                    Button {
                        draft.tasks.append(TaskItem(title: "", order: draft.tasks.count))
                    } label: {
                        Label("Add Task", systemImage: "plus")
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
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
    ) { _ in }
}

#Preview("Block Editor - Overlay") {
    BlockEditorSheet(
        title: "New Overlay",
        draft: PreviewSupport.sampleBlockDraftOverlay()
    ) { _ in }
}

#Preview("Block Editor - Edit") {
    BlockEditorSheet(
        title: "Edit Block",
        draft: PreviewSupport.sampleBlockDraftEdit()
    ) { _ in }
}

#Preview("Block Editor - Edit With Cancel") {
    BlockEditorSheet(
        title: "Edit Block",
        draft: PreviewSupport.sampleBlockDraftEdit()
    ) { _ in
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
