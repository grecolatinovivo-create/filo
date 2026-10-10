import XCTest

/// SCREENSHOT APP STORE — XCUITest sull'app reale, dal simulatore, in CI
/// (`.github/workflows/screenshots-ios.yml`). Parte da un'installazione pulita
/// (il workflow disinstalla l'app prima di ogni lingua) e cattura:
///
///   01_home            menu dopo l'intro animata
///   02_partita         FILO del giorno con un filo parzialmente tracciato
///   03_vittoria        risultato di vittoria (3 stelle o 🥇)
///   04_statistiche     statistiche
///   05_salita          modalità Salita, livello 2 con filo in corso
///   06_archivio        archivio dei FILO passati
///   07_come_si_gioca   guida "Come si gioca"
///
/// CATTURA BEST-EFFORT: ogni schermata è una fase indipendente che riparte dal
/// menu; un errore in una fase viene registrato (log + screenshot di debug in
/// <dir>/debug/) e non impedisce le altre. Il test fallisce SOLO alla fine, se
/// le schermate salvate sono meno di 5.
///
/// LA PARTITA SI RISOLVE DA CIÒ CHE SI VEDE: i 25 valori e la Somma del Giorno
/// sono letti dalle etichette VoiceOver; il percorso è cercato con una DFS
/// limitata nel tempo (il più lungo possibile) e validato sul motore reale.
/// Il generatore di FiloCore serve solo da ripiego (percorso del Sarto) se i
/// valori coincidono col FILO di oggi/ieri/domani: niente dipendenza da data,
/// fuso o generatore.
///
/// Ambiente (dal workflow, con prefisso TEST_RUNNER_ che xcodebuild rimuove):
///   SCREENSHOT_DIR  cartella radice: i PNG vanno in <dir>/<lingua>/NN_nome.png
///   FILO_LANG       "it" (default) oppure "en"
/// Ogni PNG è anche allegato all'xcresult (XCTAttachment, .keepAlways).
final class ScreenshotTests: XCTestCase {

    // MARK: Stato

    private var app: XCUIApplication!
    private var ui = Testi(lingua: "it")
    private var cartella: URL?
    private var cartellaDebug: URL?
    private var lancio = Date()
    private var salvati: [String] = []
    private var errori: [String] = []

    override func setUpWithError() throws {
        // Best-effort: un errore di una fase non deve fermare le successive.
        continueAfterFailure = true
    }

    // MARK: Test

