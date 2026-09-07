import SwiftUI

struct ErrorStateView: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    init(title: String, message: String, actionTitle: String = "处理", action: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

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
            Button(actionTitle) { action() }
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

