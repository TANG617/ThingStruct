import SwiftUI

struct TodayRootView: View {
    @Environment(ThingStructStore.self) private var store
    @State private var editorSession: BlockEditorSession?
    @State private var showingCancelConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if !store.isLoaded {
                    ContentUnavailableView("Loading", systemImage: "calendar")
                } else {
                    let result = Result { try store.todayScreenModel() }

                    switch result {
                    case let .success(model):
                        TodayTimelineView(
                            model: model,
                            selectedBlockID: store.selectedBlockID,
                            currentMinute: store.selectedDate == LocalDay.today() ? store.minuteOfDay(for: .now) : nil,
                            onSelect: { blockID in
                                store.selectBlock(blockID)
                            }
                        )
                        .safeAreaInset(edge: .bottom) {
                            if let selectedBlock = model.selectedBlock {
                                BlockDetailPanel(
                                    block: selectedBlock,
                                    onEdit: { beginEditing(selectedBlock) },
                                    onAddOverlay: { beginOverlayCreation(for: selectedBlock) },
                                    onCreateBase: { beginBaseCreation(from: selectedBlock) },
                                    onCancel: {
                                        showingCancelConfirmation = true
                                    }
                                )
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                            }
                        }

                    case let .failure(error):
                        ContentUnavailableView(
                            "Unable to Load Today",
                            systemImage: "exclamationmark.triangle",
                            description: Text(error.localizedDescription)
                        )
                    }
                }
            }
            .navigationTitle(store.selectedDate.titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        store.selectDate(store.selectedDate.adding(days: -1))
                    } label: {
                        Image(systemName: "chevron.left")
                    }

                    Button("Today") {
                        store.selectDate(.today())
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorSession = BlockEditorSession(
                            title: "New Base Block",
                            draft: .base()
                        )
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.selectDate(store.selectedDate.adding(days: 1))
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
            }
        }
        .sheet(item: $editorSession) { session in
            BlockEditorSheet(title: session.title, draft: session.draft) { draft in
                do {
                    try store.saveBlockDraft(draft, for: store.selectedDate)
                } catch {
                    store.lastErrorMessage = error.localizedDescription
                }
            }
        }
        .confirmationDialog(
            "Cancel this block?",
            isPresented: $showingCancelConfirmation,
            titleVisibility: .visible
        ) {
            if let blockID = store.selectedBlockID {
                Button("Cancel Block", role: .destructive) {
                    store.cancelBlock(on: store.selectedDate, blockID: blockID)
                }
            }
        } message: {
            Text("This keeps history but removes the block from the active plan and collapses its descendants.")
        }
        .task(id: store.selectedDate) {
            store.ensureMaterialized(for: store.selectedDate)
        }
    }

    private func beginEditing(_ block: BlockDetailModel) {
        guard let sourceBlock = store.persistedBlock(on: store.selectedDate, blockID: block.id) else { return }
        editorSession = BlockEditorSession(
            title: "Edit Block",
            draft: .editing(detail: block, sourceBlock: sourceBlock)
        )
    }

    private func beginOverlayCreation(for block: BlockDetailModel) {
        guard !block.isBlank else { return }
        editorSession = BlockEditorSession(
            title: "New Overlay",
            draft: .overlay(parentBlockID: block.id, layerIndex: block.layerIndex + 1)
        )
    }

    private func beginBaseCreation(from block: BlockDetailModel) {
        var draft = BlockDraft.base(startMinute: block.startMinuteOfDay, endMinute: block.endMinuteOfDay)
        draft.title = "New Block"
        editorSession = BlockEditorSession(
            title: "New Base Block",
            draft: draft
        )
    }
}

private struct TodayTimelineView: View {
    let model: TodayScreenModel
    let selectedBlockID: UUID?
    let currentMinute: Int?
    let onSelect: (UUID?) -> Void

    private let hourHeight: CGFloat = 76
    private let labelWidth: CGFloat = 48

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        hourGrid
                        if let currentMinute {
                            currentTimeLine(minute: currentMinute, canvasWidth: geometry.size.width)
                        }

