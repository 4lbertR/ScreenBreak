import Foundation
import SwiftUI

// MARK: - Date + Extensions

extension Date {

    /// Midnight (00:00:00) of the receiver's calendar day in the current time zone.
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// The beginning of the hour that contains the receiver.
    var startOfHour: Date {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour],
            from: self
        )
        return Calendar.current.date(from: components) ?? self
    }

    /// Human-readable relative string such as "2 min ago" or "Yesterday".
    var timeAgoString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: .now)
    }

    /// Short date string, e.g. "Feb 16, 2026".
    var shortDateString: String {
        formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// Time-only string, e.g. "3:42 PM".
    var shortTimeString: String {
        formatted(.dateTime.hour().minute())
    }

    /// Compact date + time, e.g. "Feb 16, 3:42 PM".
    var compactDateTimeString: String {
        formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    /// `true` if the receiver falls on the same calendar day as today.
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// `true` if the receiver falls on yesterday's calendar day.
    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    /// Returns a date that is `minutes` minutes after the receiver.
    func adding(minutes: Int) -> Date {
        addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// Returns a date that is `seconds` seconds after the receiver.
    func adding(seconds: Int) -> Date {
        addingTimeInterval(TimeInterval(seconds))
    }
}

// MARK: - TimeInterval + Extensions

extension TimeInterval {

    /// Long human-readable format, e.g. "2h 15m" or "45m" or "30s".
    var shortFormatted: String {
        let totalSeconds = Int(self)
        let hours   = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(seconds)s"
        }
    }

    /// Countdown-style string, e.g. "02:15" or "1:03:09".
    var countdownFormatted: String {
        let totalSeconds = Int(self)
        let hours   = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Converts to whole minutes, rounding up.
    var wholeMinutesCeil: Int {
        Int((self / 60).rounded(.up))
    }
}

// MARK: - View + Card Style

extension View {

    /// Applies the standard ScreenBreak card appearance: rounded corners,
    /// dark background, subtle shadow.
    func cardStyle(cornerRadius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color.cardDark)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
    }

    /// A translucent "glass morphism" card effect.
    func glassMorphism(
        cornerRadius: CGFloat = 20,
        blurRadius: CGFloat = 10,
        opacity: Double = 0.15
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(opacity)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.3),
                                .white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: blurRadius, x: 0, y: 4)
    }

    /// Applies a standard fade-in entrance animation.
    func fadeInAnimation(delay: Double = 0) -> some View {
        self
            .opacity(0)
            .animation(
                .easeOut(duration: 0.5).delay(delay),
                value: UUID() // triggers once on appear
            )
    }
}

// MARK: - Color + Brand Palette

extension Color {

    // MARK: Primary

    /// Brand teal used for primary actions, links, and accent elements.
    static let brandTeal = Color(red: 0.00, green: 0.80, blue: 0.78)

    /// Slightly lighter teal for hover / pressed states.
    static let brandTealLight = Color(red: 0.20, green: 0.90, blue: 0.88)

    // MARK: Backgrounds

    /// Main app background (very dark blue-grey).
    static let backgroundDark = Color(red: 0.07, green: 0.07, blue: 0.12)

    /// Secondary background for elevated surfaces.
    static let backgroundElevated = Color(red: 0.11, green: 0.11, blue: 0.18)

    /// Card / tile background.
    static let cardDark = Color(red: 0.13, green: 0.13, blue: 0.20)

    // MARK: Semantic

    /// Success / goal-met / positive feedback.
    static let successGreen = Color(red: 0.20, green: 0.84, blue: 0.48)

    /// Warning / approaching-limit / caution.
    static let warningOrange = Color(red: 1.00, green: 0.62, blue: 0.04)

    /// Danger / over-limit / destructive action.
    static let dangerRed = Color(red: 1.00, green: 0.27, blue: 0.33)

    // MARK: Text

    /// Primary text on dark backgrounds.
    static let textPrimary = Color.white

    /// Secondary / muted text.
    static let textSecondary = Color.white.opacity(0.6)

    /// Tertiary / hint text.
    static let textTertiary = Color.white.opacity(0.35)

    // MARK: Gradients (helpers)

    /// Teal-to-blue gradient used behind prominent CTAs.
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brandTeal, Color(red: 0.10, green: 0.50, blue: 0.95)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Dark gradient for full-screen backgrounds.
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundDark, Color(red: 0.04, green: 0.04, blue: 0.09)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - ShapeStyle + Brand Gradient

extension ShapeStyle where Self == LinearGradient {
    /// Convenience accessor for the brand gradient that works in any
    /// `ShapeStyle` context (e.g. `.foregroundStyle(.brandGradient)`).
    static var brandGradient: LinearGradient { Color.brandGradient }
}
