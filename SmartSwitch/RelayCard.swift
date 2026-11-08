import SwiftUI

struct RelayCard: View {
    let index: Int
    let name: String
    let isOn: Bool
    let locked: Bool
    let running: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isOn ? Theme.amber : Theme.textSecondary)
                    Spacer()
                    Circle()
                        .fill(isOn ? Theme.amber : Color.white.opacity(0.18))
                        .frame(width: 8, height: 8)
                        .shadow(color: isOn ? Theme.amber : .clear, radius: 6)
                }
                Spacer(minLength: 0)
                orb.frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                Text(name)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(running ? "Running" : (isOn ? "On" : "Off"))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(isOn ? Theme.amber : Theme.textSecondary)
                    .padding(.top, 2)
            }
            .padding(16)
            .frame(height: 196)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(
                        colors: isOn ? [Theme.amber.opacity(0.20), Theme.amber.opacity(0.04)]
                                     : [Theme.card, Theme.card],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(isOn ? Theme.amber.opacity(0.55) : Theme.stroke, lineWidth: 1)
            )
            .opacity(locked && !isOn ? 0.5 : 1)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isOn)
        }
        .buttonStyle(PressableStyle())
        .disabled(locked)
        .accessibilityLabel("\(name), \(isOn ? "on" : "off")")
    }

    private var orb: some View {
        ZStack {
            if isOn {
                Circle()
                    .fill(Theme.amber.opacity(0.40))
                    .frame(width: 84, height: 84)
                    .blur(radius: 20)
            }
            Circle()
                .fill(LinearGradient(
                    colors: isOn ? [Theme.amber, Theme.amberDeep]
                                 : [Color.white.opacity(0.11), Color.white.opacity(0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 68, height: 68)
                .overlay(Circle().stroke(Color.white.opacity(isOn ? 0.25 : 0.08), lineWidth: 1))
            Image(systemName: "power")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(isOn ? Color.black.opacity(0.78) : Color.white.opacity(0.5))
        }
    }
}
