import SwiftUI
import UIKit
import FiloCore

// MARK: - Completamento (persistenza locale)

/// Puzzle d'archivio completati (vinti), per lo stato delle righe.
/// Chiave `filo.archivio.completati` = [Int] di numeri di puzzle. Il FILO
/// del giorno conta come completato se `filo.today` dice "vinta" (lettura
/// sola: lo schema resta di GameViewModel); quando lo si rileva lo si
/// aggiunge alla chiave, così resta "Completato" anche nei giorni dopo.
/// Le partite d'archivio NON toccano statistiche né serie.
enum ArchivioCompletati {
    static let defaultsKey = "filo.archivio.completati"

    /// Sottoinsieme minimo di `GameViewModel.TodayRecord` (schema `filo.today`).
    private struct OggiMinimo: Decodable {
        let numero: Int
        let stato: StatoPartita
    }

    /// Numeri salvati nella chiave d'archivio.
    static func salvati(_ defaults: UserDefaults = .standard) -> Set<Int> {
        Set((defaults.array(forKey: defaultsKey) as? [Int]) ?? [])
    }

    /// Segna un puzzle come completato (idempotente).
    static func segna(_ numero: Int, _ defaults: UserDefaults = .standard) {
        var lista = (defaults.array(forKey: defaultsKey) as? [Int]) ?? []
        guard !lista.contains(numero) else { return }
        lista.append(numero)
        defaults.set(lista, forKey: defaultsKey)
    }

    /// Numero del FILO del giorno salvato in `filo.today`, se vinto.
    static func dailyVinto(_ defaults: UserDefaults = .standard) -> Int? {
        guard let data = defaults.data(forKey: "filo.today"),
              let oggi = try? JSONDecoder().decode(OggiMinimo.self, from: data),
              oggi.stato == .vinta else { return nil }
        return oggi.numero
    }

    /// Tutti i completati: chiave d'archivio + FILO del giorno vinto.
    static func tutti(_ defaults: UserDefaults = .standard) -> Set<Int> {
        var set = salvati(defaults)
        if let n = dailyVinto(defaults), !set.contains(n) {
            segna(n, defaults)
            set.insert(n)
        }
        return set
    }
}

// MARK: - Archivio (REDESIGN_SPEC §6.7)

/// Archivio dei FILO passati. I puzzle sono deterministici dalla data
/// (Generator.daily), quindi l'archivio non richiede alcun backend: ogni
/// giorno dall'EPOCH a ieri è rigiocabile in locale. Le partite d'archivio
/// NON toccano statistiche né serie del gioco quotidiano.
struct ArchiveView: View {
    // Requisito d'ambiente storico (chi presenta l'archivio lo fornisce già).
    @EnvironmentObject private var vm: GameViewModel
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var selezione: GiornoArchivio?
    @State private var giorni: [GiornoArchivio] = []
    @State private var caricato = false
    @State private var completati: Set<Int> = []
    @State private var filtro: Filtro = .tutti

    enum Filtro: Hashable, CaseIterable {
        case tutti, daGiocare, completati

        var titolo: LocalizedStringKey {
            switch self {
            case .tutti: return "Tutti"
            case .daGiocare: return "Da giocare"
            case .completati: return "Completati"
            }
        }
    }

    init() {
        _ = Self.stileSegmenti
    }

