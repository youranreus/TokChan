import SwiftUI

struct ClientIcon: View {
    let clientID: String

    /// Server-facing client IDs declared by Tokscale's SUPPORTED_CLIENT_TYPES.
    static let tokscaleClientIDs: Set<String> = [
        "9router", "amp", "antigravity", "antigravity-cli", "augment",
        "cherrystudio", "claude", "cline", "codebuddy", "codebuff", "codex",
        "commandcode", "copilot", "crush", "cursor", "devin-cli", "devin-desktop",
        "droid", "dsh", "freebuff", "fx", "gemini", "gjc", "goose", "grok",
        "hermes", "hindsight", "jcode", "junie", "kilocode", "kimchi", "kimi",
        "kiro", "kilo", "lmstudio", "mcode", "micode", "mux", "omp",
        "openclaw", "opencode", "opencodereview", "pi", "prime-agent", "qwen",
        "reasonix", "roocode", "senpi", "synthetic", "trae", "unsloth", "warp",
        "workbuddy", "zcode", "zed",
    ]

    /// Includes current Tokscale IDs and legacy identifiers accepted by older snapshots.
    static let knownClients = Set(assetNamesByClientID.keys)

    private static let assetNamesByClientID: [String: String] = [
        "9router": "client-gjc",
        "amp": "client-amp",
        "antigravity": "client-antigravity",
        "antigravity-cli": "client-antigravity",
        "augment": "client-augment",
        "cherrystudio": "client-cherrystudio",
        "claude": "client-claude",
        "claude-code": "client-claude",
        "cline": "client-cline",
        "codebuddy": "client-codebuddy",
        "codebuff": "client-codebuff",
        "codex": "client-openai",
        "commandcode": "client-commandcode",
        "copilot": "client-copilot",
        "crush": "client-crush",
        "cursor": "client-cursor",
        "devin": "client-devin",
        "devin-cli": "client-devin",
        "devin-desktop": "client-devin",
        "droid": "client-droid",
        "dsh": "client-dsh",
        "freebuff": "client-freebuff",
        "fx": "client-fx",
        "gemini": "client-gemini",
        "github-copilot": "client-copilot",
        "gjc": "client-gjc",
        "goose": "client-goose",
        "grok": "client-grok",
        "hermes": "client-hermes",
        "hindsight": "client-hindsight",
        "jcode": "client-jcode",
        "junie": "client-junie",
        "kilocode": "client-kilocode",
        "kimchi": "client-kimchi",
        "kimi": "client-kimi",
        "kiro": "client-kiro",
        "kilo": "client-kilocode",
        "lmstudio": "client-lmstudio",
        "mcode": "client-mcode",
        "micode": "client-micode",
        "mux": "client-mux",
        "omp": "client-omp",
        "openai": "client-openai",
        "openclaw": "client-openclaw",
        "opencode": "client-opencode",
        "opencodereview": "client-opencodereview",
        "pi": "client-pi",
        "prime-agent": "client-prime-agent",
        "qwen": "client-qwen",
        "reasonix": "client-synthetic",
        "roo": "client-roocode",
        "roocode": "client-roocode",
        "sakana": "client-sakana",
        "senpi": "client-senpi",
        "synthetic": "client-synthetic",
        "trae": "client-trae",
        "unsloth": "client-unsloth",
        "warp": "client-warp",
        "workbuddy": "client-workbuddy",
        "zcode": "client-zcode",
        "zed": "client-zed",
    ]

    static func assetName(for clientID: String) -> String? {
        assetNamesByClientID[clientID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    var body: some View {
        Group {
            if let name = Self.assetName(for: clientID) {
                Image(name)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "terminal")
                    .resizable()
                    .scaledToFit()
                    .padding(3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
        .accessibilityHidden(true)
    }
}
