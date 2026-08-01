import XCTest
@testable import FiloCore

final class RulesTests: XCTestCase {

    /// Griglia di comodo: tutti 1 (somme prevedibili) con T scelto ad hoc.
    private func engine(valori: [Int]? = nil, T: Int) -> GameEngine {
        GameEngine(valori: valori ?? Array(repeating: 1, count: 25), T: T)
    }

    // MARK: Vittoria

    func testVittoriaAutomaticaASommaEsatta() {
        var e = engine(T: 3)  // tre caselle da 1 (T qui non normativo: motore puro)
        XCTAssertEqual(e.gioca(0), .iniziato)
        XCTAssertEqual(e.gioca(1), .esteso)
        XCTAssertEqual(e.gioca(2), .vittoria)
        XCTAssertEqual(e.stato, .vinta)
        XCTAssertEqual(e.percorsoVincente, [0, 1, 2])
        XCTAssertEqual(e.fili.last, FiloConcluso(esito: .vinto, somma: 3, caselle: 3))
        XCTAssertEqual(e.gioca(3), .ignorata)  // partita conclusa: input ignorato
    }

    // MARK: Spezzato

    func testFiloSpezzatoQuandoSommaSuperaT() {
        var valori = Array(repeating: 1, count: 25)
        valori[2] = 9
        var e = engine(valori: valori, T: 5)
        e.gioca(0)
        e.gioca(1)
        XCTAssertEqual(e.gioca(2), .spezzato)   // 1+1+9 = 11 > 5
        XCTAssertEqual(e.fili, [FiloConcluso(esito: .spezzato, somma: 11, caselle: 3)])
        XCTAssertEqual(e.filiRimasti, 2)
        XCTAssertTrue(e.filo.isEmpty)
        XCTAssertEqual(e.somma, 0)
        XCTAssertEqual(e.stato, .inCorso)
    }

    // MARK: Annodato

    func testFiloAnnodatoInVicoloCieco() {
        var e = engine(T: 100)
        e.gioca(1)
        e.gioca(6)
        e.gioca(5)
        // 0 ha come vicini solo 1 (visitata) e 5 (visitata) → nodo
        XCTAssertEqual(e.gioca(0), .annodato)
        XCTAssertEqual(e.fili, [FiloConcluso(esito: .annodato, somma: 4, caselle: 4)])
        XCTAssertEqual(e.filiRimasti, 2)
    }

    // MARK: Mosse non valide + no-undo

    func testMossaNonValidaNonAlteraIlFilo() {
        var e = engine(T: 100)
        e.gioca(0)
        e.gioca(1)
        XCTAssertEqual(e.gioca(0), .giaUsata)       // già visitata (anche doppio tap)
        XCTAssertEqual(e.gioca(1), .giaUsata)       // ultima casella: nessun undo
        XCTAssertEqual(e.gioca(12), .nonAdiacente)  // lontana
        XCTAssertEqual(e.gioca(7), .nonAdiacente)   // diagonale
        XCTAssertEqual(e.filo, [0, 1])              // filo intatto: nessuna penalità
        XCTAssertEqual(e.somma, 2)
        XCTAssertEqual(e.filiRimasti, 3)
    }

    func testNessunUndo() {
        // Il motore non espone alcuna API che accorci il filo corrente:
        // dopo N estensioni valide il filo ha esattamente N caselle.
        var e = engine(T: 100)
        for idx in [0, 1, 2, 3, 4, 9] { e.gioca(idx) }
        XCTAssertEqual(e.filo.count, 6)
        e.gioca(4)   // tentativo di "tornare indietro" → giaUsata, filo invariato
        XCTAssertEqual(e.filo, [0, 1, 2, 3, 4, 9])
    }

    // MARK: Strappo

    func testStrappoVolontario() {
        var e = engine(T: 100)
        XCTAssertFalse(e.strappa())   // filo a 0 caselle: non strappabile (§6.4)
        e.gioca(0)
        e.gioca(1)
        XCTAssertTrue(e.strappa())
        XCTAssertEqual(e.fili, [FiloConcluso(esito: .strappato, somma: 2, caselle: 2)])
        XCTAssertEqual(e.filiRimasti, 2)
        XCTAssertEqual(e.stato, .inCorso)
        XCTAssertTrue(e.filo.isEmpty)
    }

    // MARK: 3 fili → sconfitta

    func testTreFiliConclusiSenzaVittoriaEsconfitta() {
        var e = engine(T: 5)
        for _ in 0..<3 {
            e.gioca(0)
            _ = e.strappa()
        }
        XCTAssertEqual(e.stato, .persa)
        XCTAssertEqual(e.filiRimasti, 0)
        XCTAssertEqual(e.gioca(0), .ignorata)
        XCTAssertFalse(e.strappa())
    }

    func testSpezzatoSulTerzoFiloChiudeLaPartita() {
        var valori = Array(repeating: 1, count: 25)
        valori[1] = 9
        var e = engine(valori: valori, T: 5)
        for _ in 0..<2 { e.gioca(0); _ = e.strappa() }
        e.gioca(0)
        XCTAssertEqual(e.gioca(1), .spezzato)   // 1+9 = 10 > 5, terzo filo
        XCTAssertEqual(e.stato, .persa)
    }

    // MARK: Prima casella mai esito immediato sui puzzle reali

    func testPrimaCasellaMaiEsitoImmediato() {
        // T ≥ 20 > 9 per costruzione (§7.5): la prima casella non può vincere né spezzare.
        let p = Generator.generate(seed: 20260801)
        for idx in 0..<25 {
            var e = GameEngine(puzzle: p)
            let m = e.gioca(idx)
            XCTAssertEqual(m, .iniziato, "prima casella \(idx) con esito immediato")
        }
    }

    // MARK: Ripristino (flusso E)

    func testRipristinoInCorsoConFiliEsauritiDiventaPersa() {
        var e = engine(T: 50)
        let tre = [FiloConcluso(esito: .spezzato, somma: 60, caselle: 8),
                   FiloConcluso(esito: .annodato, somma: 30, caselle: 7),
                   FiloConcluso(esito: .strappato, somma: 10, caselle: 3)]
        e.ripristina(fili: tre, stato: .inCorso, percorsoVincente: nil)
        XCTAssertEqual(e.stato, .persa)
    }

    func testRipristinoVintaRicostruisceIlFilo() {
        var e = engine(T: 3)
        e.ripristina(fili: [FiloConcluso(esito: .vinto, somma: 3, caselle: 3)],
                     stato: .vinta, percorsoVincente: [0, 1, 2])
        XCTAssertEqual(e.stato, .vinta)
        XCTAssertEqual(e.filo, [0, 1, 2])
        XCTAssertEqual(e.somma, 3)
    }

    func testCaselleMinime() {
        XCTAssertEqual(engine(T: 84).caselleMinime, 10)   // ceil(84/9)
        XCTAssertEqual(engine(T: 90).caselleMinime, 10)
        XCTAssertEqual(engine(T: 91).caselleMinime, 11)
    }
}
