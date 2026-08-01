import SwiftUI
import Combine
import Accessibility
import UIKit
import FiloCore

/// Stato dell'app: incapsula GameEngine (FiloCore, logica pura) e aggiunge
/// persistenza UserDefaults (schema equivalente a README §11.2), sequenze
/// animate degli esiti, cambio giorno e testi normativi NEURO_SPEC.
@MainActor
final class GameViewModel: ObservableObject {

    // MARK: Tipi

    enum Scheda: String, Identifiable {
        case comeSiGioca, risultato, statistiche, profilo
        var id: String { rawValue }
    }

    struct EsitoVisuale: Equatable {
        let percorso: [Int]
        let esito: EsitoFilo
    }

    /// Schema `filo.today` (equivalente a §11.2 web).
    struct TodayRecord: Codable {
        var data: String
        var numero: Int
        var stato: StatoPartita
        var fili: [FiloConcluso]
        var stelle: Int
        var sartoBattuto: Bool
        var percorsoVincente: [Int]?
    }

    // MARK: Stato pubblicato

    @Published private(set) var puzzle: Puzzle
    @Published private(set) var numero: Int
    @Published private(set) var dataOggi: String
    @Published private(set) var engine: GameEngine
    @Published private(set) var stats: Statistiche
    @Published private(set) var stelleOggi = 0
    @Published private(set) var sartoBattutoOggi = false

    @Published var scheda: Scheda?
    @Published var showStrappoDialog = false
    @Published private(set) var lockInput = false
    @Published private(set) var revealSarto = false
    @Published private(set) var esitoVisuale: EsitoVisuale?
    @Published private(set) var toast: String?
    @Published private(set) var showNuovoGiornoBanner = false
    @Published private(set) var shakes: [Int: Int] = [:]
    @Published private(set) var shakeTick = 0          // trigger sensoryFeedback
    @Published private(set) var casellaNonValida: Int? // flash bordo (reduce motion)

    private var bannerDismissedFor: String?
    private var risultatoMostrato = false
    private var toastTask: Task<Void, Never>?

    private let defaults = UserDefaults.standard

    // MARK: Init / bootstrap

    init() {
        let o = Self.oggiParts()
        let daily = Generator.daily(y: o.y, m: o.m, d: o.d)
        puzzle = daily.puzzle
        numero = daily.numero
        dataOggi = FiloDate.dateString(y: o.y, m: o.m, d: o.d)
        engine = GameEngine(puzzle: daily.puzzle)
        stats = Self.loadStats(from: UserDefaults.standard)
        ripristinaGiornata()
        if !defaults.bool(forKey: "filo.onboarded") {
            scheda = .comeSiGioca
        } else if engine.gameOver {
            revealSarto = true
            risultatoMostrato = true
            scheda = .risultato        // RF9: giorno concluso → risultato
        }
    }

    /// Carica (o ricarica) il puzzle del giorno corrente.
    func bootGiorno() {
        let o = Self.oggiParts()
        let daily = Generator.daily(y: o.y, m: o.m, d: o.d)
        puzzle = daily.puzzle
        numero = daily.numero
        dataOggi = FiloDate.dateString(y: o.y, m: o.m, d: o.d)
        engine = GameEngine(puzzle: daily.puzzle)
        stelleOggi = 0
        sartoBattutoOggi = false
        revealSarto = false
        esitoVisuale = nil
        lockInput = false
        risultatoMostrato = false
        showNuovoGiornoBanner = false
        scheda = nil
        ripristinaGiornata()
        if engine.gameOver {
            revealSarto = true
            risultatoMostrato = true
            scheda = .risultato
        }
    }

    /// Flusso E: fili conclusi ripristinati, filo a metà perso senza penalità.
    private func ripristinaGiornata() {
        guard let today = loadToday(), today.data == dataOggi else { return }
        engine.ripristina(fili: today.fili, stato: today.stato,
                          percorsoVincente: today.percorsoVincente)
        stelleOggi = today.stelle
        sartoBattutoOggi = today.sartoBattuto
        if today.stato == .inCorso && engine.stato == .persa {
            // reload avvenuto dopo il terzo filo ma prima della valutazione finale
            let o = Self.oggiParts()
            stats.registra(vinta: false, filiUsati: 3, caselle: 0, gold: false, oggi: o)
            salvaStats()
            salvaOggi()
        }
    }

    // MARK: Data locale

    static func oggiParts(_ date: Date = Date()) -> (y: Int, m: Int, d: Int) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    // MARK: Persistenza (UserDefaults, schema §11.2)

    private static func loadStats(from defaults: UserDefaults) -> Statistiche {
        guard let data = defaults.data(forKey: "filo.stats"),
              let s = try? JSONDecoder().decode(Statistiche.self, from: data)
        else { return Statistiche() }
        return s
    }

