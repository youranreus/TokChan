import SwiftUI

struct TokenBreakdownView: View {
    let breakdown: TokenBreakdown?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let breakdown {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(TokenCategory.allCases) { category in
                            let fraction = breakdown.fraction(for: category)
                            if fraction > 0 {
                                color(category)
                                    .frame(width: geometry.size.width * fraction)
                                    .overlay(alignment: .trailing) {
                                        Rectangle().fill(.background).frame(width: 1)
                                    }
                            }
                        }
                    }
                }
                .frame(height: 9)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .accessibilityHidden(true)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                          alignment: .leading, spacing: 8) {
                    ForEach(TokenCategory.allCases) { category in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Rectangle().fill(color(category)).frame(width: 6, height: 6)
                                Text(category.rawValue).font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 5) {
                                Text(DisplayFormatters.compactNumber(breakdown.value(for: category)))
                                    .fontWeight(.semibold)
                                Text(DisplayFormatters.percentage(breakdown.fraction(for: category)))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 11).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if breakdown.total == 0 {
                    Text("此范围暂无 Tokens 用量")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("Tokens 构成暂不可用")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityIdentifier("token-breakdown")
    }

    private func color(_ category: TokenCategory) -> Color {
        switch category {
        case .input: return .primary
        case .output: return .primary.opacity(0.8)
        case .cacheRead: return .primary.opacity(0.6)
        case .cacheWrite: return .primary.opacity(0.4)
        case .reasoning: return .primary.opacity(0.25)
        }
    }
}