    @MainActor
    func testScreenshots() throws {
        let env = ProcessInfo.processInfo.environment
        let lingua = (env["FILO_LANG"] ?? "it").lowercased().hasPrefix("en") ? "en" : "it"
        ui = Testi(lingua: lingua)
        if let dir = env["SCREENSHOT_DIR"], !dir.isEmpty {
            let radice = URL(fileURLWithPath: dir, isDirectory: true)
            let url = radice.appendingPathComponent(lingua, isDirectory: true)
            let dbg = radice.appendingPathComponent("debug", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: dbg, withIntermediateDirectories: true)
            cartella = url
            cartellaDebug = dbg
        }
        log("lingua=\(lingua) locale=\(ui.locale) cartella=\(cartella?.path ?? "-")")

        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(lingua))",
                                "-AppleLocale", ui.locale]
        // Stato persistente PRE-IMPOSTATO senza toccare l'app: i launch
        // argument "-chiave valore" finiscono in NSArgumentDomain, che
        // UserDefaults.standard consulta PRIMA del dominio dell'app (tutte le
        // chiavi FILO sono lette da UserDefaults.standard / @AppStorage).
        //  - filo.onboarded = YES → niente guida "Come si gioca" automatica
        //    (GameViewModel.init/onDailyAperto usano defaults.bool → "YES" = true)
        //  - filo.onboardingProgressivoFatto = YES → niente "Riscaldamento"
        //  - filo.suoni = <false/> → niente audio (SoundManager legge
        //    `object(forKey:) as? Bool`: serve un booleano plist, non "NO")
        // L'intro non ha chiavi (@State showIntro): si attende la sua durata.
        app.launchArguments += Testi.argomentiStato
        log("launchArguments: \(app.launchArguments)")
        lancia()

        fase("01_home") { try faseHome() }
        fase("07_come_si_gioca") { try faseGuidaDalMenu() }
        fase("daily") { try faseDaily() }               // 02, 03
        fase("04_statistiche") { try faseStatistiche() }
        fase("05_salita") { try faseSalita() }
        fase("06_archivio") { try faseArchivio() }

        log("RIEPILOGO \(lingua): salvate \(salvati.count) schermate \(salvati.sorted())")
        for e in errori { log("  errore registrato: \(e)") }
        if salvati.count < 5 {
            XCTFail("Solo \(salvati.count) screenshot salvati (minimo 5). Errori: \(errori.joined(separator: " | "))")
        }
    }

    // MARK: Fasi

    /// 01 — menu dopo l'intro (IntroView ~1,4 s + 0,3 s di dissolvenza).
    @MainActor
    private func faseHome() throws {
        let card = elemento(ui.cardDaily)
        if !card.waitForExistence(timeout: 30) {
            if elemento(ui.cardDailyFatta).exists {
                log("ATTENZIONE: il FILO di oggi risulta già giocato (installazione non pulita)")
            } else {
                throw ErroreScreenshot.fase("menu non trovato (card '\(ui.cardDaily)')")
            }
        }
        aspettaToccabile(elemento(ui.cardSalita), timeout: 20)
        attendiDalLancio(secondi: 6.5)
        scatta("01_home")
    }

    /// 02 (filo parziale) → 03 (vittoria) sul FILO del giorno.
    @MainActor
    private func faseDaily() throws {
        try tornaAlMenu()
        let card = elemento(ui.cardDaily)
        guard card.waitForExistence(timeout: 5) else {
            throw ErroreScreenshot.fase("card del FILO del giorno non disponibile (già giocato?)")
        }
        aspettaToccabile(card, timeout: 10)
        card.tap()
        // Con i flag pre-impostati non deve comparire alcun onboarding; se
        // comparisse comunque, chiudiOnboarding() ha un ripiego (rilancio).
        try chiudiOnboarding()

        let lettura = try leggiSchermo(minimoCelle: 25)
        guard let g = lettura.grigliaPiuAlta, let valori = ScreenshotPlanner.valori(da: g.celle) else {
            throw ErroreScreenshot.fase("griglia del daily non leggibile")
        }
        let T = ScreenshotPlanner.numero(dopo: ui.prefissoSommaGiorno, in: lettura.etichette)
        let L = ScreenshotPlanner.numero(dopo: ui.prefissoSarto, in: lettura.etichette)
        log("DAILY valori letti (row-major):\n\(ScreenshotPlanner.testoGriglia(valori))")
        log("DAILY somma letta=\(T.map(String.init) ?? "nil") Sarto letto=\(L.map(String.init) ?? "nil") griglia=\(g.frame) griglie trovate=\(lettura.griglie.count)")
        guard let piano = ScreenshotPlanner.pianoDaily(valori: valori, somma: T, lSarto: L, secondi: 4) else {
            throw ErroreScreenshot.fase("nessun percorso con somma \(T.map(String.init) ?? "?") sui valori letti")
        }
        log("DAILY piano: \(piano.fonte), somma \(piano.somma), percorso \(piano.percorso)")

        let percorso = piano.percorso
        let parziale = min(percorso.count - 1, max(4, percorso.count / 2))
        for idx in percorso.prefix(parziale) {
            tocca(ScreenshotPlanner.centro(idx: idx, griglia: g.frame))
        }
        pausa(0.8)
        scatta("02_partita")

        for idx in percorso.dropFirst(parziale) {
            tocca(ScreenshotPlanner.centro(idx: idx, griglia: g.frame))
        }
        // reveal del Sarto (≤ 1,8 s) + 0,75 s, poi il modal risultato
        let link = elemento(ui.linkStatistiche)
        guard link.waitForExistence(timeout: 20) else {
            throw ErroreScreenshot.fase("modal risultato non comparso dopo il percorso")
        }
        pausa(1.6)                                       // stelle animate in stagger
        scatta("03_vittoria")
    }

    /// 04 — statistiche dal menu (funziona anche se il daily è fallito).
    @MainActor
    private func faseStatistiche() throws {
        try tornaAlMenu()
        try tappa(ui.statistiche)
        let titolo = app.staticTexts[ui.statistiche]
        guard titolo.waitForExistence(timeout: 10) else {
            throw ErroreScreenshot.fase("scheda Statistiche non aperta")
        }
        pausa(0.9)
        scatta("04_statistiche")
    }

    /// 05 — Salita: livello 1 risolto, livello 2 con filo in corso.
    @MainActor
    private func faseSalita() throws {
        try tornaAlMenu()
        let card = elemento(ui.cardSalita)
        aspettaToccabile(card, timeout: 10)
        try toccaElemento(card, "card Salita")
        guard elemento(senzaMaiuscole: ui.livello(1)).waitForExistence(timeout: 10) else {
            throw ErroreScreenshot.fase("Salita non aperta")
        }
        pausa(1.3)

        let g1 = try risolviSalita(livello: 1, completo: true)
        log("SALITA L1 risolto: \(g1)")
        guard elemento(senzaMaiuscole: ui.livello(2)).waitForExistence(timeout: 10) else {
            throw ErroreScreenshot.fase("livello 2 non raggiunto")
        }
        pausa(0.8)
        let g2 = try risolviSalita(livello: 2, completo: false)
        log("SALITA L2 parziale: \(g2)")
        aspettaScomparsa(elemento(ui.livelloCompletato), timeout: 5)   // toast via
        pausa(0.6)
        scatta("05_salita")
    }

    /// 06 — Impostazioni (icona ingranaggio della Home) → voce "Archivio FILO".
    @MainActor
    private func faseArchivio() throws {
        try tornaAlMenu()
        try tappa(ui.impostazioni)
        let voce = elemento(contiene: ui.archivio)
        guard voce.waitForExistence(timeout: 10) else {
            throw ErroreScreenshot.fase("voce Archivio non trovata nelle Impostazioni")
        }
        var tentativi = 0
        while !voce.isHittable && tentativi < 4 {
            app.swipeUp()
            tentativi += 1
        }
        try toccaElemento(voce, "voce Archivio")
        guard elemento(prefisso: ui.prefissoRigaArchivio).waitForExistence(timeout: 10) else {
            throw ErroreScreenshot.fase("archivio vuoto o non aperto")
        }
        pausa(0.9)
        scatta("06_archivio")
    }

    /// 07 di ripiego — "Come si gioca" dal pulsante ? del menu.
    @MainActor
    private func faseGuidaDalMenu() throws {
        try tornaAlMenu()
        try tappa(ui.comeSiGioca)
        guard elemento(prefisso: ui.prefissoGioca).waitForExistence(timeout: 10) else {
            throw ErroreScreenshot.fase("guida non aperta dal menu")
        }
        pausa(2.6)
        scatta("07_come_si_gioca")
        // Chiusura con la X ("Chiudi"), non con "Gioca il FILO": resta sul menu.
        _ = tappaSeToccabile(ui.chiudi)
        pausa(0.8)
    }

    // MARK: Navigazione robusta

    /// Riporta al MENU chiudendo qualsiasi cosa sia aperta (onboarding,
    /// schede, Salita, daily). Il menu è riconosciuto dalla card Salita
    /// toccabile (sotto un fullScreenCover non è nell'albero).
    @MainActor
    private func tornaAlMenu() throws {
        let cardSalita = elemento(ui.cardSalita)
        for giro in 0..<10 {
            if cardSalita.exists && cardSalita.isHittable
                && !elemento(ui.chiudi).exists && !elemento(ui.salta).exists {
                pausa(1.3)                                // fine eventuale transizione a tessere
                return
            }
            if tappaSeToccabile(ui.salta) { log("tornaAlMenu[\(giro)]: Salta"); pausa(1.0); continue }
            if tappaSeToccabile(prefisso: ui.prefissoGioca) { log("tornaAlMenu[\(giro)]: Gioca"); pausa(1.0); continue }
            if tappaSeToccabile(ui.chiudi) { log("tornaAlMenu[\(giro)]: Chiudi"); pausa(1.0); continue }
            if tappaSeToccabile(ui.menu) { log("tornaAlMenu[\(giro)]: Menu"); pausa(1.5); continue }
            log("tornaAlMenu[\(giro)]: swipe giù")
            app.swipeDown()
            pausa(1.0)
        }
        // Ripiego definitivo: rilancio dell'app (stato persistente conservato,
        // flag di onboarding dai launch argument) → si riparte dal menu.
        log("tornaAlMenu: nessuna via d'uscita, RILANCIO l'app")
        lancia()
        aspettaToccabile(cardSalita, timeout: 30)
        attendiDalLancio(secondi: 6.5)
        guard cardSalita.exists && cardSalita.isHittable else {
            throw ErroreScreenshot.fase("impossibile tornare al menu (anche dopo il rilancio)")
        }
    }

    /// (Ri)lancia l'app con gli stessi argomenti.
    @MainActor
    private func lancia() {
        lancio = Date()
        app.launch()
    }

    /// Garantisce di essere sul daily (HUD "Somma del giorno") SENZA fogli di
    /// onboarding sopra. Normalmente non c'è nulla da chiudere (flag via launch
    /// argument). Ripiego: UN tentativo con "Gioca il FILO"/"Salta"; se il
    /// foglio resta, si rilancia l'app (i flag ora sono anche salvati) e si
    /// riapre il daily dal menu.
    @MainActor
    private func chiudiOnboarding() throws {
        func dailyLibero() -> Bool {
            elemento(prefisso: ui.prefissoSommaGiorno).exists
                && !elemento(ui.salta).exists
                && !elemento(prefisso: ui.prefissoGioca).exists
                && !elemento(senzaMaiuscole: ui.riscaldamento).exists
        }
        let hud = elemento(prefisso: ui.prefissoSommaGiorno)
        _ = hud.waitForExistence(timeout: 10)
        pausa(1.0)                                       // eventuale scheda differita di 0,4 s
        if dailyLibero() { return }

        log("onboarding inatteso: guida=\(elemento(prefisso: ui.prefissoGioca).exists) riscaldamento=\(elemento(senzaMaiuscole: ui.riscaldamento).exists)")
        scattaDebug("onboarding_inatteso")
        if tappaSeToccabile(prefisso: ui.prefissoGioca) { log("onboarding: tap 'Gioca il FILO'"); pausa(1.5) }
        if tappaSeToccabile(ui.salta) { log("onboarding: tap 'Salta' (una volta)"); pausa(1.5) }
        if dailyLibero() { return }

        log("onboarding ancora presente: RILANCIO l'app e riapro il daily")
        lancia()
        let card = elemento(ui.cardDaily)
        guard card.waitForExistence(timeout: 30) else {
            throw ErroreScreenshot.fase("dopo il rilancio la card del daily non c'è")
        }
        aspettaToccabile(card, timeout: 20)
        attendiDalLancio(secondi: 6.5)
        card.tap()
        _ = hud.waitForExistence(timeout: 10)
        pausa(1.0)
        guard dailyLibero() else {
            throw ErroreScreenshot.fase("onboarding presente anche dopo il rilancio")
        }
    }

    /// Legge e risolve una board della Salita. `completo`: tocca tutto il
    /// percorso (supera il livello); altrimenti si ferma alla penultima casella.
    @MainActor
    private func risolviSalita(livello: Int, completo: Bool) throws -> [Int] {
        let lettura = try leggiSchermo(minimoCelle: 25)
        guard let g = lettura.grigliaPiuAlta, let valori = ScreenshotPlanner.valori(da: g.celle) else {
            throw ErroreScreenshot.fase("board Salita L\(livello) non leggibile")
        }
        let target = ScreenshotPlanner.numero(dopo: ui.prefissoObiettivo, in: lettura.etichette)
            ?? Testi.targetSalita(livello: livello)
        log("SALITA L\(livello) target=\(target) valori:\n\(ScreenshotPlanner.testoGriglia(valori))")
        guard let percorso = ScreenshotPlanner.percorsoMigliore(somma: target, valori: valori, secondi: 3),
              ScreenshotPlanner.vince(percorso, valori: valori, somma: target) else {
            throw ErroreScreenshot.fase("Salita L\(livello): nessun percorso con somma \(target)")
        }
        let da = completo ? percorso : Array(percorso.dropLast())
        for idx in da { tocca(ScreenshotPlanner.centro(idx: idx, griglia: g.frame)) }
        return percorso
    }

    // MARK: Lettura dello schermo

    private struct Griglia {
        let celle: [ScreenshotPlanner.Cella]
        let frame: CGRect
    }

    private struct Lettura {
        let griglie: [Griglia]          // in ordine di albero: l'ULTIMA è la più in alto
        let etichette: [String]
        var grigliaPiuAlta: Griglia? { griglie.last }
    }

    /// UN solo snapshot dell'albero di accessibilità: tutte le etichette e,
    /// per ogni contenitore "Griglia di gioco…", le caselle il cui centro cade
    /// dentro il suo frame. Così due board sovrapposte (es. daily sotto e
    /// "Riscaldamento" sopra) non si mescolano mai.
    @MainActor
    private func leggiSchermo(minimoCelle: Int) throws -> Lettura {
        let scadenza = Date().addingTimeInterval(15)
        var motivo = "nessuna griglia"
        repeat {
            let radice = try app.snapshot()
            var etichette: [String] = []
            var frameGriglie: [CGRect] = []
            var celle: [(ScreenshotPlanner.Cella, CGRect)] = []

            func visita(_ s: XCUIElementSnapshot) {
                if !s.label.isEmpty { etichette.append(s.label) }
                if s.label == ui.etichettaGriglia, s.frame.width > 100, s.frame.height > 100 {
                    frameGriglie.append(s.frame)
                }
                if let c = ScreenshotPlanner.parseCella(s.label, prefisso: ui.prefissoCasella) {
                    celle.append((c, s.frame))
                }
                for figlio in s.children { visita(figlio) }
            }
            visita(radice)

            var griglie: [Griglia] = []
            for f in frameGriglie {
                var viste = Set<Int>()
                var dentro: [ScreenshotPlanner.Cella] = []
                for (c, fr) in celle where f.insetBy(dx: -2, dy: -2).contains(CGPoint(x: fr.midX, y: fr.midY))
                    && !viste.contains(c.indice) {
                    viste.insert(c.indice)
                    dentro.append(c)
                }
                if dentro.count >= minimoCelle { griglie.append(Griglia(celle: dentro, frame: f)) }
            }
            if griglie.isEmpty, frameGriglie.isEmpty, !celle.isEmpty {
                // Il contenitore non espone il frame: unione dei frame delle caselle.
                var viste = Set<Int>()
                var dentro: [ScreenshotPlanner.Cella] = []
                var frames: [CGRect] = []
                for (c, fr) in celle where !viste.contains(c.indice) {
                    viste.insert(c.indice); dentro.append(c); frames.append(fr)
                }
                let unione = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
                if dentro.count >= minimoCelle, unione.width > frames[0].width * 4 {
                    griglie.append(Griglia(celle: dentro, frame: unione))
                }
            }
            if !griglie.isEmpty {
                if griglie.count > 1 { log("ATTENZIONE: \(griglie.count) griglie a schermo, uso la più in alto") }
                return Lettura(griglie: griglie, etichette: etichette)
            }
            motivo = "contenitori griglia: \(frameGriglie.count), caselle: \(celle.count)"
            pausa(0.5)
        } while Date() < scadenza
        throw ErroreScreenshot.fase("griglia non leggibile (\(motivo))")
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
        if let cartella {
            let url = cartella.appendingPathComponent("\(nome).png")
            do {
                try shot.pngRepresentation.write(to: url, options: .atomic)
            } catch {
                log("ERRORE scrittura \(url.path): \(error)")
            }
        }
        if !salvati.contains(nome) { salvati.append(nome) }
        log("📸 \(nome)")
    }

    /// Screenshot di DEBUG al momento di un errore (cartella debug/, allegato
    /// "debug_…": non entra fra gli screenshot App Store).
    @MainActor
    private func scattaDebug(_ fase: String) {
        let shot = XCUIScreen.main.screenshot()
        let allegato = XCTAttachment(screenshot: shot)
        allegato.name = "debug_\(ui.lingua)_\(fase)"
        allegato.lifetime = .keepAlways
        add(allegato)
        if let cartellaDebug {
            let url = cartellaDebug.appendingPathComponent("\(ui.lingua)_\(fase)_\(errori.count).png")
            try? shot.pngRepresentation.write(to: url, options: .atomic)
            log("debug salvato: \(url.path)")
        }
    }

    // MARK: Fase best-effort

    @MainActor
    private func fase(_ nome: String, _ corpo: () throws -> Void) {
        log("▶︎ FASE \(nome)")
        do {
            try corpo()
        } catch {
            errori.append("[\(nome)] \(error)")
            log("✖︎ ERRORE fase \(nome): \(error)")
            scattaDebug(nome)
            log("albero UI (estratto):\n\(String(app.debugDescription.prefix(6000)))")
        }
    }

    private func log(_ s: String) {
        print("[FILO-SHOT] \(s)")
    }

    // MARK: Tocchi e query

    /// Tocco a coordinate schermo (i frame dello snapshot sono in punti,
    /// origine in alto a sinistra: in ritratto coincide con l'app).
    @MainActor
    private func tocca(_ p: CGPoint) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: p.x, dy: p.y))
            .tap()
    }

    @MainActor
    private func toccaElemento(_ e: XCUIElement, _ descrizione: String) throws {
        guard e.exists else { throw ErroreScreenshot.elemento(descrizione) }
        e.tap()
    }

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

    /// Tocca l'ULTIMO elemento toccabile con quell'etichetta (con fogli
    /// sovrapposti quello più in alto arriva per ultimo nell'albero).
    @MainActor
    private func tappa(_ label: String, timeout: TimeInterval = 10) throws {
        let query = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
        guard query.firstMatch.waitForExistence(timeout: timeout) else {
            throw ErroreScreenshot.elemento(label)
        }
        aspettaToccabile(query.firstMatch, timeout: 5)
        if !tappaUltimoToccabile(query) {
            try toccaElemento(query.firstMatch, label)
        }
    }

    @MainActor
    private func tappaSeToccabile(_ label: String) -> Bool {
        tappaUltimoToccabile(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label)))
    }

    @MainActor
    private func tappaSeToccabile(prefisso: String) -> Bool {
        tappaUltimoToccabile(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefisso)))
    }

    @MainActor
    private func tappaUltimoToccabile(_ query: XCUIElementQuery) -> Bool {
        for e in query.allElementsBoundByIndex.reversed() where e.exists && e.isHittable {
            e.tap()
            return true
        }
        return false
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
    case fase(String)
    case elemento(String)

    var description: String {
        switch self {
        case .fase(let m): return m
        case .elemento(let l): return "elemento non trovato: \(l)"
        }
    }
}

