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

    private static let usd: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "USD"
        nf.maximumFractionDigits = 2
        return nf
    }()

    private static let cad: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "CAD"
        nf.maximumFractionDigits = 2
        return nf
    }()

    static func dayKey(_ date: Date) -> String { isoDay.string(from: date) }

    static func usdHeader(_ value: Double) -> String {
        usd.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func cadDisplay(_ value: Double) -> String {
        cad.string(from: NSNumber(value: value)) ?? String(format: "C$%.2f", value)
    }

    /// Plain, separator-free value suitable for pasting into a spreadsheet.
    static func cadPlain(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
