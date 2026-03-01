import SwiftUI

struct MasSetupView: View {
    @Environment(BrewService.self) private var brewService

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "app.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(.pink)

            Text("Mac App Store CLI Not Installed")
                .font(.title2)
                .bold()

            Text("Brewy uses mas to manage Mac App Store apps. Install it via Homebrew to browse and view your App Store apps here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Button {
                Task { await brewService.installMas() }
            } label: {
                Label("Install mas", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            .controlSize(.large)
            .disabled(brewService.isPerformingAction)

            if brewService.isPerformingAction {
                VStack(spacing: 8) {
                    ProgressView()
                    if !brewService.actionOutput.isEmpty {
                        Text(brewService.actionOutput)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .frame(maxWidth: 400, alignment: .leading)
                            .padding(8)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                    }
                }
            }

            Link(destination: URL(string: "https://github.com/mas-cli/mas")!) {
                Label("Learn more about mas", systemImage: "globe")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .navigationTitle("Mac App Store")
    }
}