// MARK: - Testi dell'app nelle due lingue (da Localizable.xcstrings)

private struct Testi {
    let lingua: String
    private var it: Bool { lingua == "it" }

    var locale: String { it ? "it_IT" : "en_US" }

    /// Launch argument per NSArgumentDomain (chiavi lette da UserDefaults.standard).
    static let argomentiStato: [String] = [
        "-filo.onboarded", "YES",
        "-filo.onboardingProgressivoFatto", "YES",
        "-filo.suoni", "<false/>",
    ]

    // MenuView
    var cardDaily: String { it ? "FILO del giorno, disponibile" : "Daily FILO, available" }
    var cardDailyFatta: String {
        it ? "FILO del giorno, già completato, si rinnova a mezzanotte"
           : "Daily FILO, already completed, renews at midnight"
    }
    var cardSalita: String { it ? "Salita, sempre disponibile" : "Climb, always available" }
    var statistiche: String { it ? "Statistiche" : "Statistics" }
    /// Icona ingranaggio della Home (apre ProfileView, titolo "Impostazioni").
    var impostazioni: String { it ? "Impostazioni" : "Settings" }
    var comeSiGioca: String { it ? "Come si gioca" : "How to play" }

    // RootView / schede
    var menu: String { "Menu" }
    var chiudi: String { it ? "Chiudi" : "Close" }
    var prefissoGioca: String { it ? "Gioca il FILO #" : "Play FILO #" }
    var salta: String { it ? "Salta" : "Skip" }
    var riscaldamento: String { it ? "Riscaldamento" : "Warm-up" }
    /// ResultView: link secondario sotto "Condividi il risultato".
    var linkStatistiche: String { it ? "Vedi le statistiche" : "View statistics" }
    /// HUD del daily: accessibilityLabel "Somma del giorno: T" / "Il Sarto ha usato L caselle…"
    var prefissoSommaGiorno: String { it ? "Somma del giorno: " : "Daily sum: " }
    var prefissoSarto: String { it ? "Il Sarto ha usato " : "The Tailor used " }

