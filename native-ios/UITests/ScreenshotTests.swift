import XCTest

/// SCREENSHOT APP STORE — XCUITest sull'app reale, dal simulatore, in CI
/// (`.github/workflows/screenshots-ios.yml`). Parte da un'installazione pulita
/// (il workflow disinstalla l'app prima di ogni lingua) e cattura:
///
///   01_home            menu dopo l'intro animata
///   02_partita         FILO del giorno con un filo parzialmente tracciato
///   03_vittoria        risultato: percorso del Sarto = 3 stelle, "Filo perfetto"
///   04_statistiche     statistiche dopo la vittoria
///   05_salita          modalità Salita, livello 2 con filo in corso
///   06_archivio        archivio dei FILO passati
///   07_come_si_gioca   guida del primo avvio
///
/// Ambiente (dal workflow, con prefisso TEST_RUNNER_ che xcodebuild rimuove):
///   SCREENSHOT_DIR  cartella radice: i PNG vanno in <dir>/<lingua>/NN_nome.png
///   FILO_LANG       "it" (default) oppure "en"
/// Ogni PNG è anche allegato all'xcresult (XCTAttachment, .keepAlways) come
/// rete di sicurezza.
///
/// Le query usano le etichette di accessibilità e i testi REALI dell'app
/// (Localizable.xcstrings), nelle due lingue: nessuna modifica al codice
/// dell'app. Il percorso del Sarto si calcola con il generatore del giorno di
/// FiloCore (sorgenti compilati dentro questo bundle) e si verifica contro i
/// valori letti dalle caselle a schermo.
final class ScreenshotTests: XCTestCase {

    // MARK: Stato

    private var app: XCUIApplication!
    private var ui = Testi(lingua: "it")
    private var cartella: URL?
    private var lancio = Date()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Test

    @MainActor
    func testScreenshots() throws {
        let env = ProcessInfo.processInfo.environment
        let lingua = (env["FILO_LANG"] ?? "it").lowercased().hasPrefix("en") ? "en" : "it"
        ui = Testi(lingua: lingua)
        if let dir = env["SCREENSHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir, isDirectory: true)
                .appendingPathComponent(lingua, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            cartella = url
        }

        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(lingua))",
                                "-AppleLocale", ui.locale]
        lancio = Date()
        app.launch()

        // ── 1. MENU dopo l'intro ────────────────────────────────────────────
        // L'intro (IntroView) dura ~4,7 s + 0,45 s di dissolvenza e copre il
        // menu: attendiamo che la card del daily sia toccabile E che sia
        // trascorso il tempo dell'animazione.
        let cardDaily = elemento(ui.cardDaily)
        if !cardDaily.waitForExistence(timeout: 30) {
            if elemento(ui.cardDailyFatta).exists {
                XCTFail("Il FILO di oggi risulta già giocato: serve un'installazione pulita (simctl uninstall).")
            }
            XCTFail("Menu non trovato: manca la card '\(ui.cardDaily)'.")
            return
        }
        aspettaToccabile(cardDaily, timeout: 20)
        attendiDalLancio(secondi: 6.5)
        scatta("01_home")

        // ── 7. Guida del primo avvio (Come si gioca) ─────────────────────────
        cardDaily.tap()
        let gioca = elemento(prefisso: ui.prefissoGioca)
        if gioca.waitForExistence(timeout: 12) {
            pausa(2.6)                       // la demo 3×3 mostra qualche casella accesa
            scatta("07_come_si_gioca")
            gioca.tap()
            // Catena primo avvio: dopo la guida arriva il "Riscaldamento".
            let salta = elemento(ui.salta)
            if salta.waitForExistence(timeout: 8) {
                pausa(0.6)
                salta.tap()
                aspettaScomparsa(salta, timeout: 8)
            }
        }
        pausa(1.0)