    private func salvaStats() {
        if let data = try? JSONEncoder().encode(stats) {
            defaults.set(data, forKey: "filo.stats")
        }
    }

    private func loadToday() -> TodayRecord? {
        guard let data = defaults.data(forKey: "filo.today") else { return nil }
        return try? JSONDecoder().decode(TodayRecord.self, from: data)
    }

    /// Scrittura DOPO ogni filo concluso e a fine partita (mai a metà filo, §6.6).
    private func salvaOggi() {
        let record = TodayRecord(data: dataOggi, numero: numero, stato: engine.stato,
                                 fili: engine.fili, stelle: stelleOggi,
                                 sartoBattuto: sartoBattutoOggi,
                                 percorsoVincente: engine.percorsoVincente)
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: "filo.today")
        }
    }

    func segnaOnboarded() {
        defaults.set(true, forKey: "filo.onboarded")
    }

    // MARK: Derivati

    var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    var durataReveal: Double {
        min(1.8, 0.09 * Double(max(1, puzzle.percorsoSarto.count - 1)))
    }

    var streakEffettiva: Int {
        stats.streakEffettiva(oggi: Self.oggiParts())
    }

    /// Testo di condivisione — unica fonte: ShareText di FiloCore (§9.1).
    /// Include la riga URL finale, come CONFIG.SHARE_URL sul web: anteprima
    /// e testo condiviso coincidono carattere per carattere su ogni piattaforma.
    var shareText: String {
        ShareText.build(numero: numero, vinta: engine.stato == .vinta,
                        fili: engine.fili, T: puzzle.T, stelle: stelleOggi,
                        sartoBattuto: sartoBattutoOggi, streak: streakEffettiva,
                        url: ShareText.shareURL)
    }

    var strappaDisponibile: Bool {
        !engine.filo.isEmpty && !engine.gameOver && !lockInput
    }

    /// Corpo del dialog strappo (NEURO_SPEC §2.3, plurale normativo).
    var testoDialogStrappo: String {
        let n = engine.filiRimasti - 1
        if n == 0 { return "È l'ultimo filo: strapparlo chiude la partita di oggi." }
        if n == 1 { return "Un filo strappato non si ricuce: te ne resterà 1." }
        return "Un filo strappato non si ricuce: te ne resteranno \(n)."
    }

    /// aria-label equivalente per VoiceOver (UX_SPEC §9.4).
    func etichettaCasella(_ idx: Int) -> String {
        let r = idx / 5 + 1, c = idx % 5 + 1
        var lbl = "Casella riga \(r) colonna \(c), valore \(puzzle.valori[idx])"
        if let pos = engine.filo.firstIndex(of: idx) {
            if pos == engine.filo.count - 1 { lbl += ", ultima del filo" }
            else { lbl += ", nel filo, posizione \(pos + 1)" }
        }
        if engine.gameOver && puzzle.percorsoSarto.contains(idx) {
            lbl += ", percorso del Sarto"
        }
        return lbl
    }

    // MARK: Input di gioco

    /// viaTap = tap/VoiceOver (feedback su mossa non valida); drag = silenzioso (§6.6).
    func gioca(_ idx: Int, viaTap: Bool) {
        guard !lockInput, !engine.gameOver else { return }
        let filoPrima = engine.filo
        let mossa = engine.gioca(idx)
        switch mossa {
        case .iniziato:
            annuncia("Filo iniziato. Somma \(engine.somma) su \(puzzle.T).")
        case .esteso:
            annuncia("Più \(puzzle.valori[idx]). Somma \(engine.somma) su \(puzzle.T), \(engine.filo.count) caselle.")
        case .vittoria:
            gestisciVittoria()
        case .spezzato:
            gestisciFiloPerso(.spezzato, percorso: filoPrima + [idx])
        case .annodato:
            gestisciFiloPerso(.annodato, percorso: filoPrima + [idx])
        case .giaUsata:
            if viaTap {
                shake(idx)
                annuncia("Mossa non valida: casella già usata in questo filo.")
            }
        case .nonAdiacente:
            if viaTap {
                shake(idx)
                annuncia("Mossa non valida: la casella non è adiacente all'ultima.")
            }
        case .ignorata:
            break
        }
    }

    /// Tap secco sull'ultima casella del filo (senza estensione): shake (§6.6).
    func tapSuUltima(_ idx: Int) {
        guard !lockInput, !engine.gameOver else { return }
        shake(idx)
        annuncia("Mossa non valida: casella già usata in questo filo.")
    }

    func richiediStrappo() {
        guard strappaDisponibile else { return }
        showStrappoDialog = true
    }

    func confermaStrappo() {
        guard strappaDisponibile else { return }
        let percorso = engine.filo
        if engine.strappa() {
            gestisciFiloPerso(.strappato, percorso: percorso)
        }
    }

    private func shake(_ idx: Int) {
        shakes[idx, default: 0] += 1
        shakeTick += 1
        casellaNonValida = idx
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if casellaNonValida == idx { casellaNonValida = nil }
        }
    }

    // MARK: Esiti (sequenze animate + haptics UINotificationFeedbackGenerator)

    private func gestisciVittoria() {
        lockInput = true
        let C = engine.percorsoVincente?.count ?? 0
        let res = Punteggio.stelle(caselle: C, lSarto: puzzle.lSarto)
        stelleOggi = res.stelle
        sartoBattutoOggi = res.gold
        let o = Self.oggiParts()
        stats.registra(vinta: true, filiUsati: engine.fili.count, caselle: C,
                       gold: res.gold, oggi: o)
        salvaStats()
        salvaOggi()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let parole = res.gold ? "Tre stelle, hai battuto il Sarto!"
            : (res.stelle == 3 ? "Tre stelle" : res.stelle == 2 ? "Due stelle" : "Una stella")
        annuncia("Vittoria! Somma esatta \(puzzle.T) con \(C) caselle. \(parole).")
        revealPoiRisultato()
    }

    private func gestisciFiloPerso(_ esito: EsitoFilo, percorso: [Int]) {
        lockInput = true
        guard let concluso = engine.fili.last else { return }
        esitoVisuale = EsitoVisuale(percorso: percorso, esito: esito)
        if esito == .strappato {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        salvaOggi()
        let n = engine.filiRimasti
        switch esito {
        case .spezzato:
            annuncia("Filo spezzato: somma \(concluso.somma), superiore a \(puzzle.T). Fili rimasti: \(n).")
        case .annodato:
            annuncia("Filo annodato: nessuna casella libera adiacente. Fili rimasti: \(n).")
        default:
            annuncia("Filo strappato. Fili rimasti: \(n).")
        }
        let durata: Double = reduceMotion ? 0.24
            : (esito == .spezzato ? 0.7 : esito == .annodato ? 0.6 : 0.35)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(durata * 1_000_000_000))
            esitoVisuale = nil
            if engine.stato == .persa {
                gestisciSconfitta()
            } else {
                lockInput = false
                mostraToast(testoToastEsito(esito, somma: concluso.somma, n: n))
            }
        }
    }

    private func gestisciSconfitta() {
        let o = Self.oggiParts()
        stats.registra(vinta: false, filiUsati: 3, caselle: 0, gold: false, oggi: o)
        salvaStats()
        salvaOggi()
        annuncia("Fili finiti. Il percorso del Sarto viene rivelato.")
        revealPoiRisultato()
    }

    /// Reveal del Sarto poi modal risultato (UX_SPEC §7.5: delay 350ms, poi +400ms).
    private func revealPoiRisultato() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            revealSarto = true
            let attesa = (reduceMotion ? 0.0 : durataReveal) + 0.4
            try? await Task.sleep(nanoseconds: UInt64(attesa * 1_000_000_000))
            lockInput = false
            risultatoMostrato = true
            scheda = .risultato
        }
    }

    /// Testi toast esito (NEURO_SPEC §2.3, plurale normativo).
    func testoToastEsito(_ esito: EsitoFilo, somma: Int, n: Int) -> String {
        let resto = (n == 1) ? "Te ne resta 1." : "Te ne restano \(n)."
        switch esito {
        case .spezzato: return "💥 Crack! \(somma) su \(puzzle.T): il filo non ha retto. \(resto)"
        case .annodato: return "🪢 Vicolo cieco a \(somma) su \(puzzle.T). \(resto)"
        default: return "✂️ Strappo netto. \(resto)"
        }
    }

    // MARK: Toast e annunci

    func mostraToast(_ testo: String) {
        toastTask?.cancel()
        toast = testo
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    /// Annuncio VoiceOver (AccessibilityNotification, iOS 17).
    private func annuncia(_ testo: String) {
        AccessibilityNotification.Announcement(testo).post()
    }

    // MARK: Cambio giorno (RF10: scenePhase active + timer 30s)

    func checkNuovoGiorno() {
        let o = Self.oggiParts()
        let oggiStr = FiloDate.dateString(y: o.y, m: o.m, d: o.d)
        if oggiStr != dataOggi && bannerDismissedFor != oggiStr {
            showNuovoGiornoBanner = true
        }
    }

    func giocaNuovoGiorno() {
        showNuovoGiornoBanner = false
        bootGiorno()
    }

    func nascondiBanner() {
        let o = Self.oggiParts()
        bannerDismissedFor = FiloDate.dateString(y: o.y, m: o.m, d: o.d)
        showNuovoGiornoBanner = false
    }

    // MARK: Chiusura schede

    /// Chiamata alla chiusura del tutorial: vale come visto anche con swipe (RF7).
    func onboardingChiuso() {
        segnaOnboarded()
        if engine.gameOver && !risultatoMostrato {
            revealSarto = true
            risultatoMostrato = true
            scheda = .risultato
        }
    }
}
