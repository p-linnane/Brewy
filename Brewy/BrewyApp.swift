import Sparkle
import SwiftUI

@main
struct BrewyApp: App {
    @State private var brewService = BrewService()
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue

    // HACK: there is a known color scheme bug in SwiftUI where passing `nil` to `.preferredColorScheme`
    // doesn't change the color of some elements:
    // https://stackoverflow.com/questions/76123702/preferredcolorschemenil-visual-bug-when-switching-to-system-light-dark-more
    private var systemColorScheme: ColorScheme? {
        switch NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) {
        case .aqua: .light
        case .darkAqua: .dark
        default: nil
        }
    }

    private var preferredColorScheme: ColorScheme? {
        AppTheme(rawValue: appTheme)?.colorScheme
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(brewService)
                .preferredColorScheme(preferredColorScheme ?? systemColorScheme)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(after: .newItem) {
                Button("Refresh Packages") {
                    Task { await brewService.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Upgrade All") {
                    Task { await brewService.upgradeAll() }
                }
                .keyboardShortcut("u", modifiers: .command)

                Button("Cleanup...") {
                    Task { await brewService.cleanup() }
                }
            }
            CommandGroup(replacing: .help) {
                Button("What's New") {
                    NotificationCenter.default.post(name: .showWhatsNew, object: nil)
                }
            }
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra {
            MenuBarView()
                .environment(brewService)
        } label: {
            let count = brewService.outdatedPackages.count
            Label(
                count > 0 ? "\(count)" : "Brewy",
                systemImage: count > 0 ? "mug.fill" : "mug"
            )
        }
    }
}

// MARK: - Sparkle Updates

private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

private struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

// MARK: - Menu Bar View

private struct MenuBarView: View {
    @Environment(BrewService.self) private var brewService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let outdatedCount = brewService.outdatedPackages.count

        if outdatedCount > 0 {
            Text("\(outdatedCount) package\(outdatedCount == 1 ? "" : "s") outdated")
            Divider()
            Button("Upgrade All") {
                Task { await brewService.upgradeAll() }
            }
        } else {
            Text("All packages up to date")
        }

        Divider()

        Button("Refresh") {
            Task { await brewService.refresh() }
        }
        .keyboardShortcut("r")

        Divider()

        Button("Open Brewy") {
            openWindow(id: "main")
        }
        .keyboardShortcut("o")

        Button("Quit Brewy") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
