import Foundation

/// Generatore della SALITA v2 (SALITA_TIMER_SPEC §2) — indipendente dal
/// generatore giornaliero CONGELATO (`Generator`) e dal vecchio
/// `PracticeGenerator` (che resta invariato per compatibilità).
///
/// Perché esiste: il vecchio generatore spalmava target crescenti (100, 200,
/// 300…) su percorsi fino a 25 caselle, quindi dal livello 5 la soluzione era
/// "tutta la griglia" e i valori superavano 9; ai livelli 1–4 la soluzione era
/// spesso una fila di 5. Qui invece:
///
/// - **Griglia a "sacchetto bilanciato"**: 25 cifre = due copie di ciascuna
///   cifra 1…9 (18) + una copia in più di 7 cifre distinte estratte a caso (7),
///   mescolate sulla griglia con `Mulberry32`. Totale griglia 118…132, sempre
///   maggiore di qualsiasi target di livello ⇒ "unire tutto" non è mai la
///   risposta. Valori SEMPRE in 1…9.
/// - **Percorso d'autore**: cammino ortogonale auto-evitante di ESATTAMENTE
///   `L` caselle e somma ESATTAMENTE `T` (DFS randomizzata con potatura sulla
///   somma). Se non c'è, si rimescola con un sotto-seme nuovo.
/// - **Filtri anti-banalità** (risolutore esatto e limitato): lunghezza della
///   soluzione PIÙ CORTA ≥ Kmin(n); almeno 3 soluzioni distinte di lunghezza
///   ≤ L (un percorso e il suo inverso contano una volta); dal livello 10 il
///   percorso d'autore copre ≥ 4 righe e ≥ 4 colonne; L ≤ 18 (⇒ ≥ 7 caselle
///   fuori dal percorso).
/// - **Determinismo**: stesso `(livello, seed)` ⇒ stesso `Puzzle`, su ogni
///   piattaforma (solo aritmetica intera + `Mulberry32`).
/// - **Fallback**: se i tentativi si esauriscono, i filtri si rilassano a
///   gradini; in ultima istanza una costruzione deterministica a serpentina.
///   Mai valori fuori da 1…9, mai L > 18, `T` sempre esatto.
///
/// "Soluzione" = qualunque cammino di caselle distinte ortogonalmente
/// adiacenti la cui somma è ESATTAMENTE il target (come in `GameEngine`: la
/// vittoria scatta appena la somma coincide; i valori sono ≥ 1 quindi nessun
/// prefisso proprio di una soluzione è a sua volta una soluzione).
///
/// Logica PURA: solo Foundation, compila e si testa su Linux.
public enum SalitaGenerator {
    public static let gridSide = 5
    public static let cellCount = 25
    /// Lunghezza massima del percorso d'autore (⇒ almeno 7 caselle libere).
    public static let maxAuthorLength = 18
    /// Caselle minime fuori dal percorso d'autore.
    public static let minOffPath = cellCount - maxAuthorLength
    /// Soluzioni distinte minime (lunghezza ≤ L) richieste per ogni livello.
    public static let minSolutionsPerLevel = 3
    /// Dal livello indicato il percorso d'autore deve coprire ≥ 4 righe e
    /// ≥ 4 colonne distinte.
    public static let spansFromLevel = 10
    public static let minSpan = 4

    // MARK: - Parametri di livello

    /// Parametri di un livello della Salita.
    /// - `target`: somma da raggiungere (T).
    /// - `authorLength`: lunghezza del percorso d'autore (L).
    /// - `seconds`: budget del conto alla rovescia in modalità "Normale" (C).
    public struct Level: Equatable {
        public let n: Int
        public let target: Int
        public let authorLength: Int
        public let seconds: Int

        public init(n: Int, target: Int, authorLength: Int, seconds: Int) {
            self.n = n
            self.target = target
            self.authorLength = authorLength
            self.seconds = seconds
        }
    }

    /// Tabella di livello (spec §1–§2), `n` è normalizzato a ≥ 1:
    /// - L(n) = min(18, n + 2)
    /// - T(n) = 10 + 6·(n − 1) per n ≤ 16; per n ≥ 17: 96 + 2·((n − 14) mod 5)
    ///   (oscilla 96…104)
    /// - C(n) = min(65, 29 + 2·L) − 2·min(5, ⌊max(0, n − 20) / 5⌋)  [secondi]
    public static func parameters(level n: Int) -> Level {
        let n = max(1, n)
        let L = min(maxAuthorLength, n + 2)
        let T = n <= 16 ? 10 + 6 * (n - 1) : 96 + 2 * ((n - 14) % 5)
        let seconds = min(65, 29 + 2 * L) - 2 * min(5, max(0, n - 20) / 5)
        return Level(n: n, target: T, authorLength: L, seconds: seconds)
    }

