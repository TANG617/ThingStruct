import Foundation

extension ThingStructStore {
    func handleDeepLink(_ url: URL) {
        guard let route = ThingStructSystemRoute(url: url) else {
            return
        }

        switch route {
        case .now:
            selectedTab = .now

        case let .today(date, blockID, _, _):
            selectedTab = .today

            if let date {
                let localDay = date
                selectDate(localDay)
            }

            if let blockID {
                selectBlock(blockID)
            } else {
                selectBlock(nil)
            }

        case .templates:
            openSettings(destination: .templates)

        case .startCurrentBlockLiveActivity:
            startCurrentBlockLiveActivity()

        case .endCurrentBlockLiveActivity:
            endCurrentBlockLiveActivity()
        }
    }
}
