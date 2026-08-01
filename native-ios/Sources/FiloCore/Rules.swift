import Foundation

public enum EsitoFilo: String, Codable, Equatable {
    case spezzato, annodato, strappato, vinto
}

public struct FiloConcluso: Codable, Equatable {
    public let esito: EsitoFilo
    public let somma: Int
    public let caselle: Int

    public init(esito: EsitoFilo, somma: Int, caselle: Int) {
        self.esito = esito
        self.somma = somma
        self.caselle = caselle
    }
}

public enum StatoPartita: String, Codable, Equatable {
    case inCorso = "in-corso"
    case vinta
    case persa
}

/// Esito di una singola mossa su `GameEngine.gioca(_:)`.
public enum Mossa: Equatable {
    case iniziato                     // prima casella del filo
    case esteso                       // estensione valida, filo ancora vivo
    case vittoria                     // somma == T (partita vinta)
    case spezzato                     // somma > T: filo perso
    case annodato                     // vicolo cieco: filo perso
    case giaUsata                     // non valida: casella già nel filo (shake)
    case nonAdiacente                 // non valida: non ortogonalmente adiacente (shake)
    case ignorata                     // partita già conclusa
}

/// Macchina a stati della partita (README §6). Logica pura, nessuna UI.
/// NON esiste alcuna API di undo del singolo passo (§6.2, normativa).
public struct GameEngine {
    public let valori: [Int]
    public let T: Int

    public private(set) var fili: [FiloConcluso] = []
    public private(set) var filo: [Int] = []
    public private(set) var somma = 0
    public private(set) var stato: StatoPartita = .inCorso
    public private(set) var percorsoVincente: [Int]? = nil

    public var filiRimasti: Int { Generator.filiTotali - fili.count }
    public var gameOver: Bool { stato != .inCorso }

    public init(valori: [Int], T: Int) {
        precondition(valori.count == 25, "servono 25 valori")
        self.valori = valori
        self.T = T
    }

    public init(puzzle: Puzzle) {
        self.init(valori: puzzle.valori, T: puzzle.T)
    }

    /// Ripristino da persistenza (flusso E: fili conclusi sì, filo a metà no).
    /// Se lo stato salvato è "in-corso" con 3 fili consumati, la partita è persa (§6.6).
    public mutating func ripristina(fili salvati: [FiloConcluso],
                                    stato statoSalvato: StatoPartita,
                                    percorsoVincente percorso: [Int]?) {
        fili = Array(salvati.prefix(Generator.filiTotali))
        filo = []
        somma = 0
        percorsoVincente = percorso
        switch statoSalvato {
        case .vinta:
            stato = .vinta
            if let p = percorso { filo = p; somma = T }
        case .persa:
            stato = .persa
        case .inCorso:
            stato = fili.count >= Generator.filiTotali ? .persa : .inCorso
        }
    }

    public static func adiacenti(_ a: Int, _ b: Int) -> Bool {
        let ra = a / 5, ca = a % 5, rb = b / 5, cb = b % 5
        return abs(ra - rb) + abs(ca - cb) == 1
    }

    public static func vicini(_ idx: Int) -> [Int] {
        let r = idx / 5, c = idx % 5
        var n: [Int] = []
        if r > 0 { n.append(idx - 5) }
        if c < 4 { n.append(idx + 1) }
        if r < 4 { n.append(idx + 5) }
        if c > 0 { n.append(idx - 1) }
        return n
    }

    /// True se l'ultima casella ha almeno un vicino ortogonale non visitato.
    public func vicinoLibero(_ idx: Int) -> Bool {
        Self.vicini(idx).contains { !filo.contains($0) }
    }

    /// Caselle minime teoriche = ceil(T/9) (HUD, §6.1).
    public var caselleMinime: Int { (T + 8) / 9 }

    /// Gioca una casella (tap, drag o tastiera). Esiti automatici valutati
    /// dopo OGNI estensione nell'ordine normativo §6.3: vittoria, spezzato, annodato.
    @discardableResult
    public mutating func gioca(_ idx: Int) -> Mossa {
        guard stato == .inCorso, (0..<25).contains(idx) else { return .ignorata }
        if filo.isEmpty {
            filo.append(idx)
            somma = valori[idx]
            return valuta(primaCasella: true)
        }
        if filo.contains(idx) { return .giaUsata }
        guard Self.adiacenti(filo[filo.count - 1], idx) else { return .nonAdiacente }
        filo.append(idx)
        somma += valori[idx]
        return valuta(primaCasella: false)
    }

    private mutating func valuta(primaCasella: Bool) -> Mossa {
        if somma == T {
            percorsoVincente = filo
            fili.append(FiloConcluso(esito: .vinto, somma: somma, caselle: filo.count))
            stato = .vinta
            return .vittoria
        }
        if somma > T {
            concludiFilo(.spezzato)
            return .spezzato
        }
        if !vicinoLibero(filo[filo.count - 1]) {
            concludiFilo(.annodato)
            return .annodato
        }
        return primaCasella ? .iniziato : .esteso
    }

    /// Strappo volontario (§6.4): possibile solo con filo ≥ 1 casella.
    @discardableResult
    public mutating func strappa() -> Bool {
        guard stato == .inCorso, !filo.isEmpty else { return false }
        concludiFilo(.strappato)
        return true
    }

    private mutating func concludiFilo(_ esito: EsitoFilo) {
        fili.append(FiloConcluso(esito: esito, somma: somma, caselle: filo.count))
        filo = []
        somma = 0
        if fili.count >= Generator.filiTotali {
            stato = .persa   // terzo filo concluso senza vittoria (§6.5)
        }
    }
}
