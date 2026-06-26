import Foundation

/// Date math (month-ends) and *strict* parsing of dates copied to the clipboard.
enum DateUtils {

    /// A fixed Gregorian calendar so month-end math is stable regardless of locale.
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }()

    /// Last day of the given month (1-based month). Month overflow is normalized,
    /// so `month: 12` correctly rolls into the next January.
    static func endOfMonth(year: Int, month: Int) -> Date? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month + 1
        comps.day = 1
        guard let firstOfNext = calendar.date(from: comps) else { return nil }
        let startOfNext = calendar.startOfDay(for: firstOfNext)
        return calendar.date(byAdding: .day, value: -1, to: startOfNext)
    }

    /// The most recent `count` month-end dates that have already occurred as of `today`.
    static func lastMonthEnds(count: Int, asOf today: Date = Date()) -> [Date] {
        let comps = calendar.dateComponents([.year, .month], from: today)
        var year = comps.year ?? 2000
        var month = comps.month ?? 1
        var result: [Date] = []
        let today = calendar.startOfDay(for: today)
        var guardCounter = 0
        while result.count < count && guardCounter < count * 3 + 24 {
            if let end = endOfMonth(year: year, month: month),
               calendar.startOfDay(for: end) <= today {
                result.append(end)
            }
            month -= 1
            if month < 1 { month = 12; year -= 1 }
            guardCounter += 1
        }
        return result
    }

    /// All 12 month-ends for a calendar year (Jan 31 … Dec 31).
    static func monthEnds(year: Int) -> [Date] {
        (1...12).compactMap { endOfMonth(year: year, month: $0) }
    }

    private static let parseFormats = [
        "yyyy-MM-dd",
        "yyyy/MM/dd",
        "MM/dd/yyyy",
        "M/d/yyyy",
        "MMM d, yyyy",
        "MMMM d, yyyy",
        "d MMM yyyy",
        "d MMMM yyyy",
    ]

    private static let parser: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = calendar
        df.timeZone = TimeZone.current
        df.isLenient = false
        return df
    }()

    /// Strictly parse clipboard text as a calendar date. Requires a separator so that
    /// bare numbers (e.g. "2024") are NOT mistaken for dates — those become USD columns.
    static func parseDate(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains(where: { "-/,".contains($0) }) else { return nil }
        for format in parseFormats {
            parser.dateFormat = format
            if let date = parser.date(from: text) {
                let year = calendar.component(.year, from: date)
                if (1970...2100).contains(year) {
                    return calendar.startOfDay(for: date)
                }
            }
        }
        return nil
    }
}
