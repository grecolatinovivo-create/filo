import XCTest
@testable import FiloCore

/// Test del GENERATORE DI PRATICA (indipendente dal generatore giornaliero).
/// Gira su Linux via `swift test`. NON dipende da `reference.json`.
final class PracticeGeneratorTests: XCTestCase {

    private let targets = [6, 10, 15, 25, 50, 100, 250]
    private let seeds: [UInt64] = [1, 42, 12345, 0xDEAD_BEEF, 999_999]

    // MARK: Verifica indipendente (DFS "from scratch")

    /// Adiacenza ortogonale su griglia 5×5.
    private func adiacenti(_ a: Int, _ b: Int) -> Bool {
        let ra = a / 5, ca = a % 5, rb = b / 5, cb = b % 5
        return abs(ra - rb) + abs(ca - cb) == 1
    }

    private func vicini(_ idx: Int) -> [Int] {
        let r = idx / 5, c = idx % 5
        var n: [Int] = []
        if r > 0 { n.append(idx - 5) }
        if c < 4 { n.append(idx + 1) }
        if r < 4 { n.append(idx + 5) }
        if c > 0 { n.append(idx - 1) }
        return n
    }

    /// DFS indipendente: esiste un cammino adiacente continuo di somma == target?
    /// Pruning: i valori sono ≥ 1, quindi la somma cresce in modo monotòno e si
    /// può potare ogni ramo appena supera il target. Uscita anticipata al primo
    /// cammino trovato.
    private func esisteCamminoSomma(valori: [Int], target: Int) -> Bool {
        var visitate = [Bool](repeating: false, count: 25)
        func dfs(_ idx: Int, _ somma: Int) -> Bool {
            let s = somma + valori[idx]
            if s == target { return true }
            if s > target { return false }
            visitate[idx] = true
            defer { visitate[idx] = false }
            for v in vicini(idx) where !visitate[v] {
                if dfs(v, s) { return true }
            }
            return false
        }
        for start in 0..<25 {
            if dfs(start, 0) { return true }
        }
        return false
    }

    /// Verifica che `percorso` sia un cammino adiacente valido di somma esatta.
    private func percorsoValido(_ percorso: [Int], valori: [Int], target: Int) -> Bool {
        guard !percorso.isEmpty else { return false }
        var visti = Set<Int>()
        var somma = 0
        for (k, idx) in percorso.enumerated() {
            guard (0..<25).contains(idx), !visti.contains(idx) else { return false }
            if k > 0 && !adiacenti(percorso[k - 1], idx) { return false }
            visti.insert(idx)
            somma += valori[idx]
        }
        return somma == target
    }

    // MARK: Test

    func testValoriTuttiPositiviE25() {
        for t in targets {
            for s in seeds {
                let p = PracticeGenerator.make(target: t, seed: s)
                XCTAssertEqual(p.valori.count, 25, "target \(t) seed \(s)")
                XCTAssertTrue(p.valori.allSatisfy { $0 >= 1 }, "valori ≥ 1 (target \(t) seed \(s))")
                XCTAssertEqual(p.T, t)
            }
        }
    }

    func testPercorsoDAutoreValidoESommaEsatta() {
        for t in targets {
            for s in seeds {
                let p = PracticeGenerator.make(target: t, seed: s)
                XCTAssertTrue(percorsoValido(p.percorsoSarto, valori: p.valori, target: t),
                              "percorso d'autore non valido/incoerente (target \(t) seed \(s))")
                XCTAssertEqual(p.lSarto, p.percorsoSarto.count)
            }
        }
    }

    /// Verifica di solvibilità totalmente indipendente dal percorso d'autore:
    /// eseguita per i target trattabili (evita ricerche hamiltoniane costose).
    func testEsisteCamminoAdiacenteIndipendente() {
        // Ricerca esaustiva solo sui target piccoli (rapida). La verifica del
        // percorso d'autore (test sopra) copre in modo rigoroso tutti i target.
        for t in [6, 10, 15, 25] {
            for s in seeds {
                let p = PracticeGenerator.make(target: t, seed: s)
                XCTAssertTrue(esisteCamminoSomma(valori: p.valori, target: t),
                              "nessun cammino adiacente = \(t) trovato (seed \(s))")
            }
        }
    }

    func testDeterminismo() {
        for t in targets {
            for s in seeds {
                let a = PracticeGenerator.make(target: t, seed: s)
                let b = PracticeGenerator.make(target: t, seed: s)
                XCTAssertEqual(a, b, "make non deterministico (target \(t) seed \(s))")
            }
        }
    }

    func testTargetPiccoliEdgeCase() {
        for t in [1, 2, 3, 4, 5] {
            let p = PracticeGenerator.make(target: t, seed: 7)
            XCTAssertEqual(p.valori.count, 25)
            XCTAssertTrue(p.valori.allSatisfy { $0 >= 1 })
            XCTAssertEqual(p.T, t)
            XCTAssertTrue(percorsoValido(p.percorsoSarto, valori: p.valori, target: t),
                          "percorso non valido per target \(t)")
            XCTAssertTrue(esisteCamminoSomma(valori: p.valori, target: t),
                          "nessun cammino = \(t)")
        }
    }

    func testSemiDiversiPossonoDareGriglieDiverse() {
        // Non è un vincolo forte (collisioni possibili), ma su semi lontani ci
        // aspettiamo variazione: verifichiamo che almeno una coppia differisca.
        let a = PracticeGenerator.make(target: 25, seed: 1)
        let b = PracticeGenerator.make(target: 25, seed: 2)
        let c = PracticeGenerator.make(target: 25, seed: 3)
        XCTAssertFalse(a == b && b == c, "attesa varietà tra semi diversi")
    }
}
