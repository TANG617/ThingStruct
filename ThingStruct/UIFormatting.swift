import Foundation
import SwiftUI

// 这个文件放的是“只服务展示”的小工具。
// 一个很重要的分层习惯是：
// - 业务规则放 Engine / Store / Repository
// - 纯显示格式化放到这种 shared UI helper 里
// 这样可以避免 domain model 被 UI 文案细节污染。
extension Int {
    var formattedTime: String {
        // 这里把“分钟数”格式化成 `HH:mm`。
        let hour = self / 60
        let minute = self % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    var timelineLayerBadgeTitle: String {
        // layer 0 叫 Base，更高层叫 L1/L2/L3...
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
        // `LocalDay` 是项目自己的日期值类型，不是 Foundation 的 `Date`。
        // 如果要展示给用户看，通常要先还原成 `Date` 再交给 `DateFormatter`。
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
        // `Now` 页顶部标题故意固定成英文缩写风格，避免受当前系统语言格式影响太大。
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


// 通用加载占位视图。
// 多个根页面都会复用它，而不是每个页面自己拼一个 loading UI。
struct ScreenLoadingView: View {
    let title: String
    let systemImage: String
    var description: String?

    var body: some View {
        // SwiftUI 的视图本质就是返回一棵声明式视图树。
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

// 可恢复错误视图。
// 它不是致命崩溃，而是“给用户一个 retry 入口”的失败状态。
struct RecoverableErrorView: View {
    let title: String
    let message: String
    var retryTitle = "Retry"
    let retry: () -> Void

    var body: some View {
        // `ContentUnavailableView` 是系统提供的标准空状态/错误状态容器。
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

// 多个根页面都有同一套控制流：
// 1. store 还没准备好时显示 loading
// 2. 尝试构建 screen model
// 3. 成功则渲染内容，失败则展示可恢复错误
//
// 这个泛型容器把这套流程统一了，避免每个 tab 页面重复写。
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
                // `Result(catching:)` 是项目里对“可能抛错的加载过程”做 UI 分支的简洁写法。
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

// 下面这些 `#Preview` 主要用来单独验证通用 UI 组件，而不是跑完整页面。
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
            let style = LayerVisualStyle.forBlock(layerIndex: layer, isBlank: false, preset: .ocean)
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

        let blankStyle = LayerVisualStyle.forBlock(layerIndex: 0, isBlank: true, preset: .ocean)
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
