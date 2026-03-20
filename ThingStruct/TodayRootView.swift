import SwiftUI

struct TodayRootView: View {
    @Environment(ThingStructStore.self) private var store
    @State private var editorSession: BlockEditorSession?
    @State private var jumpToCurrentTrigger = 0

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
                        let currentMinute = store.selectedDate == LocalDay.today() ? store.minuteOfDay(for: .now) : nil
                        let currentActiveBlockID = store.selectedDate == LocalDay.today() ? store.currentActiveBlockID() : nil

                        TodayTimelineView(
                            model: model,
                            selectedBlockID: effectiveSelectedBlockID,
                            currentMinute: currentMinute,
                            currentActiveBlockID: currentActiveBlockID,
                            jumpToCurrentTrigger: jumpToCurrentTrigger,
                            resizeBounds: { blockID in
                                store.resizeBounds(on: store.selectedDate, blockID: blockID)
                            },
                            onResizeBlock: { blockID, proposedEndMinuteOfDay in
                                store.resizeBlockEnd(
                                    on: store.selectedDate,
                                    blockID: blockID,
                                    proposedEndMinuteOfDay: proposedEndMinuteOfDay
                                )
                            },
                            onSelect: { blockID in
                                store.selectBlock(blockID)
                            }
                        )

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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        selectDate(store.selectedDate.adding(days: -1))
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text(store.selectedDate.titleText)
                        .font(.headline.weight(.semibold))
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if store.selectedDate == .today() {
                        Button {
                            jumpToCurrent()
                        } label: {
                            Image(systemName: "location")
                        }
                    } else {
                        Button("Today") {
                            selectDate(.today())
                        }
                    }

                    Button {
                        editorSession = BlockEditorSession(
                            title: "New Base Block",
                            draft: .base()
                        )
                    } label: {
                        Image(systemName: "plus")
                    }

                    Button {
                        selectDate(store.selectedDate.adding(days: 1))
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
            }
        }
        .sheet(item: $editorSession) { session in
            BlockEditorSheet(title: session.title, draft: session.draft) { draft in
                do {
                    let savedBlockID = try store.saveBlockDraft(draft, for: store.selectedDate)
                    store.selectBlock(savedBlockID)
                } catch {
                    store.lastErrorMessage = error.localizedDescription
                }
            } onCancelBlock: {
                guard let blockID = session.cancelBlockID else { return }
                store.cancelBlock(on: store.selectedDate, blockID: blockID)
            }
        }
        .sheet(isPresented: detailSheetIsPresented) {
            TodayBlockDetailSheet()
                .environment(store)
        }
        .task(id: store.selectedDate) {
            store.ensureMaterialized(for: store.selectedDate)
            guard store.selectedBlockID == nil else { return }

            if let model = try? store.todayScreenModel() {
                store.selectBlock(model.initialFocusBlockID)
            }
        }
    }

    private func selectDate(_ date: LocalDay) {
        store.selectDate(date)
    }

    private func jumpToCurrent() {
        if let currentBlockID = store.currentActiveBlockID() {
            store.selectBlock(currentBlockID)
        }

        jumpToCurrentTrigger += 1
    }

    private var detailSheetIsPresented: Binding<Bool> {
        Binding(
            get: { selectedBlockDetail != nil },
            set: { isPresented in
                if !isPresented {
                    store.selectBlock(nil)
                }
            }
        )
    }

    private var selectedBlockDetail: BlockDetailModel? {
        guard store.isLoaded, let selectedBlockID = store.selectedBlockID else {
            return nil
        }

        return try? store.blockDetail(for: store.selectedDate, blockID: selectedBlockID)
    }
}

private struct TodayTimelineView: View {
    let model: TodayScreenModel
    let selectedBlockID: UUID?
    let currentMinute: Int?
    let currentActiveBlockID: UUID?
    let jumpToCurrentTrigger: Int
    let resizeBounds: (UUID) -> BlockResizeBounds?
    let onResizeBlock: (UUID, Int) -> Void
    let onSelect: (UUID?) -> Void

    @State private var lastInitialScrollDate: LocalDay?
    @State private var resizePreview: TimelineResizePreview?

    private let hourHeight: CGFloat = 76
    private let labelWidth: CGFloat = 52
    private let timelineTopInset: CGFloat = 12
    private let trackInset: CGFloat = 12

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        hourGrid
                        if let currentMinute {
                            currentTimeLine(minute: currentMinute, canvasWidth: geometry.size.width)
                        }

