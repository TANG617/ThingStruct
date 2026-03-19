import SwiftUI

struct NowRootView: View {
    @Environment(ThingStructStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if !store.isLoaded {
                    ContentUnavailableView("Loading", systemImage: "clock")
                } else {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let localDay = LocalDay(date: context.date)
                        let result = Result { try store.nowScreenModel(at: context.date) }

                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                switch result {
                                case let .success(model):
                                    nowHeader(date: context.date)
                                    activeCard(model: model)
                                    activeChainSection(model: model)
                                    tasksSection(model: model)
                                    quickLinks

                                case let .failure(error):
                                    ContentUnavailableView(
                                        "Unable to Load Now",
                                        systemImage: "exclamationmark.triangle",
                                        description: Text(error.localizedDescription)
                                    )
                                }
                            }
                            .padding(20)
                        }
                        .task(id: localDay) {
                            store.ensureMaterialized(for: localDay)
                        }
                    }
                }
            }
            .navigationTitle("Now")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func nowHeader(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalDay(date: date).titleText)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 40, weight: .bold, design: .rounded))
        }
    }

    private func activeCard(model: NowScreenModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Block")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(model.activeBlockTitle)
                .font(.title2.weight(.semibold))

            if let top = model.activeChain.last {
                Text("\(top.startMinuteOfDay.formattedTime) - \(top.endMinuteOfDay.formattedTime)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func activeChainSection(model: NowScreenModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Chain")
                .font(.headline)

            ForEach(model.activeChain) { item in
                HStack(alignment: .top, spacing: 12) {
                    Capsule()
                        .fill(item.isBlank ? Color.secondary.opacity(0.25) : Color.accentColor.opacity(0.75))
                        .frame(width: 4)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.title)
                                .font(.body.weight(item.layerIndex == model.activeChain.last?.layerIndex ? .semibold : .regular))
                            Spacer()
                            Text("L\(item.layerIndex)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(item.startMinuteOfDay.formattedTime) - \(item.endMinuteOfDay.formattedTime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, CGFloat(item.layerIndex) * 14)
                .padding(.vertical, 8)
            }
        }
    }

    private func tasksSection(model: NowScreenModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tasks")
                .font(.headline)

            if model.tasks.isEmpty {
                Text(model.statusMessage ?? "No tasks right now")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let taskSourceBlockID = model.taskSourceBlockID {
                ForEach(model.tasks) { task in
                    Button {
                        store.toggleTask(on: model.date, blockID: taskSourceBlockID, taskID: task.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .imageScale(.large)
                            Text(task.title)
                                .strikethrough(task.isCompleted)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickLinks: some View {
        HStack(spacing: 12) {
            Button {
                store.selectedTab = .today
            } label: {
                Label("Open Today", systemImage: "calendar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                store.selectedTab = .templates
            } label: {
                Label("Tomorrow", systemImage: "square.stack.3d.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}
