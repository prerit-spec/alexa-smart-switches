import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DeviceStore
    @Environment(\.dismiss) private var dismiss
    @State private var testing = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                Form {
                    Section {
                        TextField("e.g. 192.168.1.50", text: $store.host)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            Task {
                                testing = true
                                await store.refresh()
                                testing = false
                            }
                        } label: {
                            HStack {
                                Text(testing ? "Testing…" : "Test connection")
                                Spacer()
                                statusIcon
                            }
                        }
                        .tint(Theme.amber)
                    } header: {
                        Text("Device address")
                    } footer: {
                        Text("Use the IP address shown in the Serial Monitor. Your phone must be on the same WiFi as the switch.")
                    }
                    .listRowBackground(Theme.card)

                    Section("Channel names") {
                        ForEach(0..<4, id: \.self) { i in
                            HStack {
                                Text(String(format: "%02d", i + 1))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.amber)
                                TextField("Relay \(i + 1)", text: $store.names[i])
                            }
                        }
                    }
                    .listRowBackground(Theme.card)

                    Section {
                        Text(store.lastRaw.isEmpty ? "No response yet" : store.lastRaw)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                    } header: {
                        Text("Diagnostics, last /api/state reply")
                    }
                    .listRowBackground(Theme.card)

                    Section {
                        HStack {
                            Text("Smart Switch")
                            Spacer()
                            Text("1.0").foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(Theme.amber)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var statusIcon: some View {
        switch store.connection {
        case .online: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
        case .offline: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.danger)
        default: EmptyView()
        }
    }
}