                        ForEach(rootNodes) { node in
                            timelineBlock(node, canvasWidth: geometry.size.width)
                        }
                    }
                    .frame(width: geometry.size.width, height: canvasHeight, alignment: .topLeading)
                }
                .frame(height: canvasHeight)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .task(id: model.date) {
                guard lastInitialScrollDate != model.date else { return }
                lastInitialScrollDate = model.date

                if let currentMinute, let currentActiveBlockID {
                    scroll(
                        toBlock: currentActiveBlockID,
                        fallbackMinute: currentMinute,
                        anchor: .center,
                        proxy: proxy,
                        animated: false
                    )
                } else if let currentMinute {
                    scroll(to: currentMinute, anchor: .center, proxy: proxy, animated: false)
                } else {
                    scroll(to: model.initialScrollMinute, anchor: .top, proxy: proxy, animated: false)
                }
            }
            .onChange(of: jumpToCurrentTrigger) { _, _ in
                guard let currentMinute else { return }
                if let currentActiveBlockID {
                    scroll(
                        toBlock: currentActiveBlockID,
                        fallbackMinute: currentMinute,
                        anchor: .center,
                        proxy: proxy,
                        animated: true
                    )
                } else {
                    scroll(to: currentMinute, anchor: .center, proxy: proxy, animated: true)
                }
            }
        }
    }

    private var hourGrid: some View {
        ForEach(0 ... 24, id: \.self) { hour in
            let y = timelineTopInset + CGFloat(hour) * hourHeight
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
        let y = yPosition(for: minute)
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

    private func timelineBlock(_ node: TodayTimelineNode, canvasWidth: CGFloat) -> some View {
        let y = yPosition(for: node.block.startMinuteOfDay)
        let blockWidth = max(0, canvasWidth - labelWidth - trackInset * 2)

        return TimelineBlockCard(
            node: node,
            hourHeight: hourHeight,
            selectedBlockID: selectedBlockID,
            selectedPathIDs: selectedPathIDs,
            displayedEndMinuteOfDay: displayedEndMinute(for: node.block),
            endMinuteResolver: displayedEndMinute(for:),
            resizingBlockID: resizePreview?.blockID,
            onResizeStart: beginResize(for:),
            onResizeChange: updateResizePreview(for:verticalTranslation:),
            onResizeEnd: commitResize(for:),
            onSelect: onSelect
        )
        .frame(width: blockWidth, alignment: .leading)
        .offset(x: labelWidth + trackInset, y: y)
    }

    private var canvasHeight: CGFloat {
        24 * hourHeight + timelineTopInset * 2
    }

    private var blocksByID: [UUID: TimelineBlockItem] {
        Dictionary(uniqueKeysWithValues: model.blocks.map { ($0.id, $0) })
    }

    private var rootNodes: [TodayTimelineNode] {
        let childrenByParent = Dictionary(grouping: model.blocks.filter { $0.parentBlockID != nil }) { $0.parentBlockID! }
            .mapValues { $0.sorted(by: timelineNodeSort) }

        func buildNode(for block: TimelineBlockItem) -> TodayTimelineNode {
            TodayTimelineNode(
                block: block,
                children: (childrenByParent[block.id] ?? []).map(buildNode)
            )
        }

        return model.blocks
            .filter { $0.parentBlockID == nil }
            .sorted(by: timelineNodeSort)
            .map(buildNode)
    }

    private var selectedPathIDs: Set<UUID> {
        guard let selectedBlockID else { return [] }

        var path = Set([selectedBlockID])
        var cursor = blocksByID[selectedBlockID]?.parentBlockID

        while let parentID = cursor {
            path.insert(parentID)
            cursor = blocksByID[parentID]?.parentBlockID
        }

        return path
    }

    private func yPosition(for minute: Int) -> CGFloat {
        timelineTopInset + CGFloat(minute) / 60.0 * hourHeight
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

    private func scroll(to minute: Int, anchor: UnitPoint, proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(anchorHour(for: minute), anchor: anchor)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                action()
            }
        } else {
            action()
        }
    }

    private func scroll(
        toBlock blockID: UUID,
        fallbackMinute: Int,
        anchor: UnitPoint,
        proxy: ScrollViewProxy,
        animated: Bool
    ) {
        let action = {
            if blocksByID[blockID] != nil {
                proxy.scrollTo(blockID, anchor: anchor)
            } else {
                proxy.scrollTo(anchorHour(for: fallbackMinute), anchor: anchor)
            }
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                action()
            }
        } else {
            action()
        }
    }

    private func timelineNodeSort(_ lhs: TimelineBlockItem, _ rhs: TimelineBlockItem) -> Bool {
        if lhs.startMinuteOfDay != rhs.startMinuteOfDay {
            return lhs.startMinuteOfDay < rhs.startMinuteOfDay
        }
        if lhs.layerIndex != rhs.layerIndex {
            return lhs.layerIndex < rhs.layerIndex
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func displayedEndMinute(for block: TimelineBlockItem) -> Int {
        resizePreview?.blockID == block.id ? resizePreview?.proposedEndMinuteOfDay ?? block.endMinuteOfDay : block.endMinuteOfDay
    }

    private func beginResize(for blockID: UUID) {
        guard resizePreview?.blockID != blockID else { return }
        guard let bounds = resizeBounds(blockID) else { return }

        resizePreview = TimelineResizePreview(
            blockID: blockID,
            currentEndMinuteOfDay: bounds.endMinuteOfDay,
            minimumEndMinuteOfDay: bounds.minimumEndMinuteOfDay,
            maximumEndMinuteOfDay: bounds.maximumEndMinuteOfDay,
            proposedEndMinuteOfDay: bounds.endMinuteOfDay
        )
    }

    private func updateResizePreview(for blockID: UUID, verticalTranslation: CGFloat) {
        guard var resizePreview, resizePreview.blockID == blockID else { return }

        let deltaMinutes = Int((verticalTranslation / hourHeight) * 60.0)
        let proposedEndMinuteOfDay = resizePreview.currentEndMinuteOfDay + deltaMinutes
        resizePreview.proposedEndMinuteOfDay = proposedEndMinuteOfDay.aligned(
            toStep: 5,
            within: resizePreview.minimumEndMinuteOfDay ... resizePreview.maximumEndMinuteOfDay
        ) ?? resizePreview.proposedEndMinuteOfDay
        self.resizePreview = resizePreview
    }

    private func commitResize(for blockID: UUID) {
        guard let resizePreview, resizePreview.blockID == blockID else { return }
        defer { self.resizePreview = nil }

        guard resizePreview.proposedEndMinuteOfDay != resizePreview.currentEndMinuteOfDay else {
            return
        }

        onResizeBlock(blockID, resizePreview.proposedEndMinuteOfDay)
    }
}

private struct TodayTimelineNode: Identifiable {
    let block: TimelineBlockItem
    let children: [TodayTimelineNode]

    var id: UUID { block.id }
}

private struct TimelineResizePreview {
    let blockID: UUID
    let currentEndMinuteOfDay: Int
    let minimumEndMinuteOfDay: Int
    let maximumEndMinuteOfDay: Int
    var proposedEndMinuteOfDay: Int
}

private struct TimelineBlockCard: View {
    let node: TodayTimelineNode
    let hourHeight: CGFloat
    let selectedBlockID: UUID?
    let selectedPathIDs: Set<UUID>
    let displayedEndMinuteOfDay: Int
    let endMinuteResolver: (TimelineBlockItem) -> Int
    let resizingBlockID: UUID?
    let onResizeStart: (UUID) -> Void
    let onResizeChange: (UUID, CGFloat) -> Void
    let onResizeEnd: (UUID) -> Void
    let onSelect: (UUID?) -> Void

    private let minimumHeight: CGFloat = 52
    private let childInset: CGFloat = 16
    private let childGap: CGFloat = 8

    private var block: TimelineBlockItem { node.block }

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(layerIndex: block.layerIndex, isBlank: block.isBlank)
    }

    private var isSelected: Bool {
        selectedBlockID == block.id
    }

    private var isSelectedAncestor: Bool {
        selectedPathIDs.contains(block.id) && !isSelected
    }

    private var isResizing: Bool {
        resizingBlockID == block.id
    }

    private var cardHeight: CGFloat {
        max(CGFloat(displayedEndMinuteOfDay - block.startMinuteOfDay) / 60.0 * hourHeight, minimumHeight)
    }

    private var badgeTitle: String {
        if block.isBlank {
            return "Open"
        }

        return block.parentBlockID == nil ? "Base" : "Overlay"
    }

    private var taskSummary: String? {
        guard !block.isBlank, block.incompleteTaskCount > 0 else {
            return nil
        }

        return block.incompleteTaskCount == 1 ? "1 task" : "\(block.incompleteTaskCount) tasks"
    }

    private var headerReservedHeight: CGFloat {
        block.isBlank ? 38 : 58
    }

    private var headerBackdropHeight: CGFloat {
        min(cardHeight, headerReservedHeight + 22)
    }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(block.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Text(badgeTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(style.badgeForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(style.badgeBackground, in: Capsule())
            }

            if !block.isBlank {
                Text("\(block.startMinuteOfDay.formattedTime) - \(displayedEndMinuteOfDay.formattedTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let taskSummary {
                    Text(taskSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    backgroundColor,
                    backgroundColor,
                    backgroundColor.opacity(0.96),
                    backgroundColor.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: headerBackdropHeight)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let childHorizontalInset = min(childInset, max(8, geometry.size.width * 0.12))
            let childWidth = max(geometry.size.width - childHorizontalInset * 2, 1)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(backgroundColor)

                ForEach(node.children) { child in
                    let childDisplayedEndMinuteOfDay = endMinuteResolver(child.block)
                    let childHeight = max(
                        CGFloat(childDisplayedEndMinuteOfDay - child.block.startMinuteOfDay) / 60.0 * hourHeight,
                        minimumHeight
                    )
                    TimelineBlockCard(
                        node: child,
                        hourHeight: hourHeight,
                        selectedBlockID: selectedBlockID,
                        selectedPathIDs: selectedPathIDs,
                        displayedEndMinuteOfDay: childDisplayedEndMinuteOfDay,
                        endMinuteResolver: endMinuteResolver,
                        resizingBlockID: resizingBlockID,
                        onResizeStart: onResizeStart,
                        onResizeChange: onResizeChange,
                        onResizeEnd: onResizeEnd,
                        onSelect: onSelect
                    )
                    .frame(width: childWidth)
                    .offset(
                        x: childHorizontalInset,
                        y: childYOffset(for: child, childHeight: childHeight)
                    )
                }

                headerContent
                    .zIndex(1)

                if !block.isBlank {
                    VStack {
                        Spacer(minLength: 0)
                        resizeHandle
                    }
                    .padding(.bottom, 8)
                    .zIndex(2)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(
                color: (isSelected || isResizing) ? style.accent.opacity(0.18) : .clear,
                radius: 10,
                y: 4
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .gesture(
                TapGesture().onEnded {
                    onSelect(block.id)
                },
                including: .gesture
            )
        }
        .frame(height: cardHeight)
        .id(block.id)
    }

    private var backgroundColor: Color {
        if isResizing {
            return style.strongSurface
        }

        if isSelected {
            return style.strongSurface
        }

        if isSelectedAncestor {
            return style.surface.opacity(0.94)
        }

        return node.children.isEmpty ? style.surface : style.surface.opacity(0.9)
    }

    private var borderColor: Color {
        if isResizing {
            return style.accent
        }

        if isSelected {
            return style.accent
        }

        if isSelectedAncestor {
            return style.accent.opacity(0.45)
        }

        return style.border
    }

    private var borderWidth: CGFloat {
        if isResizing {
            return 2.5
        }

        if isSelected {
            return 2.5
        }

        if isSelectedAncestor {
            return 1.5
        }

        return 1
    }

    private func childYOffset(for child: TodayTimelineNode, childHeight: CGFloat) -> CGFloat {
        let relative = CGFloat(child.block.startMinuteOfDay - block.startMinuteOfDay) / 60.0 * hourHeight
        let desiredTop = headerReservedHeight + childGap
        let availableShift = max(0, cardHeight - childHeight - childGap - relative)
        let shift = min(max(0, desiredTop - relative), availableShift)
        return relative + shift
    }

    private var resizeHandle: some View {
        RoundedRectangle(cornerRadius: 999, style: .continuous)
            .fill(isResizing ? style.accent : style.marker.opacity(0.82))
            .frame(width: isResizing ? 44 : 32, height: 5)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(resizeGesture)
            .accessibilityLabel("Resize block")
    }

    private var resizeGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .first(true):
                    onResizeStart(block.id)

                case .second(true, let drag?):
                    onResizeChange(block.id, drag.translation.height)

                default:
                    break
                }
            }
            .onEnded { _ in
                onResizeEnd(block.id)
            }
    }
}

private struct TodayBlockDetailSheet: View {
    @Environment(ThingStructStore.self) private var store
    @State private var editorSession: BlockEditorSession?

    private var block: BlockDetailModel? {
        guard let selectedBlockID = store.selectedBlockID else {
            return nil
        }

        return try? store.blockDetail(for: store.selectedDate, blockID: selectedBlockID)
    }

    var body: some View {
        Group {
            if let block {
                TodayBlockDetailContent(
                    block: block,
                    onEdit: { beginEditing(block) },
                    onAddOverlay: { beginOverlayCreation(for: block) },
                    onCreateBase: { beginBaseCreation(from: block) }
                )
            } else {
                Color.clear
            }
        }
        .presentationDetents([.height(272), .medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .sheet(item: $editorSession) { session in
            BlockEditorSheet(title: session.title, draft: session.draft) { draft in
                do {
                    let savedBlockID = try store.saveBlockDraft(draft, for: store.selectedDate)
                    store.selectBlock(savedBlockID)
                } catch {
                    store.lastErrorMessage = error.localizedDescription
                }
            } onCancelBlock: {
                guard let blockID = session.cancelBlockID else { return }
                store.cancelBlock(on: store.selectedDate, blockID: blockID)
            }
        }
    }

    private func beginEditing(_ block: BlockDetailModel) {
        guard let sourceBlock = store.persistedBlock(on: store.selectedDate, blockID: block.id) else { return }

        editorSession = BlockEditorSession(
            title: "Edit Block",
            draft: .editing(detail: block, sourceBlock: sourceBlock),
            cancelBlockID: block.id
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

private struct TodayBlockDetailContent: View {
    let block: BlockDetailModel
    let onEdit: () -> Void
    let onAddOverlay: () -> Void
    let onCreateBase: () -> Void

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(layerIndex: block.layerIndex, isBlank: block.isBlank)
    }

    private var badgeTitle: String {
        if block.isBlank {
            return "Open"
        }

        return block.parentBlockID == nil ? "Base" : "Overlay"
    }

    private var normalizedNote: String? {
        let trimmed = block.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard
                actionRow

                if let normalizedNote {
                    detailSection(title: "Note") {
                        Text(normalizedNote)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if block.isBlank {
                    detailSection(title: "Open Time") {
                        Text("This part of the day is currently unassigned. Create a base block here to anchor the schedule.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if !block.tasks.isEmpty {
                    detailSection(title: "Tasks") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(block.tasks) { task in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(task.isCompleted ? .secondary : style.accent)

                                    Text(task.title)
                                        .font(.body)
                                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                                        .strikethrough(task.isCompleted, color: .secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if let parentTitle = block.parentBlockTitle {
                        Label("Inside \(parentTitle)", systemImage: "arrow.turn.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(style.accent)
                    }

                    Text(block.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("\(block.startMinuteOfDay.formattedTime) - \(block.endMinuteOfDay.formattedTime)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text(badgeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(style.badgeForeground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(style.badgeBackground, in: Capsule())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(style.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var actionRow: some View {
        if block.isBlank {
            Button {
                onCreateBase()
            } label: {
                Label("Create Base Block", systemImage: "plus.rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else {
            HStack(spacing: 10) {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onAddOverlay()
                } label: {
                    Label("Add Overlay", systemImage: "square.stack.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct BlockEditorSession: Identifiable {
    let id = UUID()
    let title: String
    let draft: BlockDraft
    var cancelBlockID: UUID? = nil
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
        currentActiveBlockID: model.selectedBlock?.id,
        jumpToCurrentTrigger: 0,
        resizeBounds: { _ in nil },
        onResizeBlock: { _, _ in },
        onSelect: { _ in }
    )
}

#Preview("Today Timeline - Blank") {
    let model = PreviewSupport.todayModel(document: ThingStructDocument(), currentMinute: nil)
    TodayTimelineView(
        model: model,
        selectedBlockID: nil,
        currentMinute: nil,
        currentActiveBlockID: nil,
        jumpToCurrentTrigger: 0,
        resizeBounds: { _ in nil },
        onResizeBlock: { _, _ in },
        onSelect: { _ in }
    )
}

#Preview("Today Timeline - Historical Day") {
    let day = PreviewSupport.referenceDay.adding(days: -1)
    let document = PreviewSupport.seededDocument(on: day)
    let model = try! ThingStructPresentation.todayScreenModel(
        document: document,
        date: day,
        selectedBlockID: nil,
        currentMinute: nil
    )
    TodayTimelineView(
        model: model,
        selectedBlockID: model.selectedBlock?.id,
        currentMinute: nil,
        currentActiveBlockID: nil,
        jumpToCurrentTrigger: 0,
        resizeBounds: { _ in nil },
        onResizeBlock: { _, _ in },
        onSelect: { _ in }
    )
}

#Preview("Today Detail Content") {
    TodayBlockDetailContent(
        block: PreviewSupport.selectedBlockDetailModel(),
        onEdit: {},
        onAddOverlay: {},
        onCreateBase: {}
    )
    .padding()
}

#Preview("Today Detail Content - Blank") {
    TodayBlockDetailContent(
        block: PreviewSupport.blankBlockDetailModel(),
        onEdit: {},
        onAddOverlay: {},
        onCreateBase: {}
    )
    .padding()
}
