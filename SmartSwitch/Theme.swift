import SwiftUI
import UIKit

enum Theme {
    static let bgTop = Color(red: 0.043, green: 0.043, blue: 0.063)
    static let bgBottom = Color(red: 0.095, green: 0.075, blue: 0.125)
    static let amber = Color(red: 1.0, green: 0.69, blue: 0.18)
    static let amberDeep = Color(red: 1.0, green: 0.48, blue: 0.10)
    static let card = Color.white.opacity(0.055)
    static let stroke = Color.white.opacity(0.09)
    static let textSecondary = Color.white.opacity(0.55)
    static let danger = Color(red: 1.0, green: 0.38, blue: 0.38)
    static let good = Color(red: 0.36, green: 0.85, blue: 0.56)

    static var amberGradient: LinearGradient {
        LinearGradient(colors: [amber, amberDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.amber.opacity(0.14), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 26) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

func formatDuration(_ ms: Int) -> String {
    if ms < 1000 { return "\(ms) ms" }
    if ms < 60_000 {
        let s = Double(ms) / 1000
        return s == s.rounded() ? "\(Int(s)) s" : String(format: "%.1f s", s)
    }
    let m = Double(ms) / 60_000
    return m == m.rounded() ? "\(Int(m)) min" : String(format: "%.1f min", m)
}