    /// Segmented control "tinto" (spec §6.7): segmento scelto su
    /// cellSelected con testo oro, gli altri testo secondario su surface.
    /// UIAppearance: vale per ogni segmented control dell'app (oggi solo questo).
    private static let stileSegmenti: Void = {
        let a = UISegmentedControl.appearance()
        a.selectedSegmentTintColor = UIColor(Theme.cellSelected)
        a.backgroundColor = UIColor(Theme.surface)
        a.setTitleTextAttributes([
            .foregroundColor: UIColor(Theme.filo),
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold)
        ], for: .selected)
        a.setTitleTextAttributes([
            .foregroundColor: UIColor(Theme.textMuted),
            .font: UIFont.systemFont(ofSize: 13, weight: .medium)
        ], for: .normal)
    }()

    var body: some View {
        GeometryReader { geo in
            let margine = FiloMetrics.margin(forWidth: geo.size.width)
            ZStack {
                FiloBackground()
                VStack(spacing: 0) {
                    barra(margine: margine)
                    if !store.featuresUnlocked {
                        paywall(margine: margine)
                    } else if caricato && giorni.isEmpty {
                        vuoto(margine: margine)
                    } else {
                        lista(margine: margine)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationCornerRadius(FiloMetrics.sheetCorner)
        .onAppear(perform: carica)
        .sheet(item: $selezione, onDismiss: aggiornaCompletati) { g in
            ArchivePlayerView(giorno: g)
                .presentationCornerRadius(FiloMetrics.sheetCorner)
        }
    }

    // MARK: Caricamento

    private func carica() {
        if !caricato {
            giorni = Self.giorniPassati(oggi: GameViewModel.oggiParts())
            caricato = true
        }
        aggiornaCompletati()
    }

    /// Completati = vittorie d'archivio + FILO del giorno vinto (`filo.today`).
    private func aggiornaCompletati() {
        completati = ArchivioCompletati.tutti()
    }

    // MARK: Header

    /// Barra 48 pt con la sola chiusura (titolo grande sotto, nel contenuto).
    private func barra(margine: CGFloat) -> some View {
        HStack {
            Spacer()
            FiloIconButton(systemName: "xmark", label: "Chiudi") { dismiss() }
        }
        .frame(height: FiloMetrics.headerHeight)
        .padding(.horizontal, max(0, margine - 10))
        .padding(.top, 4)
    }

    private var intestazione: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Archivio")
                .filoFont(.screenTitle)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ogni FILO resta disponibile.")
                    .filoFont(.body)
                    .foregroundStyle(Theme.textMuted)
                Text("Le partite d'archivio non cambiano la tua serie.")
                    .filoFont(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Lista

    private func lista(margine: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                intestazione
                Picker("Filtro", selection: $filtro) {
                    ForEach(Filtro.allCases, id: \.self) { f in
                        Text(f.titolo).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .tint(Theme.filo)
                .padding(.top, FiloMetrics.sectionGap)

                let gruppi = Self.gruppi(giorni.filter(passaFiltro))
                if gruppi.isEmpty && caricato {
                    vuotoFiltro
                        .padding(.top, FiloMetrics.sectionGapLarge)
                } else {
                    LazyVStack(alignment: .leading, spacing: FiloMetrics.sectionGap) {
                        ForEach(gruppi) { gruppo in
                            VStack(alignment: .leading, spacing: FiloMetrics.relatedGap) {
                                Text(verbatim: gruppo.titolo)
                                    .fontWeight(.semibold)
                                    .filoFont(.body)
                                    .foregroundStyle(Theme.text)
                                    .padding(.bottom, 4)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(gruppo.giorni) { g in
                                    riga(g)
                                }
                            }
                        }
                    }
                    .padding(.top, FiloMetrics.sectionGap)
                }
            }
            .padding(.horizontal, margine)
            .padding(.top, 4)
            .padding(.bottom, FiloMetrics.sectionGapLarge)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func passaFiltro(_ g: GiornoArchivio) -> Bool {
        switch filtro {
        case .tutti: return true
        case .daGiocare: return !completati.contains(g.numero)
        case .completati: return completati.contains(g.numero)
        }
    }

    private func riga(_ g: GiornoArchivio) -> some View {
        let fatto = completati.contains(g.numero)
        return Button {
            FiloHaptics.light()
            selezione = g
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: "#\(g.numero)")
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.filo)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: 44, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    // ROUND2 §12: data SF Pro Medium 15 primario; "Somma · Sarto"
                    // Regular 13 secondario.
                    Text(verbatim: g.etichettaRiga)
                        .fontWeight(.medium)
                        .filoFont(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Somma \(g.somma) · Sarto \(g.lSarto)")
                        .fontWeight(.regular)
                        .filoFont(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                statoRiga(fatto: fatto)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(RigaArchivioStyle())
        // Etichetta invariata (UI test: BEGINSWITH "FILO numero "); lo stato
        // va nel valore.
        .accessibilityLabel(Text("FILO numero \(g.numero), \(g.etichettaData), somma \(g.somma)"))
        .accessibilityValue(Text(fatto ? LocalizedStringKey("Completato") : LocalizedStringKey("Da giocare")))
    }

    @ViewBuilder
    private func statoRiga(fatto: Bool) -> some View {
        if fatto {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .medium))
                Text("Completato")
                    .filoFont(.caption)
            }
            .foregroundStyle(Theme.ok)
            .lineLimit(1)
            .fixedSize()
        } else {
            HStack(spacing: 6) {
                Text("Da giocare")
                    .filoFont(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .lineLimit(1)
            .fixedSize()
        }
    }

    private var vuotoFiltro: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            Text("Non ci sono FILO in questa sezione.")
                .filoFont(.body)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(FiloCardBackground())
    }

    // MARK: Stati vuoti / paywall

    private func vuoto(margine: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            intestazione
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "calendar")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
                Text("Il primo FILO è quello di oggi.\nDa domani ritrovi qui gli scorsi.")
                    .filoFont(.body)
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(.horizontal, margine)
        .padding(.top, 4)
        .frame(maxWidth: 560)
    }

    /// Paywall storico: irraggiungibile finché l'app è gratis
    /// (`AppConfig.everythingFree`), resta per compatibilità.
    private func paywall(margine: CGFloat) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Theme.filo)
                .accessibilityHidden(true)
            Text("Archivio dei FILO passati")
                .filoFont(.cardTitle)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text("Rigioca ogni puzzle uscito finora e sblocca i temi colorati con l'acquisto extra, una volta sola.")
                .filoFont(.body)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
            Button(store.prezzoExtra.map { "Sblocca extra · \($0)" } ?? "Sblocca extra") {
                FiloHaptics.light()
                Task { await store.acquistaExtra() }
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            .disabled(store.inCorso)
            Button("Ripristina acquisti") { Task { await store.ripristina() } }
                .buttonStyle(TertiaryButtonStyle(color: Theme.filo))
            Spacer()
        }
        .padding(.horizontal, margine)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    // MARK: Dati archivio

    struct GiornoArchivio: Identifiable, Equatable {
        let y: Int, m: Int, d: Int
        let numero: Int
        let somma: Int
        let lSarto: Int
        var id: Int { numero }

        var data: Date {
            var comps = DateComponents()
            comps.year = y; comps.month = m; comps.day = d
            return Calendar.current.date(from: comps) ?? Date()
        }

        /// Data completa localizzata (etichetta d'accessibilità).
        var etichettaData: String {
            data.formatted(.dateTime.day().month(.wide).year())
        }

        /// Data della riga (il mese è già nel titolo del gruppo): giorno
        /// della settimana + giorno + mese, iniziale maiuscola.
        var etichettaRiga: String {
            FormatoArchivio.iniziale(data.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        }
    }

    struct GruppoMese: Identifiable {
        let id: Int          // y * 100 + m
        let titolo: String
        var giorni: [GiornoArchivio]
    }

    /// Raggruppa per mese mantenendo l'ordine (dal più recente).
    static func gruppi(_ giorni: [GiornoArchivio]) -> [GruppoMese] {
        var out: [GruppoMese] = []
        for g in giorni {
            let chiave = g.y * 100 + g.m
            if let ultimo = out.indices.last, out[ultimo].id == chiave {
                out[ultimo].giorni.append(g)
            } else {
                out.append(GruppoMese(id: chiave,
                                      titolo: FormatoArchivio.mese(g.data),
                                      giorni: [g]))
            }
        }
        return out
    }

    /// Tutti i giorni dall'EPOCH fino a ieri, dal più recente. Limite prudente
    /// per non generare all'infinito (l'archivio cresce di un giorno al giorno).
    static func giorniPassati(oggi: (y: Int, m: Int, d: Int)) -> [GiornoArchivio] {
        let oggiN = FiloDate.puzzleNumber(y: oggi.y, m: oggi.m, d: oggi.d)
        guard oggiN > 1 else { return [] }
        var out: [GiornoArchivio] = []
        var cur = FiloDate.previousDay(y: oggi.y, m: oggi.m, d: oggi.d)
        var n = oggiN - 1
        let massimo = 400
        while n >= 1 && out.count < massimo {
            let daily = Generator.daily(y: cur.y, m: cur.m, d: cur.d)
            out.append(GiornoArchivio(y: cur.y, m: cur.m, d: cur.d, numero: daily.numero,
                                      somma: daily.puzzle.T, lSarto: daily.puzzle.lSarto))
            cur = FiloDate.previousDay(y: cur.y, m: cur.m, d: cur.d)
            n -= 1
        }
        return out
    }
}

/// Formattazione delle date d'archivio (fuori da ArchiveView: niente
/// isolamento @MainActor ereditato, usabile anche da GiornoArchivio).
private enum FormatoArchivio {
    /// "LLLL yyyy" localizzato (ordine dei campi secondo la lingua).
    private static let formatoMese: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return f
    }()

    /// Titolo del gruppo mensile, es. "Ottobre 2026".
    static func mese(_ data: Date) -> String {
        iniziale(formatoMese.string(from: data))
    }

    /// Iniziale maiuscola secondo la lingua corrente.
    static func iniziale(_ s: String) -> String {
        guard let primo = s.first else { return s }
        return String(primo).uppercased(with: Locale.current) + s.dropFirst()
    }
}

/// Riga d'archivio (ROUND2 §12): fondo surface che passa a surfaceRaised
/// quando premuta (0,12 s), bordo 1 pt come le card. Niente scale.
private struct RigaArchivioStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                FiloCardBackground(radius: 16,
                                   fill: configuration.isPressed ? Theme.surfaceRaised : Theme.surface)
            )
            .animation(FiloMotion.press, value: configuration.isPressed)
    }
}

