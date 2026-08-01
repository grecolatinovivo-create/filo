import XCTest
@testable import FiloCore

/// PARITÀ CON IL WEB — il test più importante del progetto.
/// reference.json è stato esportato dal motore JS di index.html (#debug,
/// window.__filoDebug.generateForSeed) e NON va mai rigenerato dal codice Swift:
/// se un seed differisce, è sbagliata la semantica 32-bit di questo porting.
final class ReferenceParityTests: XCTestCase {

    struct RefEntry: Decodable {
        let seed: Int
        let numero: Int?
        let valori: [Int]
        let T: Int
        let percorsoSarto: [Int]
        let L: Int
        let seedUsato: Int
    }

    static func loadReference() throws -> [RefEntry] {
        #if SWIFT_PACKAGE
        let url = try XCTUnwrap(Bundle.module.url(forResource: "reference", withExtension: "json"))
        #else
        let url = try XCTUnwrap(Bundle(for: ReferenceParityTests.self)
            .url(forResource: "reference", withExtension: "json"))
        #endif
        return try JSONDecoder().decode([RefEntry].self, from: Data(contentsOf: url))
    }

    func testParitaCompletaConIlMotoreJS() throws {
        let entries = try Self.loadReference()
        XCTAssertGreaterThanOrEqual(entries.count, 300, "servono almeno 300 seed di riferimento")
        for e in entries {
            let p = Generator.generate(seed: e.seed)
            XCTAssertEqual(p.valori, e.valori, "valori diversi per seed \(e.seed)")
            XCTAssertEqual(p.T, e.T, "T diverso per seed \(e.seed)")
            XCTAssertEqual(p.percorsoSarto, e.percorsoSarto, "percorso diverso per seed \(e.seed)")
            XCTAssertEqual(p.lSarto, e.L, "L_sarto diverso per seed \(e.seed)")
            XCTAssertEqual(p.seedUsato, e.seedUsato, "guardia seed+1 divergente per seed \(e.seed)")
        }
    }

    func testVettoriCongelati() {
        // §7.6 — vettori normativi congelati dalla prima implementazione conforme.
        let a = Generator.generate(seed: 20260801)
        XCTAssertEqual(a.T, 97)
        XCTAssertEqual(a.lSarto, 17)
        let b = Generator.generate(seed: 20260802)
        XCTAssertEqual(b.T, 84)
        XCTAssertEqual(b.lSarto, 17)
        let c = Generator.generate(seed: 20261225)
        XCTAssertEqual(c.T, 85)
        XCTAssertEqual(c.lSarto, 19)
    }

    func testNumeroPuzzleDaEpoch() throws {
        // EPOCH 2026-08-01 → FILO #1; il riferimento porta il numero calcolato dal JS.
        XCTAssertEqual(FiloDate.puzzleNumber(y: 2026, m: 8, d: 1), 1)
        XCTAssertEqual(FiloDate.puzzleNumber(y: 2026, m: 8, d: 2), 2)
        XCTAssertEqual(FiloDate.puzzleNumber(y: 2026, m: 7, d: 31), 0)
        for e in try Self.loadReference() {
            guard let numero = e.numero else { continue }
            let y = e.seed / 10000, m = (e.seed % 10000) / 100, d = e.seed % 100
            XCTAssertEqual(FiloDate.puzzleNumber(y: y, m: m, d: d), numero,
                           "numero puzzle diverso per la data seed \(e.seed)")
        }
    }

    func testInvariantiGeneratore() throws {
        for e in try Self.loadReference() {
            let p = Generator.generate(seed: e.seed)
            XCTAssertGreaterThanOrEqual(p.T, 20, "guardia T ≥ 20 violata (seed \(e.seed))")
            XCTAssertEqual(p.valori.count, 25)
            XCTAssertTrue(p.valori.allSatisfy { (1...9).contains($0) })
            XCTAssertTrue((16...20).contains(p.lSarto))
            XCTAssertEqual(p.percorsoSarto.count, p.lSarto)
            XCTAssertEqual(Set(p.percorsoSarto).count, p.lSarto, "percorso non auto-evitante")
            for i in 1..<p.percorsoSarto.count {
                XCTAssertTrue(GameEngine.adiacenti(p.percorsoSarto[i - 1], p.percorsoSarto[i]),
                              "passo non ortogonale nel percorso (seed \(e.seed))")
            }
            XCTAssertEqual(p.percorsoSarto.reduce(0) { $0 + p.valori[$1] }, p.T)
        }
    }
}
