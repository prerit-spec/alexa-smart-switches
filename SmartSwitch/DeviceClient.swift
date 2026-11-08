import Foundation

struct DeviceClient: Sendable {
    private let session: URLSession

    init() {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 2.5
        c.timeoutIntervalForResource = 4
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: c)
    }

    func get(host: String, path: String, query: [URLQueryItem] = []) async throws -> Data {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { throw DeviceError.noHost }
        if !h.lowercased().hasPrefix("http") { h = "http://" + h }
        guard let base = URL(string: h),
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw DeviceError.badAddress
        }
        comps.path = path
        comps.queryItems = query.isEmpty ? nil : query
        guard let url = comps.url else { throw DeviceError.badAddress }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DeviceError.badStatus(http.statusCode)
        }
        return data
    }

    func fetchState(host: String) async throws -> Data {
        try await get(host: host, path: "/api/state")
    }

    /// index nil = all relays
    func setRelay(host: String, index: Int?, on: Bool) async throws {
        let id = index.map(String.init) ?? "all"
        _ = try await get(host: host, path: "/api/set", query: [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "state", value: on ? "1" : "0")
        ])
    }

    func setCycle(host: String, enabled: Bool, ms: Int?) async throws {
        var q = [URLQueryItem(name: "enabled", value: enabled ? "1" : "0")]
        if let ms { q.append(URLQueryItem(name: "ms", value: String(ms))) }
        _ = try await get(host: host, path: "/api/cycle", query: q)
    }
}
