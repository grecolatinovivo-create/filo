import XCTest

/// GATE DI QUALITÀ — PRIMO AVVIO VERO (nessun launch argument di onboarding).
///
/// Il workflow `screenshots-ios.yml` disinstalla l'app e lancia SOLO questo
/// test prima degli screenshot: se fallisce, il job fallisce.
///
/// Percorso verificato (installazione pulita):
///   intro → menu → card "FILO del giorno" → guida "Come si gioca"
///   → "Gioca il FILO #N" → "Riscaldamento" → UN tocco su "Salta"
///   → entro 5 s il riscaldamento è sparito e il daily ("Somma del giorno")
///   è visibile e INTERATTIVO (un tocco su una casella cambia l'HUD).
///
/// Regressione coperta: `vm.scheda` era legato a DUE `.sheet(item:)` (MenuView
/// e RootView, quest'ultima dentro il fullScreenCover del menu): iOS impilava
/// due fogli identici e dopo "Salta" uno restava orfano, insensibile ai tocchi.
///
/// Ambiente (dal workflow, con prefisso TEST_RUNNER_ che xcodebuild rimuove):
///   SCREENSHOT_DIR  screenshot diagnostici in <dir>/debug/firstlaunch_*.png
///   FILO_LANG       "it" (default) oppure "en"
final class FirstLaunchTests: XCTestCase {

    private var app: XCUIApplication!
    private var t = TestiPrimoAvvio(lingua: "it")
    private var cartellaDebug: URL?
    private var lancio = Date()
    private var scatti = 0

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPrimoAvvioSaltaRiscaldamentoPortaAlDaily() throws {
        let env = ProcessInfo.processInfo.environment
        let lingua = (env["FILO_LANG"] ?? "it").lowercased().hasPrefix("en") ? "en" : "it"
        t = TestiPrimoAvvio(lingua: lingua)
        if let dir = env["SCREENSHOT_DIR"], !dir.isEmpty {
            let dbg = URL(fileURLWithPath: dir, isDirectory: true)
                .appendingPathComponent("debug", isDirectory: true)
            try? FileManager.default.createDirectory(at: dbg, withIntermediateDirectories: true)
            cartellaDebug = dbg
        }

        app = XCUIApplication()
        // SOLO lingua e regione: nessuna chiave di onboarding pre-impostata.
        app.launchArguments += ["-AppleLanguages", "(\(lingua))", "-AppleLocale", t.locale]
        log("lingua=\(lingua) launchArguments=\(app.launchArguments)")
        lancio = Date()
        app.launch()

        // 1. Intro → menu: la card del daily diventa toccabile.
        let card = elemento(t.cardDaily)
        try passo("menu") {
            guard card.waitForExistence(timeout: 30) else {
                throw ErrorePrimoAvvio("card '\(t.cardDaily)' assente: non è un primo avvio pulito?")
            }
            guard aspetta(card, "isHittable == true", timeout: 20) else {
                throw ErrorePrimoAvvio("card del daily non toccabile dopo l'intro")
            }
            attendiDalLancio(secondi: 6.5)   // fine intro + dissolvenza
            scatta("01_menu")
            card.tap()
        }

        // 2. Guida "Come si gioca" del primo avvio → "Gioca il FILO #N".
        try passo("come_si_gioca") {
            let gioca = elemento(prefisso: t.prefissoGioca)
            guard gioca.waitForExistence(timeout: 15) else {
                throw ErrorePrimoAvvio("la guida 'Come si gioca' non è comparsa aprendo il daily")
            }
            var giri = 0
            while !gioca.isHittable && giri < 3 {
                app.swipeUp()
                giri += 1
            }
            guard aspetta(gioca, "isHittable == true", timeout: 5) else {
                throw ErrorePrimoAvvio("'\(t.prefissoGioca)…' non toccabile")
            }
            scatta("02_come_si_gioca")
            gioca.tap()
        }

        // 3. "Riscaldamento" → UN SOLO tocco su "Salta".
        let salta = elemento(t.salta)
        let titoloRiscaldamento = elemento(senzaMaiuscole: t.riscaldamento)
        try passo("riscaldamento") {
            guard salta.waitForExistence(timeout: 10),
                  aspetta(salta, "isHittable == true", timeout: 5) else {
                throw ErrorePrimoAvvio("il 'Riscaldamento' non è comparso dopo la guida")
            }
            let saltaVisibili = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", t.salta)).allElementsBoundByIndex
                .filter { $0.exists }.count
            log("pulsanti '\(t.salta)' nell'albero: \(saltaVisibili)")
            scatta("03_riscaldamento")
            salta.tap()
        }

        // 4. Entro 5 s: riscaldamento sparito, daily visibile e toccabile.
        let hud = elemento(prefisso: t.prefissoSommaGiorno)
        try passo("dopo_salta") {
            let attese = [
                XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: salta),
                XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: titoloRiscaldamento),
                XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: hud),
            ]
            let esito = XCTWaiter().wait(for: attese, timeout: 5)
            scatta("04_dopo_salta")
            guard esito == .completed else {
                throw ErrorePrimoAvvio("dopo UN tocco su '\(t.salta)' entro 5 s: "
                    + "salta.exists=\(salta.exists) riscaldamento.exists=\(titoloRiscaldamento.exists) "
                    + "hud.exists=\(hud.exists) hud.isHittable=\(hud.exists && hud.isHittable) (esito \(esito.rawValue))")
            }
            guard elemento(t.etichettaGriglia).exists else {
                throw ErrorePrimoAvvio("griglia del daily ('\(t.etichettaGriglia)') non presente")
            }
        }

        // 5. Il daily è interattivo: un tocco su una casella cambia l'HUD.
        try passo("tocco_casella") {
            let casella = elemento(prefisso: t.prefissoCasellaCentrale)
            guard casella.waitForExistence(timeout: 5),
                  aspetta(casella, "isHittable == true", timeout: 5) else {
                throw ErrorePrimoAvvio("casella '\(t.prefissoCasellaCentrale)…' non toccabile")
            }
            let prima = try firmaHUD()
            log("HUD prima: \(prima) — casella: \(casella.label)")
            casella.tap()
            var dopo = prima
            let scadenza = Date().addingTimeInterval(3)
            while Date() < scadenza {
                dopo = try firmaHUD()
                if dopo != prima { break }
                Thread.sleep(forTimeInterval: 0.25)
            }
            log("HUD dopo: \(dopo) — casella: \(casella.exists ? casella.label : "-")")
            scatta("05_dopo_tocco")
            guard !prima.isEmpty, dopo != prima else {
                throw ErrorePrimoAvvio("l'HUD non è cambiato dopo il tocco sulla casella (prima \(prima), dopo \(dopo))")
            }
        }
        log("OK: primo avvio → guida → riscaldamento saltato con un tocco → daily interattivo")
    }

    // MARK: Lettura HUD

    /// Etichette dell'HUD fra "Somma del giorno: T" e "Fili rimasti: n di 3"
    /// (Sarto, somma del filo, caselle), da UN solo snapshot dell'albero.
    @MainActor
    private func firmaHUD() throws -> [String] {
        let radice = try app.snapshot()
        var etichette: [String] = []
        func visita(_ s: XCUIElementSnapshot) {
            if !s.label.isEmpty { etichette.append(s.label) }
            for figlio in s.children { visita(figlio) }
        }
        visita(radice)
        guard let inizio = etichette.firstIndex(where: { $0.hasPrefix(t.prefissoSommaGiorno) }) else {
            return []
        }
        let resto = etichette[(inizio + 1)...]
        let fine = resto.firstIndex(where: { $0.hasPrefix(t.prefissoFiliRimasti) }) ?? resto.endIndex
        return Array(etichette[inizio..<fine])
    }

    // MARK: Passi con diagnostica

    @MainActor
    private func passo(_ nome: String, _ corpo: () throws -> Void) throws {
        log("▶︎ \(nome)")
        do {
            try corpo()
        } catch {
            log("✖︎ \(nome): \(error)")
            scatta("ERRORE_\(nome)")
            log("albero UI (estratto):\n\(String(app.debugDescription.prefix(8000)))")
            XCTFail("[\(nome)] \(error)")
            throw error
        }
    }

    // MARK: Screenshot diagnostici (mai App Store)

    @MainActor
    private func scatta(_ nome: String) {
        scatti += 1
        let shot = XCUIScreen.main.screenshot()
        let allegato = XCTAttachment(screenshot: shot)
        allegato.name = "firstlaunch_\(t.lingua)_\(nome)"
        allegato.lifetime = .keepAlways
        add(allegato)
        if let cartellaDebug {
            let url = cartellaDebug.appendingPathComponent("firstlaunch_\(t.lingua)_\(nome).png")
            do {
                try shot.pngRepresentation.write(to: url, options: .atomic)
                log("debug salvato: \(url.path)")
            } catch {
                log("ERRORE scrittura \(url.path): \(error)")
            }
        }
    }

    private func log(_ s: String) {
        print("[FILO-FIRST] \(s)")
    }

    // MARK: Query e attese

    @MainActor
    private func elemento(_ label: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func elemento(senzaMaiuscole label: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }

    @MainActor
    private func elemento(prefisso: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefisso)).firstMatch
    }

    @MainActor
    private func aspetta(_ e: XCUIElement, _ formato: String, timeout: TimeInterval) -> Bool {
        let attesa = XCTNSPredicateExpectation(predicate: NSPredicate(format: formato), object: e)
        return XCTWaiter().wait(for: [attesa], timeout: timeout) == .completed
    }

    private func attendiDalLancio(secondi: TimeInterval) {
        let trascorso = Date().timeIntervalSince(lancio)
        if trascorso < secondi { Thread.sleep(forTimeInterval: secondi - trascorso) }
    }
}