        // ── 2. Partita in corso con filo parziale ───────────────────────────
        let grigliaDaily = try leggiGriglia()
        let valoriMostrati = ScreenshotPlanner.valori(da: grigliaDaily.celle)
        guard let daily = ScreenshotPlanner.puzzleDelGiorno(valoriMostrati: valoriMostrati) else {
            XCTFail("La griglia a schermo non corrisponde al FILO di oggi/ieri/domani calcolato con FiloCore.")
            return
        }
        XCTAssertTrue(ScreenshotPlanner.verificaSarto(daily.puzzle),
                      "Il percorso del Sarto non dà una vittoria a 3 stelle sul motore reale.")
        let sarto = daily.puzzle.percorsoSarto
        let parziale = max(4, sarto.count / 2)
        for idx in sarto.prefix(parziale) {
            tocca(ScreenshotPlanner.centro(idx: idx, griglia: grigliaDaily.frame))
        }
        pausa(0.8)
        scatta("02_partita")

        // ── 3. Vittoria con il percorso del Sarto ───────────────────────────
        for idx in sarto.dropFirst(parziale) {
            tocca(ScreenshotPlanner.centro(idx: idx, griglia: grigliaDaily.frame))
        }
        // reveal del Sarto (≤ 1,8 s) + 0,75 s, poi il modal risultato
        let linkStatistiche = elemento(ui.linkStatistiche)
        XCTAssertTrue(linkStatistiche.waitForExistence(timeout: 20),
                      "Il modal risultato non è comparso dopo il percorso del Sarto.")
        pausa(1.6)                           // stelle animate in stagger
        scatta("03_vittoria")

        // ── 4. Statistiche ──────────────────────────────────────────────────
        try tappa(ui.chiudi)
        aspettaScomparsa(linkStatistiche, timeout: 8)
        pausa(0.6)
        try tappa(ui.statistiche)
        let titoloStatistiche = app.staticTexts[ui.statistiche]
        XCTAssertTrue(titoloStatistiche.waitForExistence(timeout: 10), "Statistiche non aperte.")
        pausa(0.9)
        scatta("04_statistiche")
        try tappa(ui.chiudi)
        aspettaScomparsa(titoloStatistiche, timeout: 8)
        pausa(0.6)

        // ── 5. Salita: livello 1 risolto, livello 2 con filo in corso ───────
        try tappa(ui.menu)                   // ritorno al menu (transizione a tessere)
        let cardSalita = elemento(ui.cardSalita)
        XCTAssertTrue(cardSalita.waitForExistence(timeout: 10), "Card Salita non trovata.")
        aspettaToccabile(cardSalita, timeout: 10)
        pausa(1.3)                           // fine transizione: durante le tessere il tap è ignorato
        cardSalita.tap()
        XCTAssertTrue(elemento(senzaMaiuscole: ui.livello(1)).waitForExistence(timeout: 10), "Salita non aperta.")
        pausa(1.3)

        let griglia1 = try leggiGriglia()
        guard let valori1 = ScreenshotPlanner.valori(da: griglia1.celle),
              let soluzione1 = ScreenshotPlanner.percorso(somma: Testi.targetSalita(livello: 1), valori: valori1)
        else { XCTFail("Livello 1 della Salita: nessun percorso a somma esatta trovato."); return }
        for idx in soluzione1 { tocca(ScreenshotPlanner.centro(idx: idx, griglia: griglia1.frame)) }
        XCTAssertTrue(elemento(senzaMaiuscole: ui.livello(2)).waitForExistence(timeout: 10), "Livello 2 non raggiunto.")
        pausa(0.8)

        let griglia2 = try leggiGriglia()
        guard let valori2 = ScreenshotPlanner.valori(da: griglia2.celle),
              let soluzione2 = ScreenshotPlanner.percorso(somma: Testi.targetSalita(livello: 2), valori: valori2)
        else { XCTFail("Livello 2 della Salita: nessun percorso a somma esatta trovato."); return }
        for idx in soluzione2.dropLast() { tocca(ScreenshotPlanner.centro(idx: idx, griglia: griglia2.frame)) }
        aspettaScomparsa(elemento(ui.livelloSuperato), timeout: 5)   // toast via
        pausa(0.6)
        scatta("05_salita")

