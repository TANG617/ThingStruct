import SwiftUI

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
    var reminders: [ReminderRule]
    var tasks: [TaskItem]

    func makeBlock(dayPlanID: UUID) -> TimeBlock {
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
                startMinuteOfDay: absoluteStartMinuteOfDay,
                requestedEndMinuteOfDay: hasExplicitAbsoluteEnd ? absoluteEndMinuteOfDay : nil
            )

        case .relative:
            return .relative(
                startOffsetMinutes: relativeOffsetMinutes,
                requestedDurationMinutes: hasRelativeDuration ? relativeDurationMinutes : nil
            )
        }
    }
}

extension BlockDraft {
    static func base(startMinute: Int = 540, endMinute: Int = 600) -> BlockDraft {
        BlockDraft(
            mode: .createBase,
            title: "",
            note: "",
            timingMode: .absolute,
            absoluteStartMinuteOfDay: startMinute,
            hasExplicitAbsoluteEnd: true,
            absoluteEndMinuteOfDay: endMinute,
            relativeOffsetMinutes: 0,
            hasRelativeDuration: false,
            relativeDurationMinutes: 60,
            reminders: [],
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
            reminders: [],
            tasks: []
        )
    }

    static func editing(detail: BlockDetailModel, sourceBlock: TimeBlock) -> BlockDraft {
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
            absoluteStart = startMinuteOfDay
            absoluteEnd = requestedEndMinuteOfDay ?? detail.endMinuteOfDay
            relativeOffset = 0
            relativeDuration = max(detail.endMinuteOfDay - detail.startMinuteOfDay, 30)
            hasAbsoluteEnd = requestedEndMinuteOfDay != nil
            hasDuration = false

        case let .relative(startOffsetMinutes, requestedDurationMinutes):
            timingMode = .relative
            absoluteStart = detail.startMinuteOfDay
            absoluteEnd = detail.endMinuteOfDay
            relativeOffset = startOffsetMinutes
            relativeDuration = requestedDurationMinutes ?? max(detail.endMinuteOfDay - detail.startMinuteOfDay, 30)
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
            reminders: sourceBlock.reminders,
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
            absoluteStart = startMinuteOfDay
            absoluteEnd = requestedEndMinuteOfDay ?? startMinuteOfDay + 60
            relativeOffset = 0
            relativeDuration = 60
            hasAbsoluteEnd = requestedEndMinuteOfDay != nil
            hasDuration = false

        case let .relative(startOffsetMinutes, requestedDurationMinutes):
            timingMode = .relative
            absoluteStart = 0
            absoluteEnd = 60
            relativeOffset = startOffsetMinutes
            relativeDuration = requestedDurationMinutes ?? 60
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
    @State var draft: BlockDraft
    let onSave: (BlockDraft) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $draft.title)
                    TextField("Note", text: $draft.note, axis: .vertical)
                        .lineLimit(2 ... 4)
                }

                Section("Timing") {
                    Picker("Mode", selection: $draft.timingMode) {
                        ForEach(BlockTimingDraftMode.allCases) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if draft.timingMode == .absolute {
                        MinutePickerRow(title: "Start", minuteOfDay: $draft.absoluteStartMinuteOfDay)
                        Toggle("Explicit End", isOn: $draft.hasExplicitAbsoluteEnd)
                        if draft.hasExplicitAbsoluteEnd {
                            MinutePickerRow(title: "End", minuteOfDay: $draft.absoluteEndMinuteOfDay)
                        }
                    } else {
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

                Section("Reminders") {
                    if draft.reminders.isEmpty {
                        Text("No reminders")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(draft.reminders) { reminder in
                        HStack {
                            Text(reminder.triggerMode == .atStart ? "At Start" : "Before Start")
                            Spacer()
                            if reminder.triggerMode == .beforeStart {
                                Text("\(reminder.offsetMinutes) min")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        draft.reminders.remove(atOffsets: offsets)
                    }

                    Button {
                        draft.reminders.append(ReminderRule(triggerMode: .atStart))
                    } label: {
                        Label("Add Start Reminder", systemImage: "bell")
                    }

                    Button {
                        draft.reminders.append(ReminderRule(triggerMode: .beforeStart, offsetMinutes: 5))
                    } label: {
                        Label("Add 5-Min Reminder", systemImage: "bell.badge")
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
    }
}

private struct MinutePickerRow: View {
    let title: String
    @Binding var minuteOfDay: Int

    var body: some View {
        DatePicker(
            title,
            selection: Binding(
                get: { date(for: minuteOfDay) },
                set: { minuteOfDay = minuteOfDay(from: $0) }
            ),
            displayedComponents: .hourAndMinute
        )
    }

    private func date(for minuteOfDay: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: 2001, month: 1, day: 1, hour: minuteOfDay / 60, minute: minuteOfDay % 60)
        ) ?? .now
    }

    private func minuteOfDay(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
