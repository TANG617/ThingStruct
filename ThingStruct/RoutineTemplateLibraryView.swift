/*
 * RoutineTemplateLibraryView.swift
 * Routine Template Library View
 *
 * Displays all saved routine templates for management:
 * - Tap template to apply routine for today
 * - Swipe left to edit template
 * - Swipe right to delete template
 * - Add new templates
 */

import SwiftUI
import SwiftData

// MARK: - Routine Template Library View

@MainActor
struct RoutineTemplateLibraryView: View {
    
    // MARK: - Environment
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Queries
    
    @Query(sort: \RoutineTemplate.title) private var templates: [RoutineTemplate]
    @Query(sort: \StateItem.order) private var allStates: [StateItem]
    
    // MARK: - State
    
    @State private var showingAddTemplate = false
    @State private var editingTemplate: RoutineTemplate?
    
    // MARK: - Computed Properties
    
    private var today: Date {
        Calendar.current.startOfDay(for: Date.now)
    }
    
    /// 今天的所有状态
    private var todayStates: [StateItem] {
        allStates.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }
    
    /// 当前正在进行的状态（第一个未完成的）
    private var currentState: StateItem? {
        todayStates.first { !$0.isCompleted }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(templates) { template in
                    RoutineTemplateRowView(template: template) {
                        applyRoutineTemplate(template)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            editingTemplate = template
                        } label: {
                            Label("Edit", systemImage: "pencil.circle.fill")
                        }
                        .tint(.accentColor)
                    }
                }
                .onDelete(perform: deleteTemplates)
                
                if templates.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No Routine Templates", systemImage: "calendar.day.timeline.left")
                        } description: {
                            Text("Tap + to create a routine template")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Routine Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddTemplate = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .fontWeight(.medium)
                    }
                }
            }
            .sheet(isPresented: $showingAddTemplate) {
                RoutineTemplateEditView()
            }
            .sheet(item: $editingTemplate) { template in
                RoutineTemplateEditView(template: template)
            }
        }
    }
    
    // MARK: - Actions
    
    /// 手动应用 RoutineTemplate
    /// 将模板中的 states 插入到 currentState 之后
    private func applyRoutineTemplate(_ template: RoutineTemplate) {
        // 确定插入位置的 order
        let insertOrder: Int
        if let current = currentState {
            insertOrder = current.order + 1
        } else {
            // 没有当前状态，插入到最后
            insertOrder = (todayStates.map { $0.order }.max() ?? -1) + 1
        }
        
        // 更新后续 states 的 order（为新 states 腾出空间）
        let statesToShift = todayStates.filter { $0.order >= insertOrder }
        let shiftAmount = template.stateTemplates.count
        
        for state in statesToShift {
            state.order += shiftAmount
        }
        
        // 创建新的 states
        _ = template.createStates(
            for: today,
            startOrder: insertOrder,
            modelContext: modelContext
        )
        
        dismiss()
    }
    
    private func deleteTemplates(offsets: IndexSet) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            for index in offsets {
                modelContext.delete(templates[index])
            }
        }
    }
}

// MARK: - Routine Template Row View

@MainActor
struct RoutineTemplateRowView: View {
    let template: RoutineTemplate
    let onTap: () -> Void
    
    /// 重复日期的显示文本
    private var repeatDaysText: String {
        if template.repeatDays.isEmpty {
            return "Manual only"
        }
        // 按周一到周日排序显示
        let sortedDays = Weekday.mondayFirst.filter { template.repeatDays.contains($0) }
        return sortedDays.map { $0.shortName }.joined(separator: ", ")
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 12) {
                        // 状态数量
                        HStack(spacing: 4) {
                            Image(systemName: "square.stack")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(template.stateTemplates.count) states")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        // 重复日期
                        HStack(spacing: 4) {
                            Image(systemName: template.hasAutoRepeat ? "repeat" : "hand.tap")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(repeatDaysText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // 应用按钮提示
                Image(systemName: "play.circle")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RoutineTemplateRowButtonStyle())
    }
}

// MARK: - Button Style

@MainActor
struct RoutineTemplateRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.accentColor.opacity(0.15) : Color.clear)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    RoutineTemplateLibraryView()
        .modelContainer(for: [RoutineTemplate.self, StateTemplate.self, ChecklistItem.self], inMemory: true)
}
