/*
 * WeekdayPicker.swift
 * 星期选择器组件
 *
 * 用于选择 RoutineTemplate 的重复日期
 * 显示 7 个圆形按钮（Mon-Sun），支持多选
 */

import SwiftUI

// MARK: - WeekdayPicker

/// 星期选择器
/// 显示 7 个圆形按钮，支持多选
struct WeekdayPicker: View {
    
    // MARK: - Properties
    
    /// 已选择的日期（双向绑定）
    @Binding var selectedDays: Set<Weekday>
    
    /// 被其他模板占用的日期（不可选择）
    let occupiedDays: Set<Weekday>
    
    // MARK: - Body
    
    var body: some View {
        HStack(spacing: 8) {
            // 按周一到周日的顺序显示（更符合习惯）
            ForEach(Weekday.mondayFirst) { day in
                WeekdayButton(
                    day: day,
                    isSelected: selectedDays.contains(day),
                    isOccupied: occupiedDays.contains(day),
                    onTap: { toggleDay(day) }
                )
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Actions
    
    private func toggleDay(_ day: Weekday) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            if selectedDays.contains(day) {
                selectedDays.remove(day)
            } else {
                selectedDays.insert(day)
            }
        }
    }
}

// MARK: - WeekdayButton

/// 单个星期按钮
/// 圆形，显示星期缩写（Mon, Tue 等）
struct WeekdayButton: View {
    
    // MARK: - Properties
    
    let day: Weekday
    let isSelected: Bool
    let isOccupied: Bool
    let onTap: () -> Void
    
    // MARK: - Body
    
    var body: some View {
        Button(action: onTap) {
            Text(day.shortName)
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 40, height: 40)
                .background(backgroundColor)
                .foregroundStyle(foregroundColor)
                .clipShape(Circle())
                .overlay {
                    // 未选中时显示边框
                    if !isSelected && !isOccupied {
                        Circle()
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isOccupied)
    }
    
    // MARK: - Computed Properties
    
    private var backgroundColor: Color {
        if isOccupied {
            return Color.gray.opacity(0.2)
        }
        if isSelected {
            return Color.accentColor
        }
        return Color.clear
    }
    
    private var foregroundColor: Color {
        if isOccupied {
            return .gray
        }
        if isSelected {
            return .white
        }
        return .primary
    }
}

// MARK: - Preview

#Preview("WeekdayPicker") {
    struct PreviewWrapper: View {
        @State private var selected: Set<Weekday> = [.monday, .wednesday, .friday]
        let occupied: Set<Weekday> = [.saturday, .sunday]
        
        var body: some View {
            VStack(spacing: 20) {
                Text("Selected: \(selected.map { $0.shortName }.joined(separator: ", "))")
                
                WeekdayPicker(selectedDays: $selected, occupiedDays: occupied)
                
                Text("(Sat, Sun are occupied)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}
