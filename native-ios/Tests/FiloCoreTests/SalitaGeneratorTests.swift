import XCTest
@testable import FiloCore

/// Test del generatore della SALITA v2 (SALITA_TIMER_SPEC §2).
/// Gira su Linux via `swift test`. Indipendente da `reference.json` e dal
/// generatore giornaliero congelato.
final class SalitaGeneratorTests: XCTestCase {

    private static let livelli = Array(1...60)
    private static let semi: [UInt64] = [1, 42, 2026, 0xDEAD_BEEF]

    /// Puzzle generati una volta sola e condivisi fra i test (livello, seme).
    private static let campione: [(n: Int, seed: UInt64, puzzle: Puzzle)] = {
        var out: [(Int, UInt64, Puzzle)] = []
        for n in livelli {
            for s in semi { out.append((n, s, SalitaGenerator.make(level: n, seed: s))) }
        }
        return out
    }()

    // MARK: Verifiche indipendenti

    private func adiacenti(_ a: Int, _ b: Int) -> Bool {
        abs(a / 5 - b / 5) + abs(a % 5 - b % 5) == 1
    }

    private func vicini(_ i: Int) -> [Int] {
        (0..<25).filter { adiacenti(i, $0) }
    }

    private func percorsoValido(_ p: [Int], valori: [Int], target: Int) -> Bool {
        guard !p.isEmpty, Set(p).count == p.count else { return false }
        for (k, c) in p.enumerated() {
            guard (0..<25).contains(c) else { return false }
            if k > 0 && !adiacenti(p[k - 1], c) { return false }
        }
        return p.reduce(0) { $0 + valori[$1] } == target
    }

    /// Enumerazione ingenua (solo potatura "somma > target"): lunghezza più
    /// corta e numero di soluzioni non orientate di lunghezza ≤ maxLen.
    private func bruteForce(valori: [Int], target: Int, maxLen: Int) -> (shortest: Int?, count: Int) {
        var shortest: Int? = nil
        var count = 0
        var visit = [Bool](repeating: false, count: 25)
        var path: [Int] = []
        func dfs(_ c: Int, _ s: Int) {
            path.append(c); visit[c] = true
            defer { path.removeLast(); visit[c] = false }
            if s == target {
                shortest = min(shortest ?? Int.max, path.count)
                if path.count == 1 || path[0] < c { count += 1 }
                return
            }
            if path.count >= maxLen { return }
            for n in vicini(c) where !visit[n] && s + valori[n] <= target { dfs(n, s + valori[n]) }
        }
        for s in 0..<25 where valori[s] <= target { dfs(s, valori[s]) }
        return (shortest, count)
    }

    // MARK: Parametri

    func testParametriEsempiDellaSpec() {
        func check(_ n: Int, L: Int, C: Int, line: UInt = #line) {
            let p = SalitaGenerator.parameters(level: n)
            XCTAssertEqual(p.n, n, line: line)
            XCTAssertEqual(p.authorLength, L, "L(\(n))", line: line)
            XCTAssertEqual(p.seconds, C, "C(\(n))", line: line)
        }
        check(1, L: 3, C: 35)
        check(4, L: 6, C: 41)
        check(10, L: 12, C: 53)
        check(15, L: 17, C: 63)
        for n in 16...20 { check(n, L: 18, C: 65) }
        check(25, L: 18, C: 63)
        check(35, L: 18, C: 59)
        for n in 45...200 { check(n, L: 18, C: 55) }   // pavimento

        // T(n)
        for n in 1...16 { XCTAssertEqual(SalitaGenerator.parameters(level: n).target, 10 + 6 * (n - 1)) }
        XCTAssertEqual(SalitaGenerator.parameters(level: 1).target, 10)
        XCTAssertEqual(SalitaGenerator.parameters(level: 16).target, 100)
        XCTAssertEqual(SalitaGenerator.parameters(level: 17).target, 102)
        XCTAssertEqual(SalitaGenerator.parameters(level: 18).target, 104)
        XCTAssertEqual(SalitaGenerator.parameters(level: 19).target, 96)
        XCTAssertEqual(SalitaGenerator.parameters(level: 20).target, 98)
        XCTAssertEqual(SalitaGenerator.parameters(level: 21).target, 100)
        for n in 17...200 {
            let t = SalitaGenerator.parameters(level: n).target
            XCTAssertTrue((96...104).contains(t) && t % 2 == 0, "T(\(n)) = \(t)")
        }
        // L(n) ≤ 18 sempre, n normalizzato a ≥ 1
        for n in -3...200 { XCTAssertLessThanOrEqual(SalitaGenerator.parameters(level: n).authorLength, 18) }
        XCTAssertEqual(SalitaGenerator.parameters(level: 0), SalitaGenerator.parameters(level: 1))
    }

