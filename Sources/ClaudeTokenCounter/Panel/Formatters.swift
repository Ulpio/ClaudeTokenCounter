import Foundation
import CCUsageCore

enum Format {
    /// 2_400_000 → "2.4M"
    static func tokens(_ value: UInt64) -> String {
        let v = Double(value)
        switch v {
        case 1_000_000_000...: return String(format: "%.2fB", v / 1_000_000_000)
        case 1_000_000...:     return String(format: "%.1fM", v / 1_000_000)
        case 1_000...:         return String(format: "%.1fk", v / 1_000)
        default:               return "\(value)"
        }
    }

    /// Money parcial ganha "+" para indicar que é piso, não valor exato.
    static func money(_ money: Money) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        let base = formatter.string(from: NSDecimalNumber(decimal: money.usd)) ?? "$0.00"
        return money.isPartial ? base + "+" : base
    }

    /// 4320 → "1h 12m"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    static func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int(fraction * 100))%"
    }
}
