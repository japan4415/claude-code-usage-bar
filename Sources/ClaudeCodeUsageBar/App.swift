import SwiftUI
import AppKit

@main
struct ClaudeCodeUsageBarApp: App {
    @StateObject private var viewModel = UsageViewModel.autoStarting()

    /// Plain string for the menu bar title, updated via NotificationCenter.
    /// Using a plain `@State String` avoids the macOS SwiftUI bug where
    /// accessing `ObservableObject` / `@Observable` properties — or even
    /// updating a `@State` struct — inside a `MenuBarExtra` label causes
    /// the status item to disappear entirely.
    @State private var labelText: String = "CC \u{2014}"

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(viewModel: viewModel)
        } label: {
            Text(labelText)
                .monospacedDigit()
                .onReceive(NotificationCenter.default.publisher(for: .usageLabelDidChange)) { notification in
                    if let snapshot = notification.userInfo?["snapshot"] as? UsageLabelSnapshot {
                        labelText = UsageLabel.formatTitle(
                            fiveHourPercentage: snapshot.fiveHourPercentage,
                            sevenDayPercentage: snapshot.sevenDayPercentage,
                            displayMode: snapshot.displayMode
                        )
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}

private extension UsageViewModel {
    /// Factory used by `@StateObject` — starts file watching immediately
    /// so that the menu bar label is updated before the popover is opened.
    @MainActor
    static func autoStarting() -> UsageViewModel {
        let vm = UsageViewModel()
        vm.start()
        return vm
    }
}