// MARK: - Supporto

private struct ErrorePrimoAvvio: Error, CustomStringConvertible {
    let description: String
    init(_ m: String) { description = m }
}

/// Testi dell'app nelle due lingue (da Localizable.xcstrings).
private struct TestiPrimoAvvio {
    let lingua: String
    private var it: Bool { lingua == "it" }

    var locale: String { it ? "it_IT" : "en_US" }
    var cardDaily: String { it ? "FILO del giorno, disponibile" : "Daily FILO, available" }
    var prefissoGioca: String { it ? "Gioca il FILO #" : "Play FILO #" }
    var salta: String { it ? "Salta" : "Skip" }
    var riscaldamento: String { it ? "Riscaldamento" : "Warm-up" }
    /// HUD: accessibilityLabel "Somma del giorno: T" / "Fili rimasti: n di 3"
    var prefissoSommaGiorno: String { it ? "Somma del giorno: " : "Daily sum: " }
    var prefissoFiliRimasti: String { it ? "Fili rimasti: " : "Threads left: " }
    var etichettaGriglia: String {
        it ? "Griglia di gioco, 5 righe per 5 colonne" : "Game grid, 5 rows by 5 columns"
    }
    /// Casella centrale (riga 3, colonna 3): qualsiasi casella può aprire il filo.
    var prefissoCasellaCentrale: String { it ? "Casella riga 3 colonna 3, valore " : "Cell row 3 column 3, value " }
}
