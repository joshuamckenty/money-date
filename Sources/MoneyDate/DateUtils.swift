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
        "MM/dd/yy",
        "M/d/yy",
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

    private static let dateDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// Parse clipboard text as a calendar date. A plain number is never a date
    /// (it becomes a USD column). Tries deterministic formats first, then falls
    /// back to NSDataDetector for natural-language / locale formats.
    static func parseDate(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isPlainNumber(text) else { return nil }

        // 1) Deterministic formats (require a separator).
        if text.contains(where: { "-/,.".contains($0) }) {
            for format in parseFormats {
                parser.dateFormat = format
                if let date = parser.date(from: text), inRange(date) {
                    return calendar.startOfDay(for: date)
                }
            }
        }

        // 2) Fallback: detect natural/locale dates, but only when the match
        //    spans (nearly) the whole string so we don't pick a date out of
        //    arbitrary text or a stray number.
        if let detector = dateDetector {
            let range = NSRange(text.startIndex..., in: text)
            if let match = detector.firstMatch(in: text, options: [], range: range),
               match.range.length >= range.length - 2,
               let date = match.date, inRange(date) {
                return calendar.startOfDay(for: date)
            }
        }
        return nil
    }

    private static func inRange(_ date: Date) -> Bool {
        (1970...2100).contains(calendar.component(.year, from: date))
    }

    /// True if the text is just a numeric amount (optionally with $, commas, spaces).
    private static func isPlainNumber(_ text: String) -> Bool {
        var t = text
        for token in ["$", ",", " ", "\u{00A0}"] {
            t = t.replacingOccurrences(of: token, with: "")
        }
        return !t.isEmpty && Double(t) != nil
    }
}
