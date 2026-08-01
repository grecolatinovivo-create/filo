import XCTest
@testable import FiloCore

final class ScoringTests: XCTestCase {

    // MARK: Stelle — i 4 casi di §8.1

    func testStelleQuattroCasi() {
        // C > L → ⭐⭐⭐ + 🥇
        var r = Punteggio.stelle(caselle: 19, lSarto: 18)
        XCTAssertEqual(r.stelle, 3); XCTAssertTrue(r.gold)
        XCTAssertEqual(r.label, "Hai battuto il Sarto!")
        // C == L → ⭐⭐⭐
        r = Punteggio.stelle(caselle: 18, lSarto: 18)
        XCTAssertEqual(r.stelle, 3); XCTAssertFalse(r.gold)
        XCTAssertEqual(r.label, "Filo perfetto")
        // L-3 ≤ C < L → ⭐⭐ (entrambi i bordi)
        r = Punteggio.stelle(caselle: 17, lSarto: 18)
        XCTAssertEqual(r.stelle, 2); XCTAssertEqual(r.label, "Filo elegante")
        r = Punteggio.stelle(caselle: 15, lSarto: 18)
        XCTAssertEqual(r.stelle, 2)
        // C < L-3 → ⭐
        r = Punteggio.stelle(caselle: 14, lSarto: 18)
        XCTAssertEqual(r.stelle, 1); XCTAssertFalse(r.gold)
        XCTAssertEqual(r.label, "Filo riuscito")
    }

    // MARK: Streak §8.2

    func testStreakIncrementoSuGiorniConsecutivi() {
        var s = Statistiche()
        s.registra(vinta: true, filiUsati: 1, caselle: 12, gold: false, oggi: (2026, 8, 1))
        XCTAssertEqual(s.streak, 1)
        s.registra(vinta: true, filiUsati: 2, caselle: 15, gold: false, oggi: (2026, 8, 2))
        XCTAssertEqual(s.streak, 2)
        s.registra(vinta: true, filiUsati: 1, caselle: 19, gold: true, oggi: (2026, 8, 3))
        XCTAssertEqual(s.streak, 3)
        XCTAssertEqual(s.maxStreak, 3)
        XCTAssertEqual(s.vinte, 3)
        XCTAssertEqual(s.giocate, 3)
        XCTAssertEqual(s.distFili, [2, 1, 0])
        XCTAssertEqual(s.recordCaselle, 19)
        XCTAssertEqual(s.sartoBattuto, 1)
    }

    func testStreakResetSuSconfitta() {
        var s = Statistiche()
        s.registra(vinta: true, filiUsati: 1, caselle: 12, gold: false, oggi: (2026, 8, 1))
        s.registra(vinta: true, filiUsati: 1, caselle: 12, gold: false, oggi: (2026, 8, 2))
        XCTAssertEqual(s.streak, 2)
        s.registra(vinta: false, filiUsati: 3, caselle: 0, gold: false, oggi: (2026, 8, 3))
        XCTAssertEqual(s.streak, 0)
        XCTAssertEqual(s.maxStreak, 2)   // il record resta
        // vittoria dopo la sconfitta: riparte da 1
        s.registra(vinta: true, filiUsati: 1, caselle: 10, gold: false, oggi: (2026, 8, 4))
        XCTAssertEqual(s.streak, 1)
    }

    func testStreakGapDiGiorniRiparteDaUno() {
        var s = Statistiche()
        s.registra(vinta: true, filiUsati: 1, caselle: 12, gold: false, oggi: (2026, 8, 1))
        s.registra(vinta: true, filiUsati: 1, caselle: 12, gold: false, oggi: (2026, 8, 2))
        XCTAssertEqual(s.streak, 2)
        // salta il 3 e il 4, vince il 5 → streak = 1
        s.registra(vinta: true, filiUsati: 1, caselle: 12, gold: false, oggi: (2026, 8, 5))
        XCTAssertEqual(s.streak, 1)
        XCTAssertEqual(s.maxStreak, 2)
    }

    func testStreakACavalloDiMese() {
        var s = Statistiche()
        s.registra(vinta: true, filiUsati: 1, caselle: 12, gold: false, oggi: (2026, 8, 31))
        s.registra(vinta: true, filiUsati: 1, caselle: 12, gold: false, oggi: (2026, 9, 1))
        XCTAssertEqual(s.streak, 2)
    }

    func testStreakEffettiva() {
        var s = Statistiche()
        s.registra(vinta: true, filiUsati: 1, caselle: 12, gold: false, oggi: (2026, 8, 1))
        s.registra(vinta: true, filiUsati: 1, caselle: 12, gold: false, oggi: (2026, 8, 2))
        // stesso giorno della vittoria → valida
        XCTAssertEqual(s.streakEffettiva(oggi: (2026, 8, 2)), 2)
        // giorno dopo (non ancora giocato) → ancora valida
        XCTAssertEqual(s.streakEffettiva(oggi: (2026, 8, 3)), 2)
        // due giorni dopo senza vittorie → azzerata alla visualizzazione
        XCTAssertEqual(s.streakEffettiva(oggi: (2026, 8, 4)), 0)
        XCTAssertEqual(Statistiche().streakEffettiva(oggi: (2026, 8, 4)), 0)
    }

    // MARK: FiloDate

    func testPreviousDay() {
        XCTAssertTrue(FiloDate.previousDay(y: 2026, m: 8, d: 2) == (2026, 8, 1))
        XCTAssertTrue(FiloDate.previousDay(y: 2026, m: 9, d: 1) == (2026, 8, 31))
        XCTAssertTrue(FiloDate.previousDay(y: 2027, m: 1, d: 1) == (2026, 12, 31))
        XCTAssertTrue(FiloDate.previousDay(y: 2028, m: 3, d: 1) == (2028, 2, 29))  // bisestile
        XCTAssertTrue(FiloDate.previousDay(y: 2027, m: 3, d: 1) == (2027, 2, 28))
    }

    func testDateString() {
        XCTAssertEqual(FiloDate.dateString(y: 2026, m: 8, d: 1), "2026-08-01")
        XCTAssertEqual(FiloDate.dateString(y: 2026, m: 12, d: 25), "2026-12-25")
    }
}
