import Foundation

private struct FrankfurterResponse: Decodable {
    let rates: [String: Double]
}

/// The single place that pings the Frankfurter FX endpoint.
///
/// Requests for the same date are coalesced into one in-flight network call
/// (no thundering herd), and failures retry with exponential backoff.
actor RateService {
    static let shared = RateService()

    private var tasks: [String: Task<Double?, Never>] = [:]

    /// CAD-per-USD for the given "yyyy-MM-dd" key, or nil after exhausting retries.
    /// Concurrent callers for the same key await a single shared fetch.
    func fetchRate(forKey key: String) async -> Double? {
        if let existing = tasks[key] {
            return await existing.value
        }
        let task = Task<Double?, Never> {
            await Self.fetchWithBackoff(key: key)
        }
        tasks[key] = task
        let result = await task.value
        tasks[key] = nil   // cleared so a later refresh can retry a failed key
        return result
    }

    private static func fetchWithBackoff(key: String) async -> Double? {
        let maxAttempts = 5
        var delay: UInt64 = 1_000_000_000   // 1s, doubling, capped at 30s
        for attempt in 0..<maxAttempts {
            if let rate = await fetchOnce(key: key) { return rate }
            if Task.isCancelled { return nil }
            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, 30_000_000_000)
            }
        }
        return nil
    }

    private static func fetchOnce(key: String) async -> Double? {
        // `key` is an internally-formatted yyyy-MM-dd string, never raw user input.
        guard let url = URL(string: "https://api.frankfurter.dev/v1/\(key)?base=USD&symbols=CAD") else {
            return nil
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
            guard let cad = decoded.rates["CAD"], cad.isFinite, cad > 0 else { return nil }
            return cad
        } catch {
            return nil
        }
    }
}
