import Foundation

/// Logica PURA del test degli screenshot (solo Foundation, niente XCTest):
/// lettura delle etichette VoiceOver delle caselle, scelta del puzzle del
/// giorno coerente con la griglia mostrata e ricerca di percorsi a somma
/// esatta. Vive in un file separato così si compila e si verifica anche su
/// Linux insieme ai sorgenti di FiloCore (che il target FILOUITests compila
/// dentro il proprio bundle: qui `Generator`, `FiloDate`, `GameEngine` sono
/// tipi dello stesso modulo, senza `import FiloCore`).
enum ScreenshotPlanner {

    /// Una casella letta dall'interfaccia (riga e colonna 1-based, come nelle
    /// etichette "Casella riga R colonna C, valore V" / "Cell row R column C, value V").
    struct Cella: Equatable {
        let r: Int
        let c: Int
        let valore: Int
        var indice: Int { (r - 1) * 5 + (c - 1) }
    }

    /// Estrae riga, colonna e valore dall'etichetta di una casella. Le etichette
    /// possono avere suffissi (", ultima del filo", ", nel filo, posizione 3"…):
    /// contano solo i primi tre numeri dopo il prefisso localizzato.
    static func parseCella(_ label: String, prefisso: String) -> Cella? {
        guard label.hasPrefix(prefisso) else { return nil }
        var numeri: [Int] = []
        var corrente = ""
        for ch in label.dropFirst(prefisso.count) {
            if ch.isASCII, ch.isNumber {
                corrente.append(ch)
            } else if !corrente.isEmpty {
                numeri.append(Int(corrente) ?? -1)
                corrente = ""
                if numeri.count == 3 { break }
            }
        }
        if !corrente.isEmpty, numeri.count < 3 { numeri.append(Int(corrente) ?? -1) }
        guard numeri.count == 3,
              (1...5).contains(numeri[0]), (1...5).contains(numeri[1]), numeri[2] >= 1
        else { return nil }
        return Cella(r: numeri[0], c: numeri[1], valore: numeri[2])
    }

    /// Valori row-major (25) dalle caselle lette; nil se ne manca qualcuna.
    static func valori(da celle: [Cella]) -> [Int]? {
        var v = [Int](repeating: 0, count: 25)
        var visti = Set<Int>()
        for c in celle where !visti.contains(c.indice) {
            v[c.indice] = c.valore
            visti.insert(c.indice)
        }
        return visti.count == 25 ? v : nil
    }

    /// Terna (anno, mese, giorno) della data nel calendario dato: identica a
    /// `GameViewModel.oggiParts` dell'app (Calendar.current, mezzanotte locale).
    static func parti(_ data: Date, calendar: Calendar) -> (y: Int, m: Int, d: Int) {
        let c = calendar.dateComponents([.year, .month, .day], from: data)
        return (c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    /// Puzzle del giorno coerente con la griglia mostrata dall'app. Prova oggi
    /// (stesso calcolo di FiloDate/Generator.daily usato dall'app), poi ieri e
    /// domani per tollerare un test che scavalla la mezzanotte. Se i valori a
    /// schermo non sono disponibili, si fida della data di oggi.
    static func puzzleDelGiorno(valoriMostrati: [Int]?,
                                adesso: Date = Date(),
                                calendar: Calendar = .current)
        -> (puzzle: Puzzle, numero: Int, data: String)? {
        for delta in [0, -1, 1] {
            guard let giorno = calendar.date(byAdding: .day, value: delta, to: adesso) else { continue }
            let p = parti(giorno, calendar: calendar)
            let daily = Generator.daily(y: p.y, m: p.m, d: p.d)
            let etichetta = FiloDate.dateString(y: p.y, m: p.m, d: p.d)
            guard let mostrati = valoriMostrati else {
                return (daily.puzzle, daily.numero, etichetta)
            }
            if daily.puzzle.valori == mostrati {
                return (daily.puzzle, daily.numero, etichetta)
            }
        }
        return nil
    }

    /// Verifica che il percorso del Sarto, giocato sul motore reale, dia una
    /// vittoria con esattamente lSarto caselle (= 3 stelle, "Filo perfetto").
    static func verificaSarto(_ puzzle: Puzzle) -> Bool {
        var engine = GameEngine(puzzle: puzzle)
        var ultima: Mossa = .ignorata
        for idx in puzzle.percorsoSarto { ultima = engine.gioca(idx) }
        guard ultima == .vittoria, engine.percorsoVincente == puzzle.percorsoSarto else { return false }
        let stelle = Punteggio.stelle(caselle: puzzle.percorsoSarto.count, lSarto: puzzle.lSarto)
        return stelle.stelle == 3
    }

    /// Percorso semplice di caselle ortogonalmente adiacenti con somma ESATTA
    /// `target` (valori tutti ≥ 1, quindi ogni prefisso resta sotto il target e
    /// non è mai "annodato": la casella successiva del percorso è libera).
    /// Restituisce il più LUNGO trovato entro `budget` nodi visitati (più
    /// bello da vedere). Nil se non esiste.
    static func percorso(somma target: Int, valori: [Int], budget: Int = 400_000) -> [Int]? {
        guard valori.count == 25, target > 0 else { return nil }
        var migliore: [Int]?
        var visitati = 0
        var cammino: [Int] = []
        var usate = [Bool](repeating: false, count: 25)

        func vicini(_ i: Int) -> [Int] {
            let r = i / 5, c = i % 5
            var n: [Int] = []
            if r > 0 { n.append(i - 5) }
            if c < 4 { n.append(i + 1) }
            if r < 4 { n.append(i + 5) }
            if c > 0 { n.append(i - 1) }
            return n
        }

        func esplora(_ i: Int, _ somma: Int) {
            visitati += 1
            if visitati > budget { return }
            cammino.append(i)
            usate[i] = true
            defer { cammino.removeLast(); usate[i] = false }
            if somma == target {
                if cammino.count > (migliore?.count ?? 0) { migliore = cammino }
                return
            }
            for n in vicini(i) where !usate[n] && somma + valori[n] <= target {
                esplora(n, somma + valori[n])
            }
        }

        for start in 0..<25 where valori[start] <= target {
            esplora(start, valori[start])
            if visitati > budget { break }
        }
        return migliore
    }

    /// Centro della casella `idx` in coordinate schermo, dato il frame della
    /// griglia: stessa geometria di BoardView/PracticeBoardView (5 colonne,
    /// gap 6 pt, lato = (larghezza − 4·gap) / 5).
    static func centro(idx: Int, griglia: CGRect, gap: CGFloat = 6) -> CGPoint {
        let lato = (griglia.width - gap * 4) / 5
        let r = CGFloat(idx / 5), c = CGFloat(idx % 5)
        return CGPoint(x: griglia.minX + c * (lato + gap) + lato / 2,
                       y: griglia.minY + r * (lato + gap) + lato / 2)
    }
}
