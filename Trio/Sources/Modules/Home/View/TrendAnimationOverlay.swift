import SwiftUI

/// Maps the current glucose trend arrow onto one of five little animated "vehicles" -- reusing
/// the exact same 5-way bucketing `CurrentGlucoseView` already uses to rotate the trend arrow
/// (steep up / 45° up / flat / 45° down / steep down), so this never disagrees with the arrow
/// itself.
enum TrendMood: CaseIterable {
    case up
    case slightUp
    case stable
    case slightDown
    case down

    init?(direction: BloodGlucose.Direction?) {
        switch direction {
        case .doubleUp,
             .singleUp,
             .tripleUp:
            self = .up
        case .fortyFiveUp:
            self = .slightUp
        case .flat:
            self = .stable
        case .fortyFiveDown:
            self = .slightDown
        case .doubleDown,
             .singleDown,
             .tripleDown:
            self = .down
        default:
            // nil, .none ("NONE"), .notComputable, .rateOutOfRange: nothing sensible to animate
            return nil
        }
    }

    var emoji: String {
        switch self {
        case .up: return "🚀"
        case .slightUp: return "🛫"
        case .stable: return "🛸"
        case .slightDown: return "🛬"
        case .down: return "🪂"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .up: return String(localized: "Glucose rising quickly", comment: "Trend animation accessibility label")
        case .slightUp: return String(localized: "Glucose rising slowly", comment: "Trend animation accessibility label")
        case .stable: return String(localized: "Glucose stable", comment: "Trend animation accessibility label")
        case .slightDown: return String(
                localized: "Glucose falling slowly",
                comment: "Trend animation accessibility label"
            )
        case .down: return String(localized: "Glucose falling quickly", comment: "Trend animation accessibility label")
        }
    }
}

/// A small, centered, self-dismissing animation that echoes the current trend arrow with a
/// themed vehicle -- a rocket taking straight up, a plane climbing or descending on a diagonal, a
/// hovering UFO for flat, and a parachute drifting straight down. Reappears whenever a fresh
/// glucose reading changes the trend, and taps anywhere within its frame (i.e. anywhere on the
/// Home dashboard, per how this is placed in `HomeLayout.swift`) dismiss it until the next
/// reading.
struct TrendAnimationOverlay: View {
    let direction: BloodGlucose.Direction?
    let readingDate: Date?

    @State private var isDismissed = false
    @State private var lastReadingDate: Date?

    private var mood: TrendMood? { TrendMood(direction: direction) }

    var body: some View {
        ZStack {
            if let mood, !isDismissed {
                // Fills the whole dashboard area so a tap anywhere on the Home screen dismisses
                // the animation, not just a tap directly on the icon.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isDismissed = true
                        }
                    }

                AnimatedTrendIcon(mood: mood)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: readingDate) {
            guard readingDate != lastReadingDate else { return }
            lastReadingDate = readingDate
            isDismissed = false
        }
    }
}

/// The vehicle itself -- deliberately compact (the whole badge, including its soft backing
/// circle, stays under 90pt across) so it sits quietly in the middle of the dashboard rather than
/// covering the chart or header panels.
private struct AnimatedTrendIcon: View {
    let mood: TrendMood

    @State private var animate = false

    var body: some View {
        Text(mood.emoji)
            .font(.system(size: 46))
            .padding(16)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 6)
            )
            .rotationEffect(.degrees(rotationDegrees))
            .offset(x: offset.x, y: offset.y)
            .accessibilityLabel(Text(mood.accessibilityDescription))
            .onAppear {
                withAnimation(.easeInOut(duration: animationDuration).repeatForever(autoreverses: true)) {
                    animate = true
                }
            }
    }

    private var animationDuration: Double {
        switch mood {
        case .up,
             .down:
            return 0.6
        case .slightUp,
             .slightDown:
            return 1.1
        case .stable:
            return 1.6
        }
    }

    private var rotationDegrees: Double {
        switch mood {
        case .up:
            return animate ? -8 : 8
        case .down:
            return animate ? 8 : -8
        case .slightUp:
            return -18
        case .slightDown:
            return 18
        case .stable:
            return animate ? 6 : -6
        }
    }

    /// Straight-line vehicles (rocket/parachute) bob vertically; diagonal ones (the two planes)
    /// glide along their climb/descent line; the UFO just hovers side to side.
    private var offset: (x: CGFloat, y: CGFloat) {
        switch mood {
        case .up:
            return (0, animate ? -16 : 4)
        case .slightUp:
            return animate ? (10, -12) : (-10, 4)
        case .stable:
            return (animate ? 10 : -10, 0)
        case .slightDown:
            return animate ? (10, 12) : (-10, -4)
        case .down:
            return (0, animate ? 16 : -4)
        }
    }
}
