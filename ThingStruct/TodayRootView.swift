import SwiftUI

struct TodayRootView: View {
    @Environment(ThingStructStore.self) private var store
    @State private var editorSession: BlockEditorSession?
    @State private var pendingCancelBlockID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if !store.isLoaded {
                    ScreenLoadingView(
                        title: "Loading Today",
                        systemImage: "calendar",
                        description: "Preparing your timeline and current context."
                    )
                } else {
                    let result = Result { try store.todayScreenModel() }

                    switch result {
                    case let .success(model):
                        let effectiveSelectedBlockID = store.selectedBlockID ?? model.initialFocusBlockID

                        TodayTimelineView(
                            model: model,
                            selectedBlockID: effectiveSelectedBlockID,
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
                                        pendingCancelBlockID = selectedBlock.id
                                    }
                                )
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                            }
                        }

                    case let .failure(error):
                        RecoverableErrorView(
                            title: "Unable to Load Today",
                            message: error.localizedDescription
                        ) {
                            store.reload()
                        }
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
            isPresented: Binding(
                get: { pendingCancelBlockID != nil },
                set: { if !$0 { pendingCancelBlockID = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let blockID = pendingCancelBlockID {
                Button("Cancel Block", role: .destructive) {
                    store.cancelBlock(on: store.selectedDate, blockID: blockID)
                    pendingCancelBlockID = nil
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
            .overlay(alignment: .bottomTrailing) {
                if let currentMinute {
                    Button {
                        scroll(to: currentMinute, anchor: .center, proxy: proxy)
                    } label: {
                        Image(systemName: "location.fill")
                            .imageScale(.large)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .accessibilityLabel("Jump to Current Time")
                }
            }
            .task(id: model.initialScrollMinute) {
                scroll(to: model.initialScrollMinute, anchor: .top, proxy: proxy)
            }
        }
    }

    private var hourGrid: some View {
        ForEach(0 ... 24, id: \.self) { hour in
            let y = CGFloat(hour) * hourHeight
            HStack(spacing: 0) {
                Text(hourLabel(for: hour))
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
        let blockWidth = max(0, canvasWidth - labelWidth - 20 - xInset)
        let style = LayerVisualStyle.forBlock(layerIndex: block.layerIndex, isBlank: block.isBlank)

        return Button {
            onSelect(block.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(block.title)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text("L\(block.layerIndex)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(style.badgeForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(style.badgeBackground, in: Capsule())
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
            .background(style.strongSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        selectedBlockID == block.id ? style.accent : style.border,
                        style: StrokeStyle(lineWidth: selectedBlockID == block.id ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .frame(width: blockWidth, alignment: .leading)
        .offset(x: labelWidth + 8 + xInset, y: y)
    }

    private func anchorHour(for minute: Int) -> Int {
        max(0, min(23, minute / 60))
    }

    private func hourLabel(for hour: Int) -> String {
        if hour == 24 {
            return "24:00"
        }

        return String(format: "%02d:00", hour)
    }

    private func scroll(to minute: Int, anchor: UnitPoint, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(anchorHour(for: minute), anchor: anchor)
        }
    }
}

private struct BlockDetailPanel: View {
    let block: BlockDetailModel
    let onEdit: () -> Void
    let onAddOverlay: () -> Void
    let onCreateBase: () -> Void
    let onCancel: () -> Void

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(layerIndex: block.layerIndex, isBlank: block.isBlank)
    }

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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(style.badgeForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(style.badgeBackground, in: Capsule())
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

                if block.tasks.count > 3 {
                    Text("+\(block.tasks.count - 3) more tasks")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                horizontalActions
                verticalActions
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(style.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var horizontalActions: some View {
        HStack(spacing: 10) {
            if block.isBlank {
                createBaseButton
            } else {
                editButton
                addOverlayButton
                cancelButton
            }
        }
    }

    @ViewBuilder
    private var verticalActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if block.isBlank {
                createBaseButton
            } else {
                editButton
                addOverlayButton
                cancelButton
            }
        }
    }

    private var createBaseButton: some View {
        Button {
            onCreateBase()
        } label: {
            Label("Create Base Block", systemImage: "plus.rectangle.on.rectangle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private var editButton: some View {
        Button("Edit", action: onEdit)
            .buttonStyle(.borderedProminent)
    }

    private var addOverlayButton: some View {
        Button("Add Overlay", action: onAddOverlay)
            .buttonStyle(.bordered)
    }

    private var cancelButton: some View {
        Button("Cancel", role: .destructive, action: onCancel)
            .buttonStyle(.bordered)
    }
}

private struct BlockEditorSession: Identifiable {
    let id = UUID()
    let title: String
    let draft: BlockDraft
}

#Preview("Today Root") {
    TodayRootView()
        .environment(PreviewSupport.store(tab: .today))
}

#Preview("Today Root - Empty Day") {
    TodayRootView()
        .environment(
            PreviewSupport.store(
                tab: .today,
                document: ThingStructDocument()
            )
        )
}

#Preview("Today Root - Loading") {
    TodayRootView()
        .environment(PreviewSupport.store(tab: .today, loaded: false))
}

#Preview("Today Timeline") {
    let model = PreviewSupport.todayModel()
    TodayTimelineView(
        model: model,
        selectedBlockID: model.selectedBlock?.id,
        currentMinute: 9 * 60 + 30,
        onSelect: { _ in }
    )
}

#Preview("Today Timeline - Blank") {
    let model = PreviewSupport.todayModel(document: ThingStructDocument(), currentMinute: nil)
    TodayTimelineView(
        model: model,
        selectedBlockID: nil,
        currentMinute: nil,
        onSelect: { _ in }
    )
}

#Preview("Block Detail Panel") {
    BlockDetailPanel(
        block: PreviewSupport.selectedBlockDetailModel(),
        onEdit: {},
        onAddOverlay: {},
        onCreateBase: {},
        onCancel: {}
    )
    .padding()
}

#Preview("Block Detail Panel - Blank") {
    BlockDetailPanel(
        block: PreviewSupport.blankBlockDetailModel(),
        onEdit: {},
        onAddOverlay: {},
        onCreateBase: {},
        onCancel: {}
    )
    .padding()
}