    // Griglia (BoardView / PracticeBoardView)
    var etichettaGriglia: String {
        it ? "Griglia di gioco, 5 righe per 5 colonne" : "Game grid, 5 rows by 5 columns"
    }
    var prefissoCasella: String { it ? "Casella riga " : "Cell row " }

    // Salita
    func livello(_ n: Int) -> String { it ? "Livello \(n)" : "Level \(n)" }
    /// Toast di livello superato (SalitaViewModel).
    var livelloCompletato: String { it ? "Livello completato" : "Level complete" }
    var prefissoObiettivo: String { it ? "Obiettivo: " : "Target: " }

    /// Target dei livelli della Salita v2 (SalitaGenerator.parameters:
    /// T(n) = 10 + 6·(n − 1) fino al 16, poi 96…104). Solo ripiego: il
    /// target vero è letto dall'etichetta "Obiettivo: N".
    static func targetSalita(livello n: Int) -> Int {
        let l = max(1, n)
        if l <= 16 { return 10 + 6 * (l - 1) }
        return 96 + 2 * ((l - 14) % 5)
    }

    // Impostazioni / Archivio
    var archivio: String { it ? "Archivio FILO" : "FILO archive" }
    var prefissoRigaArchivio: String { it ? "FILO numero " : "FILO number " }
}
