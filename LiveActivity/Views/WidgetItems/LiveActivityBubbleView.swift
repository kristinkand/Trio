//
//  LiveActivityBubbleView.swift
//  LiveActivityExtension
//
//  Mirrors the main app's round "bobble"
//  (Trio/Sources/Modules/Home/View/Header/CurrentGlucoseView.swift) for the
//  Live Activity widget: a colored ring with a directional arrow, glucose
//  value centered inside. Built independently of CurrentGlucoseView since
//  the widget extension can't access Core Data / LoopKit types -- driven
//  purely off ActivityKit's ContentState/ContentAdditionalState instead.
//
import SwiftUI
import WidgetKit

struct LiveActivityBubbleView: View {
    @Environment(\.colorScheme) var colorScheme

    var context: ActivityViewContext<LiveActivityAttributes>
    var glucoseColor: Color

    // Same fixed rainbow ring gradient and arrow tint as CurrentGlucoseView,
    // kept visually identical between the main app and the widget.
    private let ringGradient = AngularGradient(colors: [
        Color(red: 0.7215686275, green: 0.3411764706, blue: 1),
        Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569),
        Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765),
        Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961),
        Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902),
        Color(red: 0.7215686275, green: 0.3411764706, blue: 1)
    ], center: .center, startAngle: .degrees(270), endAngle: .degrees(-90))

    private let arrowColor = Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902)

    var body: some View {
        ZStack {
            WidgetBobble(gradient: ringGradient, color: arrowColor)
                .rotationEffect(.degrees(context.state.detailedViewState.rotationDegrees))
                .scaleEffect(0.65)

            Text(context.state.bg)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(context.isStale ? .secondary : glucoseColor)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: 85, height: 85)
    }
}
