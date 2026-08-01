import Foundation

/// Aritmetica di calendario pura (nessun fuso, nessuna Date): il gioco ragiona
/// per "mezzanotte locale" e qui contano solo le terne (anno, mese, giorno).
public enum FiloDate {
    /// EPOCH del gioco: 2026-08-01 → FILO #1 (README §7.1).
    public static let epoch: (y: Int, m: Int, d: Int) = (2026, 8, 1)

    /// Seed del giorno: anno*10000 + mese*100 + giorno (README §7.1).
    public static func seed(y: Int, m: Int, d: Int) -> Int {
        y * 10000 + m * 100 + d
    }

    /// Numero di giorni dal 1970-01-01 (algoritmo days_from_civil di H. Hinnant).
    /// Puro: equivale alla differenza fra mezzanotte locali del JS (Math.round assorbe la DST).
    public static func dayNumber(y: Int, m: Int, d: Int) -> Int {
        let yy = y - (m <= 2 ? 1 : 0)
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// Numero del puzzle: giorni dall'EPOCH + 1 (README §7.1).
    public static func puzzleNumber(y: Int, m: Int, d: Int) -> Int {
        dayNumber(y: y, m: m, d: d) - dayNumber(y: epoch.y, m: epoch.m, d: epoch.d) + 1
    }

    /// "YYYY-MM-DD" — stesso formato delle chiavi di persistenza web (§11.2).
    public static func dateString(y: Int, m: Int, d: Int) -> String {
        String(format: "%04d-%02d-%02d", y, m, d)
    }

    public static func isLeapYear(_ y: Int) -> Bool {
        (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
    }

    public static func daysInMonth(y: Int, m: Int) -> Int {
        switch m {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        default: return isLeapYear(y) ? 29 : 28
        }
    }

    /// Il giorno precedente (per il confronto streak "ieri", §8.2).
    public static func previousDay(y: Int, m: Int, d: Int) -> (y: Int, m: Int, d: Int) {
        if d > 1 { return (y, m, d - 1) }
        if m == 1 { return (y - 1, 12, 31) }
        return (y, m - 1, daysInMonth(y: y, m: m - 1))
    }
}
