import XCTest
@testable import FiloCore

/// Confronto carattere per carattere con gli esempi normativi §9.2 del README.
final class ShareTextTests: XCTestCase {

    // Esempio 1 — vittoria al terzo filo, 19 caselle, Sarto (18) battuto, streak 5.
    // Input costruiti: T=100; spezzato a 120 (n=5 per definizione);
    // annodato a 70 → p=0.7 → n=3 (🟦🟦🟦⬜⬜); vinto 19 caselle, 3 stelle + 🥇.
    func testEsempioVittoriaTerzoFiloConStreak() {
        let fili = [
            FiloConcluso(esito: .spezzato, somma: 120, caselle: 14),
            FiloConcluso(esito: .annodato, somma: 70, caselle: 12),
            FiloConcluso(esito: .vinto, somma: 100, caselle: 19)
        ]
        let atteso = """
        FILO #217 🧵
        🟦🟦🟦🟦🟦 💥
        🟦🟦🟦⬜⬜ 🪢
        🟩🟩🟩🟩🟩 19/25 ⭐⭐⭐🥇
        🔥 5 di fila
        """
        XCTAssertEqual(ShareText.build(numero: 217, vinta: true, fili: fili, T: 100,
                                       stelle: 3, sartoBattuto: true, streak: 5),
                       atteso)
    }

    // Esempio 2 — vittoria al primo filo, 12 caselle (Sarto 18 → ⭐), niente streak.
    func testEsempioVittoriaPrimoFiloSenzaStreak() {
        let fili = [FiloConcluso(esito: .vinto, somma: 84, caselle: 12)]
        let atteso = """
        FILO #217 🧵
        🟩🟩🟩🟩🟩 12/25 ⭐
        """
        XCTAssertEqual(ShareText.build(numero: 217, vinta: true, fili: fili, T: 84,
                                       stelle: 1, sartoBattuto: false, streak: 1),
                       atteso)
    }

    // Esempio 3 — sconfitta: ❌ in riga 1, nessuna riga streak anche se streak ≥ 2.
    // Secondo filo annodato a 45 su 100 → p=0.45 → n=2 (🟦🟦⬜⬜⬜).
    func testEsempioSconfitta() {
        let fili = [
            FiloConcluso(esito: .spezzato, somma: 130, caselle: 15),
            FiloConcluso(esito: .annodato, somma: 45, caselle: 8),
            FiloConcluso(esito: .spezzato, somma: 104, caselle: 13)
        ]
        let atteso = """
        FILO #217 🧵 ❌
        🟦🟦🟦🟦🟦 💥
        🟦🟦⬜⬜⬜ 🪢
        🟦🟦🟦🟦🟦 💥
        """
        XCTAssertEqual(ShareText.build(numero: 217, vinta: false, fili: fili, T: 100,
                                       stelle: 0, sartoBattuto: false, streak: 5),
                       atteso)
    }

    func testStreakDueMostrataUnoNo() {
        let fili = [FiloConcluso(esito: .vinto, somma: 50, caselle: 10)]
        let conStreak = ShareText.build(numero: 3, vinta: true, fili: fili, T: 50,
                                        stelle: 1, sartoBattuto: false, streak: 2)
        XCTAssertTrue(conStreak.hasSuffix("\n🔥 2 di fila"))
        let senzaStreak = ShareText.build(numero: 3, vinta: true, fili: fili, T: 50,
                                          stelle: 1, sartoBattuto: false, streak: 1)
        XCTAssertFalse(senzaStreak.contains("🔥"))
    }

    func testFiloStrappatoUsaIlNodo() {
        // Strappato → suffisso 🪢 come annodato (§9.1: "🪢 se annodato o strappato").
        let fili = [
            FiloConcluso(esito: .strappato, somma: 20, caselle: 4),
            FiloConcluso(esito: .vinto, somma: 100, caselle: 18)
        ]
        let out = ShareText.build(numero: 9, vinta: true, fili: fili, T: 100,
                                  stelle: 3, sartoBattuto: false, streak: 0)
        XCTAssertEqual(out, "FILO #9 🧵\n🟦⬜⬜⬜⬜ 🪢\n🟩🟩🟩🟩🟩 18/25 ⭐⭐⭐")
    }

    func testBarraCasiLimite() {
        // somma == T-1 su un filo perso: p appena sotto 1 → n=4
        let quasi = [FiloConcluso(esito: .annodato, somma: 99, caselle: 20)]
        let out = ShareText.build(numero: 1, vinta: false, fili: quasi, T: 100,
                                  stelle: 0, sartoBattuto: false, streak: 0)
        XCTAssertTrue(out.contains("🟦🟦🟦🟦⬜ 🪢"))
        // nessuna riga URL senza url configurato (§9.1)
        XCTAssertFalse(out.lowercased().contains("http"))
        XCTAssertFalse(out.contains("[DA INSERIRE URL]"))
    }

    func testNessunaRigaURLSenzaConfig() {
        // §9.1: url assente o vuoto → la riga URL NON esiste (mai inventare domini).
        let fili = [FiloConcluso(esito: .vinto, somma: 97, caselle: 17)]
        let out = ShareText.build(numero: 217, vinta: true, fili: fili, T: 97,
                                  stelle: 3, sartoBattuto: false, streak: 7)
        XCTAssertEqual(out.split(separator: "\n").count, 3)  // titolo + filo + streak
        XCTAssertFalse(out.lowercased().contains("http"))
        let vuoto = ShareText.build(numero: 217, vinta: true, fili: fili, T: 97,
                                    stelle: 3, sartoBattuto: false, streak: 7, url: "")
        XCTAssertFalse(vuoto.lowercased().contains("http"))
    }

    func testRigaURLQuandoConfigurata() {
        // Come il web con CONFIG.SHARE_URL: il testo TERMINA con la riga URL,
        // che compare UNA sola volta (parità con share_url_test.js).
        let fili = [FiloConcluso(esito: .vinto, somma: 97, caselle: 17)]
        let out = ShareText.build(numero: 217, vinta: true, fili: fili, T: 97,
                                  stelle: 3, sartoBattuto: false, streak: 7,
                                  url: ShareText.shareURL)
        XCTAssertTrue(out.hasSuffix("\n" + ShareText.shareURL))
        XCTAssertEqual(out.components(separatedBy: ShareText.shareURL).count - 1, 1)
        XCTAssertEqual(out.split(separator: "\n").count, 4)  // titolo + filo + streak + URL
    }
}
