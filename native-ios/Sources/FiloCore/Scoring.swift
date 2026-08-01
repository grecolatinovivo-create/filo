import Foundation

public struct RisultatoStelle: Equatable {
    public let stelle: Int      // 1..3
    public let gold: Bool       // 🥇 Sarto battuto
    public let label: String    // etichetta normativa §8.1

    public init(stelle: Int, gold: Bool, label: String) {
        self.stelle = stelle
        self.gold = gold
        self.label = label
    }
}

public enum Punteggio {
    /// Stelle in caso di vittoria (README §8.1, 4 casi vs L_sarto).
    public static func stelle(caselle C: Int, lSarto L: Int) -> RisultatoStelle {
        if C > L { return RisultatoStelle(stelle: 3, gold: true, label: "Hai battuto il Sarto!") }
        if C == L { return RisultatoStelle(stelle: 3, gold: false, label: "Filo perfetto") }
        if C >= L - 3 { return RisultatoStelle(stelle: 2, gold: false, label: "Filo elegante") }
        return RisultatoStelle(stelle: 1, gold: false, label: "Filo riuscito")
    }
}

/// Statistiche del giocatore — schema equivalente a `filo.stats` web (§11.2).
public struct Statistiche: Codable, Equatable {
    public var giocate = 0
    public var vinte = 0
    public var streak = 0
    public var maxStreak = 0
    public var distFili = [0, 0, 0]
    public var recordCaselle = 0
    public var sartoBattuto = 0
    public var ultimaVittoria: String? = nil   // "YYYY-MM-DD"

    public init() {}

    /// Registra l'esito del giorno (§8.2): vittoria del giorno D con ultima
    /// vittoria D-1 → streak+1, altrimenti streak = 1; sconfitta → streak = 0.
    public mutating func registra(vinta: Bool, filiUsati: Int, caselle: Int,
                                  gold: Bool, oggi: (y: Int, m: Int, d: Int)) {
        giocate += 1
        let oggiStr = FiloDate.dateString(y: oggi.y, m: oggi.m, d: oggi.d)
        if vinta {
            vinte += 1
            let ieri = FiloDate.previousDay(y: oggi.y, m: oggi.m, d: oggi.d)
            let ieriStr = FiloDate.dateString(y: ieri.y, m: ieri.m, d: ieri.d)
            streak = (ultimaVittoria == ieriStr) ? streak + 1 : 1
            maxStreak = max(maxStreak, streak)
            ultimaVittoria = oggiStr
            if (1...3).contains(filiUsati) { distFili[filiUsati - 1] += 1 }
            recordCaselle = max(recordCaselle, caselle)
            if gold { sartoBattuto += 1 }
        } else {
            streak = 0
        }
    }

    /// Streak da mostrare/condividere: valida solo se l'ultima vittoria è
    /// oggi o ieri, altrimenti 0 (gap → azzerata alla visualizzazione).
    public func streakEffettiva(oggi: (y: Int, m: Int, d: Int)) -> Int {
        guard let uv = ultimaVittoria else { return 0 }
        let oggiStr = FiloDate.dateString(y: oggi.y, m: oggi.m, d: oggi.d)
        let ieri = FiloDate.previousDay(y: oggi.y, m: oggi.m, d: oggi.d)
        let ieriStr = FiloDate.dateString(y: ieri.y, m: ieri.m, d: ieri.d)
        return (uv == oggiStr || uv == ieriStr) ? streak : 0
    }
}
