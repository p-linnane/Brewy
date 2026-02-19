import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsView: View {
    @AppStorage("brewPath") private var brewPath = "/opt/homebrew/bin/brew"
    @AppStorage("autoRefreshInterval") private var autoRefreshInterval = 0
    @AppStorage("showCasksByDefault") private var showCasksByDefault = false
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue

    var body: some View {
        Form {
            TextField("Homebrew Path:", text: $brewPath)
                .help("Path to the brew executable")

            Picker("Auto-refresh:", selection: $autoRefreshInterval) {
                Text("Off").tag(0)
                Text("Every 5 minutes").tag(300)
                Text("Every 15 minutes").tag(900)
                Text("Every hour").tag(3600)
            }

            Picker("Appearance:", selection: $appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.rawValue).tag(theme.rawValue)
                }
            }

            Toggle("Show Casks by default", isOn: $showCasksByDefault)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 450, height: 230)
    }
}