// MARK: - Sessione d'archivio

/// Sessione di gioco d'archivio: un GameEngine isolato, senza statistiche
/// né serie. Riusa la logica pura di FiloCore (nessuna deviazione di regole).
/// Unica persistenza: alla vittoria il numero va in `filo.archivio.completati`.
@MainActor
final class ArchiveSession: ObservableObject {
    let puzzle: Puzzle
    let numero: Int
    @Published private(set) var engine: GameEngine
    @Published private(set) var revealSarto = false
    /// Filo appena perso (spezzato/annodato/tagliato), per la resa d'uscita.
    @Published private(set) var esitoVisuale: EsitoVisuale?
    /// Breve bordo error sulla mossa non valida via tap.
    @Published private(set) var casellaNonValida: Int?

    struct EsitoVisuale: Equatable {
        let id: Int
        let percorso: [Int]
        let esito: EsitoFilo
    }

    private var contatoreEsiti = 0

    init(giorno g: ArchiveView.GiornoArchivio) {
        let daily = Generator.daily(y: g.y, m: g.m, d: g.d)
        puzzle = daily.puzzle
        numero = daily.numero
        engine = GameEngine(puzzle: daily.puzzle)
    }

    /// viaTap = tap/VoiceOver (feedback sulla mossa non valida); drag = silenzioso.
    func gioca(_ idx: Int, viaTap: Bool) {
        guard !engine.gameOver else { return }
        let prima = engine.filo
        let mossa = engine.gioca(idx)
        switch mossa {
        case .iniziato, .esteso:
            SoundManager.shared.plin(passo: engine.filo.count)
        case .vittoria:
            SoundManager.shared.plin(passo: engine.filo.count)
            FiloHaptics.success()
            ArchivioCompletati.segna(numero)
            revealSarto = true
        case .spezzato, .annodato:
            let esito: EsitoFilo = mossa == .spezzato ? .spezzato : .annodato
            if esito == .spezzato { FiloHaptics.error() } else { FiloHaptics.warning() }
            mostraEsito(percorso: prima + [idx], esito: esito)
            if engine.stato == .persa { revealSarto = true }
        case .giaUsata, .nonAdiacente:
            if viaTap { segnalaNonValida(idx) }
        case .ignorata:
            break
        }
    }

