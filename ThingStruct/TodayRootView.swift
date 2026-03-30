import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TodayRootView: View {
    @Environment(ThingStructStore.self) private var store

    @State private var editorSession: BlockEditorSession?
    @State private var selection: TodaySelection = .none
    @State private var pendingCancellationBlockID: UUID?
    @State private var jumpToCurrentTrigger = 0
    @State private var scrollToBlockTrigger = 0
    @State private var scrollToBlockID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if !store.isLoaded {
                    ScreenLoadingView(
                        title: "Loading Today",
                        systemImage: "calendar",
                        description: "Preparing your timeline and current context."
                    )
                } else if store.requiresTemplateSelection(for: store.selectedDate) {
                    TodayTemplateChooserView(date: store.selectedDate)
                } else {
                    RootScreenContainer(
                        isLoaded: true,
                        loadingTitle: "Loading Today",
                        loadingSystemImage: "calendar",
                        loadingDescription: "Preparing your timeline and current context.",
                        errorTitle: "Unable to Load Today",
                        retry: store.reload
                    ) {
                        try store.todayScreenModel()
                    } content: { model in
                        timelineContent(model: model)
                    }
                }
            }
            .navigationTitle(store.selectedDate.titleText)
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $editorSession) { session in
            TodayBlockEditorPresenter(session: session) { savedBlockID, shouldScrollToSavedBlock in
                handleSavedBlock(
                    savedBlockID,
                    shouldScrollToSavedBlock: shouldScrollToSavedBlock
                )
            }
        }
        .confirmationDialog(
            "Cancel this block?",
            isPresented: Binding(
                get: { pendingCancellationBlockID != nil },
                set: { if !$0 { pendingCancellationBlockID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Cancel Block", role: .destructive) {
                confirmCancellation()
            }

            Button("Keep Block", role: .cancel) {
                pendingCancellationBlockID = nil
            }
        } message: {
            Text("This block will be removed from today’s running plan.")
        }
        .onChange(of: store.selectedDate) { _, _ in
            pendingCancellationBlockID = nil
            selection = store.selectedBlockID.map { .block(id: $0, panel: .compact) } ?? .none
        }
        .onChange(of: store.selectedBlockID) { _, newValue in
            guard let blockID = newValue else { return }
            selection = .block(id: blockID, panel: .compact)
        }
        .onChange(of: store.selectedTab) { _, newValue in
            guard newValue != .today else { return }
            selection = .none
            pendingCancellationBlockID = nil
        }
    }

    private func timelineContent(model: TodayScreenModel) -> some View {
        TodayTimelineView(
            model: model,
            selectedBlockID: selection.blockID,
            selectedOpenSlotID: selection.openSlotID,
            isAdjustingTime: selection.panelState == .adjustingTime,
            currentMinute: store.currentMinuteOnSelectedDate(),
            jumpToCurrentTrigger: jumpToCurrentTrigger,
            scrollToBlockID: scrollToBlockID,
            scrollToBlockTrigger: scrollToBlockTrigger,
            timingResolver: { blockID in
                store.persistedBlock(on: store.selectedDate, blockID: blockID)?.timing
            },
            resizeBounds: { blockID in
                store.resizeBounds(on: store.selectedDate, blockID: blockID)
            },
            onResizeBlockStart: { blockID, proposedStartMinuteOfDay in
                store.resizeBlockStart(
                    on: store.selectedDate,
                    blockID: blockID,
                    proposedStartMinuteOfDay: proposedStartMinuteOfDay
                )
            },
            onResizeBlockEnd: { blockID, proposedEndMinuteOfDay in
                store.resizeBlockEnd(
                    on: store.selectedDate,
                    blockID: blockID,
                    proposedEndMinuteOfDay: proposedEndMinuteOfDay
                )
            },
            onSelectBlock: handleBlockSelection,
            onSelectOpenSlot: handleOpenSlotSelection,
            onClearSelection: clearSelection
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inspector(for: model)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    store.moveSelectedDate(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
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
                        store.selectDate(.today())
                    }
                }

                Menu {
                    ForEach(model.addOptions) { option in
                        Button {
                            beginCreate(from: option)
                        } label: {
                            Label(option.title, systemImage: systemImageName(for: option.kind))
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }

                Button {
                    store.moveSelectedDate(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: selection)
        .task(id: model.date) {
            syncSelectionForDisplayedDate(using: model)
        }
        .onChange(of: model.blocks.map(\.id)) { _, _ in
            validateSelection(using: model)
        }
        .onChange(of: model.openSlots.map(\.id)) { _, _ in
            validateSelection(using: model)
        }
    }

    @ViewBuilder
    private func inspector(for model: TodayScreenModel) -> some View {
        switch selection {
        case .none:
            EmptyView()

        case let .block(id, panel):
            if let detail = selectedBlockDetail(for: id) {
                TodayDockedInspector(
                    panelState: panel,
                    onExpand: expandSelection,
                    onCollapse: collapseSelection,
                    onDismiss: clearSelection
                ) {
                    TodayBlockInspectorView(
                        detail: detail,
                        panelState: panel,
                        onSelectParent: {
                            selectParentBlock(from: detail)
                        },
                        onEdit: {
                            beginEditingBlock(id)
                        },
                        onExpand: expandSelection,
                        onAdjustTime: {
                            selection = .block(id: id, panel: .adjustingTime)
                        },
                        onFinishAdjusting: {
                            selection = .block(id: id, panel: .expanded)
                        },
                        onCancelAdjusting: {
                            selection = .block(id: id, panel: .expanded)
                        },
                        onAddOverlay: {
                            beginCreateOverlay(on: id, layerIndex: detail.layerIndex + 1)
                        },
                        onRequestCancellation: {
                            pendingCancellationBlockID = id
                        }
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let block = model.blocks.first(where: { $0.id == id }) {
                TodayDockedInspector(
                    panelState: panel,
                    onExpand: expandSelection,
                    onCollapse: collapseSelection,
                    onDismiss: clearSelection
                ) {
                    TodayUnavailableInspectorView(
                        title: block.title,
                        startMinuteOfDay: block.startMinuteOfDay,
                        endMinuteOfDay: block.endMinuteOfDay
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

        case let .openSlot(id, panel):
            if let slot = model.openSlots.first(where: { $0.id == id }) {
                TodayDockedInspector(
                    panelState: panel,
                    onExpand: expandSelection,
                    onCollapse: collapseSelection,
                    onDismiss: clearSelection
                ) {
                    TodayOpenSlotInspectorView(
                        slot: slot,
                        panelState: panel,
                        onAddBlock: {
                            beginCreate(in: slot)
                        },
                        onExpand: expandSelection
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func syncSelectionForDisplayedDate(using model: TodayScreenModel) {
        guard model.date == store.selectedDate else { return }

        switch selection {
        case let .block(id, panel) where model.blocks.contains(where: { $0.id == id }):
            selection = .block(id: id, panel: panel)
            store.selectBlock(id)

        case let .openSlot(id, panel) where model.openSlots.contains(where: { $0.id == id }):
            selection = .openSlot(id: id, panel: panel)
            store.selectBlock(nil)

        default:
            if let blockID = store.selectedBlockID, model.blocks.contains(where: { $0.id == blockID }) {
                selection = .block(id: blockID, panel: .compact)
            } else {
                selection = .none
            }
        }
    }

    private func validateSelection(using model: TodayScreenModel) {
        switch selection {
        case .none:
            return

        case let .block(id, _):
            guard model.blocks.contains(where: { $0.id == id }) else {
                selection = .none
                store.selectBlock(nil)
                pendingCancellationBlockID = nil
                return
            }

        case let .openSlot(id, _):
            guard model.openSlots.contains(where: { $0.id == id }) else {
                selection = .none
                pendingCancellationBlockID = nil
                return
            }
        }
    }

    private func jumpToCurrent() {
        let blockID = store.currentActiveBlockID()
        store.selectBlock(blockID)
        selection = blockID.map { .block(id: $0, panel: .compact) } ?? .none
        pendingCancellationBlockID = nil
        jumpToCurrentTrigger += 1
    }

    private func handleBlockSelection(_ blockID: UUID) {
        store.selectBlock(blockID)
        pendingCancellationBlockID = nil

        switch selection {
        case let .block(id, panel) where id == blockID:
            if panel == .compact {
                selection = .block(id: blockID, panel: .expanded)
            }

        default:
            selection = .block(id: blockID, panel: .compact)
        }
    }

    private func handleOpenSlotSelection(_ slotID: UUID) {
        store.selectBlock(nil)
        pendingCancellationBlockID = nil

        switch selection {
        case let .openSlot(id, panel) where id == slotID:
            if panel == .compact {
                selection = .openSlot(id: slotID, panel: .expanded)
            }

        default:
            selection = .openSlot(id: slotID, panel: .compact)
        }
    }

    private func clearSelection() {
        selection = .none
        store.selectBlock(nil)
        pendingCancellationBlockID = nil
    }

    private func expandSelection() {
        guard selection.panelState == .compact else { return }
        selection = selection.withPanel(.expanded)
    }

    private func collapseSelection() {
        guard selection.panelState == .expanded else { return }
        selection = selection.withPanel(.compact)
    }

    private func beginCreate(in slot: TodayOpenSlotItem) {
        var draft = BlockDraft.base(
            startMinute: slot.startMinuteOfDay,
            endMinute: slot.endMinuteOfDay
        )
        draft.title = "New Block"
        editorSession = BlockEditorSession(
            title: "New Block",
            draft: draft,
            scrollToSavedBlockOnSave: true
        )
    }

    private func beginCreate(from option: TodayAddOption) {
        switch option.kind {
        case .base:
            editorSession = BlockEditorSession(
                title: option.title,
                draft: .base(),
                scrollToSavedBlockOnSave: true
            )

        case let .overlay(parentBlockID, layerIndex):
            editorSession = BlockEditorSession(
                title: option.title,
                draft: .overlay(
                    parentBlockID: parentBlockID,
                    layerIndex: layerIndex,
                    parentResolvedRange: resolvedRange(for: parentBlockID)
                ),
                scrollToSavedBlockOnSave: true
            )
        }
    }

    private func beginEditingBlock(_ blockID: UUID) {
        store.selectBlock(blockID)
        pendingCancellationBlockID = nil

        guard
            let detail = try? store.blockDetailModel(on: store.selectedDate, blockID: blockID),
            let sourceBlock = store.persistedBlock(on: store.selectedDate, blockID: blockID)
        else {
            return
        }

        selection = .block(id: blockID, panel: .compact)
        editorSession = BlockEditorSession(
            title: "Edit Block",
            draft: .editing(
                detail: detail,
                sourceBlock: sourceBlock,
                parentResolvedRange: sourceBlock.parentBlockID.flatMap(resolvedRange(for:))
            )
        )
    }

    private func handleSavedBlock(_ blockID: UUID, shouldScrollToSavedBlock: Bool) {
        store.selectBlock(blockID)
        selection = .block(id: blockID, panel: .compact)
        pendingCancellationBlockID = nil

        guard shouldScrollToSavedBlock else { return }
        scrollToBlockID = blockID
        scrollToBlockTrigger += 1
    }

    private func beginCreateOverlay(on blockID: UUID, layerIndex: Int) {
        editorSession = BlockEditorSession(
            title: "New Overlay",
            draft: .overlay(
                parentBlockID: blockID,
                layerIndex: layerIndex,
                parentResolvedRange: resolvedRange(for: blockID)
            ),
            scrollToSavedBlockOnSave: true
        )
    }

    private func confirmCancellation() {
        guard let blockID = pendingCancellationBlockID else { return }
        pendingCancellationBlockID = nil
        selection = .none
        store.cancelBlock(on: store.selectedDate, blockID: blockID)
        store.selectBlock(nil)
    }

    private func selectParentBlock(from detail: BlockDetailModel) {
        guard let parentID = detail.parentBlockID else { return }
        store.selectBlock(parentID)
        selection = .block(id: parentID, panel: .compact)
        scrollToBlockID = nil
    }

    private func selectedBlockDetail(for blockID: UUID) -> BlockDetailModel? {
        guard let detail = try? store.blockDetailModel(on: store.selectedDate, blockID: blockID) else {
            return nil
        }
        return detail
    }

    private func systemImageName(for kind: TodayAddOptionKind) -> String {
        switch kind {
        case .base:
            return "rectangle.badge.plus"
        case .overlay:
            return "square.stack.badge.plus"
        }
    }

    private func resolvedRange(for blockID: UUID) -> (start: Int, end: Int)? {
        guard
            let block = store.persistedBlock(on: store.selectedDate, blockID: blockID),
            let start = block.resolvedStartMinuteOfDay,
            let end = block.resolvedEndMinuteOfDay
        else {
            return nil
        }

        return (start, end)
    }
}

private enum TodayPanelState: Equatable {
    case compact
    case expanded
    case adjustingTime
}

private enum TodaySelection: Equatable {
    case none
    case block(id: UUID, panel: TodayPanelState)
    case openSlot(id: UUID, panel: TodayPanelState)

    var blockID: UUID? {
        guard case let .block(id, _) = self else { return nil }
        return id
    }

    var openSlotID: UUID? {
        guard case let .openSlot(id, _) = self else { return nil }
        return id
    }

    var panelState: TodayPanelState? {
        switch self {
        case .none:
            return nil
        case let .block(_, panel), let .openSlot(_, panel):
            return panel
        }
    }

    func withPanel(_ panel: TodayPanelState) -> TodaySelection {
        switch self {
        case .none:
            return .none
        case let .block(id, _):
            return .block(id: id, panel: panel)
        case let .openSlot(id, _):
            return .openSlot(id: id, panel: panel)
        }
    }
}

private struct TodayTimelineView: View {
    let model: TodayScreenModel
    let selectedBlockID: UUID?
    let selectedOpenSlotID: UUID?
    let isAdjustingTime: Bool
    let currentMinute: Int?
    let jumpToCurrentTrigger: Int
    let scrollToBlockID: UUID?
    let scrollToBlockTrigger: Int
    let timingResolver: (UUID) -> TimeBlockTiming?
    let resizeBounds: (UUID) -> BlockResizeBounds?
    let onResizeBlockStart: (UUID, Int) -> Void
    let onResizeBlockEnd: (UUID, Int) -> Void
    let onSelectBlock: (UUID) -> Void
    let onSelectOpenSlot: (UUID) -> Void
    let onClearSelection: () -> Void

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
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onClearSelection)

                        hourGrid

                        if let currentMinute {
                            currentTimeLine(minute: currentMinute, canvasWidth: geometry.size.width)
                        }

                        ForEach(model.openSlots) { slot in
                            timelineOpenSlot(slot, canvasWidth: geometry.size.width)
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

                if let focusBlockID = model.initialFocusBlockID,
                   let fallbackMinute = currentMinute ?? model.blocks.first(where: { $0.id == focusBlockID })?.startMinuteOfDay {
                    scroll(
                        toBlock: focusBlockID,
                        fallbackMinute: fallbackMinute,
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
                if let selectedBlockID {
                    scroll(
                        toBlock: selectedBlockID,
                        fallbackMinute: currentMinute ?? model.initialScrollMinute,
                        anchor: .center,
                        proxy: proxy,
                        animated: true
                    )
                } else if let currentMinute {
                    scroll(to: currentMinute, anchor: .center, proxy: proxy, animated: true)
                }
            }
            .onChange(of: scrollToBlockTrigger) { _, _ in
                guard let scrollToBlockID else { return }
                scroll(
                    toBlock: scrollToBlockID,
                    fallbackMinute: currentMinute ?? model.initialScrollMinute,
                    anchor: .center,
                    proxy: proxy,
                    animated: true
                )
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
        let startDelta = propagatedStartDelta(
            for: node.block.id,
            timing: timingResolver(node.block.id),
            inheritedStartDelta: 0,
            resizePreview: resizePreview
        )
        let displayedStartMinuteOfDay = displayedStartMinute(
            for: node.block.id,
            originalStartMinuteOfDay: node.block.startMinuteOfDay,
            startDelta: startDelta,
            resizePreview: resizePreview
        )
        let displayedEndMinuteOfDay = displayedEndMinute(
            for: node.block.id,
            originalEndMinuteOfDay: node.block.endMinuteOfDay,
            startDelta: startDelta,
            resizePreview: resizePreview
        )
        let y = yPosition(for: displayedStartMinuteOfDay)
        let blockWidth = max(0, canvasWidth - labelWidth - trackInset * 2)

        return TimelineBlockCard(
            node: node,
            hourHeight: hourHeight,
            selectedBlockID: selectedBlockID,
            selectedPathIDs: selectedPathIDs,
            displayedStartMinuteOfDay: displayedStartMinuteOfDay,
            displayedEndMinuteOfDay: displayedEndMinuteOfDay,
            inheritedStartDelta: startDelta,
            timingResolver: timingResolver,
            resizingBlockID: resizePreview?.blockID,
            resizingEdge: resizePreview?.edge,
            resizePreview: resizePreview,
            isAdjustingTime: isAdjustingTime,
            onResizeStart: beginResize(for:edge:),
            onResizeChange: updateResizePreview(for:edge:verticalTranslation:),
            onResizeEnd: commitResize(for:edge:),
            onSelect: onSelectBlock
        )
        .frame(width: blockWidth, alignment: .leading)
        .offset(x: labelWidth + trackInset, y: y)
    }

    private func timelineOpenSlot(_ slot: TodayOpenSlotItem, canvasWidth: CGFloat) -> some View {
        let y = yPosition(for: slot.startMinuteOfDay)
        let trackWidth = max(0, canvasWidth - labelWidth - trackInset * 2)

        return TimelineOpenSlotEntry(
            slot: slot,
            hourHeight: hourHeight,
            isSelected: selectedOpenSlotID == slot.id,
            onSelect: { onSelectOpenSlot(slot.id) }
        )
        .frame(width: trackWidth, alignment: .leading)
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

    private func beginResize(for blockID: UUID, edge: TimelineResizeEdge) {
        guard resizePreview?.blockID != blockID || resizePreview?.edge != edge else { return }
        guard let bounds = resizeBounds(blockID) else { return }

        resizePreview = TimelineResizePreview(
            blockID: blockID,
            edge: edge,
            currentStartMinuteOfDay: bounds.startMinuteOfDay,
            currentEndMinuteOfDay: bounds.endMinuteOfDay,
            minimumStartMinuteOfDay: bounds.minimumStartMinuteOfDay,
            maximumStartMinuteOfDay: bounds.maximumStartMinuteOfDay,
            minimumEndMinuteOfDay: bounds.minimumEndMinuteOfDay,
            maximumEndMinuteOfDay: bounds.maximumEndMinuteOfDay,
            proposedStartMinuteOfDay: bounds.startMinuteOfDay,
            proposedEndMinuteOfDay: bounds.endMinuteOfDay
        )
        TodayHaptics.resizeActivated()
    }

    private func updateResizePreview(for blockID: UUID, edge: TimelineResizeEdge, verticalTranslation: CGFloat) {
        guard var resizePreview, resizePreview.blockID == blockID, resizePreview.edge == edge else { return }

        let deltaMinutes = Int((verticalTranslation / hourHeight) * 60.0)

        switch edge {
        case .start:
            let proposedStartMinuteOfDay = resizePreview.currentStartMinuteOfDay + deltaMinutes
            resizePreview.proposedStartMinuteOfDay = proposedStartMinuteOfDay.aligned(
                toStep: 5,
                within: resizePreview.minimumStartMinuteOfDay ... resizePreview.maximumStartMinuteOfDay
            ) ?? resizePreview.proposedStartMinuteOfDay

        case .end:
            let proposedEndMinuteOfDay = resizePreview.currentEndMinuteOfDay + deltaMinutes
            resizePreview.proposedEndMinuteOfDay = proposedEndMinuteOfDay.aligned(
                toStep: 5,
                within: resizePreview.minimumEndMinuteOfDay ... resizePreview.maximumEndMinuteOfDay
            ) ?? resizePreview.proposedEndMinuteOfDay
        }

        self.resizePreview = resizePreview
    }

    private func commitResize(for blockID: UUID, edge: TimelineResizeEdge) {
        guard let resizePreview, resizePreview.blockID == blockID, resizePreview.edge == edge else { return }
        defer { self.resizePreview = nil }

        switch edge {
        case .start:
            guard resizePreview.proposedStartMinuteOfDay != resizePreview.currentStartMinuteOfDay else {
                return
            }
            onResizeBlockStart(blockID, resizePreview.proposedStartMinuteOfDay)

        case .end:
            guard resizePreview.proposedEndMinuteOfDay != resizePreview.currentEndMinuteOfDay else {
                return
            }
            onResizeBlockEnd(blockID, resizePreview.proposedEndMinuteOfDay)
        }
    }
}

private enum TimelineResizeEdge {
    case start
    case end
}

private struct TodayTimelineNode: Identifiable {
    let block: TimelineBlockItem
    let children: [TodayTimelineNode]

    var id: UUID { block.id }
}

private struct TimelineResizePreview {
    let blockID: UUID
    let edge: TimelineResizeEdge
    let currentStartMinuteOfDay: Int
    let currentEndMinuteOfDay: Int
    let minimumStartMinuteOfDay: Int
    let maximumStartMinuteOfDay: Int
    let minimumEndMinuteOfDay: Int
    let maximumEndMinuteOfDay: Int
    var proposedStartMinuteOfDay: Int
    var proposedEndMinuteOfDay: Int
}

@MainActor
private enum TodayHaptics {
    static func resizeActivated() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 0.9)
        #endif
    }
}

private func propagatedStartDelta(
    for blockID: UUID,
    timing: TimeBlockTiming?,
    inheritedStartDelta: Int,
    resizePreview: TimelineResizePreview?
) -> Int {
    if let resizePreview, resizePreview.blockID == blockID, resizePreview.edge == .start {
        return resizePreview.proposedStartMinuteOfDay - resizePreview.currentStartMinuteOfDay
    }

    guard inheritedStartDelta != 0 else {
        return 0
    }

    guard case .relative? = timing else {
        return 0
    }

    return inheritedStartDelta
}

private func displayedStartMinute(
    for blockID: UUID,
    originalStartMinuteOfDay: Int,
    startDelta: Int,
    resizePreview: TimelineResizePreview?
) -> Int {
    if let resizePreview, resizePreview.blockID == blockID {
        return resizePreview.proposedStartMinuteOfDay
    }

    return originalStartMinuteOfDay + startDelta
}

private func displayedEndMinute(
    for blockID: UUID,
    originalEndMinuteOfDay: Int,
    startDelta: Int,
    resizePreview: TimelineResizePreview?
) -> Int {
    if let resizePreview, resizePreview.blockID == blockID {
        return resizePreview.proposedEndMinuteOfDay
    }

    return originalEndMinuteOfDay + startDelta
}

private struct TimelineBlockCard: View {
    @Environment(\.thingStructTintPreset) private var tintPreset

    let node: TodayTimelineNode
    let hourHeight: CGFloat
    let selectedBlockID: UUID?
    let selectedPathIDs: Set<UUID>
    let displayedStartMinuteOfDay: Int
    let displayedEndMinuteOfDay: Int
    let inheritedStartDelta: Int
    let timingResolver: (UUID) -> TimeBlockTiming?
    let resizingBlockID: UUID?
    let resizingEdge: TimelineResizeEdge?
    let resizePreview: TimelineResizePreview?
    let isAdjustingTime: Bool
    let onResizeStart: (UUID, TimelineResizeEdge) -> Void
    let onResizeChange: (UUID, TimelineResizeEdge, CGFloat) -> Void
    let onResizeEnd: (UUID, TimelineResizeEdge) -> Void
    let onSelect: (UUID) -> Void

    private let minimumHeight: CGFloat = 52
    private let childInset: CGFloat = 16
    private let childGap: CGFloat = 8
    private let maximumVerticalGap: CGFloat = 3

    private var block: TimelineBlockItem { node.block }

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(
            layerIndex: block.layerIndex,
            isBlank: false,
            preset: tintPreset
        )
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

    private var showsResizeHandles: Bool {
        isSelected && isAdjustingTime
    }

    private var nodeStartDelta: Int {
        propagatedStartDelta(
            for: block.id,
            timing: timingResolver(block.id),
            inheritedStartDelta: inheritedStartDelta,
            resizePreview: resizePreview
        )
    }

    private var durationHeight: CGFloat {
        CGFloat(displayedEndMinuteOfDay - displayedStartMinuteOfDay) / 60.0 * hourHeight
    }

    private var outerFrameHeight: CGFloat {
        max(durationHeight, minimumHeight)
    }

    private var visualVerticalInset: CGFloat {
        let availableGap = max(0, durationHeight - minimumHeight)
        return min(maximumVerticalGap / 2, availableGap / 2)
    }

    private var cardHeight: CGFloat {
        outerFrameHeight - visualVerticalInset * 2
    }

    private var taskSummary: String? {
        guard block.incompleteTaskCount > 0 else {
            return nil
        }

        return block.incompleteTaskCount == 1 ? "1 task" : "\(block.incompleteTaskCount) tasks"
    }

    private var headerReservedHeight: CGFloat {
        58
    }

    private var headerBackdropHeight: CGFloat {
        min(cardHeight, headerReservedHeight + 22)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(block.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)
            }

            Text("\(displayedStartMinuteOfDay.formattedTime) - \(displayedEndMinuteOfDay.formattedTime)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let taskSummary {
                Text(taskSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            .clipShape(cardShape)
        }
        .allowsHitTesting(false)
    }

    var body: some View {
        GeometryReader { geometry in
            let childHorizontalInset = min(childInset, max(8, geometry.size.width * 0.12))
            let childWidth = max(geometry.size.width - childHorizontalInset * 2, 1)

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    cardShape
                        .fill(backgroundColor)

                    selectionSurface

                    ForEach(Array(node.children), id: \.id) { child in
                        childCard(
                            for: child,
                            width: childWidth,
                            horizontalInset: childHorizontalInset
                        )
                    }

                    headerContent
                        .zIndex(1)

                    if showsResizeHandles {
                        resizeHandleOverlay
                            .zIndex(2)
                    }
                }
                .clipShape(cardShape)
                .frame(width: geometry.size.width, height: cardHeight, alignment: .topLeading)
                .offset(y: visualVerticalInset)
                .overlay(
                    cardShape
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                )
                .shadow(
                    color: (isSelected || isResizing) ? style.accent.opacity(0.16) : .clear,
                    radius: 10,
                    y: 4
                )
            }
        }
        .frame(height: outerFrameHeight)
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
            return style.accent.opacity(0.42)
        }

        return style.border
    }

    private var borderWidth: CGFloat {
        if isResizing || isSelected {
            return 2.2
        }

        if isSelectedAncestor {
            return 1.5
        }

        return 1
    }

    private func childYOffset(for child: TodayTimelineNode, childHeight: CGFloat) -> CGFloat {
        let childRange = childDisplayedRange(of: child)
        let relative = CGFloat(childRange.startMinuteOfDay - displayedStartMinuteOfDay) / 60.0 * hourHeight
        let desiredTop = headerReservedHeight + childGap
        let availableShift = max(0, cardHeight - childHeight - childGap - relative)
        let shift = min(max(0, desiredTop - relative), availableShift)
        return relative + shift
    }

    private func childCard(
        for child: TodayTimelineNode,
        width: CGFloat,
        horizontalInset: CGFloat
    ) -> some View {
        let childRange = childDisplayedRange(of: child)
        let childHeight = max(
            CGFloat(childRange.endMinuteOfDay - childRange.startMinuteOfDay) / 60.0 * hourHeight,
            minimumHeight
        )

        return TimelineBlockCard(
            node: child,
            hourHeight: hourHeight,
            selectedBlockID: selectedBlockID,
            selectedPathIDs: selectedPathIDs,
            displayedStartMinuteOfDay: childRange.startMinuteOfDay,
            displayedEndMinuteOfDay: childRange.endMinuteOfDay,
            inheritedStartDelta: nodeStartDelta,
            timingResolver: timingResolver,
            resizingBlockID: resizingBlockID,
            resizingEdge: resizingEdge,
            resizePreview: resizePreview,
            isAdjustingTime: isAdjustingTime,
            onResizeStart: onResizeStart,
            onResizeChange: onResizeChange,
            onResizeEnd: onResizeEnd,
            onSelect: onSelect
        )
        .frame(width: width)
        .offset(
            x: horizontalInset,
            y: childYOffset(for: child, childHeight: childHeight)
        )
    }

    private func childDisplayedRange(of child: TodayTimelineNode) -> (startMinuteOfDay: Int, endMinuteOfDay: Int) {
        let startDelta = propagatedStartDelta(
            for: child.block.id,
            timing: timingResolver(child.block.id),
            inheritedStartDelta: nodeStartDelta,
            resizePreview: resizePreview
        )

        return (
            startMinuteOfDay: displayedStartMinute(
                for: child.block.id,
                originalStartMinuteOfDay: child.block.startMinuteOfDay,
                startDelta: startDelta,
                resizePreview: resizePreview
            ),
            endMinuteOfDay: displayedEndMinute(
                for: child.block.id,
                originalEndMinuteOfDay: child.block.endMinuteOfDay,
                startDelta: startDelta,
                resizePreview: resizePreview
            )
        )
    }

    private var selectionSurface: some View {
        Color.clear
            .contentShape(cardShape)
            .onTapGesture {
                onSelect(block.id)
            }
    }

    private var resizeHandleOverlay: some View {
        VStack {
            resizeHandle(edge: .start)
                .padding(.top, 8)

            Spacer(minLength: 0)

            resizeHandle(edge: .end)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 10)
    }

    private func resizeHandle(edge: TimelineResizeEdge) -> some View {
        TimelineResizeHandle(
            label: edge == .start ? "Start" : "End",
            systemImage: edge == .start ? "arrow.up" : "arrow.down",
            tint: style.accent
        )
        .gesture(resizeGesture(edge: edge))
        .accessibilityLabel(edge == .start ? "Adjust block start time" : "Adjust block end time")
    }

    private func resizeGesture(edge: TimelineResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                onResizeStart(block.id, edge)
                onResizeChange(block.id, edge, value.translation.height)
            }
            .onEnded { _ in
                onResizeEnd(block.id, edge)
            }
    }
}

private struct TimelineResizeHandle: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(label)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.7), lineWidth: 1)
        )
    }
}

private struct TimelineOpenSlotEntry: View {
    @Environment(\.thingStructTintPreset) private var tintPreset

    let slot: TodayOpenSlotItem
    let hourHeight: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void

    private var slotHeight: CGFloat {
        CGFloat(slot.durationMinutes) / 60.0 * hourHeight
    }

    private var showsTimeRange: Bool {
        slotHeight >= 54
    }

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(
            layerIndex: 0,
            isBlank: true,
            preset: tintPreset
        )
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isSelected ? style.surface.opacity(0.55) : style.surface.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? style.accent.opacity(0.88) : style.border.opacity(0.55),
                        style: StrokeStyle(lineWidth: isSelected ? 1.6 : 1, dash: [6, 6])
                    )
            )
            .frame(height: max(slotHeight, 10))
            .overlay(alignment: showsTimeRange ? .leading : .center) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(isSelected ? style.accent : .secondary)

                    if showsTimeRange {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Time")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text("\(slot.startMinuteOfDay.formattedTime) - \(slot.endMinuteOfDay.formattedTime)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture(perform: onSelect)
    }
}

private struct TodayDockedInspector<Content: View>: View {
    let panelState: TodayPanelState
    let onExpand: () -> Void
    let onCollapse: () -> Void
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    private var allowsPanelToggle: Bool {
        panelState != .adjustingTime
    }

    private var showsDismiss: Bool {
        panelState != .adjustingTime
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                if allowsPanelToggle {
                    Button(action: togglePanel) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.34))
                            .frame(width: 42, height: 5)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(panelState == .compact ? "Expand inspector" : "Collapse inspector")
                } else {
                    Capsule()
                        .fill(Color.secondary.opacity(0.34))
                        .frame(width: 42, height: 5)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }

                if showsDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            content()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 18, y: 6)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .simultaneousGesture(panelDragGesture)
    }

    private var panelDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                guard allowsPanelToggle else { return }

                if value.translation.height < -28 {
                    onExpand()
                } else if value.translation.height > 32 {
                    onCollapse()
                }
            }
    }

    private func togglePanel() {
        switch panelState {
        case .compact:
            onExpand()
        case .expanded:
            onCollapse()
        case .adjustingTime:
            break
        }
    }
}

