import Foundation

/// Tolerant parser for the device's /api/state JSON. It accepts several common shapes so the
/// app keeps working if key names differ slightly (relays array, relay1...relay4, r1...r4, etc.).
enum StateParser {

    static func parse(_ data: Data) -> Snapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var snap = Snapshot()

        if let arr = obj as? [Any] {
            guard let r = relays(fromArray: arr) else { return nil }
            snap.relays = r
            return snap
        }
        guard let raw = obj as? [String: Any] else { return nil }
        let d = lowered(raw)

        var found: [Bool]? = nil
        for key in ["relays", "states", "state", "switches", "channels", "outputs"] {
            if let arr = d[key] as? [Any], let r = relays(fromArray: arr) { found = r; break }
            if let sub = d[key] as? [String: Any], let r = relays(fromDict: lowered(sub)) { found = r; break }
        }
        if found == nil { found = relays(fromDict: d) }
        guard let relays = found else { return nil }
        snap.relays = relays

        var cycleDict: [String: Any]? = nil
        for key in ["cycle", "cyclemode", "cycle_mode"] {
            if let sub = d[key] as? [String: Any] { cycleDict = lowered(sub); break }
        }
        let src = cycleDict ?? d
        let enabledKeys = cycleDict != nil
            ? ["enabled", "running", "on", "active", "state"]
            : ["cycleenabled", "cycle_enabled", "cyclemode", "cycle_mode", "cycle", "cyclerunning"]
        for k in enabledKeys {
            if let v = src[k], let b = toBool(v) {
                snap.cycleEnabled = b
                snap.cycleKnown = true
                break
            }
        }
        for k in ["ms", "cyclems", "cycle_ms", "periodms", "period_ms", "onms", "on_ms", "intervalms", "interval"] {
            if let v = src[k], let n = toInt(v) { snap.cycleMs = n; break }
        }
        for k in ["remainingms", "remaining_ms", "remaining", "leftms", "left_ms", "left", "timeleft"] {
            if let v = src[k], let n = toInt(v) { snap.remainingMs = n; break }
        }
        return snap
    }

    // MARK: helpers

    private static func lowered(_ d: [String: Any]) -> [String: Any] {
        d.reduce(into: [String: Any]()) { $0[$1.key.lowercased()] = $1.value }
    }

    private static func relays(fromArray arr: [Any]) -> [Bool]? {
        let vals = arr.compactMap { toBool($0) }
        guard vals.count >= 4 else { return nil }
        return Array(vals.prefix(4))
    }

    private static func relays(fromDict d: [String: Any]) -> [Bool]? {
        for prefix in ["relay", "r", "ch", "channel", "switch", "s", ""] {
            for base in [1, 0] {
                var out: [Bool] = []
                for i in base..<(base + 4) {
                    guard let v = d["\(prefix)\(i)"], let b = toBool(v) else { break }
                    out.append(b)
                }
                if out.count == 4 { return out }
            }
        }
        return nil
    }

    private static func toBool(_ v: Any) -> Bool? {
        if let n = v as? NSNumber { return n.intValue != 0 }
        if let s = v as? String {
            switch s.lowercased() {
            case "1", "on", "true", "high", "yes", "enabled", "running": return true
            case "0", "off", "false", "low", "no", "disabled", "stopped": return false
            default: return nil
            }
        }
        if let d = v as? [String: Any] {
            let ld = lowered(d)
            for k in ["state", "on", "value", "status"] {
                if let inner = ld[k], let b = toBool(inner) { return b }
            }
        }
        return nil
    }

    private static func toInt(_ v: Any) -> Int? {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) }
        return nil
    }
}