    /// Tocco sull'ultima casella senza estensione: "già usata".
    func tapSuUltima(_ idx: Int) {
        guard !engine.gameOver else { return }
        segnalaNonValida(idx)
    }

    func strappa() {
        guard !engine.filo.isEmpty, !engine.gameOver else { return }
        let percorso = engine.filo
        _ = engine.strappa()
        FiloHaptics.medium()
        mostraEsito(percorso: percorso, esito: .strappato)
        if engine.stato == .persa { revealSarto = true }
    }

    func ricomincia() {
        engine = GameEngine(puzzle: puzzle)
        revealSarto = false
        esitoVisuale = nil
        casellaNonValida = nil
    }

    var stelle: Int {
        guard engine.stato == .vinta else { return 0 }
        let c = engine.percorsoVincente?.count ?? 0
        return Punteggio.stelle(caselle: c, lSarto: puzzle.lSarto).stelle
    }

    /// Esito finale (stessa voce del risultato quotidiano, senza emoji né
    /// punti esclamativi).
    var esitoTesto: String {
        switch engine.stato {
        case .vinta:
            let c = engine.percorsoVincente?.count ?? 0
            if c > puzzle.lSarto { return String(localized: "Hai superato il Sarto") }
            if c == puzzle.lSarto { return String(localized: "Hai eguagliato il Sarto") }
            return String(localized: "Filo completato")
        case .persa: return String(localized: "Il Sarto la spunta — riprova")
        case .inCorso: return ""
        }
    }

