import SwiftUI

struct CycleCard: View {
    @EnvironmentObject var store: DeviceStore
    @FocusState private var focused: Bool

    private let presets = [250, 500, 1000, 5000, 30000, 60000]

    private var enabled: Bool { store.snapshot.cycleEnabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cycle mode")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Relays switch on one after another, in a loop.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { store.snapshot.cycleEnabled },
                    set: { store.setCycle(enabled: $0) }))
                    .labelsHidden()
                    .tint(Theme.amber)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ON TIME PER RELAY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    HStack {
                        TextField("60000", text: $store.cycleInputMs)
                            .keyboardType(.numberPad)
                            .focused($focused)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text("ms")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.28)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(focused ? Theme.amber.opacity(0.7) : Theme.stroke, lineWidth: 1))

                    if enabled {
                        Button {
                            focused = false
                            store.applyCycleTime()
                        } label: {
                            Text("Apply")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.85))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(Theme.amberGradient))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { p in
                        Button {
                            store.cycleInputMs = String(p)
                            Haptics.tap()
                        } label: {
                            Text(formatDuration(p))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(store.cycleInputMs == String(p)
                                                           ? Theme.amber.opacity(0.22) : Color.white.opacity(0.07)))
                                .overlay(Capsule().stroke(store.cycleInputMs == String(p)
                                                          ? Theme.amber.opacity(0.6) : Color.clear, lineWidth: 1))
                                .foregroundStyle(store.cycleInputMs == String(p) ? Theme.amber : Color.white.opacity(0.8))
                        }
                    }
                }
            }

            if enabled {
                HStack(spacing: 8) {
                    Circle().fill(Theme.amber).frame(width: 7, height: 7)
                        .shadow(color: Theme.amber, radius: 5)
                    Text(statusText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.amber)
                }
                .transition(.opacity)
            }
        }
        .padding(20)
        .cardStyle()
        .animation(.easeInOut(duration: 0.25), value: enabled)
        .onChange(of: store.cycleInputMs) { _, v in
            let digits = String(v.filter(\.isNumber).prefix(8))
            if digits != v { store.cycleInputMs = digits }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }

    private var statusText: String {
        var parts: [String] = []
        if let a = store.snapshot.activeRelay {
            parts.append("\(store.name(a)) running")
        } else {
            parts.append("Cycling")
        }
        if let left = store.snapshot.remainingMs { parts.append("\(formatDuration(left)) left") }
        else if let ms = store.snapshot.cycleMs { parts.append("\(formatDuration(ms)) each") }
        return parts.joined(separator: " · ")
    }
}