    /// Kmin(n): lunghezza minima ammessa per la soluzione PIÙ CORTA.
    /// | 1–3: ⌈0,55·L⌉ | 4–10: ⌈0,65·L⌉ | 11–20: ⌈0,70·L⌉ | 21–30: 15 | 31+: 16 |
    /// (aritmetica intera: ⌈p·L/100⌉ = (p·L + 99) / 100). Mai oltre L.
    static func minShortest(level n: Int) -> Int {
        let p = parameters(level: n)
        let L = p.authorLength
        let k: Int
        switch p.n {
        case ...3: k = (55 * L + 99) / 100
        case 4...10: k = (65 * L + 99) / 100
        case 11...20: k = (70 * L + 99) / 100
        case 21...30: k = 15
        default: k = 16
        }
        return min(k, L)
    }

    // MARK: - Generazione (API pubblica)

    /// Puzzle del livello `n` della Salita. Deterministico: stesso `(n, seed)`
    /// ⇒ stesso `Puzzle`. `Puzzle.T == parameters(level: n).target`,
    /// `percorsoSarto` = percorso d'autore, `lSarto` = L(n).
    /// `seedUsato` riporta il sotto-seme a 32 bit del tentativo accettato
    /// (informativo; per riprodurre il puzzle basta `(n, seed)`).
    ///
    /// Pensato per essere precalcolato fuori dal main thread (tempi in
    /// `notes/SALITA_GENERATOR.md`).
    public static func make(level n: Int, seed: UInt64) -> Puzzle {
        let p = parameters(level: n)
        let pieni = Requisiti(target: p.target, length: p.authorLength,
                              minShortest: minShortest(level: p.n),
                              minSolutions: minSolutionsPerLevel,
                              spans: p.n >= spansFromLevel,
                              noUniform: true)
        let base = mix(seed ^ mix(UInt64(truncatingIfNeeded: p.n) &+ 0x5A11_7A00))

        // Scala di rilassamento (solo se i tentativi a filtri pieni falliscono,
        // evento che nei test su livelli 1…60 non si verifica).
        var r1 = pieni; r1.minSolutions = 2
        var r2 = r1; r2.minSolutions = 1; r2.spans = false
        r2.minShortest = max(1, pieni.minShortest - 1)
        var r3 = r2; r3.minShortest = 1
        let scala: [(Requisiti, Int)] = [(pieni, 400), (r1, 60), (r2, 60), (r3, 60)]

        let cifre = Array(1...9)
        var tentativo: UInt64 = 0
        for (req, quanti) in scala {
            for _ in 0..<quanti {
                let sub = mix(base &+ tentativo)
                tentativo &+= 1
                if let puzzle = tentativoSacchetto(req, cifre: cifre, sub: sub, bilanciato: true) {
                    return puzzle
                }
            }
        }
        return fallbackDeterministico(pieni, sub: mix(base))
    }