    /// Etichetta VoiceOver della casella (stesse chiavi del gioco quotidiano).
    func etichettaCasella(_ idx: Int) -> String {
        let r = idx / 5 + 1, c = idx % 5 + 1
        var lbl = String(localized: "Casella riga \(r) colonna \(c), valore \(puzzle.valori[idx])")
        if let pos = engine.filo.firstIndex(of: idx) {
            if pos == engine.filo.count - 1 { lbl += String(localized: ", ultima del filo") }
            else { lbl += String(localized: ", nel filo, posizione \(pos + 1)") }
        }
        if engine.gameOver && puzzle.percorsoSarto.contains(idx) {
            lbl += String(localized: ", percorso del Sarto")
        }
        return lbl
    }

    private func mostraEsito(percorso: [Int], esito: EsitoFilo) {
        contatoreEsiti += 1
        let nuovo = EsitoVisuale(id: contatoreEsiti, percorso: percorso, esito: esito)
        esitoVisuale = nuovo
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if self?.esitoVisuale == nuovo { self?.esitoVisuale = nil }
        }
    }

    private func segnalaNonValida(_ idx: Int) {
        casellaNonValida = idx
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if self?.casellaNonValida == idx { self?.casellaNonValida = nil }
        }
    }
}

// MARK: - Player d'archivio

/// Player d'archivio: stessa resa del gioco quotidiano (header, HUD,
/// board 2.0), senza statistiche né serie.
struct ArchivePlayerView: View {
    @StateObject private var s: ArchiveSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(giorno: ArchiveView.GiornoArchivio) {
        _s = StateObject(wrappedValue: ArchiveSession(giorno: giorno))
    }

