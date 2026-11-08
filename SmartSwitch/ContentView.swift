import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: DeviceStore
    @Environment(\.scenePhase) private var phase
    @State private var showSettings = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    if case .offline(let message) = store.connection {
                        offlineBanner(message)
                    }
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(0..<4, id: \.self) { i in
                            RelayCard(
                                index: i,
                                name: store.name(i),
                                isOn: store.snapshot.relays[i],
                                locked: store.snapshot.cycleEnabled,
                                running: store.snapshot.activeRelay == i
                            ) { store.toggle(i) }
                        }
                    }
                    bulkButtons
                    CycleCard()
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.refresh() }
        }
        .overlay(alignment: .bottom) {
            if let t = store.toast {
                Text(t)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.toast)
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(store)
        }
        .onAppear {
            store.startPolling()
            if store.host.trimmingCharacters(in: .whitespaces).isEmpty { showSettings = true }
        }
        .onChange(of: phase) { _, p in
            if p == .active { store.startPolling() } else { store.stopPolling() }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Smart Switch")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
            }
            Spacer()
            statusPill
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.top, 8)
    }

    private var statusPill: some View {
        let (label, color): (String, Color) = {
            switch store.connection {
            case .online: return ("Online", Theme.good)
            case .offline: return ("Offline", Theme.danger)
            default: return ("Connecting", Theme.amber)
            }
        }()
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }

    private func offlineBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(Theme.danger)
            Text(message)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.85))
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.danger.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.danger.opacity(0.35), lineWidth: 1))
    }

    private var bulkButtons: some View {
        HStack(spacing: 14) {
            bulkButton("All ON", icon: "bolt.fill", filled: true) { store.setAll(true) }
            bulkButton("All OFF", icon: "moon.fill", filled: false) { store.setAll(false) }
        }
        .opacity(store.snapshot.cycleEnabled ? 0.45 : 1)
        .disabled(store.snapshot.cycleEnabled)
    }

    private func bulkButton(_ title: String, icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(filled ? Color.black.opacity(0.85) : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule().fill(filled ? AnyShapeStyle(Theme.amberGradient) : AnyShapeStyle(Theme.card))
            )
            .overlay(Capsule().stroke(filled ? Color.clear : Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    private var footer: some View {
        Group {
            if let t = store.lastUpdated, store.connection.isOnline {
                Text("\(store.host) · updated \(t, style: .relative) ago")
            } else {
                Text(store.host.isEmpty ? "No device set" : store.host)
            }
        }
        .font(.system(size: 12, design: .rounded))
        .foregroundStyle(Theme.textSecondary)
        .padding(.top, 4)
    }
}
