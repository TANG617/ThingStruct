import Foundation
import SwiftUI

// Small formatting helpers often live in shared files like this in SwiftUI projects.
// The goal is to keep domain logic elsewhere and put display-only helpers here.
extension Int {
    var formattedTime: String {
        let hour = self / 60
        let minute = self % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    var timelineLayerBadgeTitle: String {
        self == 0 ? "Base" : "L\(self)"
    }

    var nextTimelineLayerTitle: String {
        (self + 1).timelineLayerBadgeTitle
    }

    var addNextTimelineLayerActionTitle: String {
        "Add \(nextTimelineLayerTitle)"
    }

    var newNextTimelineLayerActionTitle: String {
        "New \(nextTimelineLayerTitle)"
    }
}

extension LocalDay {
    var titleText: String {
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = Calendar.current.date(from: components) else {
            return description
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    var nowNavigationTitle: String {
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = Calendar.current.date(from: components) else {
            return description
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: date)
    }
}


struct ScreenLoadingView: View {
    let title: String
    let systemImage: String
    var description: String?

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)

            Label(title, systemImage: systemImage)
                .font(.headline)

            if let description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct RecoverableErrorView: View {
    let title: String
    let message: String
    var retryTitle = "Retry"
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(retryTitle, action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// Many root screens in the app follow the same control flow:
// 1. Show a loading placeholder before the store is ready.
// 2. Try to build a screen model.
// 3. Show either the screen content or a recoverable error.
//
// This shared wrapper keeps that pattern consistent across tabs.
struct RootScreenContainer<Value, Content: View>: View {
    let isLoaded: Bool
    let loadingTitle: String
    let loadingSystemImage: String
    let loadingDescription: String
    let errorTitle: String
    let retry: () -> Void
    let load: () throws -> Value
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        Group {
            if !isLoaded {
                ScreenLoadingView(
                    title: loadingTitle,
                    systemImage: loadingSystemImage,
                    description: loadingDescription
                )
            } else {
                switch Result(catching: load) {
                case let .success(value):
                    content(value)

                case let .failure(error):
                    RecoverableErrorView(
                        title: errorTitle,
                        message: error.localizedDescription,
                        retry: retry
                    )
                }
            }
        }
    }
}

#Preview("Loading State") {
    ScreenLoadingView(
        title: "Loading Today",
        systemImage: "calendar",
        description: "Preparing your timeline and current context."
    )
}

#Preview("Recoverable Error") {
    RecoverableErrorView(
        title: "Unable to Load Templates",
        message: "The preview is simulating a recoverable state."
    ) {}
}

#Preview("Root Screen Container") {
    RootScreenContainer(
        isLoaded: true,
        loadingTitle: "Loading",
        loadingSystemImage: "clock",
        loadingDescription: "Previewing a shared screen wrapper.",
        errorTitle: "Error",
        retry: {}
    ) {
        "Preview"
    } content: { value in
        Text(value)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Layer Palette") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(0 ... 4, id: \.self) { layer in
            let style = LayerVisualStyle.forBlock(layerIndex: layer, isBlank: false)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(style.strongSurface)
                    .frame(width: 58, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(style.border, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Layer \(layer)")
                        .font(.headline)
                    Text("Higher layer keeps the same hue, but gets darker.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(style.badgeForeground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(style.badgeBackground, in: Capsule())
            }
            .padding(14)
            .background(style.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }

        let blankStyle = LayerVisualStyle.forBlock(layerIndex: 0, isBlank: true)
        Text("Blank blocks stay neutral.")
            .font(.subheadline)
            .foregroundStyle(blankStyle.accent)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(blankStyle.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}
