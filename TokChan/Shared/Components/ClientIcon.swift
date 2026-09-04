import SwiftUI

struct ClientIcon: View {
    let clientID: String

    static let knownClients: Set<String> = [
        "amp",
        "antigravity",
        "cherrystudio",
        "claude",
        "codebuff",
        "copilot",
        "crush",
        "cursor",
        "devin",
        "droid",
        "freebuff",
        "fx",
        "gemini",
        "goose",
        "hermes",
        "hindsight",
        "jcode",
        "kilocode",
        "kimi",
        "mux",
        "openai",
        "openclaw",
        "opencode",
        "pi",
        "qwen",
        "roocode",
        "sakana",
        "senpi",
        "synthetic",
        "trae",
        "zed",
    ]

    static func assetName(for clientID: String) -> String? {
        let normalized = clientID.lowercased()
        let aliases = ["codex": "openai", "kilo": "kilocode", "claude-code": "claude",
                       "github-copilot": "copilot", "roo": "roocode"]
        let name = aliases[normalized] ?? normalized
        return knownClients.contains(name) ? "client-\(name)" : nil
    }

    var body: some View {
        Group {
            if let name = Self.assetName(for: clientID) {
                Image(name).resizable().scaledToFit()
            } else {
                Image(systemName: "terminal").resizable().scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }
}
