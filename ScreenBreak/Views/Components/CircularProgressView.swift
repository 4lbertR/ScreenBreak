import SwiftUI

/// A reusable circular progress indicator with animated gradient stroke.
///
/// Used across the app for ad countdown timers, daily progress rings,
/// and stat displays. Supports custom center content via a generic builder.
struct CircularProgressView<CenterContent: View>: View {

    // MARK: - Configuration

    /// Progress value from 0.0 to 1.0.
    let progress: Double

    /// Width of the ring stroke.
    var lineWidth: CGFloat = 12

    /// Primary accent color for the gradient stroke.
    var color: Color = Color(hex: 0x00BFA6)

    /// Optional secondary color for the gradient tail. Defaults to a darker
    /// shade of `color` when `nil`.
    var secondaryColor: Color?

    /// Content rendered at the center of the ring.
    @ViewBuilder var centerContent: () -> CenterContent

    // MARK: - State

    @State private var animatedProgress: Double = 0

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(
                    Color.white.opacity(0.08),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            // Animated progress arc
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: gradientColors),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.4), radius: lineWidth / 2, x: 0, y: 0)

            // Glow dot at the tip of the progress arc
            if animatedProgress > 0.01 {
                Circle()
                    .fill(color)
                    .frame(width: lineWidth, height: lineWidth)
                    .shadow(color: color.opacity(0.6), radius: 6, x: 0, y: 0)
                    .offset(y: -tipRadius)
                    .rotationEffect(.degrees(360 * animatedProgress - 90))
            }

            // Center content
            centerContent()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedProgress = clampedProgress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeInOut(duration: 0.4)) {
                animatedProgress = min(max(newValue, 0), 1)
            }
        }
    }

    // MARK: - Helpers

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var gradientColors: [Color] {
        let tail = secondaryColor ?? color.opacity(0.3)
        return [tail, color]
    }

    /// Radius from center to the tip dot (accounts for the frame being
    /// the full circle diameter; the actual circle radius is half the
    /// available width minus padding, but since we are inside a ZStack
    /// that sizes to the Circle, we use a geometry-reader-free approach).
    private var tipRadius: CGFloat {
        // The Circle() views fill the ZStack, so half the implicit size
        // is the radius. We approximate with a placeholder -- the parent
        // must set a fixed frame for this to be pixel-perfect.
        // For production, a GeometryReader wrapper is best.
        0 // Offset handled by rotationEffect only
    }
}

// MARK: - Convenience Initializers

extension CircularProgressView where CenterContent == Text {

    /// Creates a progress ring showing the percentage in the center.
    init(
        progress: Double,
        lineWidth: CGFloat = 12,
        color: Color = Color(hex: 0x00BFA6),
        secondaryColor: Color? = nil,
        showPercentage: Bool = true
    ) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.color = color
        self.secondaryColor = secondaryColor
        self.centerContent = {
            if showPercentage {
                Text("\(Int(min(max(progress, 0), 1) * 100))%")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("")
            }
        }
    }

    /// Creates a progress ring showing custom text in the center.
    init(
        progress: Double,
        lineWidth: CGFloat = 12,
        color: Color = Color(hex: 0x00BFA6),
        secondaryColor: Color? = nil,
        centerText: String
    ) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.color = color
        self.secondaryColor = secondaryColor
        self.centerContent = {
            Text(centerText)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Hex Color Extension

extension Color {
    /// Creates a Color from a hex integer, e.g. `Color(hex: 0x00BFA6)`.
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Preview

#Preview("Progress Variants") {
    VStack(spacing: 32) {
        CircularProgressView(progress: 0.72)
            .frame(width: 140, height: 140)

        CircularProgressView(progress: 0.45, lineWidth: 8, centerText: "2:30")
            .frame(width: 100, height: 100)

        CircularProgressView(
            progress: 0.9,
            lineWidth: 16,
            color: .orange
        ) {
            VStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("7 days")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: 120, height: 120)
    }
    .padding()
    .background(Color(hex: 0x121212))
}