    var body: some View {
        GeometryReader { geo in
            let margine = FiloMetrics.margin(forWidth: geo.size.width)
            ZStack {
                FiloBackground()
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, max(0, margine - 10))
                    Spacer(minLength: 8)
                    hud
                    Spacer(minLength: 16)
                    ArchiveBoard(session: s)
                        .padding(.horizontal, margine)
                    Spacer(minLength: 16)
                    azioni
                        .padding(.horizontal, margine)
                        .frame(maxWidth: 480)
                    Spacer(minLength: 16)
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Header 48 pt

    private var header: some View {
        ZStack {
            Text("FILO #\(s.numero)")
                .filoFont(.headerTitle)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer()
                FiloIconButton(systemName: "xmark", label: "Chiudi") { dismiss() }
            }
        }
        .frame(height: FiloMetrics.headerHeight)
    }

    // MARK: HUD (ordine: obiettivo → Sarto → somma/caselle → fili rimasti)

    private var hud: some View {
        VStack(spacing: 6) {
            VStack(spacing: 2) {
                Text("Obiettivo")
                    .eyebrowStyle()
                Text(verbatim: "\(s.puzzle.T)")
                    .filoFont(.target)
                    .monospacedDigit()
                    .foregroundStyle(Theme.gold)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Obiettivo: \(s.puzzle.T)"))

            Text("Sarto: \(s.puzzle.lSarto) caselle")
                .filoFont(.caption)
                .foregroundStyle(Theme.textMuted)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Somma attuale")
                    .filoFont(.caption)
                    .foregroundStyle(Theme.textTertiary)
                Text(verbatim: "\(s.engine.somma)")
                    .filoFont(.currentSum)
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : FiloMotion.numeric, value: s.engine.somma)
                Text(verbatim: "/ \(s.puzzle.T)")
                    .filoFont(.body)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.top, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Somma attuale"))
            .accessibilityValue(Text(verbatim: "\(s.engine.somma) / \(s.puzzle.T)"))

            Text("\(s.engine.filo.count) caselle")
                .filoFont(.caption)
                .foregroundStyle(Theme.textMuted)

            ThreadsLeftIndicator(outcomes: s.engine.fili.map(\.esito),
                                 remaining: s.engine.filiRimasti)
                .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: Azioni / esito

    @ViewBuilder
    private var azioni: some View {
        if s.engine.gameOver {
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    if s.engine.stato == .vinta {
                        StarRow(earned: s.stelle, size: 24, spacing: 8)
                    }
                    Text(s.esitoTesto)
                        .filoFont(.cardTitle)
                        .foregroundStyle(s.engine.stato == .vinta ? Theme.gold : Theme.text)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)
                Button("Rigioca") {
                    FiloHaptics.light()
                    withAnimation(FiloMotion.adaptive(FiloMotion.screen, reduceMotion: reduceMotion)) {
                        s.ricomincia()
                    }
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            }
            .transition(.opacity)
        } else {
            HStack(spacing: 12) {
                Button("Rigioca") {
                    s.ricomincia()
                }
                .buttonStyle(SecondaryButtonStyle(enabled: !s.engine.fili.isEmpty || !s.engine.filo.isEmpty,
                                                  fullWidth: true))
                .disabled(s.engine.fili.isEmpty && s.engine.filo.isEmpty)
                Button("Taglia il filo") { s.strappa() }
                    .buttonStyle(DestructiveButtonStyle(enabled: !s.engine.filo.isEmpty, fullWidth: true))
                    .disabled(s.engine.filo.isEmpty)
            }
        }
    }
}

// MARK: - Board d'archivio

/// Board per il player d'archivio (REDESIGN_SPEC §5): tessere → filo →
/// numeri con maschera. Input tap + drag con la stessa semantica di
/// BoardView, ma disaccoppiata dal GameViewModel quotidiano. Haptics:
/// selezione (throttled) a ogni casella nuova; gli esiti li emette la
/// sessione.
private struct ArchiveBoard: View {
    @ObservedObject var session: ArchiveSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var trimFilo: CGFloat = 1
    @State private var sartoTrim: CGFloat = 0
    @State private var dragAttivo = false
    @State private var downSuUltima = false
    @State private var caselleAlDown = 0
    @State private var popIdx: Int?
    @State private var popScale: CGFloat = 1
    @State private var endScale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let side = BoardMetrics.side(forWidth: geo.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(0..<25, id: \.self) { idx in
                    let o = BoardMetrics.origin(idx, side: side)
                    ArchiveCellView(session: session, idx: idx, side: side)
                        .frame(width: side, height: side)
                        .scaleEffect(popIdx == idx ? popScale : 1)
                        .offset(x: o.x, y: o.y)
                }
                BoardThreadLayer(side: side,
                                 filo: session.engine.filo,
                                 trim: trimFilo,
                                 sarto: session.revealSarto ? session.puzzle.percorsoSarto : [],
                                 sartoTrim: sartoTrim,
                                 endScale: endScale,
                                 esitoPercorso: session.esitoVisuale?.percorso,
                                 esito: session.esitoVisuale?.esito)
                    .id(session.esitoVisuale?.id ?? 0)
                // numeri SOPRA il filo (layer inerte)
                BoardNumberLayer(side: side, valori: session.puzzle.valori,
                                 filo: session.engine.filo,
                                 popIdx: popIdx, popScale: popScale)
            }
            .frame(width: geo.size.width, height: geo.size.width, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(dragGesture(side: side))
        }
        .frame(maxWidth: BoardMetrics.maxWidth, maxHeight: BoardMetrics.maxWidth)
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: session.engine.filo.count) { vecchio, nuovo in
            casellaAggiunta(vecchio: vecchio, nuovo: nuovo)
        }
        .onChange(of: session.engine.stato) { _, stato in
            if stato == .vinta { assesta() }
        }
        .onChange(of: session.revealSarto) { _, attivo in
            aggiornaSarto(attivo: attivo, animato: true)
        }
        .onAppear {
            aggiornaSarto(attivo: session.revealSarto, animato: false)
            FiloHaptics.prepare()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Griglia di gioco, 5 righe per 5 colonne")
    }

    /// Nuova casella: segmento cucito in 0,12 s, selezione (throttled),
    /// prima casella con scale 0,97 → 1.
    private func casellaAggiunta(vecchio: Int, nuovo: Int) {
        guard nuovo > vecchio else { trimFilo = 1; return }
        if session.engine.stato == .inCorso { FiloHaptics.selection() }
        if nuovo == 1, let primo = session.engine.filo.first, !reduceMotion {
            popIdx = primo
            popScale = 0.97
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 16_000_000)
                withAnimation(FiloMotion.tile) { popScale = 1 }
            }
        }
        guard nuovo >= 2, !reduceMotion else { trimFilo = 1; return }
        trimFilo = CGFloat(nuovo - 2) / CGFloat(nuovo - 1)
        withAnimation(FiloMotion.segment) { trimFilo = 1 }
    }

    /// Somma esatta: il nodo finale si assesta 1 → 1,08 → 1.
    private func assesta() {
        guard !reduceMotion else { return }
        withAnimation(FiloMotion.settle) { endScale = 1.08 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            withAnimation(FiloMotion.settle) { endScale = 1 }
        }
    }

    private func aggiornaSarto(attivo: Bool, animato: Bool) {
        guard attivo else { sartoTrim = 0; return }
        if reduceMotion || !animato {
            sartoTrim = 1
        } else {
            sartoTrim = 0
            withAnimation(.easeInOut(duration: 1.2)) { sartoTrim = 1 }
        }
    }

    private func dragGesture(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in
                guard !session.engine.gameOver,
                      let idx = BoardMetrics.cell(at: g.location, side: side) else { return }
                if !dragAttivo {
                    dragAttivo = true
                    caselleAlDown = session.engine.filo.count
                    // down sull'ultima casella = possibile ripresa del drag
                    downSuUltima = (session.engine.filo.last == idx)
                    if !downSuUltima { session.gioca(idx, viaTap: true) }
                } else {
                    // fuori griglia o mossa non valida: silenzioso, il filo resta
                    session.gioca(idx, viaTap: false)
                }
            }
            .onEnded { g in
                if dragAttivo, downSuUltima,
                   session.engine.filo.count == caselleAlDown,
                   !session.engine.gameOver,
                   let idx = BoardMetrics.cell(at: g.location, side: side),
                   idx == session.engine.filo.last {
                    session.tapSuUltima(idx)
                }
                dragAttivo = false
                downSuUltima = false
            }
    }
}

/// Casella della board d'archivio (layer di fondo): tessera piatta, breve
/// bordo error sulla mossa non valida, tocchi e accessibilità (stesse
/// etichette del gioco quotidiano).
private struct ArchiveCellView: View {
    @ObservedObject var session: ArchiveSession
    let idx: Int
    let side: CGFloat

    var body: some View {
        let inFilo = session.engine.filo.contains(idx)
        let nonValida = session.casellaNonValida == idx

        ZStack {
            TesseraArte(accesa: inFilo, lato: side)
            if nonValida {
                RoundedRectangle(cornerRadius: Arte.raggio(side), style: .continuous)
                    .strokeBorder(Theme.spezzato, lineWidth: 1.5)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: inFilo)
        .animation(.easeOut(duration: 0.12), value: nonValida)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.etichettaCasella(idx))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            session.gioca(idx, viaTap: true)
        }
    }
}
