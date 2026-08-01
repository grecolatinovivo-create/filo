import Foundation

/// Il puzzle generato (output §7.5). `seedUsato` documenta l'eventuale scatto
/// della guardia T < 20 → seed+1.
public struct Puzzle: Codable, Equatable {
    public let valori: [Int]          // 25 valori 1..9, row-major
    public let T: Int                 // Somma del Giorno (≥ 20 garantito)
    public let percorsoSarto: [Int]   // percorso d'autore (indici 0..24)
    public let lSarto: Int            // lunghezza del percorso (16..20)
    public let seedUsato: Int

    public init(valori: [Int], T: Int, percorsoSarto: [Int], lSarto: Int, seedUsato: Int) {
        self.valori = valori
        self.T = T
        self.percorsoSarto = percorsoSarto
        self.lSarto = lSarto
        self.seedUsato = seedUsato
    }
}

/// Generatore giornaliero deterministico (README §7).
/// L'ORDINE delle chiamate rng è NORMATIVO e identico al JS di index.html:
/// 1) L_sarto  2) startIdx  3) shuffle Fisher-Yates dentro la DFS  4) 25 valori
/// 5) guardia: se T < 20 si rigenera tutto con seed+1.
public enum Generator {
    public static let gridSide = 5
    public static let cellCount = 25
    public static let filiTotali = 3

    public static func generate(seed seedInit: Int) -> Puzzle {
        var seed = seedInit
        while true {
            var rng = Mulberry32(seed: seed)
            let L = 16 + Int(rng.next() * 5)      // 16..20 (1 chiamata rng)
            let start = Int(rng.next() * 25)      // 0..24  (1 chiamata rng)
            var percorso = [start]
            var visitate = Set<Int>()
            visitate.insert(start)

            // DFS deterministica con backtracking (§7.3).
            func dfs() -> Bool {
                if percorso.count == L { return true }
                let last = percorso[percorso.count - 1]
                let r = last / 5, c = last % 5
                // ordine fisso [su, destra, giù, sinistra], filtro visitate
                var v: [Int] = []
                if r > 0 && !visitate.contains(last - 5) { v.append(last - 5) }
                if c < 4 && !visitate.contains(last + 1) { v.append(last + 1) }
                if r < 4 && !visitate.contains(last + 5) { v.append(last + 5) }
                if c > 0 && !visitate.contains(last - 1) { v.append(last - 1) }
                // Fisher-Yates con rng: for i = len-1 .. 1 (nessuna chiamata se len < 2)
                var i = v.count - 1
                while i >= 1 {
                    let j = Int(rng.next() * Double(i + 1))
                    v.swapAt(i, j)
                    i -= 1
                }
                for cand in v {
                    percorso.append(cand)
                    visitate.insert(cand)
                    if dfs() { return true }
                    percorso.removeLast()
                    visitate.remove(cand)
                }
                return false
            }
            _ = dfs()

            // Passo 2 — 25 valori row-major (§7.4)
            var valori: [Int] = []
            valori.reserveCapacity(25)
            for _ in 0..<25 { valori.append(1 + Int(rng.next() * 9)) }

            // Passo 3 — Somma del Giorno + guardia (§7.5)
            var T = 0
            for p in percorso { T += valori[p] }
            if T >= 20 {
                return Puzzle(valori: valori, T: T, percorsoSarto: percorso,
                              lSarto: L, seedUsato: seed)
            }
            seed += 1
        }
    }

    /// Puzzle del giorno (data locale) con numero progressivo.
    public static func daily(y: Int, m: Int, d: Int) -> (puzzle: Puzzle, numero: Int) {
        (generate(seed: FiloDate.seed(y: y, m: m, d: d)),
         FiloDate.puzzleNumber(y: y, m: m, d: d))
    }
}