    /// Generatore generico (usato dal riscaldamento: 6/2, 10/3, 15/4).
    /// Produce un percorso d'autore di `length` caselle a somma esatta
    /// `target`, mai una fila di cifre identiche (quando la somma lo consente),
    /// e garantisce che la soluzione più corta abbia almeno `minShortest`
    /// caselle. Deterministico per `(target, length, seed, minShortest)`.
    ///
    /// Normalizzazione degli input (mai valori fuori da 1…9, mai L > 18):
    /// `target` in 1…162 (= 9·18), `length` in ⌈target/9⌉…min(18, target),
    /// `minShortest` in 1…length.
    ///
    /// Strategia: prima sacchetto bilanciato (escludendo la cifra = target
    /// quando `minShortest ≥ 2`) con riparazione a scambi; poi costruzione
    /// guidata cella per cella (adatta ai target piccoli); poi rilassamento di
    /// `minShortest` a gradini; infine fallback deterministico.
    public static func make(target: Int, length: Int, seed: UInt64, minShortest: Int) -> Puzzle {
        let T = min(max(1, target), 9 * maxAuthorLength)
        let Lmin = (T + 8) / 9
        let L = max(Lmin, min(length, maxAuthorLength, T))
        let k = min(max(1, minShortest), L)
        let req = Requisiti(target: T, length: L, minShortest: k, minSolutions: 1,
                            spans: false, noUniform: true)
        let base = mix(seed ^ mix(UInt64(truncatingIfNeeded: T) &* 0x1_0000_0001
                                  &+ UInt64(truncatingIfNeeded: L) &* 0x100
                                  &+ UInt64(truncatingIfNeeded: k)))

        var cifre = Array(1...9)
        if k >= 2 { cifre.removeAll { $0 == T } }

        var tentativo: UInt64 = 0
        func prossimo() -> UInt64 { defer { tentativo &+= 1 }; return mix(base &+ tentativo) }

        for _ in 0..<60 {
            if let p = tentativoSacchetto(req, cifre: cifre, sub: prossimo(), bilanciato: false) { return p }
        }
        for _ in 0..<200 {
            if let p = tentativoCostruttivo(req, sub: prossimo()) { return p }
        }
        var rilassato = req
        while rilassato.minShortest > 1 {
            rilassato.minShortest -= 1
            for _ in 0..<60 {
                if let p = tentativoCostruttivo(rilassato, sub: prossimo()) { return p }
            }
        }
        return fallbackDeterministico(req, sub: mix(base))
    }

    // MARK: - Risolutori esatti (pubblici per test e diagnostica)

    /// Lunghezza della soluzione PIÙ CORTA (cammino ortogonale auto-evitante a
    /// somma esatta `target`) fra quelle di lunghezza ≤ `maxLength`; `nil` se
    /// non ne esiste nessuna. Esatto: DFS limitata in profondità con potatura
    /// sulla somma (supero del target) e sulla somma massima raggiungibile con
    /// le caselle rimaste (somma delle k cifre più grandi ≤ target).
    public static func shortestSolutionLength(valori: [Int], target: Int, maxLength: Int) -> Int? {
        guard valori.count == cellCount, target >= 1, maxLength >= 1 else { return nil }
        var s = Solutore(valori: valori, target: target)
        return s.piuCorta(maxLength: maxLength, alPrimo: false, budget: .max)?.count
    }

    /// Numero di soluzioni distinte di lunghezza ≤ `maxLength`, contato fino a
    /// `limit` (uscita anticipata). Un cammino e il suo inverso contano UNA
    /// volta (si conta solo l'orientamento con prima casella < ultima casella).
    public static func countSolutions(valori: [Int], target: Int, maxLength: Int, limit: Int) -> Int {
        guard valori.count == cellCount, target >= 1, maxLength >= 1, limit >= 1 else { return 0 }
        var s = Solutore(valori: valori, target: target)
        return s.conta(maxLength: maxLength, limit: limit, budget: .max) ?? 0
    }

    // MARK: - Interni: requisiti e seme

    struct Requisiti {
        var target: Int
        var length: Int
        var minShortest: Int
        var minSolutions: Int
        var spans: Bool
        var noUniform: Bool
    }

    /// Budget (nodi visitati) per tentativo: mantengono il tempo limitato e
    /// deterministico. Un budget esaurito invalida il tentativo (non si
    /// accetta MAI una griglia non verificata).
    static let budgetAutore = 40_000
    static let budgetVerifica = 400_000
    static let riparazioniMax = 24

    /// splitmix64: rimescola semi a 64 bit (deterministico, solo interi).
    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Sotto-seme → `Mulberry32` (stato a 32 bit) e valore di `seedUsato`.
    static func seme32(_ sub: UInt64) -> Int {
        Int(UInt32(truncatingIfNeeded: sub ^ (sub >> 32)))
    }

    // MARK: - Interni: tentativi

    /// Sacchetto di 25 cifre. `bilanciato` con 9 cifre = specifica di livello:
    /// due copie di 1…9 + 7 cifre distinte estratte a caso; in generale ogni
    /// cifra ammessa compare ⌊25/k⌋ volte e 25 mod k cifre distinte una volta
    /// in più. Poi Fisher-Yates sulla griglia.
    static func sacchetto(cifre: [Int], rng: inout Mulberry32) -> [Int] {
        let k = cifre.count
        var bag: [Int] = []
        bag.reserveCapacity(cellCount)
        for _ in 0..<(cellCount / k) { bag.append(contentsOf: cifre) }
        var extra = cifre
        fisherYates(&extra, rng: &rng)
        bag.append(contentsOf: extra.prefix(cellCount % k))
        fisherYates(&bag, rng: &rng)
        return bag
    }

