import Foundation
import Combine

struct DateRow: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
}

struct AmountColumn: Identifiable, Codable, Equatable {
    var id = UUID()
    var usd: Double
    var added: Date
}

private struct PersistedState: Codable {
    var rows: [DateRow]
    var columns: [AmountColumn]
}

private struct FrankfurterResponse: Decodable {
    let rates: [String: Double]
}

/// Owns all app state: the date rows, the USD columns, and the cached USD→CAD rates.
/// Fetches historical rates from the ECB-backed Frankfurter API (free, no key).
@MainActor
final class Store: ObservableObject {

    // How many rows/columns the table shows by default.
    static let visibleRows = 15
    static let visibleColumns = 5
    static let defaultMonthEnds = 12

    @Published private(set) var rows: [DateRow] = []
    @Published private(set) var columns: [AmountColumn] = []
    @Published private(set) var rates: [String: Double] = [:]   // "yyyy-MM-dd" → CAD per USD
    @Published var selectedYear: Int

    private var inFlight: Set<String> = []

    init() {
        let now = Date()
        self.selectedYear = DateUtils.calendar.component(.year, from: now)
        loadState()
        loadRates()
        if rows.isEmpty {
            resetDates()
        }
        prefetchRates()
    }

    // MARK: - Derived views

    /// Rows newest-first; the first element is the "topmost date".
    var sortedRows: [DateRow] { rows.sorted { $0.date > $1.date } }
    /// Columns newest-first; the first element is the "latest value".
    var sortedColumns: [AmountColumn] { columns.sorted { $0.added > $1.added } }

    var displayedRows: [DateRow] { Array(sortedRows.prefix(Self.visibleRows)) }
    var displayedColumns: [AmountColumn] { Array(sortedColumns.prefix(Self.visibleColumns)) }

    var hiddenColumnCount: Int { max(0, columns.count - Self.visibleColumns) }
    var hiddenRowCount: Int { max(0, rows.count - Self.visibleRows) }

    /// CAD value of `usd` as of `date`, or nil if the rate isn't cached yet.
    func cadValue(usd: Double, date: Date) -> Double? {
        guard let rate = rates[Formatters.dayKey(date)] else { return nil }
        return usd * rate
    }

    // MARK: - Mutations

    func addColumn(usd: Double) {
        columns.append(AmountColumn(usd: usd, added: Date()))
        saveState()
    }

    func addRow(date: Date) {
        let key = Formatters.dayKey(date)
        guard !rows.contains(where: { Formatters.dayKey($0.date) == key }) else { return }
        rows.append(DateRow(date: date))
        saveState()
        fetchRate(for: date)
    }

    /// Back to the most recent 12 month-ends.
    func resetDates() {
        rows = DateUtils.lastMonthEnds(count: Self.defaultMonthEnds).map { DateRow(date: $0) }
        saveState()
        prefetchRates()
    }

    /// Replace rows with the 12 month-ends of `year`.
    func populate(year: Int) {
        rows = DateUtils.monthEnds(year: year).map { DateRow(date: $0) }
        saveState()
        prefetchRates()
    }

    // MARK: - Clipboard handling

    /// Route freshly-copied text: a parseable date adds a row, a parseable number adds a column.
    /// (Input is already length-bounded and trimmed by `Clipboard`.)
    func handlePaste(_ text: String) {
        if let date = DateUtils.parseDate(text) {
            addRow(date: date)
        } else if let usd = Self.parseUSD(text) {
            addColumn(usd: usd)
        }
    }

    /// Parse a USD amount from clipboard text, tolerating "$", currency codes, and thousands separators.
    /// Rejects non-finite values and absurd magnitudes.
    static func parseUSD(_ text: String) -> Double? {
        var cleaned = text
        for token in ["$", "USD", "CAD", "\u{00A0}", " "] {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }
        cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, abs(value) <= 1e12 else {
            return nil
        }
        return value
    }

    /// CAD value for the latest column × topmost date, as a plain pasteable string.
    /// Returns nil if there's no data or the rate isn't cached yet.
    func latestCellCADPlain() -> String? {
        guard let column = sortedColumns.first, let row = sortedRows.first,
              let cad = cadValue(usd: column.usd, date: row.date) else { return nil }
        return Formatters.cadPlain(cad)
    }

    // MARK: - Rates

    private func prefetchRates() {
        for row in rows { fetchRate(for: row.date) }
    }

    private func fetchRate(for date: Date) {
        let key = Formatters.dayKey(date)
        guard rates[key] == nil, !inFlight.contains(key) else { return }
        // Future dates have no ECB rate yet; skip the request.
        guard DateUtils.calendar.startOfDay(for: date) <= DateUtils.calendar.startOfDay(for: Date()) else { return }
        guard let url = URL(string: "https://api.frankfurter.dev/v1/\(key)?base=USD&symbols=CAD") else { return }

        inFlight.insert(key)
        Task { [weak self] in
            defer { self?.inFlight.remove(key) }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
                let decoded = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
                guard let cad = decoded.rates["CAD"], cad.isFinite, cad > 0 else { return }
                self?.rates[key] = cad
                self?.saveRates()
            } catch {
                // Network/parse failures are non-fatal; the cell stays blank and can retry later.
            }
        }
    }

    // MARK: - Persistence (fixed paths inside Application Support only)

    private static func appDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("money-date", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func stateURL() throws -> URL { try appDirectory().appendingPathComponent("state.json") }
    private static func ratesURL() throws -> URL { try appDirectory().appendingPathComponent("rates.json") }

    private func loadState() {
        guard let url = try? Self.stateURL(),
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        rows = state.rows
        columns = state.columns
    }

    private func saveState() {
        guard let url = try? Self.stateURL() else { return }
        let state = PersistedState(rows: rows, columns: columns)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadRates() {
        guard let url = try? Self.ratesURL(),
              let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode([String: Double].self, from: data) else { return }
        rates = cached
    }

    private func saveRates() {
        guard let url = try? Self.ratesURL() else { return }
        if let data = try? JSONEncoder().encode(rates) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
