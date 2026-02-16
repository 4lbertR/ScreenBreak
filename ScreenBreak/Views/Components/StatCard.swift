import SwiftUI

/// A reusable statistics card component with dark glass-morphism styling.
///
/// Used across the Dashboard and Stats views to present key metrics
/// with an icon, title, value, and optional subtitle. Supports three
/// size variants: `.compact`, `.regular`, and `.large`.
struct StatCard: View {

    // MARK: - Configuration

    /// SF Symbol name for the leading icon.
    let icon: String

    /// Short label describing the stat (e.g. "Time Saved").
    let title: String

    /// The primary value to display (e.g. "2h 15m").
    let value: String

    /// Optional secondary text below the value.
    var subtitle: String? = nil

    /// Controls padding, font sizes, and minimum dimensions.
    var size: CardSize = .regular

    /// Accent color used for the icon and subtle highlights.
    var accentColor: Color = Color(hex: 0x00BFA6)

    // MARK: - Size Variant

    enum CardSize {
        case compact
        case regular
        case large

        var iconFont: Font {
            switch self {
            case .compact: return .body
            case .regular: return .title3
            case .large:   return .title
            }
        }

        var valueFont: Font {
            switch self {
            case .compact: return .system(.body, design: .rounded, weight: .bold)
            case .regular: return .system(.title3, design: .rounded, weight: .bold)
            case .large:   return .system(.title, design: .rounded, weight: .bold)
            }
        }

        var titleFont: Font {
            switch self {
            case .compact: return .caption
            case .regular: return .caption
            case .large:   return .subheadline
            }
        }

        var padding: CGFloat {
            switch self {
            case .compact: return 12
            case .regular: return 16
            case .large:   return 20
            }
        }

        var iconContainerSize: CGFloat {
            switch self {
            case .compact: return 32
            case .regular: return 40
            case .large:   return 48
            }
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 14) {
            // Icon container
            ZStack {
                RoundedRectangle(cornerRadius: size == .compact ? 8 : 10, style: .continuous)
                    .fill(accentColor.opacity(0.15))

                Image(systemName: icon)
                    .font(size.iconFont)
                    .fontWeight(.semibold)
                    .foregroundStyle(accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: size.iconContainerSize, height: size.iconContainerSize)

            // Text content
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(size.titleFont)
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(value)
                    .font(size.valueFont)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())

                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()
        }
        .padding(size.padding)
        .background {
            RoundedRectangle(cornerRadius: size == .compact ? 12 : 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .overlay {
            RoundedRectangle(cornerRadius: size == .compact ? 12 : 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.12),
                            .white.opacity(0.04),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Wide Stat Card Variant

/// A wider stat card that stacks the value prominently, used for hero metrics.
struct WideStatCard: View {

    let icon: String
    let title: String
    let value: String
    var subtitle: String? = nil
    var accentColor: Color = Color(hex: 0x00BFA6)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(accentColor)
                    .symbolRenderingMode(.hierarchical)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()
            }

            Text(value)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.12),
                            .white.opacity(0.04),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Preview

#Preview("Stat Cards") {
    ScrollView {
        VStack(spacing: 16) {
            StatCard(
                icon: "clock.fill",
                title: "Time Saved",
                value: "2h 15m",
                subtitle: "Today",
                size: .compact
            )

            StatCard(
                icon: "lock.open.fill",
                title: "Unlocks",
                value: "5",
                subtitle: "3 less than yesterday"
            )

            StatCard(
                icon: "play.rectangle.fill",
                title: "Ad Time",
                value: "12m 30s",
                size: .large,
                accentColor: .orange
            )

            WideStatCard(
                icon: "flame.fill",
                title: "Current Streak",
                value: "14 days",
                subtitle: "Your longest: 21 days",
                accentColor: .orange
            )
        }
        .padding()
    }
    .background(Color(hex: 0x121212))
}