    /// Un tentativo "sacchetto": griglia mescolata → percorso d'autore →
    /// filtro Kmin (con riparazione a scambi fuori dal percorso, che conserva
    /// la composizione del sacchetto) → conteggio soluzioni.
    static func tentativoSacchetto(_ req: Requisiti, cifre: [Int], sub: UInt64,
                                   bilanciato: Bool) -> Puzzle? {
        var rng = Mulberry32(seed: seme32(sub))
        var griglia = sacchetto(cifre: cifre, rng: &rng)
        guard griglia.reduce(0, +) > req.target else { return nil }

        var solA = Solutore(valori: griglia, target: req.target)
        guard let autore = solA.autore(length: req.length, spans: req.spans,
                                       noUniform: req.noUniform, rng: &rng,
                                       budget: budgetAutore) else { return nil }
        var sulPercorso: UInt32 = 0
        for c in autore { sulPercorso |= bit(c) }

        if req.minShortest > 1 {
            var riparazioni = 0
            while true {
                var s = Solutore(valori: griglia, target: req.target)
                let w = s.piuCorta(maxLength: req.minShortest - 1, alPrimo: true,
                                   budget: budgetVerifica)
                if s.esaurito { return nil }
                guard let corta = w else { break }
                riparazioni += 1
                if riparazioni > riparazioniMax { return nil }
                // Scambio: una casella della soluzione troppo corta (fuori dal
                // percorso d'autore) con una casella libera di valore diverso.
                var nellaCorta: UInt32 = 0
                for c in corta { nellaCorta |= bit(c) }
                let fuori = corta.filter { sulPercorso & bit($0) == 0 }
                if fuori.isEmpty { return nil }
                let a = fuori[Int(rng.next() * Double(fuori.count))]
                let candidati = (0..<cellCount).filter {
                    (sulPercorso | nellaCorta) & bit($0) == 0 && griglia[$0] != griglia[a]
                }
                if candidati.isEmpty { return nil }
                let b = candidati[Int(rng.next() * Double(candidati.count))]
                griglia.swapAt(a, b)
            }
        }

        var sc = Solutore(valori: griglia, target: req.target)
        guard let n = sc.conta(maxLength: req.length, limit: req.minSolutions,
                               budget: budgetVerifica),
              n >= req.minSolutions else { return nil }

        return Puzzle(valori: griglia, T: req.target, percorsoSarto: autore,
                      lSarto: autore.count, seedUsato: seme32(sub))
    }

    /// Un tentativo "costruttivo" (target piccoli): percorso casuale con
    /// valori = composizione casuale di T (non uniforme), poi ogni casella
    /// libera riceve la prima cifra (in ordine casuale) che non crea soluzioni
    /// più corte di `minShortest`. Le caselle non ancora assegnate valgono
    /// T + 1 (impraticabili) durante la verifica.
    static func tentativoCostruttivo(_ req: Requisiti, sub: UInt64) -> Puzzle? {
        var rng = Mulberry32(seed: seme32(sub))
        let T = req.target, L = req.length
        guard let percorso = camminoCasuale(length: L, rng: &rng) else { return nil }
        guard var parti = composizione(target: T, length: L, rng: &rng) else { return nil }
        if req.noUniform { rendiNonUniforme(&parti) }

        let blocco = T + 1
        var griglia = [Int](repeating: blocco, count: cellCount)
        var sulPercorso: UInt32 = 0
        for (i, c) in percorso.enumerated() { griglia[c] = parti[i]; sulPercorso |= bit(c) }

        func nessunaCorta(_ g: [Int]) -> Bool {
            guard req.minShortest > 1 else { return true }
            var s = Solutore(valori: g, target: T)
            let w = s.piuCorta(maxLength: req.minShortest - 1, alPrimo: true, budget: budgetVerifica)
            return w == nil && !s.esaurito
        }
        guard nessunaCorta(griglia) else { return nil }

        var libere = (0..<cellCount).filter { sulPercorso & bit($0) == 0 }
        fisherYates(&libere, rng: &rng)
        for c in libere {
            var cifre = Array(1...9)
            fisherYates(&cifre, rng: &rng)
            var ok = false
            for d in cifre {
                griglia[c] = d
                if d > T || nessunaCorta(griglia) { ok = true; break }
            }
            if !ok { return nil }
        }
        guard griglia.reduce(0, +) > T else { return nil }
        var sc = Solutore(valori: griglia, target: T)
        guard let n = sc.conta(maxLength: L, limit: req.minSolutions, budget: budgetVerifica),
              n >= req.minSolutions else { return nil }
        return Puzzle(valori: griglia, T: T, percorsoSarto: percorso, lSarto: L,
                      seedUsato: seme32(sub))
    }

