import Foundation

/// Shared number/date formatters used throughout the UI.
enum Formatters {

    /// "yyyy-MM-dd" — used both for display and as the FX-cache / API key.
    static let isoDay: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = DateUtils.calendar
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private static var currencyFormatters: [String: NumberFormatter] = [:]

    private static func currencyFormatter(_ code: String) -> NumberFormatter {
        if let existing = currencyFormatters[code] { return existing }
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = code
        nf.maximumFractionDigits = 2
        currencyFormatters[code] = nf
        return nf
    }

    static func dayKey(_ date: Date) -> String { isoDay.string(from: date) }

    /// Formatted amount in the given currency, e.g. "US$1,234.56" or "C$1,655.43".
    static func amount(_ value: Double, code: String) -> String {
        currencyFormatter(code).string(from: NSNumber(value: value))
            ?? String(format: "%@ %.2f", code, value)
    }

    /// Plain, separator-free value suitable for pasting into a spreadsheet.
    static func plain(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