        // ── 6. Archivio (Profilo → Archivio FILO) ───────────────────────────
        try tappa(ui.chiudi)                 // chiude la Salita (xmark "Chiudi")
        let profilo = elemento(ui.profilo)
        XCTAssertTrue(profilo.waitForExistence(timeout: 10), "Pulsante Profilo non trovato.")
        aspettaToccabile(profilo, timeout: 10)
        pausa(1.3)
        profilo.tap()
        let voceArchivio = elemento(contiene: ui.archivio)
        XCTAssertTrue(voceArchivio.waitForExistence(timeout: 10), "Voce Archivio non trovata nel Profilo.")
        var tentativi = 0
        while !voceArchivio.isHittable && tentativi < 4 {
            app.swipeUp()
            tentativi += 1
        }
        voceArchivio.tap()
        let rigaArchivio = elemento(prefisso: ui.prefissoRigaArchivio)
        XCTAssertTrue(rigaArchivio.waitForExistence(timeout: 10), "Archivio vuoto o non aperto.")
        pausa(0.9)
        scatta("06_archivio")
    }

    // MARK: Screenshot

    /// Cattura lo schermo intero (risoluzione nativa del simulatore), lo
    /// allega all'xcresult e lo salva su disco se è stata indicata la cartella.
    @MainActor
    private func scatta(_ nome: String) {
        let shot = XCUIScreen.main.screenshot()
        let allegato = XCTAttachment(screenshot: shot)
        allegato.name = "\(ui.lingua)_\(nome)"
        allegato.lifetime = .keepAlways
        add(allegato)
        guard let cartella else { return }
        let url = cartella.appendingPathComponent("\(nome).png")
        do {
            try shot.pngRepresentation.write(to: url, options: .atomic)
        } catch {
            XCTFail("Impossibile scrivere \(url.path): \(error)")
        }
    }

    // MARK: Griglia

    private struct Griglia {
        let celle: [ScreenshotPlanner.Cella]
        let frame: CGRect
    }

    /// Legge in UN solo snapshot dell'albero di accessibilità le 25 caselle
    /// (etichetta → riga, colonna, valore) e il frame della griglia
    /// ("Griglia di gioco, 5 righe per 5 colonne"). Se il contenitore non
    /// espone il frame, lo ricava dall'unione dei frame delle caselle.
    @MainActor
    private func leggiGriglia() throws -> Griglia {
        let scadenza = Date().addingTimeInterval(15)
        var ultimoErrore = "griglia non trovata"
        repeat {
            let radice = try app.snapshot()
            var celle: [ScreenshotPlanner.Cella] = []
            var frameCelle: [CGRect] = []
            var frameGriglia: CGRect?
            var visti = Set<Int>()

            func visita(_ s: XCUIElementSnapshot) {
                if s.label == ui.etichettaGriglia, s.frame.width > 100, s.frame.height > 100 {
                    frameGriglia = s.frame
                }
                if let c = ScreenshotPlanner.parseCella(s.label, prefisso: ui.prefissoCasella),
                   !visti.contains(c.indice) {
                    visti.insert(c.indice)
                    celle.append(c)
                    frameCelle.append(s.frame)
                }
                for figlio in s.children { visita(figlio) }
            }
            visita(radice)

            if celle.count == 25 {
                if let g = frameGriglia {
                    return Griglia(celle: celle, frame: g)
                }
                let unione = frameCelle.dropFirst().reduce(frameCelle[0]) { $0.union($1) }
                if let prima = frameCelle.first, unione.width > prima.width * 4 {
                    return Griglia(celle: celle, frame: unione)
                }
                ultimoErrore = "frame della griglia non disponibile"
            } else {
                ultimoErrore = "trovate \(celle.count) caselle su 25"
            }
            pausa(0.5)
        } while Date() < scadenza
        throw ErroreScreenshot.griglia(ultimoErrore)
    }

    /// Tocco a coordinate schermo (i frame dello snapshot sono in punti,
    /// origine in alto a sinistra: in ritratto coincide con l'app).
    @MainActor
    private func tocca(_ p: CGPoint) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: p.x, dy: p.y))
            .tap()
    }

    // MARK: Query

    @MainActor
    private func elemento(_ label: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Confronto senza maiuscole/minuscole: le didascalie (captionStyle)
    /// usano textCase(.uppercase) e l'etichetta esposta può essere maiuscola.
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
    private func elemento(contiene: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", contiene)).firstMatch
    }

    /// Tocca il primo elemento TOCCABILE con quell'etichetta (con fogli e
    /// cover sovrapposti la stessa etichetta può esistere più volte).
    @MainActor
    private func tappa(_ label: String, timeout: TimeInterval = 10) throws {
        let query = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
        guard query.firstMatch.waitForExistence(timeout: timeout) else {
            throw ErroreScreenshot.elemento(label)
        }
        for e in query.allElementsBoundByIndex where e.exists && e.isHittable {
            e.tap()
            return
        }
        query.firstMatch.tap()
    }

    // MARK: Attese

    @MainActor
    private func aspettaToccabile(_ e: XCUIElement, timeout: TimeInterval) {
        let attesa = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"),
                                               object: e)
        _ = XCTWaiter().wait(for: [attesa], timeout: timeout)
    }

    @MainActor
    private func aspettaScomparsa(_ e: XCUIElement, timeout: TimeInterval) {
        let attesa = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                               object: e)
        _ = XCTWaiter().wait(for: [attesa], timeout: timeout)
    }

    /// Pausa breve, SOLO per lasciar finire un'animazione nota dell'app.
    private func pausa(_ secondi: TimeInterval) {
        Thread.sleep(forTimeInterval: secondi)
    }

    private func attendiDalLancio(secondi: TimeInterval) {
        let trascorso = Date().timeIntervalSince(lancio)
        if trascorso < secondi { pausa(secondi - trascorso) }
    }
}