    /// Fallback finale deterministico (non dovrebbe servire): percorso a
    /// serpentina sulle prime L caselle, valori = T distribuito in modo
    /// bilanciato (1…9, reso non uniforme se possibile), caselle libere con
    /// cifre 1…9 a rotazione (saltando la cifra = T). Rispetta sempre
    /// valori 1…9, L ≤ 18, somma esatta e totale griglia > T.
    static func fallbackDeterministico(_ req: Requisiti, sub: UInt64) -> Puzzle {
        let T = req.target, L = req.length
        var serpentina: [Int] = []
        for r in 0..<gridSide {
            let riga = (0..<gridSide).map { r * gridSide + $0 }
            serpentina.append(contentsOf: r % 2 == 0 ? riga : riga.reversed())
        }
        let percorso = Array(serpentina.prefix(L))
        var parti = [Int](repeating: T / L, count: L)
        for i in 0..<(T % L) { parti[i] += 1 }
        if req.noUniform { rendiNonUniforme(&parti) }
        var griglia = [Int](repeating: 0, count: cellCount)
        for (i, c) in percorso.enumerated() { griglia[c] = parti[i] }
        let rotazione = (1...9).filter { $0 != T }
        var k = Int(sub % UInt64(rotazione.count))
        for c in serpentina.dropFirst(L) {
            griglia[c] = rotazione[k % rotazione.count]
            k += 1
        }
        return Puzzle(valori: griglia, T: T, percorsoSarto: percorso, lSarto: L,
                      seedUsato: seme32(sub))
    }

    // MARK: - Interni: utilità

    @inline(__always) static func bit(_ c: Int) -> UInt32 { UInt32(1) << UInt32(c) }

    static func fisherYates(_ a: inout [Int], rng: inout Mulberry32) {
        var i = a.count - 1
        while i >= 1 {
            let j = Int(rng.next() * Double(i + 1))
            a.swapAt(i, j)
            i -= 1
        }
    }

    /// Vicini ortogonali [su, destra, giù, sinistra], tabella piatta 25×4 con
    /// sentinella −1.
    static let viciniPiatti: [Int] = {
        var t = [Int](repeating: -1, count: 100)
        for i in 0..<25 {
            let r = i / 5, c = i % 5
            var k = 0
            if r > 0 { t[i * 4 + k] = i - 5; k += 1 }
            if c < 4 { t[i * 4 + k] = i + 1; k += 1 }
            if r < 4 { t[i * 4 + k] = i + 5; k += 1 }
            if c > 0 { t[i * 4 + k] = i - 1; k += 1 }
        }
        return t
    }()

    /// Cammino auto-evitante casuale di `length` caselle (nessun vincolo di somma).
    static func camminoCasuale(length L: Int, rng: inout Mulberry32) -> [Int]? {
        let nb = viciniPiatti
        var percorso = [Int(rng.next() * Double(cellCount))]
        var visitate = bit(percorso[0])
        var nodi = 0
        func dfs() -> Bool {
            if percorso.count == L { return true }
            nodi += 1
            if nodi > budgetAutore { return false }
            let last = percorso[percorso.count - 1]
            var cand: [Int] = []
            for k in 0..<4 {
                let n = nb[last * 4 + k]
                if n >= 0 && visitate & bit(n) == 0 { cand.append(n) }
            }
            fisherYates(&cand, rng: &rng)
            for n in cand {
                percorso.append(n); visitate |= bit(n)
                if dfs() { return true }
                percorso.removeLast(); visitate &= ~bit(n)
            }
            return false
        }
        return dfs() ? percorso : nil
    }