    func testTabellaKmin() {
        // 1–3: ⌈0,55·L⌉
        XCTAssertEqual(SalitaGenerator.minShortest(level: 1), 2)   // L 3
        XCTAssertEqual(SalitaGenerator.minShortest(level: 2), 3)   // L 4
        XCTAssertEqual(SalitaGenerator.minShortest(level: 3), 3)   // L 5
        // 4–10: ⌈0,65·L⌉
        XCTAssertEqual(SalitaGenerator.minShortest(level: 4), 4)   // L 6
        XCTAssertEqual(SalitaGenerator.minShortest(level: 10), 8)  // L 12
        // 11–20: ⌈0,70·L⌉
        XCTAssertEqual(SalitaGenerator.minShortest(level: 11), 10) // L 13
        XCTAssertEqual(SalitaGenerator.minShortest(level: 20), 13) // L 18
        for n in 21...30 { XCTAssertEqual(SalitaGenerator.minShortest(level: n), 15) }
        for n in 31...60 { XCTAssertEqual(SalitaGenerator.minShortest(level: n), 16) }
    }

    // MARK: Livelli 1…60 × semi

    func testValoriSempreDa1a9() {
        for (n, s, p) in Self.campione {
            XCTAssertEqual(p.valori.count, 25)
            XCTAssertTrue(p.valori.allSatisfy { (1...9).contains($0) }, "n \(n) seed \(s)")
        }
    }

    func testSacchettoBilanciato() {
        for (n, s, p) in Self.campione {
            var conta = [Int](repeating: 0, count: 10)
            for v in p.valori { conta[v] += 1 }
            let cifre = conta[1...9]
            XCTAssertTrue(cifre.allSatisfy { $0 == 2 || $0 == 3 }, "n \(n) seed \(s): \(conta)")
            XCTAssertEqual(cifre.filter { $0 == 3 }.count, 7, "n \(n) seed \(s)")
        }
    }

    func testPercorsoDAutoreValidoESommaT() {
        for (n, s, p) in Self.campione {
            let par = SalitaGenerator.parameters(level: n)
            XCTAssertEqual(p.T, par.target, "n \(n)")
            XCTAssertEqual(p.lSarto, par.authorLength, "n \(n)")
            XCTAssertEqual(p.percorsoSarto.count, p.lSarto, "n \(n)")
            XCTAssertLessThanOrEqual(p.lSarto, 18)
            XCTAssertGreaterThanOrEqual(25 - p.lSarto, 7, "≥ 7 caselle fuori dal percorso")
            XCTAssertTrue(percorsoValido(p.percorsoSarto, valori: p.valori, target: p.T),
                          "percorso d'autore non valido (n \(n) seed \(s))")
            let cifre = p.percorsoSarto.map { p.valori[$0] }
            XCTAssertGreaterThan(Set(cifre).count, 1, "fila di cifre identiche (n \(n))")
            // Il percorso è giocabile nel motore reale e vince all'ultima casella.
            var e = GameEngine(puzzle: p)
            var ultima: Mossa = .ignorata
            for c in p.percorsoSarto { ultima = e.gioca(c) }
            XCTAssertEqual(ultima, .vittoria, "n \(n) seed \(s)")
            XCTAssertEqual(e.stato, .vinta)
        }
    }

    func testTotaleGrigliaMaggioreDiT() {
        for (n, s, p) in Self.campione {
            let tot = p.valori.reduce(0, +)
            XCTAssertNotEqual(tot, p.T)
            XCTAssertGreaterThan(tot, p.T, "n \(n) seed \(s)")
            XCTAssertTrue((118...132).contains(tot), "totale \(tot) fuori 118…132")
        }
    }

