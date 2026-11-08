import SwiftUI
import Combine

@MainActor
final class DeviceStore: ObservableObject {
    static let cycleRange = 100...86_400_000

    @Published var snapshot = Snapshot()
    @Published var connection: ConnectionState = .unknown
    @Published var lastRaw = ""
    @Published var lastUpdated: Date?
    @Published var toast: String?
    @Published var cycleInputMs = "60000"

    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "host") }
    }
    @Published var names: [String] {
        didSet { UserDefaults.standard.set(names, forKey: "names") }
    }

    private let client = DeviceClient()
    private var pollTask: Task<Void, Never>?
    private var inFlight = 0
    private var syncedCycleInput = false
    private var toastTask: Task<Void, Never>?

    init() {
        host = UserDefaults.standard.string(forKey: "host") ?? ""
        let saved = UserDefaults.standard.stringArray(forKey: "names") ?? []
        names = saved.count == 4 ? saved : ["Relay 1", "Relay 2", "Relay 3", "Relay 4"]
    }

    func name(_ i: Int) -> String {
        let n = names[i].trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Relay \(i + 1)" : n
    }

    // MARK: polling

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            connection = .offline("Add your device address in Settings")
            return
        }
        if connection == .unknown { connection = .connecting }
        let host = self.host
        let client = self.client
        do {
            let data = try await client.fetchState(host: host)
            lastRaw = String(data: data, encoding: .utf8) ?? "<binary data>"
            guard let snap = StateParser.parse(data) else {
                connection = .offline("Reached the device, but couldn't read its reply. See Settings, Diagnostics.")
                return
            }
            if inFlight == 0 { apply(snap) }
            connection = .online
            lastUpdated = Date()
        } catch {
            connection = .offline(friendly(error))
        }
    }

    private func apply(_ new: Snapshot) {
        var merged = new
        if !new.cycleKnown { merged.cycleEnabled = snapshot.cycleEnabled }
        if merged.cycleMs == nil { merged.cycleMs = snapshot.cycleMs }
        snapshot = merged
        if !syncedCycleInput, let ms = merged.cycleMs, Self.cycleRange.contains(ms) {
            cycleInputMs = String(ms)
            syncedCycleInput = true
        }
    }

    // MARK: relay actions

    func toggle(_ i: Int) { setRelay(i, on: !snapshot.relays[i]) }

    func setRelay(_ i: Int, on: Bool) {
        guard !snapshot.cycleEnabled else { return }
        Haptics.tap()
        let old = snapshot.relays
        snapshot.relays[i] = on
        let host = self.host, client = self.client
        Task { [self] in await perform(revertTo: old) { try await client.setRelay(host: host, index: i, on: on) } }
    }

    func setAll(_ on: Bool) {
        guard !snapshot.cycleEnabled else { return }
        Haptics.tap()
        let old = snapshot.relays
        snapshot.relays = Array(repeating: on, count: 4)
        let host = self.host, client = self.client
        Task { [self] in await perform(revertTo: old) { try await client.setRelay(host: host, index: nil, on: on) } }
    }

    // MARK: cycle actions

    var validCycleMs: Int? {
        guard let v = Int(cycleInputMs.trimmingCharacters(in: .whitespaces)),
              Self.cycleRange.contains(v) else { return nil }
        return v
    }

    func setCycle(enabled: Bool) {
        var ms: Int? = nil
        if enabled {
            guard let v = validCycleMs else {
                Haptics.error()
                showToast("Enter a time from 100 to 86,400,000 ms")
                return
            }
            ms = v
        }
        Haptics.tap()
        let old = snapshot
        snapshot.cycleEnabled = enabled
        if enabled { snapshot.cycleMs = ms } else { snapshot.relays = Array(repeating: false, count: 4) }
        let host = self.host, client = self.client
        Task { [self] in
            inFlight += 1
            do { try await client.setCycle(host: host, enabled: enabled, ms: ms) }
            catch { snapshot = old; showToast(friendly(error)); Haptics.error() }
            inFlight -= 1
            await refresh()
        }
    }

    func applyCycleTime() {
        guard snapshot.cycleEnabled else { return }
        setCycle(enabled: true)
    }

    // MARK: internals

    private func perform(revertTo old: [Bool], _ work: @escaping () async throws -> Void) async {
        inFlight += 1
        do { try await work() }
        catch {
            snapshot.relays = old
            showToast(friendly(error))
            Haptics.error()
        }
        inFlight -= 1
        await refresh()
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    private func friendly(_ error: Error) -> String {
        if let e = error as? DeviceError { return e.errorDescription ?? "Something went wrong" }
        if let u = error as? URLError {
            switch u.code {
            case .timedOut: return "The device didn't respond. Is it powered and on the same WiFi?"
            case .notConnectedToInternet, .cannotConnectToHost, .networkConnectionLost, .cannotFindHost:
                return "Can't reach the device. Check WiFi, the address, and Local Network access for this app."
            default: return u.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
