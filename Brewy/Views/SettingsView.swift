import SwiftUI

struct SettingsView: View {
    @AppStorage("brewPath") private var brewPath = "/opt/homebrew/bin/brew"
    @AppStorage("autoRefreshInterval") private var autoRefreshInterval = 0
    @AppStorage("showCasksByDefault") private var showCasksByDefault = false

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

            Toggle("Show Casks by default", isOn: $showCasksByDefault)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 450, height: 200)
    }
}
