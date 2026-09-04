import SwiftUI

struct ErrorStateView: View {
    let title: String
    let message: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(4)
                .help(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Button("处理") { action() }
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