    func testFiltroKmin() {
        for (n, s, p) in Self.campione {
            let L = p.lSarto
            let k = SalitaGenerator.minShortest(level: n)
            XCTAssertNil(SalitaGenerator.shortestSolutionLength(valori: p.valori, target: p.T, maxLength: k - 1),
                         "soluzione più corta di \(k) (n \(n) seed \(s))")
            let corta = SalitaGenerator.shortestSolutionLength(valori: p.valori, target: p.T, maxLength: L)
            XCTAssertNotNil(corta)
            XCTAssertGreaterThanOrEqual(corta ?? 0, k, "n \(n) seed \(s)")
            XCTAssertLessThanOrEqual(corta ?? 99, L)
        }
    }

    func testAlmenoTreSoluzioniEntroL() {
        for (n, s, p) in Self.campione {
            let c = SalitaGenerator.countSolutions(valori: p.valori, target: p.T, maxLength: p.lSarto, limit: 3)
            XCTAssertEqual(c, 3, "meno di 3 soluzioni ≤ L (n \(n) seed \(s))")
        }
    }

    func testSpanDalLivello10() {
        for (n, s, p) in Self.campione where n >= 10 {
            let righe = Set(p.percorsoSarto.map { $0 / 5 }).count
            let colonne = Set(p.percorsoSarto.map { $0 % 5 }).count
            XCTAssertGreaterThanOrEqual(righe, 4, "n \(n) seed \(s)")
            XCTAssertGreaterThanOrEqual(colonne, 4, "n \(n) seed \(s)")
        }
    }

    func testDeterminismo() {
        for (n, s, p) in Self.campione where n % 3 == 0 || n <= 3 {
            XCTAssertEqual(SalitaGenerator.make(level: n, seed: s), p, "n \(n) seed \(s)")
        }
        // Semi diversi ⇒ griglie diverse (attesa varietà, non vincolo forte).
        let griglie = Set(Self.semi.map { SalitaGenerator.make(level: 12, seed: $0).valori })
        XCTAssertGreaterThan(griglie.count, 1)
        // Livelli diversi con lo stesso seme non riusano la stessa griglia.
        XCTAssertNotEqual(SalitaGenerator.make(level: 20, seed: 7).valori,
                          SalitaGenerator.make(level: 21, seed: 7).valori)
    }

    // MARK: Risolutori

    /// I risolutori ottimizzati coincidono con l'enumerazione ingenua.
    func testRisolutoriControEnumerazioneIngenua() {
        // Puzzle reali dei livelli bassi (target ≤ 52) …
        for (n, _, p) in Self.campione where n <= 8 {
            let bf = bruteForce(valori: p.valori, target: p.T, maxLen: p.lSarto)
            XCTAssertEqual(SalitaGenerator.shortestSolutionLength(valori: p.valori, target: p.T, maxLength: p.lSarto),
                           bf.shortest, "n \(n)")
            XCTAssertEqual(SalitaGenerator.countSolutions(valori: p.valori, target: p.T, maxLength: p.lSarto,
                                                          limit: Int.max), bf.count, "n \(n)")
        }
        // … e griglie pseudo-casuali con target e lunghezze varie.
        var rng = Mulberry32(seed: 99)
        for _ in 0..<40 {
            let valori = (0..<25).map { _ in 1 + Int(rng.next() * 9) }
            let target = 3 + Int(rng.next() * 30)
            let maxLen = 1 + Int(rng.next() * 8)
            let bf = bruteForce(valori: valori, target: target, maxLen: maxLen)
            XCTAssertEqual(SalitaGenerator.shortestSolutionLength(valori: valori, target: target, maxLength: maxLen),
                           bf.shortest)
            XCTAssertEqual(SalitaGenerator.countSolutions(valori: valori, target: target, maxLength: maxLen,
                                                          limit: Int.max), bf.count)
            // limite rispettato
            XCTAssertEqual(SalitaGenerator.countSolutions(valori: valori, target: target, maxLength: maxLen, limit: 2),
                           min(2, bf.count))
        }
    }

    func testPercorsoEInversoContanoUnaVolta() {
        // Griglia di 1 con un solo 2 nell'angolo: target 3 ⇒ le soluzioni sono
        // le coppie (2, vicino) e le terne di 1 in fila; ciascuna conta una volta.
        var valori = [Int](repeating: 9, count: 25)
        valori[0] = 1; valori[1] = 2
        XCTAssertEqual(SalitaGenerator.countSolutions(valori: valori, target: 3, maxLength: 5, limit: 100), 1)
        XCTAssertEqual(SalitaGenerator.shortestSolutionLength(valori: valori, target: 3, maxLength: 5), 2)
        XCTAssertNil(SalitaGenerator.shortestSolutionLength(valori: valori, target: 3, maxLength: 1))
        // Una sola casella = target: una soluzione di lunghezza 1.
        XCTAssertEqual(SalitaGenerator.countSolutions(valori: valori, target: 9, maxLength: 1, limit: 100), 23)
        XCTAssertEqual(SalitaGenerator.shortestSolutionLength(valori: valori, target: 9, maxLength: 3), 1)
    }

