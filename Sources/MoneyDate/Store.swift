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

private struct AppSettings: Codable {
    var hotKey: HotKeyConfig
    var fromCurrency: String
    var toCurrency: String
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
    @Published private(set) var hotKeyConfig: HotKeyConfig = .default
    @Published private(set) var fromCurrency: String = "USD"
    @Published private(set) var toCurrency: String = "CAD"
    @Published var selectedYear: Int

    // Transient highlight state for visual feedback (auto-cleared after a short delay).
    @Published private(set) var recentlyAddedRowID: UUID?
    @Published private(set) var recentlyAddedColumnID: UUID?
    @Published private(set) var flashCellKey: String?

    private var inFlight: Set<String> = []
    private var clearAddedTask: Task<Void, Never>?
    private var clearFlashTask: Task<Void, Never>?
    private var refreshTimer: Timer?

    init() {
        let now = Date()
        self.selectedYear = DateUtils.calendar.component(.year, from: now)
        loadState()
        loadRates()
        loadSettings()
        if rows.isEmpty {
            resetDates()
        }
        prefetchRates()
        startRefreshTimer()
    }

    /// Periodically retry any still-missing rates (e.g. after the app started offline).
    /// Cheap and coalesced by RateService, so it can't stampede the endpoint.
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMissingRates() }
        }
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

    /// Cache key for a rate: "FROM|TO|yyyy-MM-dd".
    private func rateKey(_ date: Date) -> String {
        "\(fromCurrency)|\(toCurrency)|\(Formatters.dayKey(date))"
    }

    /// `amount` (in the FROM currency) converted to the TO currency as of `date`,
    /// or nil if that rate isn't cached yet.
    func convertedValue(amount: Double, date: Date) -> Double? {
        guard let rate = rates[rateKey(date)] else { return nil }
        return amount * rate
    }

    // MARK: - Mutations

    func addColumn(usd: Double) {
        let column = AmountColumn(usd: usd, added: Date())
        columns.append(column)
        markAdded(columnID: column.id)
        saveState()
    }

    func addRow(date: Date) {
        let key = Formatters.dayKey(date)
        guard !rows.contains(where: { Formatters.dayKey($0.date) == key }) else { return }
        let row = DateRow(date: date)
        rows.append(row)
        markAdded(rowID: row.id)
        saveState()
        fetchRate(for: date)
    }

    func deleteRow(id: UUID) {
        rows.removeAll { $0.id == id }
        saveState()
    }

    func deleteColumn(id: UUID) {
        columns.removeAll { $0.id == id }
        saveState()
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

    /// Update and persist the global copy hotkey. AppDelegate observes this and re-registers.
    func setHotKey(_ config: HotKeyConfig) {
        hotKeyConfig = config
        saveSettings()
    }

    /// Update the From/To currencies, persist, and fetch rates for the new pair.
    func setCurrencies(from: String, to: String) {
        guard Currency.isValid(from), Currency.isValid(to) else { return }
        fromCurrency = from
        toCurrency = to
        saveSettings()
        prefetchRates()
    }

    // MARK: - Clipboard handling

    /// Route freshly-copied text: a parseable date adds a row, a parseable number adds a column.
    /// (Input is already length-bounded and trimmed by `Clipboard`.)
    func handlePaste(_ text: String) {
        let monthFirst = Currency.usesMonthFirstDates(fromCurrency)
        if let date = DateUtils.parseDate(text, monthFirst: monthFirst) {
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

    static func cellKey(columnID: UUID, date: Date) -> String {
        "\(columnID.uuidString)|\(Formatters.dayKey(date))"
    }

    /// Copy the CAD value for the latest column × topmost date (used by the global hotkey).
    /// Does NOT add a column. Returns false if there's nothing to copy yet.
    @discardableResult
    func copyLatest() -> Bool {
        guard let column = sortedColumns.first, let row = sortedRows.first else { return false }
        return copyCell(column: column, date: row.date)
    }

    /// Copy a single cell's converted (TO-currency) value to the clipboard and flash it.
    @discardableResult
    func copyCell(column: AmountColumn, date: Date) -> Bool {
        guard let value = convertedValue(amount: column.usd, date: date) else { return false }
        Clipboard.shared.copy(Formatters.plain(value))
        flash(cellKey: Self.cellKey(columnID: column.id, date: date))
        return true
    }

    // MARK: - Visual feedback

    private func markAdded(rowID: UUID? = nil, columnID: UUID? = nil) {
        recentlyAddedRowID = rowID
        recentlyAddedColumnID = columnID
        clearAddedTask?.cancel()
        clearAddedTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            self?.recentlyAddedRowID = nil
            self?.recentlyAddedColumnID = nil
        }
    }

    private func flash(cellKey: String) {
        flashCellKey = cellKey
        clearFlashTask?.cancel()
        clearFlashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.flashCellKey = nil
        }
    }

    // MARK: - Rates

    private func prefetchRates() {
        for row in rows { fetchRate(for: row.date) }
    }

    /// Re-attempt any displayed date whose rate is still missing for the current pair.
    func refreshMissingRates() {
        for row in rows where rates[rateKey(row.date)] == nil {
            fetchRate(for: row.date)
        }
    }

    private func fetchRate(for date: Date) {
        let key = rateKey(date)
        guard rates[key] == nil, !inFlight.contains(key) else { return }
        // Future dates have no ECB rate yet; skip the request.
        guard DateUtils.calendar.startOfDay(for: date) <= DateUtils.calendar.startOfDay(for: Date()) else { return }

        let dayKey = Formatters.dayKey(date)
        let from = fromCurrency, to = toCurrency
        inFlight.insert(key)
        Task { [weak self] in
            // RateService coalesces concurrent requests for the same (date,from,to)
            // and retries with exponential backoff; nil means it gave up for now.
            let rate = await RateService.shared.fetchRate(date: dayKey, from: from, to: to)
            self?.inFlight.remove(key)
            guard let rate else { return }   // stays blank; a later refresh can retry
            self?.rates[key] = rate
            self?.saveRates()
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
    private static func settingsURL() throws -> URL { try appDirectory().appendingPathComponent("settings.json") }

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

    private func loadSettings() {
        guard let url = try? Self.settingsURL(),
              let data = try? Data(contentsOf: url) else { return }
        if let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            hotKeyConfig = settings.hotKey
            if Currency.isValid(settings.fromCurrency) { fromCurrency = settings.fromCurrency }
            if Currency.isValid(settings.toCurrency) { toCurrency = settings.toCurrency }
        } else if let legacy = try? JSONDecoder().decode(HotKeyConfig.self, from: data) {
            // Backward compat: settings.json used to hold a bare HotKeyConfig.
            hotKeyConfig = legacy
        }
    }

    private func saveSettings() {
        guard let url = try? Self.settingsURL() else { return }
        let settings = AppSettings(hotKey: hotKeyConfig, fromCurrency: fromCurrency, toCurrency: toCurrency)
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
