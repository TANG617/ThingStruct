import SwiftUI
import WidgetKit

@main
struct ThingStructWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ThingStructNowWidget()

        if #available(iOS 16.1, *) {
            ThingStructCurrentBlockLiveActivity()
        }

        if #available(iOS 18.0, *) {
            ThingStructOpenNowControl()
            ThingStructCompleteCurrentTaskControl()
            ThingStructOpenCurrentBlockControl()
            ThingStructStartLiveActivityControl()
        }
    }
}