    // MARK: Fallback

    func testFallbackDeterministicoSempreValido() {
        for n in 1...60 {
            let par = SalitaGenerator.parameters(level: n)
            let req = SalitaGenerator.Requisiti(target: par.target, length: par.authorLength,
                                                minShortest: SalitaGenerator.minShortest(level: n),
                                                minSolutions: 3, spans: n >= 10, noUniform: true)
            let p = SalitaGenerator.fallbackDeterministico(req, sub: UInt64(n))
            XCTAssertTrue(p.valori.allSatisfy { (1...9).contains($0) }, "n \(n)")
            XCTAssertLessThanOrEqual(p.lSarto, 18)
            XCTAssertEqual(p.lSarto, p.percorsoSarto.count)
            XCTAssertTrue(percorsoValido(p.percorsoSarto, valori: p.valori, target: par.target), "n \(n)")
            XCTAssertGreaterThan(p.valori.reduce(0, +), par.target)
            XCTAssertEqual(p, SalitaGenerator.fallbackDeterministico(req, sub: UInt64(n)))
        }
    }

    // MARK: Riscaldamento (make generico)

    func testRiscaldamento() {
        let casi = [(6, 2), (10, 3), (15, 4)]
        let semiW: [UInt64] = [0xF11040, 0xF11041, 0xF11042, 1, 42, 2026, 777, 0xDEAD_BEEF]
        for (t, l) in casi {
            for k in 1...l {
                for s in semiW {
                    let p = SalitaGenerator.make(target: t, length: l, seed: s, minShortest: k)
                    let ctx = "\(t)/\(l) minShortest \(k) seed \(s)"
                    XCTAssertEqual(p.T, t, ctx)
                    XCTAssertEqual(p.lSarto, l, ctx)
                    XCTAssertEqual(p.percorsoSarto.count, l, ctx)
                    XCTAssertTrue(p.valori.allSatisfy { (1...9).contains($0) }, ctx)
                    XCTAssertTrue(percorsoValido(p.percorsoSarto, valori: p.valori, target: t), ctx)
                    XCTAssertGreaterThan(p.valori.reduce(0, +), t, ctx)
                    let cifre = p.percorsoSarto.map { p.valori[$0] }
                    XCTAssertGreaterThan(Set(cifre).count, 1, "fila di cifre identiche: \(cifre) \(ctx)")
                    let corta = SalitaGenerator.shortestSolutionLength(valori: p.valori, target: t, maxLength: 25)
                    XCTAssertGreaterThanOrEqual(corta ?? 0, k, ctx)
                    XCTAssertEqual(SalitaGenerator.make(target: t, length: l, seed: s, minShortest: k), p,
                                   "non deterministico: \(ctx)")
                }
            }
        }
    }

    func testGenericoNormalizzaGliInput() {
        // Lunghezza oltre 18 → 18; target oltre 9·18 → 162; valori sempre 1…9.
        let a = SalitaGenerator.make(target: 500, length: 40, seed: 3, minShortest: 30)
        XCTAssertEqual(a.T, 162)
        XCTAssertEqual(a.lSarto, 18)
        XCTAssertTrue(a.valori.allSatisfy { (1...9).contains($0) })
        XCTAssertTrue(percorsoValido(a.percorsoSarto, valori: a.valori, target: a.T))
        // Lunghezza troppo corta per il target → ⌈T/9⌉.
        let b = SalitaGenerator.make(target: 40, length: 2, seed: 3, minShortest: 2)
        XCTAssertEqual(b.lSarto, 5)
        XCTAssertTrue(percorsoValido(b.percorsoSarto, valori: b.valori, target: 40))
        // Target minuscolo.
        let c = SalitaGenerator.make(target: 1, length: 3, seed: 3, minShortest: 3)
        XCTAssertEqual(c.lSarto, 1)
        XCTAssertTrue(percorsoValido(c.percorsoSarto, valori: c.valori, target: 1))
        XCTAssertTrue(c.valori.allSatisfy { (1...9).contains($0) })
    }
}
