import Combine
import Sparkle
import SwiftUI

/// Wraps Sparkle's SPUStandardUpdaterController for SwiftUI consumption.
///
/// Instantiate once in `RunwayApp` and pass the `.updater` to views that
/// need check-for-updates or auto-update-toggle functionality.
@MainActor
final class AppUpdaterController {
    let controller: SPUStandardUpdaterController

    var updater: SPUUpdater { controller.updater }

    init() {
        // startingUpdater: true → begins automatic background checks on launch
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
}

// MARK: - CheckForUpdatesViewModel

/// Bridges Sparkle's KVO `canCheckForUpdates` into a SwiftUI-observable property.
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: \.canCheckForUpdates, on: self)
    }
}

// MARK: - CheckForUpdatesView

/// A button that triggers a manual update check. Suitable for menus and settings.
struct CheckForUpdatesView: View {
    @StateObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self._viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates\u{2026}", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

// MARK: - AutoUpdateToggleView

/// A toggle that controls Sparkle's automatic update checking preference.
struct AutoUpdateToggleView: View {
    private let updater: SPUUpdater
    @State private var automaticallyChecks: Bool

    init(updater: SPUUpdater) {
        self.updater = updater
        self._automaticallyChecks = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        Toggle("Automatically check for updates", isOn: $automaticallyChecks)
            .onChange(of: automaticallyChecks) { _, newValue in
                updater.automaticallyChecksForUpdates = newValue
            }
    }
}
