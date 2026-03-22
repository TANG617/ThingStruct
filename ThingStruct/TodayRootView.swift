import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// `TodayRootView` is the most interaction-heavy screen in the app.
//
// It combines:
// - a timeline visualization
// - selection state (`selectedBlockID`)
// - editor sheet presentation
// - direct manipulation gestures for resizing blocks
struct TodayRootView: View {
    // `@Environment(Type.self)` reads a shared dependency from the surrounding
    // SwiftUI tree. Think of it as injected app state rather than a global singleton.
    @Environment(ThingStructStore.self) private var store
    // `@State` stores view-local mutable state that survives body recomputation.
    @State private var editorSession: BlockEditorSession?
    @State private var presentedDetail: PresentedTodayBlockDetail?
    @State private var jumpToCurrentTrigger = 0

    var body: some View {
        // `NavigationStack` is the native container that provides titles, toolbars,
        // and future push navigation behavior.
        NavigationStack {
            RootScreenContainer(
                isLoaded: store.isLoaded,
                loadingTitle: "Loading Today",
                loadingSystemImage: "calendar",
                loadingDescription: "Preparing your timeline and current context.",
                errorTitle: "Unable to Load Today",
                retry: store.reload
            ) {
                try store.todayScreenModel()
            } content: { model in
                TodayTimelineView(
                    model: model,
                    selectedBlockID: store.selectedBlockID,
                    currentMinute: store.currentMinuteOnSelectedDate(),
                    jumpToCurrentTrigger: jumpToCurrentTrigger,
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
                    onCreateBaseInOpenSlot: { startMinuteOfDay, endMinuteOfDay in
                        var draft = BlockDraft.base(
                            startMinute: startMinuteOfDay,
                            endMinute: endMinuteOfDay
                        )
                        draft.title = "New Block"
                        editorSession = BlockEditorSession(
                            title: "New Base Block",
                            draft: draft
                        )
                    },
                    onSelect: handleSelection
                )
            }
            .navigationTitle(store.selectedDate.titleText)
            .navigationBarTitleDisplayMode(.inline)
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

                    Button {
                        editorSession = BlockEditorSession(
                            title: "New Base Block",
                            draft: .base()
                        )
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
        }
        .onAppear {
            syncPresentedDetail(with: store.selectedBlockID)
        }
        .onChange(of: store.selectedBlockID) { _, blockID in
            syncPresentedDetail(with: blockID)
        }
        .onChange(of: editorSession?.id) { _, editorSessionID in
            guard editorSessionID == nil else { return }
            syncPresentedDetail(with: store.selectedBlockID)
        }
        .sheet(item: $editorSession) { session in
            TodayBlockEditorPresenter(session: session)
        }
        .sheet(item: $presentedDetail, onDismiss: {
            if editorSession == nil {
                store.selectBlock(nil)
            }
        }) { presented in
            TodayBlockDetailSheet(blockID: presented.id)
                .environment(store)
        }
    }

    private func jumpToCurrent() {
        // The timeline watches this trigger with `.onChange`, so bumping the integer
        // is a simple way to request an imperative scroll from an otherwise
        // declarative view hierarchy.
        let blockID = store.currentActiveBlockID()
        store.selectBlock(blockID)
        syncPresentedDetail(with: blockID)
        jumpToCurrentTrigger += 1
    }

    private func handleSelection(_ blockID: UUID?) {
        store.selectBlock(blockID)
        syncPresentedDetail(with: blockID)
    }

    private func syncPresentedDetail(with blockID: UUID?) {
        guard editorSession == nil else { return }

        if let blockID {
            presentedDetail = PresentedTodayBlockDetail(id: blockID)
        } else {
            presentedDetail = nil
        }
    }
}

private struct TodayTimelineView: View {
    let model: TodayScreenModel
    let selectedBlockID: UUID?
    let currentMinute: Int?
    let jumpToCurrentTrigger: Int
    let timingResolver: (UUID) -> TimeBlockTiming?
    let resizeBounds: (UUID) -> BlockResizeBounds?
    let onResizeBlockStart: (UUID, Int) -> Void
    let onResizeBlockEnd: (UUID, Int) -> Void
    let onCreateBaseInOpenSlot: (Int, Int) -> Void
    let onSelect: (UUID?) -> Void

    @State private var lastInitialScrollDate: LocalDay?
    @State private var resizePreview: TimelineResizePreview?

    // The timeline uses a manual y-axis scale because time maps to position continuously,
    // not to "one row per item" like a normal list.
    private let hourHeight: CGFloat = 76
    private let labelWidth: CGFloat = 52
    private let timelineTopInset: CGFloat = 12
    private let trackInset: CGFloat = 12

