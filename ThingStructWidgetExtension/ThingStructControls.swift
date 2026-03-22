import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct ThingStructOpenNowControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ThingStructSharedConfig.openNowControlKind) {
            ControlWidgetButton(action: OpenNowControlIntent()) {
                Label("Now", systemImage: "bolt.circle")
            }
        }
        .displayName("Open Now")
        .description("Jump straight into the Now screen.")
    }
}

@available(iOS 18.0, *)
struct ThingStructCompleteCurrentTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ThingStructSharedConfig.completeCurrentTaskControlKind) {
            ControlWidgetButton(action: CompleteCurrentTaskControlIntent()) {
                Label("Complete Current Task", systemImage: "checkmark.circle")
            }
        }
        .displayName("Complete Task")
        .description("Check off the highest-priority current task.")
    }
}

@available(iOS 18.0, *)
struct ThingStructOpenCurrentBlockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ThingStructSharedConfig.openCurrentBlockControlKind) {
            ControlWidgetButton(action: OpenCurrentBlockControlIntent()) {
                Label("Open Current Block", systemImage: "scope")
            }
        }
        .displayName("Open Current Block")
        .description("Open ThingStruct to the active block.")
    }
}

@available(iOS 18.0, *)
struct ThingStructStartLiveActivityControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ThingStructSharedConfig.startLiveActivityControlKind) {
            ControlWidgetButton(action: StartCurrentBlockLiveActivityControlIntent()) {
                Label("Start Live Activity", systemImage: "waveform.path.ecg.rectangle")
            }
        }
        .displayName("Start Live Activity")
        .description("Start tracking the active block as a Live Activity.")
    }
}