    /// Composizione casuale di `target` in `length` parti, ciascuna 1…9.
    static func composizione(target T: Int, length L: Int, rng: inout Mulberry32) -> [Int]? {
        guard L >= 1, T >= L, T <= 9 * L else { return nil }
        var parti = [Int](repeating: 1, count: L)
        var resto = T - L
        while resto > 0 {
            let liberi = (0..<L).filter { parti[$0] < 9 }
            let i = liberi[Int(rng.next() * Double(liberi.count))]
            parti[i] += 1
            resto -= 1
        }
        return parti
    }

    /// Se tutte le parti sono uguali (e ce ne sono almeno 2), sposta un'unità
    /// fra le prime due: la somma resta invariata, i valori restano in 1…9.
    static func rendiNonUniforme(_ parti: inout [Int]) {
        guard parti.count >= 2, let v = parti.first, parti.allSatisfy({ $0 == v }) else { return }
        if v < 9 && v > 1 { parti[0] += 1; parti[1] -= 1 }
    }
}

// MARK: - Risolutore

/// Ricerche esatte su griglia 5×5. Struct con metodi `mutating` (niente
/// controlli di esclusività a runtime), insieme delle visitate come bitmask
/// a 32 bit, tabella dei vicini precalcolata, potatura per somma.
struct Solutore {
    let v: [Int]
    let T: Int
    /// top[k] = somma delle k cifre più grandi fra quelle ≤ T (limite
    /// superiore di ciò che k caselle in più possono aggiungere).
    let top: [Int]
    /// low[k] = somma delle k cifre più piccole (limite inferiore).
    let low: [Int]
    let nb: [Int]

    private(set) var esaurito = false
    private var visitate: UInt32 = 0
    private var percorso = [Int](repeating: 0, count: 26)
    private var scratch = [Int](repeating: 0, count: 26 * 4)
    private var limite = 0
    private var migliore: [Int]? = nil
    private var alPrimo = false
    private var fatto = false
    private var nodi = 0
    private var budget = Int.max
    private var trovate = 0
    private var limiteConto = 0
    private var maxLen = 0
    // ricerca d'autore
    private var lunghezza = 0
    private var spans = false
    private var noUniform = false

    init(valori: [Int], target: Int) {
        v = valori
        T = target
        let utili = valori.filter { $0 <= target }.sorted(by: >)
        var t = [Int](repeating: 0, count: 26)
        for k in 1...25 { t[k] = t[k - 1] + (k <= utili.count ? utili[k - 1] : 0) }
        top = t
        let asc = valori.sorted()
        var l = [Int](repeating: 0, count: 26)
        for k in 1...25 { l[k] = l[k - 1] + asc[k - 1] }
        low = l
        nb = SalitaGenerator.viciniPiatti
    }

    @inline(__always) private static func bit(_ c: Int) -> UInt32 { UInt32(1) << UInt32(c) }

    // MARK: Soluzione più corta

    /// Soluzione più corta di lunghezza ≤ `maxLength` (o la prima trovata se
    /// `alPrimo`). Con `budget` finito, `esaurito` segnala una ricerca
    /// incompleta (il risultato `nil` non è allora una prova di assenza).
    mutating func piuCorta(maxLength: Int, alPrimo: Bool, budget: Int) -> [Int]? {
        limite = min(maxLength, 25)
        migliore = nil
        self.alPrimo = alPrimo
        self.budget = budget
        fatto = false; esaurito = false; nodi = 0; visitate = 0
        guard limite >= 1 else { return nil }
        for s in 0..<25 {
            if fatto { break }
            let x = v[s]
            if x <= T { dfsCorta(s, 1, x) }
        }
        return migliore
    }

    private mutating func dfsCorta(_ c: Int, _ d: Int, _ s: Int) {
        nodi += 1
        if nodi > budget { esaurito = true; fatto = true; return }
        percorso[d - 1] = c
        if s == T {
            migliore = Array(percorso[0..<d])
            limite = d - 1
            if alPrimo { fatto = true }
            return
        }
        if d >= limite { return }
        if s + top[limite - d] < T { return }
        let b = Self.bit(c)
        visitate |= b
        let base = c << 2
        for k in 0..<4 {
            let n = nb[base + k]
            if n < 0 { break }
            if visitate & Self.bit(n) != 0 { continue }
            let s2 = s + v[n]
            if s2 > T { continue }
            dfsCorta(n, d + 1, s2)
            if fatto || d >= limite { break }
        }
        visitate &= ~b
    }

    // MARK: Conteggio soluzioni

