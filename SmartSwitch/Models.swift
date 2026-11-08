import Foundation

struct Snapshot: Equatable {
    var relays: [Bool] = [false, false, false, false]
    var cycleKnown = false
    var cycleEnabled = false
    var cycleMs: Int? = nil
    var remainingMs: Int? = nil

    /// Only one relay is on at a time during a cycle, so the active step can be inferred.
    var activeRelay: Int? {
        guard cycleEnabled else { return nil }
        return relays.firstIndex(of: true)
    }
}

enum ConnectionState: Equatable {
    case unknown
    case connecting
    case online
    case offline(String)

    var isOnline: Bool { self == .online }
}

enum DeviceError: LocalizedError {
    case noHost, badAddress, badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .noHost: return "Add your device address in Settings"
        case .badAddress: return "That device address isn't valid"
        case .badStatus(let c): return "Device replied with error \(c)"
        }
    }
}