// MARK: - Errori

private enum ErroreScreenshot: Error, CustomStringConvertible {
    case griglia(String)
    case elemento(String)

    var description: String {
        switch self {
        case .griglia(let m): return "Griglia: \(m)"
        case .elemento(let l): return "Elemento non trovato: \(l)"
        }
    }
}

// MARK: - Testi dell'app nelle due lingue (da Localizable.xcstrings)

private struct Testi {
    let lingua: String
    private var it: Bool { lingua == "it" }

    var locale: String { it ? "it_IT" : "en_US" }

    // MenuView
    var cardDaily: String { it ? "FILO del giorno, disponibile" : "Daily FILO, available" }
    var cardDailyFatta: String {
        it ? "FILO del giorno, già completato, si rinnova a mezzanotte"
           : "Daily FILO, already completed, renews at midnight"
    }
    var cardSalita: String { it ? "Salita, sempre disponibile" : "Climb, always available" }
    var statistiche: String { it ? "Statistiche" : "Statistics" }
    var profilo: String { it ? "Profilo e temi" : "Profile and themes" }

    // RootView / schede
    var menu: String { "Menu" }
    var chiudi: String { it ? "Chiudi" : "Close" }
    var prefissoGioca: String { it ? "Gioca il FILO #" : "Play FILO #" }
    var salta: String { it ? "Salta" : "Skip" }
    var linkStatistiche: String { it ? "📊 Le tue statistiche" : "📊 Your statistics" }

    // Griglia (BoardView / PracticeBoardView)
    var etichettaGriglia: String {
        it ? "Griglia di gioco, 5 righe per 5 colonne" : "Game grid, 5 rows by 5 columns"
    }
    var prefissoCasella: String { it ? "Casella riga " : "Cell row " }

    // Salita
    func livello(_ n: Int) -> String { it ? "Livello \(n)" : "Level \(n)" }
    var livelloSuperato: String { it ? "Livello superato!" : "Level cleared!" }

    /// Target dei livelli della Salita (SalitaViewModel.target: 10, 25, 50, 100…).
    static func targetSalita(livello n: Int) -> Int {
        switch n {
        case ..<2: return 10
        case 2: return 25
        case 3: return 50
        case 4: return 100
        default: return 100 + (n - 4) * 100
        }
    }

    // Profilo / Archivio
    var archivio: String { it ? "Archivio FILO" : "FILO archive" }
    var prefissoRigaArchivio: String { it ? "FILO numero " : "FILO number " }
}
