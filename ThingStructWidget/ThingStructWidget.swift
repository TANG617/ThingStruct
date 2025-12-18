//
//  ThingStructWidget.swift
//  ThingStructWidget
//
//  Created by TimLi on 2025/12/17.
//

import WidgetKit
import SwiftUI

// 注意：Widget Extension 需要单独配置 SwiftData 或使用 App Group 共享数据
// 这里提供一个简化版本，实际使用时需要配置数据共享

struct ThingStructWidget: Widget {
    let kind: String = "ThingStructWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StateProvider()) { entry in
            ThingStructWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("状态")
        .description("显示今天的当前状态")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct StateProvider: TimelineProvider {
    func placeholder(in context: Context) -> StateEntry {
        StateEntry(date: Date(), state: nil)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (StateEntry) -> ()) {
        let entry = StateEntry(date: Date(), state: getFirstState())
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<StateEntry>) -> ()) {
        let currentDate = Date()
        let entry = StateEntry(date: currentDate, state: getFirstState())
        
        // 每小时更新一次
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func getFirstState() -> WidgetState? {
        // 注意：Widget Extension 需要配置 App Group 来共享数据
        // 这里使用简化的方式，实际需要从共享的 SwiftData store 读取
        // 或者使用 UserDefaults/App Group 来传递状态数据
        return nil
    }
}

struct StateEntry: TimelineEntry {
    let date: Date
    let state: WidgetState?
}

struct WidgetState: Identifiable {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let checklistItems: [WidgetChecklistItem]
    
    var totalChecklistCount: Int {
        checklistItems.count
    }
    
    var incompleteChecklistCount: Int {
        checklistItems.filter { !$0.isCompleted }.count
    }
}

struct WidgetChecklistItem: Identifiable {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let order: Int
}

struct ThingStructWidgetEntryView: View {
    var entry: StateProvider.Entry
    
    var body: some View {
        if let state = entry.state {
            StateWidgetView(state: state, family: .systemSmall)
        } else {
            EmptyStateView()
        }
    }
}

struct StateWidgetView: View {
    let state: WidgetState
    let family: WidgetFamily
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(state: state)
        case .systemMedium:
            MediumWidgetView(state: state)
        case .systemLarge:
            LargeWidgetView(state: state)
        default:
            SmallWidgetView(state: state)
        }
    }
}

struct SmallWidgetView: View {
    let state: WidgetState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: state.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(state.isCompleted ? .green : .blue)
                Text("今天")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(state.title)
                .font(.headline)
                .lineLimit(2)
                .strikethrough(state.isCompleted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

struct MediumWidgetView: View {
    let state: WidgetState
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: state.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(state.isCompleted ? .green : .blue)
                    Text("今天")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(state.title)
                    .font(.headline)
                    .lineLimit(2)
                    .strikethrough(state.isCompleted)
                
                if state.totalChecklistCount > 0 {
                    Text("\(state.totalChecklistCount - state.incompleteChecklistCount)/\(state.totalChecklistCount) 已完成")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

struct LargeWidgetView: View {
    let state: WidgetState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: state.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(state.isCompleted ? .green : .blue)
                Text("今天")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(state.title)
                .font(.title2)
                .fontWeight(.semibold)
                .strikethrough(state.isCompleted)
            
            if !state.checklistItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("检查清单")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(state.checklistItems.sorted(by: { $0.order < $1.order }).prefix(5)) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                                .foregroundColor(item.isCompleted ? .green : .secondary)
                                .font(.caption)
                            Text(item.title)
                                .font(.caption)
                                .strikethrough(item.isCompleted)
                        }
                    }
                    
                    if state.checklistItems.count > 5 {
                        Text("还有 \(state.checklistItems.count - 5) 项...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("今天没有状态")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview(as: .systemSmall) {
    ThingStructWidget()
} timeline: {
    StateEntry(date: .now, state: WidgetState(
        id: UUID(),
        title: "示例状态",
        isCompleted: false,
        checklistItems: []
    ))
    StateEntry(date: .now, state: nil)
}