    /// Conta (fino a `limit`) le soluzioni di lunghezza ≤ `maxLength`,
    /// un percorso e il suo inverso una volta sola. `nil` = budget esaurito.
    mutating func conta(maxLength: Int, limit: Int, budget: Int) -> Int? {
        maxLen = min(maxLength, 25)
        limiteConto = limit
        self.budget = budget
        trovate = 0; fatto = false; esaurito = false; nodi = 0; visitate = 0
        for s in 0..<25 {
            if fatto { break }
            let x = v[s]
            if x <= T { dfsConta(s, 1, x) }
        }
        if esaurito && trovate < limit { return nil }
        return trovate
    }

    private mutating func dfsConta(_ c: Int, _ d: Int, _ s: Int) {
        nodi += 1
        if nodi > budget { esaurito = true; fatto = true; return }
        if d == 1 { percorso[0] = c }
        if s == T {
            if d == 1 || percorso[0] < c {
                trovate += 1
                if trovate >= limiteConto { fatto = true }
            }
            return
        }
        if d >= maxLen { return }
        if s + top[maxLen - d] < T { return }
        let b = Self.bit(c)
        visitate |= b
        let base = c << 2
        for k in 0..<4 {
            let n = nb[base + k]
            if n < 0 { break }
            if visitate & Self.bit(n) != 0 { continue }
            let s2 = s + v[n]
            if s2 > T { continue }
            dfsConta(n, d + 1, s2)
            if fatto { break }
        }
        visitate &= ~b
    }

    // MARK: Percorso d'autore

    /// Cammino di ESATTAMENTE `length` caselle a somma ESATTAMENTE T,
    /// randomizzato (partenze e ordine dei vicini via `rng`), con potatura
    /// low/top sulle caselle rimanenti; `spans` impone ≥ 4 righe e ≥ 4
    /// colonne distinte; `noUniform` scarta cammini di cifre tutte uguali.
    mutating func autore(length: Int, spans: Bool, noUniform: Bool,
                         rng: inout Mulberry32, budget: Int) -> [Int]? {
        lunghezza = length
        self.spans = spans
        self.noUniform = noUniform
        self.budget = budget
        fatto = false; esaurito = false; nodi = 0; visitate = 0
        guard length >= 1, length <= 25 else { return nil }
        var partenze = Array(0..<25)
        SalitaGenerator.fisherYates(&partenze, rng: &rng)
        for s in partenze {
            if fatto { break }
            let x = v[s]
            if x <= T && dfsAutore(s, 1, x, &rng) {
                return Array(percorso[0..<length])
            }
        }
        return nil
    }

    private mutating func dfsAutore(_ c: Int, _ d: Int, _ s: Int, _ rng: inout Mulberry32) -> Bool {
        nodi += 1
        if nodi > budget { esaurito = true; fatto = true; return false }
        percorso[d - 1] = c
        if d == lunghezza { return s == T && finaleValido() }
        let r = lunghezza - d
        if s + low[r] > T || s + top[r] < T { return false }
        let b = Self.bit(c)
        visitate |= b
        // candidati in scratch[d*4 ..< d*4+m], mescolati con Fisher-Yates
        let base = c << 2, off = d << 2
        var m = 0
        for k in 0..<4 {
            let n = nb[base + k]
            if n < 0 { break }
            if visitate & Self.bit(n) == 0 && s + v[n] <= T { scratch[off + m] = n; m += 1 }
        }
        var i = m - 1
        while i >= 1 {
            let j = Int(rng.next() * Double(i + 1))
            scratch.swapAt(off + i, off + j)
            i -= 1
        }
        for k in 0..<m {
            let n = scratch[off + k]
            if dfsAutore(n, d + 1, s + v[n], &rng) { visitate &= ~b; return true }
            if fatto { break }
        }
        visitate &= ~b
        return false
    }

    private func finaleValido() -> Bool {
        let p = percorso[0..<lunghezza]
        if noUniform && lunghezza >= 2 {
            let v0 = v[p[p.startIndex]]
            if p.allSatisfy({ v[$0] == v0 }) { return false }
        }
        if spans {
            var righe = 0, colonne = 0
            for c in p { righe |= 1 << (c / 5); colonne |= 1 << (c % 5) }
            if righe.nonzeroBitCount < SalitaGenerator.minSpan
                || colonne.nonzeroBitCount < SalitaGenerator.minSpan { return false }
        }
        return true
    }
}