private struct TodayBlockInspectorView: View {
    let detail: BlockDetailModel
    let panelState: TodayPanelState
    let onSelectParent: () -> Void
    let onEdit: () -> Void
    let onExpand: () -> Void
    let onAdjustTime: () -> Void
    let onFinishAdjusting: () -> Void
    let onCancelAdjusting: () -> Void
    let onAddOverlay: () -> Void
    let onRequestCancellation: () -> Void

    var body: some View {
        switch panelState {
        case .compact:
            compactBody

        case .expanded:
            expandedBody

        case .adjustingTime:
            adjustingBody
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if detail.parentBlockTitle != nil {
                parentButton
            }

            HStack(spacing: 10) {
                Button("Edit", action: onEdit)
                    .buttonStyle(.borderedProminent)

                Button("Details", action: onExpand)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if detail.parentBlockTitle != nil {
                parentButton
            }

            TodayInspectorSection(title: "Note", systemImage: "note.text") {
                if let note = detail.note, !note.isEmpty {
                    Text(note)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No note")
                        .foregroundStyle(.secondary)
                }
            }

            TodayInspectorSection(title: "Checklist", systemImage: "checklist") {
                if detail.tasks.isEmpty {
                    Text("No checklist items")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(detail.tasks) { task in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isCompleted ? Color.accentColor : Color.secondary)
                                    .padding(.top, 1)

                                Text(task.title)
                                    .strikethrough(task.isCompleted, color: .secondary)
                                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }

            TodayInspectorSection(title: "Reminders", systemImage: "bell") {
                if detail.reminders.isEmpty {
                    Text("No reminders")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(detail.reminders) { reminder in
                            Label(reminderSummary(reminder), systemImage: "bell.badge")
                                .font(.body)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Actions")
                    .font(.headline)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Button("Edit", action: onEdit)
                            .buttonStyle(.borderedProminent)

                        Button("Adjust Time", action: onAdjustTime)
                            .buttonStyle(.bordered)

                        Button("Add Overlay", action: onAddOverlay)
                            .buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Button("Edit", action: onEdit)
                            .buttonStyle(.borderedProminent)

                        Button("Adjust Time", action: onAdjustTime)
                            .buttonStyle(.bordered)

                        Button("Add Overlay", action: onAddOverlay)
                            .buttonStyle(.bordered)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Danger Zone")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button("Cancel Block", role: .destructive, action: onRequestCancellation)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var adjustingBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Text("Drag the visible top and bottom handles on the selected block. Scrolling and ordinary taps will no longer resize the card.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Done", action: onFinishAdjusting)
                    .buttonStyle(.borderedProminent)

                Button("Cancel", action: onCancelAdjusting)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text("\(detail.startMinuteOfDay.formattedTime) - \(detail.endMinuteOfDay.formattedTime)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var parentButton: some View {
        Button(action: onSelectParent) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.turn.up.left")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Parent Block")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(detail.parentBlockTitle ?? "")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func reminderSummary(_ reminder: ReminderRule) -> String {
        if let preset = ReminderPreset(rule: reminder) {
            return preset.title
        }

        switch reminder.triggerMode {
        case .atStart:
            return "At start"
        case .beforeStart:
            return "\(reminder.offsetMinutes) min before"
        }
    }
}

private struct TodayOpenSlotInspectorView: View {
    let slot: TodayOpenSlotItem
    let panelState: TodayPanelState
    let onAddBlock: () -> Void
    let onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Open Time")
                    .font(.headline)

                Text("\(slot.startMinuteOfDay.formattedTime) - \(slot.endMinuteOfDay.formattedTime)")
                    .font(.title3.weight(.semibold))

                Text(durationText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if panelState == .expanded {
                Text("This gap is free. Add a block with the full range as a starting point, then fine-tune it in the editor if needed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("Add Block", action: onAddBlock)
                    .buttonStyle(.borderedProminent)

                if panelState == .compact {
                    Button("Details", action: onExpand)
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var durationText: String {
        let hours = slot.durationMinutes / 60
        let minutes = slot.durationMinutes % 60

        switch (hours, minutes) {
        case (0, let minutes):
            return "\(minutes) min available"
        case (let hours, 0):
            return hours == 1 ? "1 hour available" : "\(hours) hours available"
        default:
            return "\(hours)h \(minutes)m available"
        }
    }
}

private struct TodayUnavailableInspectorView: View {
    let title: String
    let startMinuteOfDay: Int
    let endMinuteOfDay: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))

            Text("\(startMinuteOfDay.formattedTime) - \(endMinuteOfDay.formattedTime)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("This block is no longer available in the current day plan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TodayInspectorSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct BlockEditorSession: Identifiable {
    let id = UUID()
    let title: String
    let draft: BlockDraft
    var scrollToSavedBlockOnSave = false
    var cancelBlockID: UUID? = nil
}

private struct TodayBlockEditorPresenter: View {
    @Environment(ThingStructStore.self) private var store

    let session: BlockEditorSession
    let onSaveSuccess: (UUID, Bool) -> Void

    var body: some View {
        BlockEditorSheet(title: session.title, draft: session.draft) { draft in
            do {
                let savedBlockID = try store.saveBlockDraft(draft, for: store.selectedDate)
                onSaveSuccess(savedBlockID, session.scrollToSavedBlockOnSave)
                return true
            } catch {
                store.presentError(error)
                return false
            }
        } onCancelBlock: {
            guard let blockID = session.cancelBlockID else { return }
            store.cancelBlock(on: store.selectedDate, blockID: blockID)
        }
    }
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
        selectedOpenSlotID: nil,
        isAdjustingTime: false,
        currentMinute: 9 * 60 + 30,
        jumpToCurrentTrigger: 0,
        scrollToBlockID: nil,
        scrollToBlockTrigger: 0,
        timingResolver: { _ in nil },
        resizeBounds: { _ in nil },
        onResizeBlockStart: { _, _ in },
        onResizeBlockEnd: { _, _ in },
        onSelectBlock: { _ in },
        onSelectOpenSlot: { _ in },
        onClearSelection: {}
    )
}

#Preview("Today Timeline - Blank") {
    let model = PreviewSupport.todayModel(document: ThingStructDocument(), currentMinute: nil)
    TodayTimelineView(
        model: model,
        selectedBlockID: nil,
        selectedOpenSlotID: nil,
        isAdjustingTime: false,
        currentMinute: nil,
        jumpToCurrentTrigger: 0,
        scrollToBlockID: nil,
        scrollToBlockTrigger: 0,
        timingResolver: { _ in nil },
        resizeBounds: { _ in nil },
        onResizeBlockStart: { _, _ in },
        onResizeBlockEnd: { _, _ in },
        onSelectBlock: { _ in },
        onSelectOpenSlot: { _ in },
        onClearSelection: {}
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
        selectedOpenSlotID: nil,
        isAdjustingTime: false,
        currentMinute: nil,
        jumpToCurrentTrigger: 0,
        scrollToBlockID: nil,
        scrollToBlockTrigger: 0,
        timingResolver: { _ in nil },
        resizeBounds: { _ in nil },
        onResizeBlockStart: { _, _ in },
        onResizeBlockEnd: { _, _ in },
        onSelectBlock: { _ in },
        onSelectOpenSlot: { _ in },
        onClearSelection: {}
    )
}
