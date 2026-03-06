import SwiftUI

struct DryRunConfirmationSheet: View {
    @Environment(\.dismiss)
    private var dismiss
    let title: String
    let message: String
    let confirmLabel: String
    let dryRunAction: @MainActor () async -> String
    let confirmAction: @MainActor () async -> Void

    @State private var isLoadingPreview = true
    @State private var previewOutput = ""
    @State private var hasLoadedPreview = false

    var body: some View {
        VStack(spacing: 16) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            previewSection

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmLabel, role: .destructive) {
                    dismiss()
                    Task { await confirmAction() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isLoadingPreview)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task {
            guard !hasLoadedPreview else { return }
            hasLoadedPreview = true
            previewOutput = await dryRunAction()
            isLoadingPreview = false
        }
    }

    @ViewBuilder private var previewSection: some View {
        if isLoadingPreview {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading preview\u{2026}")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        } else if previewOutput.isEmpty {
            Text("No specific files listed. The operation may still free up space.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        } else {
            ScrollView {
                Text(previewOutput)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 300)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        }
    }
}
