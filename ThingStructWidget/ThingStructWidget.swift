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
        StaticConfiguration(kind: kind, provider: TaskProvider()) { entry in
            ThingStructWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("任务")
        .description("显示今天的第一个任务")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: Date(), task: nil)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> ()) {
        let entry = TaskEntry(date: Date(), task: getFirstTask())
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> ()) {
        let currentDate = Date()
        let entry = TaskEntry(date: currentDate, task: getFirstTask())
        
        // 每小时更新一次
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func getFirstTask() -> WidgetTask? {
        // 注意：Widget Extension 需要配置 App Group 来共享数据
        // 这里使用简化的方式，实际需要从共享的 SwiftData store 读取
        // 或者使用 UserDefaults/App Group 来传递任务数据
        return nil
    }
}

struct TaskEntry: TimelineEntry {
    let date: Date
    let task: WidgetTask?
}

struct WidgetTask: Identifiable {
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
    var entry: TaskProvider.Entry
    
    var body: some View {
        if let task = entry.task {
            TaskWidgetView(task: task, family: .systemSmall)
        } else {
            EmptyTaskView()
        }
    }
}

struct TaskWidgetView: View {
    let task: WidgetTask
    let family: WidgetFamily
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(task: task)
        case .systemMedium:
            MediumWidgetView(task: task)
        case .systemLarge:
            LargeWidgetView(task: task)
        default:
            SmallWidgetView(task: task)
        }
    }
}

struct SmallWidgetView: View {
    let task: WidgetTask
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.isCompleted ? .green : .blue)
                Text("今天")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(task.title)
                .font(.headline)
                .lineLimit(2)
                .strikethrough(task.isCompleted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

struct MediumWidgetView: View {
    let task: WidgetTask
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(task.isCompleted ? .green : .blue)
                    Text("今天")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(task.title)
                    .font(.headline)
                    .lineLimit(2)
                    .strikethrough(task.isCompleted)
                
                if task.totalChecklistCount > 0 {
                    Text("\(task.totalChecklistCount - task.incompleteChecklistCount)/\(task.totalChecklistCount) 已完成")
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
    let task: WidgetTask
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.isCompleted ? .green : .blue)
                Text("今天")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(task.title)
                .font(.title2)
                .fontWeight(.semibold)
                .strikethrough(task.isCompleted)
            
            if !task.checklistItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("检查清单")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(task.checklistItems.sorted(by: { $0.order < $1.order }).prefix(5)) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                                .foregroundColor(item.isCompleted ? .green : .secondary)
                                .font(.caption)
                            Text(item.title)
                                .font(.caption)
                                .strikethrough(item.isCompleted)
                        }
                    }
                    
                    if task.checklistItems.count > 5 {
                        Text("还有 \(task.checklistItems.count - 5) 项...")
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

struct EmptyTaskView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("今天没有任务")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview(as: .systemSmall) {
    ThingStructWidget()
} timeline: {
    TaskEntry(date: .now, task: WidgetTask(
        id: UUID(),
        title: "示例任务",
        isCompleted: false,
        checklistItems: []
    ))
    TaskEntry(date: .now, task: nil)
}
