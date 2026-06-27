import Foundation

/// The currencies offered in the From/To pickers. Restricted to this ISO 4217
/// allow-list (a subset of what Frankfurter/ECB supports) so the values placed
/// into request URLs are always known-safe.
enum Currency {
    static let all: [String] = [
        "USD", "CAD", "EUR", "GBP", "AUD", "NZD", "JPY", "CHF", "CNY",
        "INR", "MXN", "BRL", "ZAR", "SGD", "HKD", "SEK", "NOK", "DKK",
        "PLN", "CZK", "HUF", "ILS", "KRW", "TRY", "THB",
    ]

    static func isValid(_ code: String) -> Bool { all.contains(code) }

    /// A representative locale for a currency, used to decide date ordering.
    private static let localeByCurrency: [String: String] = [
        "USD": "en_US", "CAD": "en_CA", "EUR": "en_IE", "GBP": "en_GB",
        "AUD": "en_AU", "NZD": "en_NZ", "JPY": "ja_JP", "CHF": "de_CH",
        "CNY": "zh_CN", "INR": "en_IN", "MXN": "es_MX", "BRL": "pt_BR",
        "ZAR": "en_ZA", "SGD": "en_SG", "HKD": "en_HK", "SEK": "sv_SE",
        "NOK": "nb_NO", "DKK": "da_DK", "PLN": "pl_PL", "CZK": "cs_CZ",
        "HUF": "hu_HU", "ILS": "he_IL", "KRW": "ko_KR", "TRY": "tr_TR",
        "THB": "th_TH",
    ]

    static func locale(for code: String) -> Locale {
        Locale(identifier: localeByCurrency[code] ?? "en_US")
    }

    /// Whether ambiguous numeric dates in this currency's locale are month-first
    /// (e.g. USD → true). Unknown currencies default to US month-first.
    static func usesMonthFirstDates(_ code: String) -> Bool {
        let locale = locale(for: code)
        let template = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? "M/d"
        guard let m = template.firstIndex(of: "M"), let d = template.firstIndex(of: "d") else {
            return true
        }
        return m < d
    }
}
