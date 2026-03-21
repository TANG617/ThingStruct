import SwiftUI

// Small reusable control for selecting weekdays while respecting "locked" weekdays.
// This is a good example of a custom SwiftUI control:
// - parent owns the state (`@Binding`)
// - child renders that state and emits user intent (`onTap`)
struct WeekdayPicker: View {
    @Binding var selectedDays: Set<Weekday>
    let occupiedDays: Set<Weekday>

    private let columns = [
        GridItem(.adaptive(minimum: 68, maximum: 96), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
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

    private func toggleDay(_ day: Weekday) {
        // Explicit animation is opt-in in SwiftUI.
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            if selectedDays.contains(day) {
                selectedDays.remove(day)
            } else {
                selectedDays.insert(day)
            }
        }
    }
}

struct WeekdayButton: View {
    let day: Weekday
    let isSelected: Bool
    let isOccupied: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // The button's visual appearance is entirely derived from state.
            // There is no imperative "set selected background color" step.
            HStack(spacing: 6) {
                Text(day.shortName)
                    .font(.subheadline.weight(.semibold))

                if isOccupied {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                }
            }
                .frame(maxWidth: .infinity, minHeight: 38)
                .padding(.horizontal, 8)
                .background(backgroundColor)
                .foregroundStyle(foregroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isSelected ? 0 : 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isOccupied)
        .accessibilityLabel(day.fullName)
        .accessibilityValue(accessibilityValue)
    }

    private var backgroundColor: Color {
        if isOccupied {
            return Color(uiColor: .tertiarySystemFill)
        }
        if isSelected {
            return Color.accentColor
        }
        return Color(uiColor: .secondarySystemGroupedBackground)
    }

    private var foregroundColor: Color {
        if isOccupied {
            return .secondary
        }
        if isSelected {
            return .white
        }
        return .primary
    }

    private var borderColor: Color {
        if isOccupied {
            return .clear
        }

        return Color.secondary.opacity(0.18)
    }

    private var accessibilityValue: String {
        if isOccupied {
            return "Unavailable"
        }

        return isSelected ? "Selected" : "Not Selected"
    }
}

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

#Preview("Weekday Button - Selected") {
    WeekdayButton(
        day: .monday,
        isSelected: true,
        isOccupied: false,
        onTap: {}
    )
    .padding()
}

#Preview("Weekday Button - Occupied") {
    WeekdayButton(
        day: .saturday,
        isSelected: false,
        isOccupied: true,
        onTap: {}
    )
    .padding()
}

#Preview("Weekday Button - Default") {
    WeekdayButton(
        day: .wednesday,
        isSelected: false,
        isOccupied: false,
        onTap: {}
    )
    .padding()
}
