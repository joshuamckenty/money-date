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

    /// TO-per-FROM rate for the given date, or nil after exhausting retries.
    /// Concurrent callers for the same (date, from, to) await a single shared fetch.
    func fetchRate(date: String, from: String, to: String) async -> Double? {
        let coalesceKey = "\(from)|\(to)|\(date)"
        if let existing = tasks[coalesceKey] {
            return await existing.value
        }
        let task = Task<Double?, Never> {
            await Self.fetchWithBackoff(date: date, from: from, to: to)
        }
        tasks[coalesceKey] = task
        let result = await task.value
        tasks[coalesceKey] = nil   // cleared so a later refresh can retry a failed key
        return result
    }

    private static func fetchWithBackoff(date: String, from: String, to: String) async -> Double? {
        let maxAttempts = 5
        var delay: UInt64 = 1_000_000_000   // 1s, doubling, capped at 30s
        for attempt in 0..<maxAttempts {
            if let rate = await fetchOnce(date: date, from: from, to: to) { return rate }
            if Task.isCancelled { return nil }
            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, 30_000_000_000)
            }
        }
        return nil
    }

    private static func fetchOnce(date: String, from: String, to: String) async -> Double? {
        // `date` is internally-formatted yyyy-MM-dd; from/to come from the Currency
        // allow-list — never raw user input — so the URL is built from safe values.
        guard let url = URL(string: "https://api.frankfurter.dev/v1/\(date)?base=\(from)&symbols=\(to)") else {
            return nil
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
            guard let rate = decoded.rates[to], rate.isFinite, rate > 0 else { return nil }
            return rate
        } catch {
            return nil
        }
    }
}
