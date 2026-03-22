import SwiftUI

// `TemplateEditorSheet` is a form for editing a saved template in isolation.
//
// Notice the separation of concerns:
// - local `@State` holds mutable form inputs
// - `onSave` / `onDelete` are injected commands from the parent/store
// - validation and preview run locally against the current draft
struct TemplateEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let template: SavedDayTemplate
    let occupiedWeekdays: Set<Weekday>
    let onSave: (String, [BlockTemplate], Set<Weekday>) throws -> Void
    let onDelete: () -> Void

    // These `@State` properties are the editable "working copy".
    // The saved template is not mutated until the user taps Save.
    @State private var title: String
    @State private var assignedWeekdays: Set<Weekday>
    @State private var blocks: [BlockTemplate]
    @State private var editorSession: TemplateBlockEditorSession?
    @State private var showingDeleteConfirmation = false
    @State private var validationMessage: String?

    init(
        template: SavedDayTemplate,
        assignedWeekdays: Set<Weekday>,
        occupiedWeekdays: Set<Weekday>,
        onSave: @escaping (String, [BlockTemplate], Set<Weekday>) throws -> Void,
        onDelete: @escaping () -> Void
    ) {
        // Custom init is how a SwiftUI view seeds its `@State` working copy from
        // incoming model values exactly once at creation time.
        self.template = template
        self.occupiedWeekdays = occupiedWeekdays
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: template.title)
        _assignedWeekdays = State(initialValue: assignedWeekdays)
        _blocks = State(initialValue: template.blocks)
    }

    var body: some View {
        NavigationStack {
            // `List` is flexible enough to mix editable rows, summaries, and buttons
            // in one native scrolling container.
            List {
                Section("Title") {
                    TextField("Template Title", text: $title)
                }

                Section("Weekdays") {
                    WeekdayPicker(
                        selectedDays: $assignedWeekdays,
                        occupiedDays: occupiedWeekdays
                    )

                    if !occupiedWeekdays.isEmpty {
                        Text("Weekdays already assigned to other templates are locked here. You can reassign them from Schedule.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Blocks") {
                    if blocks.isEmpty {
                        ContentUnavailableView(
                            "No Blocks Yet",
                            systemImage: "square.stack.3d.up.slash",
                            description: Text("Add a base block to start shaping this template.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    } else {
                        ForEach(displayEntries) { entry in
                            TemplateBlockRow(
                                block: entry.block,
                                resolvedRange: entry.resolvedRange,
                                onEdit: { beginEditing(entry.block) },
                                onAddOverlay: { beginOverlayCreation(for: entry.block) },
                                onDelete: { deleteBlockCascade(entry.block.id) }
                            )
                        }
                    }

                    Button {
                        editorSession = TemplateBlockEditorSession(
                            title: "New Base Block",
                            draft: .base()
                        )
                    } label: {
                        Label("Add Base Block", systemImage: "plus.rectangle.on.rectangle")
                    }
                }

                Section("Preview") {
                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        let preview = previewDayPlan
                        Text("\(preview.blocks.filter { $0.layerIndex == 0 }.count) base blocks")
                        Text("\(preview.blocks.count) total blocks")
                            .foregroundStyle(.secondary)
                    }

                    Text("Saving a template does not automatically rewrite already materialized future day plans. Use Schedule to explicitly regenerate a future date.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Delete Template", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
            .navigationTitle("Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try onSave(
                                title.trimmingCharacters(in: .whitespacesAndNewlines),
                                blocks,
                                assignedWeekdays
                            )
                            dismiss()
                        } catch {
                            validationMessage = error.localizedDescription
                        }
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        validationMessage != nil
                    )
                }
            }
        }
        .sheet(item: $editorSession) { session in
            // Reusing `BlockEditorSheet` keeps template editing and day-plan editing
            // on the same mental model.
            BlockEditorSheet(title: session.title, draft: session.draft) { draft in
                apply(draft)
                return true
            }
        }
        .presentationDetents([.large])
        .confirmationDialog(
            "Delete this template?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Template", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("Weekday rules and overrides pointing to this template will be removed. Existing day plans stay as snapshots.")
        }
        .onAppear(perform: validateDraft)
    }

    private var previewDayPlan: DayPlan {
        // Preview is built from the current unsaved template draft.
        (try? TemplateEngine.previewDayPlan(from: currentTemplate)) ?? DayPlan(date: LocalDay(year: 2001, month: 1, day: 1))
    }

    private var displayEntries: [TemplateBlockDisplayEntry] {
        // If the template currently validates, we sort by resolved time so the list
        // matches the eventual instantiated order. Otherwise we fall back to a simpler sort.
        if let preview = try? TemplateEngine.previewDayPlan(from: currentTemplate) {
            let previewByID = Dictionary(uniqueKeysWithValues: preview.blocks.map { ($0.id, $0) })
            return blocks
                .sorted { lhs, rhs in
                    let lhsPreview = previewByID[lhs.id]
                    let rhsPreview = previewByID[rhs.id]
                    let lhsStart = lhsPreview?.resolvedStartMinuteOfDay ?? Int.max
                    let rhsStart = rhsPreview?.resolvedStartMinuteOfDay ?? Int.max
                    if lhsStart != rhsStart {
                        return lhsStart < rhsStart
                    }
                    if lhs.layerIndex != rhs.layerIndex {
                        return lhs.layerIndex < rhs.layerIndex
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .map { block in
                    // Pair the authored template block with its preview-resolved clock range
                    // so the row can explain both the definition and the eventual outcome.
                    let resolvedBlock = previewByID[block.id]
                    return TemplateBlockDisplayEntry(
                        block: block,
                        resolvedRange: resolvedBlock.flatMap { resolvedBlock in
                            guard
                                let start = resolvedBlock.resolvedStartMinuteOfDay,
                                let end = resolvedBlock.resolvedEndMinuteOfDay
                            else {
                                return nil
                            }
                            return (start, end)
                        }
                    )
                }
        }

        return blocks
            .sorted {
                if $0.layerIndex != $1.layerIndex {
                    return $0.layerIndex < $1.layerIndex
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            .map { TemplateBlockDisplayEntry(block: $0, resolvedRange: nil) }
    }

    private var currentTemplate: SavedDayTemplate {
        // This computed value turns the local editing state back into a domain template value.
        SavedDayTemplate(
            id: template.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? template.title : title,
            sourceSuggestedTemplateID: template.sourceSuggestedTemplateID,
            blocks: blocks,
            createdAt: template.createdAt,
            updatedAt: template.updatedAt
        )
    }

    private func beginEditing(_ block: BlockTemplate) {
        editorSession = TemplateBlockEditorSession(
            title: "Edit Block",
            draft: .editing(templateBlock: block)
        )
    }

    private func beginOverlayCreation(for block: BlockTemplate) {
        editorSession = TemplateBlockEditorSession(
            title: block.layerIndex.newNextTimelineLayerActionTitle,
            draft: .overlay(parentBlockID: block.id, layerIndex: block.layerIndex + 1)
        )
    }

    private func apply(_ draft: BlockDraft) {
        // Interpret the generic draft in template-editing terms and update the local array.
        switch draft.mode {
        case .createBase:
            blocks.append(makeTemplateBlock(from: draft, id: UUID(), parentBlockID: nil, layerIndex: 0))

        case let .createOverlay(parentBlockID, layerIndex):
            blocks.append(
                makeTemplateBlock(
                    from: draft,
                    id: UUID(),
                    parentBlockID: parentBlockID,
                    layerIndex: layerIndex
                )
            )

        case let .edit(blockID):
            guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
            let existing = blocks[index]
            blocks[index] = makeTemplateBlock(
                from: draft,
                id: existing.id,
                parentBlockID: existing.parentTemplateBlockID,
                layerIndex: existing.layerIndex
            )
        }

        validateDraft()
    }

    private func deleteBlockCascade(_ blockID: UUID) {
        // Blocks are stored flat, so deleting a subtree means doing our own graph walk.
        let childrenByParent = Dictionary(grouping: blocks, by: \.parentTemplateBlockID)
        var pending = [blockID]
        var deleted: Set<UUID> = []

        while let current = pending.popLast() {
            guard deleted.insert(current).inserted else { continue }
            pending.append(contentsOf: childrenByParent[current, default: []].map(\.id))
        }

        blocks.removeAll { deleted.contains($0.id) }
        validateDraft()
    }

    private func validateDraft() {
        // Re-run the real engine so the editor's validation exactly matches runtime behavior.
        do {
            _ = try TemplateEngine.previewDayPlan(from: currentTemplate)
            validationMessage = nil
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func makeTemplateBlock(
        from draft: BlockDraft,
        id: UUID,
        parentBlockID: UUID?,
        layerIndex: Int
    ) -> BlockTemplate {
        // Template-side conversion mirrors `BlockDraft.makeBlock(dayPlanID:)`, but the
        // destination type is `BlockTemplate` instead of a concrete day-plan block.
        BlockTemplate(
            id: id,
            parentTemplateBlockID: parentBlockID,
            layerIndex: layerIndex,
            title: draft.title.isEmpty ? "Untitled" : draft.title,
            note: draft.note.isEmpty ? nil : draft.note,
            reminders: draft.reminders,
            taskBlueprints: draft.tasks.enumerated().map { index, task in
                TaskBlueprint(title: task.title, order: index)
            },
            timing: draft.timing
        )
    }
}

private struct TemplateBlockDisplayEntry: Identifiable {
    let block: BlockTemplate
    let resolvedRange: (start: Int, end: Int)?

    var id: UUID { block.id }
}

private struct TemplateBlockEditorSession: Identifiable {
    let id = UUID()
    let title: String
    let draft: BlockDraft
}

private struct TemplateBlockRow: View {
    let block: BlockTemplate
    let resolvedRange: (start: Int, end: Int)?
    let onEdit: () -> Void
    let onAddOverlay: () -> Void
    let onDelete: () -> Void

    private var layerBadgeTitle: String {
        block.layerIndex.timelineLayerBadgeTitle
    }

    private var addChildLayerTitle: String {
        block.layerIndex.addNextTimelineLayerActionTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.title)
                        .font(.headline)
                    Text(timingLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(layerBadgeTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label("\(block.taskBlueprints.count) tasks", systemImage: "checklist")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack {
                    editButton
                    addOverlayButton
                    deleteButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    editButton
                    addOverlayButton
                    deleteButton
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var timingLabel: String {
        if let resolvedRange {
            return "\(resolvedRange.start.formattedTime) - \(resolvedRange.end.formattedTime)"
        }
        return block.timing.displayLabel
    }

    private var editButton: some View {
        Button("Edit", action: onEdit)
            .buttonStyle(.borderedProminent)
    }

    private var addOverlayButton: some View {
        Button(addChildLayerTitle, action: onAddOverlay)
            .buttonStyle(.bordered)
    }

    private var deleteButton: some View {
        Button("Delete", role: .destructive, action: onDelete)
            .buttonStyle(.bordered)
    }
}

private extension TimeBlockTiming {
    var displayLabel: String {
        switch self {
        case let .absolute(startMinuteOfDay, requestedEndMinuteOfDay):
            if let requestedEndMinuteOfDay {
                return "\(startMinuteOfDay.formattedTime) - \(requestedEndMinuteOfDay.formattedTime)"
            }
            return startMinuteOfDay.formattedTime

        case let .relative(startOffsetMinutes, requestedDurationMinutes):
            if let requestedDurationMinutes {
                return "+\(startOffsetMinutes)m / \(requestedDurationMinutes)m"
            }
            return "+\(startOffsetMinutes)m"
        }
    }
}

#Preview("Template Editor - Filled") {
    let template = PreviewSupport.savedTemplate()
    TemplateEditorSheet(
        template: template,
        assignedWeekdays: [.monday, .tuesday, .wednesday],
        occupiedWeekdays: [.thursday, .friday]
    ) { _, _, _ in
    } onDelete: {
    }
}

#Preview("Template Editor - Empty") {
    TemplateEditorSheet(
        template: PreviewSupport.emptyTemplate(),
        assignedWeekdays: [],
        occupiedWeekdays: [.monday]
    ) { _, _, _ in
    } onDelete: {
    }
}

#Preview("Template Block Row - Resolved") {
    TemplateBlockRow(
        block: PreviewSupport.sampleTemplateBlock(),
        resolvedRange: (8 * 60, 10 * 60 + 30),
        onEdit: {},
        onAddOverlay: {},
        onDelete: {}
    )
    .padding()
}

#Preview("Template Block Row - Relative") {
    TemplateBlockRow(
        block: PreviewSupport.sampleOverlayTemplateBlock(),
        resolvedRange: nil,
        onEdit: {},
        onAddOverlay: {},
        onDelete: {}
    )
    .padding()
}