                        ForEach(model.blocks) { block in
                            timelineBlock(block, canvasWidth: geometry.size.width)
                        }
                    }
                    .frame(width: geometry.size.width, height: 24 * hourHeight, alignment: .topLeading)
                }
                .frame(height: 24 * hourHeight)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .task(id: model.initialScrollMinute) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(anchorHour(for: model.initialScrollMinute), anchor: .top)
                }
            }
        }
    }

    private var hourGrid: some View {
        ForEach(0 ... 24, id: \.self) { hour in
            let y = CGFloat(hour) * hourHeight
            HStack(spacing: 0) {
                Text(String(format: "%02d:00", hour == 24 ? 23 : hour))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth, alignment: .leading)
                    .offset(y: -8)

                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 1)
            }
            .frame(height: 1)
            .offset(y: y)
            .id(hour)
        }
    }

    private func currentTimeLine(minute: Int, canvasWidth: CGFloat) -> some View {
        let y = CGFloat(minute) / 60.0 * hourHeight
        return HStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .offset(x: labelWidth - 4)
            Rectangle()
                .fill(.red)
                .frame(height: 2)
        }
        .frame(width: canvasWidth, alignment: .leading)
        .offset(y: y)
    }

    private func timelineBlock(_ block: TimelineBlockItem, canvasWidth: CGFloat) -> some View {
        let y = CGFloat(block.startMinuteOfDay) / 60.0 * hourHeight
        let height = max(CGFloat(block.endMinuteOfDay - block.startMinuteOfDay) / 60.0 * hourHeight, 40)
        let xInset = CGFloat(block.layerIndex) * 18
        let blockWidth = max(180, canvasWidth - labelWidth - 36 - xInset)

        return Button {
            onSelect(block.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(block.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text("L\(block.layerIndex)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("\(block.startMinuteOfDay.formattedTime) - \(block.endMinuteOfDay.formattedTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if block.incompleteTaskCount > 0 {
                    Text("\(block.incompleteTaskCount) tasks")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height, alignment: .topLeading)
            .background(background(for: block), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selectedBlockID == block.id ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .frame(width: blockWidth, alignment: .leading)
        .offset(x: labelWidth + 8 + xInset, y: y)
    }

    private func background(for block: TimelineBlockItem) -> some ShapeStyle {
        if block.isBlank {
            return AnyShapeStyle(Color.secondary.opacity(0.12))
        }

        switch block.layerIndex {
        case 0:
            return AnyShapeStyle(.thinMaterial)
        case 1:
            return AnyShapeStyle(Color.accentColor.opacity(0.16))
        default:
            return AnyShapeStyle(Color.accentColor.opacity(0.10))
        }
    }

    private func anchorHour(for minute: Int) -> Int {
        max(0, min(23, minute / 60))
    }
}

private struct BlockDetailPanel: View {
    let block: BlockDetailModel
    let onEdit: () -> Void
    let onAddOverlay: () -> Void
    let onCreateBase: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.title)
                        .font(.headline)
                    Text("\(block.startMinuteOfDay.formattedTime) - \(block.endMinuteOfDay.formattedTime)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("L\(block.layerIndex)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let note = block.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !block.tasks.isEmpty {
                ForEach(block.tasks.prefix(3)) { task in
                    HStack(spacing: 8) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        Text(task.title)
                            .font(.footnote)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                if block.isBlank {
                    Button {
                        onCreateBase()
                    } label: {
                        Label("Create Base Block", systemImage: "plus.rectangle.on.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Edit", action: onEdit)
                        .buttonStyle(.borderedProminent)
                    Button("Add Overlay", action: onAddOverlay)
                        .buttonStyle(.bordered)
                    Button("Cancel", role: .destructive, action: onCancel)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct BlockEditorSession: Identifiable {
    let id = UUID()
    let title: String
    let draft: BlockDraft
}
