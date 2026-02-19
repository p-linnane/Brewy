import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var release: AppcastRelease?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 520, height: 400)
        .task { await fetchLatestRelease() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("What's New")
                    .font(.title2)
                    .fontWeight(.semibold)
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text("Brewy \(version)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack {
                Spacer()
                ProgressView("Loading release notes…")
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let errorMessage {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await fetchLatestRelease() }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else if let release {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(release.version ?? release.title)
                            .font(.headline)
                        if let date = release.publishedDate {
                            Spacer()
                            Text(date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let html = release.descriptionHTML,
                       let attributed = Self.attributedString(from: html) {
                        Text(attributed)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - HTML Rendering

    private static func attributedString(from html: String) -> AttributedString? {
        guard let data = html.data(using: .utf8),
              let nsAttr = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
              )
        else { return nil }
        return try? AttributedString(nsAttr, including: \.swiftUI)
    }

    // MARK: - Networking

    private func fetchLatestRelease() async {
        isLoading = true
        errorMessage = nil

        guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feedURL) else {
            errorMessage = "No update feed configured."
            isLoading = false
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                errorMessage = "Failed to load release notes.\nPlease check your internet connection."
                isLoading = false
                return
            }

            let parser = AppcastParser()
            release = parser.parse(data: data)

            if release == nil {
                errorMessage = "No release notes found."
            }
            isLoading = false
        } catch {
            errorMessage = "Failed to load release notes.\n\(error.localizedDescription)"
            isLoading = false
        }
    }
}
