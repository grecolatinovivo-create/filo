import Foundation

/// Generatore di PRATICA — indipendente dal generatore giornaliero CONGELATO.
///
/// A differenza di `Generator.daily`/`Generator.generate` (che impone T ≥ 20 e
/// non è utilizzabile per somme piccole o target arbitrari), questo produce un
/// `Puzzle` su griglia 5×5 con `T = target` GARANTENDO l'esistenza di almeno un
/// percorso continuo di caselle ortogonalmente adiacenti (no diagonali) la cui
/// somma è ESATTAMENTE `target`.
///
/// È usato dalle modalità extra (onboarding progressivo, Salita) e NON tocca in
/// alcun modo l'ordine delle chiamate rng del generatore giornaliero: riusa solo
/// `Mulberry32` (invariato) come sorgente deterministica propria.
///
/// Logica PURA: solo Foundation, compila e si testa su Linux.
public enum PracticeGenerator {
    public static let gridSide = 5
    public static let cellCount = 25

    /// Costruisce un puzzle di pratica con somma target esatta e seme dato.
    /// Deterministico: stesso `target` + stesso `seed` ⇒ stesso `Puzzle`.
    ///
    /// - Nota: con valori tutti ≥ 1 su 25 caselle, il target massimo teorico
    ///   dipende dai valori assegnati; il percorso d'autore riceve i valori
    ///   necessari a totalizzare esattamente `target` (possono superare 9 per
    ///   target grandi), mentre le caselle di riempimento restano piccole (1..9).
    public static func make(target: Int, seed: UInt64) -> Puzzle {
        let tgt = max(1, target)
        var attempt: UInt64 = 0
        while attempt < 10_000 {
            let s = seed &+ attempt
            var rng = Mulberry32(seed: Int(truncatingIfNeeded: s))
            let puzzle = build(target: tgt, seedUsato: Int(truncatingIfNeeded: s), rng: &rng)
            // Verifica interna di solvibilità: il percorso d'autore deve essere
            // un cammino adiacente valido e sommare ESATTAMENTE al target.
            if isValidSolution(percorso: puzzle.percorsoSarto, valori: puzzle.valori, target: tgt) {
                return puzzle
            }
            attempt &+= 1
        }
        // Fallback deterministico (non dovrebbe mai servire): riga in alto.
        return fallback(target: tgt, seedUsato: Int(truncatingIfNeeded: seed))
    }

    // MARK: Costruzione

    private static func build(target: Int, seedUsato: Int, rng: inout Mulberry32) -> Puzzle {
        let L = chooseLength(target: target, rng: &rng)
        let percorso = buildPath(length: L, rng: &rng) ?? Array(0..<L)

        var valori = [Int](repeating: 0, count: cellCount)

        // Distribuzione bilanciata del target sulle L caselle del percorso:
        // ognuna parte da 1, il resto è spalmato quasi uniformemente (max ±1).
        let base = (target - L) / L        // ≥ 0 perché L ≤ target
        let extra = (target - L) % L       // 0..<L
        for p in percorso { valori[p] = 1 + base }
        var ordine = percorso
        fisherYates(&ordine, rng: &rng)
        for k in 0..<extra { valori[ordine[k]] += 1 }

        // Caselle di riempimento: valori piccoli 1..9 (decoy).
        let sulPercorso = Set(percorso)
        for i in 0..<cellCount where !sulPercorso.contains(i) {
            valori[i] = 1 + Int(rng.next() * 9)     // 1..9
        }

        return Puzzle(valori: valori, T: target,
                      percorsoSarto: percorso, lSarto: percorso.count,
                      seedUsato: seedUsato)
    }

    /// Lunghezza del percorso: puntiamo a un valore medio ~5 per casella,
    /// vincolata a [inferiore, superiore] con inferiore ≥ 2 quando possibile.
    private static func chooseLength(target: Int, rng: inout Mulberry32) -> Int {
        let jitter = (rng.next() - 0.5) * 2.0      // consuma sempre 1 rng: coerenza
        if target <= 1 { return 1 }
        let lower = 2
        let upper = min(target, cellCount)
        if lower >= upper { return upper }
        var L = Int((Double(target) / 5.0 + jitter).rounded())
        if L < lower { L = lower }
        if L > upper { L = upper }
        return L
    }

    /// Cammino auto-evitante di `length` caselle adiacenti, con DFS a
    /// backtracking (start e ordine dei vicini scelti via rng). Su 5×5 un
    /// cammino di lunghezza ≤ 25 esiste sempre: il backtracking lo trova.
    private static func buildPath(length L: Int, rng: inout Mulberry32) -> [Int]? {
        let start = Int(rng.next() * Double(cellCount))
        var percorso = [start]
        var visitate = Set([start])

        func dfs() -> Bool {
            if percorso.count == L { return true }
            let last = percorso[percorso.count - 1]
            var vicini = neighbors(last).filter { !visitate.contains($0) }
            fisherYates(&vicini, rng: &rng)
            for c in vicini {
                percorso.append(c); visitate.insert(c)
                if dfs() { return true }
                percorso.removeLast(); visitate.remove(c)
            }
            return false
        }
        return dfs() ? percorso : nil
    }

    // MARK: Utilità pure

    /// Vicini ortogonali (su, destra, giù, sinistra) di un indice 0..24.
    static func neighbors(_ idx: Int) -> [Int] {
        let r = idx / gridSide, c = idx % gridSide
        var n: [Int] = []
        if r > 0 { n.append(idx - gridSide) }
        if c < gridSide - 1 { n.append(idx + 1) }
        if r < gridSide - 1 { n.append(idx + gridSide) }
        if c > 0 { n.append(idx - 1) }
        return n
    }

    private static func fisherYates(_ a: inout [Int], rng: inout Mulberry32) {
        var i = a.count - 1
        while i >= 1 {
            let j = Int(rng.next() * Double(i + 1))
            a.swapAt(i, j)
            i -= 1
        }
    }

    /// True se `percorso` è un cammino adiacente valido (indici distinti in
    /// 0..24, consecutivi ortogonalmente adiacenti) e somma esattamente `target`.
    static func isValidSolution(percorso: [Int], valori: [Int], target: Int) -> Bool {
        guard !percorso.isEmpty, valori.count == cellCount else { return false }
        var visti = Set<Int>()
        var somma = 0
        for (k, idx) in percorso.enumerated() {
            guard (0..<cellCount).contains(idx), !visti.contains(idx) else { return false }
            if k > 0 && !areAdjacent(percorso[k - 1], idx) { return false }
            visti.insert(idx)
            somma += valori[idx]
        }
        return somma == target
    }

    static func areAdjacent(_ a: Int, _ b: Int) -> Bool {
        let ra = a / gridSide, ca = a % gridSide
        let rb = b / gridSide, cb = b % gridSide
        return abs(ra - rb) + abs(ca - cb) == 1
    }

    // MARK: Fallback

    private static func fallback(target: Int, seedUsato: Int) -> Puzzle {
        let tgt = max(1, target)
        let L = min(tgt, cellCount)
        let percorso = Array(0..<L)
        var valori = [Int](repeating: 1, count: cellCount)
        let base = (tgt - L) / L
        let extra = (tgt - L) % L
        for p in percorso { valori[p] = 1 + base }
        for k in 0..<extra { valori[percorso[k]] += 1 }
        return Puzzle(valori: valori, T: tgt, percorsoSarto: percorso,
                      lSarto: percorso.count, seedUsato: seedUsato)
    }
}