    var body: some View {
        // `ScrollViewReader` gives imperative scrolling control inside an otherwise
        // declarative view tree. We use it for "jump to current" and initial focus.
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
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
                // `.task(id:)` reruns whenever the ID changes.
                // That is exactly what we want when the user switches to a different date.
                guard lastInitialScrollDate != model.date else { return }
                lastInitialScrollDate = model.date

                if let focusBlockID = model.initialFocusBlockID, let fallbackMinute = currentMinute ?? model.blocks.first(where: { $0.id == focusBlockID })?.startMinuteOfDay {
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
            .onChange(of: selectedBlockID) { _, blockID in
                guard let blockID else { return }
                scroll(
                    toBlock: blockID,
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
        // Resizing a parent block's start can visually shift relative descendants.
        // These helper values compute the temporary on-screen preview positions.
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
            onResizeStart: beginResize(for:edge:),
            onResizeChange: updateResizePreview(for:edge:verticalTranslation:),
            onResizeEnd: commitResize(for:edge:),
            onSelect: onSelect
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
            onCreateBase: onCreateBaseInOpenSlot
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
        // We rebuild a tree from the flat block list on demand.
        // With Swift value types this is a normal pattern: derive transient structure
        // during rendering instead of storing multiple mutable representations.
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
        // This computes the selected block plus all ancestors so the UI can subtly
        // highlight the whole active path through the nested overlay tree.
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
        // `ScrollViewReader` scrolls to view IDs, not raw pixel offsets.
        // We therefore map a time minute to the nearest hour-marker view ID.
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
        // Prefer the exact block view when possible. If the block vanished because the
        // underlying data changed, fall back to an hour marker near the same time.
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
        // Gesture code is simpler if we snapshot bounds/current values at gesture start
        // and then update a lightweight preview struct as the drag changes.
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

private struct PresentedTodayBlockDetail: Identifiable, Equatable {
    let id: UUID
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
    // Relative children move with a parent's dragged start edge during preview.
    // Absolute-timed descendants keep their own absolute position.
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
    // The block currently being dragged reads its own preview directly.
    // Other blocks either stay fixed or inherit an ancestor delta.
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
    let onResizeStart: (UUID, TimelineResizeEdge) -> Void
    let onResizeChange: (UUID, TimelineResizeEdge, CGFloat) -> Void
    let onResizeEnd: (UUID, TimelineResizeEdge) -> Void
    let onSelect: (UUID?) -> Void

    private let minimumHeight: CGFloat = 52
    private let childInset: CGFloat = 16
    private let childGap: CGFloat = 8
    private let maximumVerticalGap: CGFloat = 3

    private var block: TimelineBlockItem { node.block }

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(layerIndex: block.layerIndex, isBlank: false)
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

    private var badgeTitle: String {
        block.layerIndex.timelineLayerBadgeTitle
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
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let childHorizontalInset = min(childInset, max(8, geometry.size.width * 0.12))
            let childWidth = max(geometry.size.width - childHorizontalInset * 2, 1)

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    // Nested overlays are drawn recursively: a card renders its children
                    // by embedding more `TimelineBlockCard` views inside itself.
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(backgroundColor)

                    ForEach(Array(node.children), id: \.id) { child in
                        childCard(
                            for: child,
                            width: childWidth,
                            horizontalInset: childHorizontalInset
                        )
                    }

                    headerContent
                        .zIndex(1)

                    VStack {
                        resizeHandle(edge: .start)
                            .padding(.top, 8)
                        Spacer(minLength: 0)
                        resizeHandle(edge: .end)
                    }
                    .padding(.bottom, 8)
                    .zIndex(2)
                }
                .frame(width: geometry.size.width, height: cardHeight, alignment: .topLeading)
                .offset(y: visualVerticalInset)
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
        }
        .frame(height: outerFrameHeight)
        .id(block.id)
    }

    private var backgroundColor: Color {
        // Appearance is derived from semantic state rather than mutated imperatively.
        // That makes selection/resizing visuals deterministic and easy to reason about.
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
        // Children should remain close to their true time position, but the parent
        // header also needs breathing room so nested cards do not visually collide
        // with the title area.
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
        // Recursive rendering asks the same question at every level:
        // "given the current preview delta from my ancestors, where should this child
        // appear right now?"
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

    private func resizeHandle(edge: TimelineResizeEdge) -> some View {
        Color.clear
            .frame(height: 24)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(resizeGesture(edge: edge))
            .accessibilityLabel(edge == .start ? "Resize block start" : "Resize block end")
    }

    private func resizeGesture(edge: TimelineResizeEdge) -> some Gesture {
        // `sequenced(before:)` lets us model "long press, then drag" as one gesture.
        // This avoids accidental resizes during normal scrolling/tapping.
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .first(true):
                    onResizeStart(block.id, edge)

                case .second(true, let drag?):
                    onResizeChange(block.id, edge, drag.translation.height)

                default:
                    break
                }
            }
            .onEnded { _ in
                onResizeEnd(block.id, edge)
            }
    }
}

private struct TimelineOpenSlotEntry: View {
    let slot: TodayOpenSlotItem
    let hourHeight: CGFloat
    let onCreateBase: (Int, Int) -> Void

    private var slotHeight: CGFloat {
        CGFloat(slot.durationMinutes) / 60.0 * hourHeight
    }

    private var showsTimeRange: Bool {
        slotHeight >= 64
    }

    var body: some View {
        Color.clear
            .frame(height: max(slotHeight, 1))
            .overlay(alignment: showsTimeRange ? .center : .topLeading) {
                HStack(spacing: 8) {
                    Button {
                        onCreateBase(slot.startMinuteOfDay, slot.endMinuteOfDay)
                    } label: {
                        if showsTimeRange {
                            Label("Add Base", systemImage: "plus.circle.fill")
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(showsTimeRange ? .regular : .small)

                    if showsTimeRange {
                        Text("\(slot.startMinuteOfDay.formattedTime) - \(slot.endMinuteOfDay.formattedTime)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, showsTimeRange ? 0 : 4)
                .padding(.leading, 8)
            }
    }
}

private struct TodayBlockDetailSheet: View {
    @Environment(ThingStructStore.self) private var store
    @State private var editorSession: BlockEditorSession?
    let blockID: UUID

    var body: some View {
        Group {
            if let block = currentBlock {
                // The detail sheet stays intentionally small and native-looking.
                // It is a contextual inspector, not a full-screen destination.
                TodayBlockDetailContent(
                    block: block,
                    onEdit: { beginEditing(block) },
                    onAddOverlay: { beginOverlayCreation(for: block) }
                )
            } else {
                ContentUnavailableView(
                    "Block Unavailable",
                    systemImage: "rectangle.slash",
                    description: Text("This block is no longer available on the selected day.")
                )
                .padding(.horizontal, 20)
            }
        }
        .presentationDetents([.height(272), .medium])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .sheet(item: $editorSession) { session in
            TodayBlockEditorPresenter(session: session)
        }
    }

    private var currentBlock: BlockDetailModel? {
        if store.selectedBlockID == blockID {
            return store.selectedBlockDetail
        }

        return try? store.blockDetailModel(on: store.selectedDate, blockID: blockID)
    }

    private func beginEditing(_ block: BlockDetailModel) {
        // The detail model is presentation data. To build an editor draft we re-read
        // the persisted source block so timing information matches what is actually stored.
        guard let sourceBlock = store.persistedBlock(on: store.selectedDate, blockID: block.id) else { return }

        editorSession = BlockEditorSession(
            title: "Edit Block",
            draft: .editing(detail: block, sourceBlock: sourceBlock),
            cancelBlockID: block.id
        )
    }

    private func beginOverlayCreation(for block: BlockDetailModel) {
        editorSession = BlockEditorSession(
            title: block.layerIndex.newNextTimelineLayerActionTitle,
            draft: .overlay(parentBlockID: block.id, layerIndex: block.layerIndex + 1)
        )
    }
}

private struct TodayBlockDetailContent: View {
    let block: BlockDetailModel
    let onEdit: () -> Void
    let onAddOverlay: () -> Void

    private var style: LayerVisualStyle {
        LayerVisualStyle.forBlock(layerIndex: block.layerIndex, isBlank: false)
    }

    private var badgeTitle: String {
        block.layerIndex.timelineLayerBadgeTitle
    }

    private var addChildLayerTitle: String {
        block.layerIndex.addNextTimelineLayerActionTitle
    }

    private var normalizedNote: String? {
        // Treat empty note text the same as a missing note so the render logic stays simple.
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

                if !block.tasks.isEmpty {
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
                Label(addChildLayerTitle, systemImage: "square.stack.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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

private struct TodayBlockEditorPresenter: View {
    @Environment(ThingStructStore.self) private var store

    let session: BlockEditorSession

    var body: some View {
        // This adapter translates generic form output (`BlockDraft`) into concrete
        // store mutations. Parent views stay focused on layout instead of save logic.
        BlockEditorSheet(title: session.title, draft: session.draft) { draft in
            do {
                let savedBlockID = try store.saveBlockDraft(draft, for: store.selectedDate)
                store.selectBlock(savedBlockID)
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
        currentMinute: 9 * 60 + 30,
        jumpToCurrentTrigger: 0,
        timingResolver: { _ in nil },
        resizeBounds: { _ in nil },
        onResizeBlockStart: { _, _ in },
        onResizeBlockEnd: { _, _ in },
        onCreateBaseInOpenSlot: { _, _ in },
        onSelect: { _ in }
    )
}

#Preview("Today Timeline - Blank") {
    let model = PreviewSupport.todayModel(document: ThingStructDocument(), currentMinute: nil)
    TodayTimelineView(
        model: model,
        selectedBlockID: nil,
        currentMinute: nil,
        jumpToCurrentTrigger: 0,
        timingResolver: { _ in nil },
        resizeBounds: { _ in nil },
        onResizeBlockStart: { _, _ in },
        onResizeBlockEnd: { _, _ in },
        onCreateBaseInOpenSlot: { _, _ in },
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
        jumpToCurrentTrigger: 0,
        timingResolver: { _ in nil },
        resizeBounds: { _ in nil },
        onResizeBlockStart: { _, _ in },
        onResizeBlockEnd: { _, _ in },
        onCreateBaseInOpenSlot: { _, _ in },
        onSelect: { _ in }
    )
}

#Preview("Today Detail Content") {
    TodayBlockDetailContent(
        block: PreviewSupport.selectedBlockDetailModel(),
        onEdit: {},
        onAddOverlay: {}
    )
    .padding()
}
