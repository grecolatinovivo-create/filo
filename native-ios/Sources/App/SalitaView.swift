import SwiftUI
import Combine
import FiloCore

/// MODALITÀ SALITA — livelli progressivi, separata dal daily.
/// Target crescenti (10, 25, 50, 100, poi +100 a livello), 3 vite. Ogni livello
/// è un puzzle di `PracticeGenerator`. Non tocca statistiche né persistenza del
/// gioco giornaliero; salva solo il record `filo.salitaBest`.
/// Haptics d'esito (REDESIGN_SPEC §8): livello superato = success, vita persa
/// = warning. Li emette QUESTO view model: la board va creata con
/// `outcomeHaptics: false` per non duplicarli.
@MainActor
final class SalitaViewModel: ObservableObject {
    @Published private(set) var livello = 1
    @Published private(set) var vite = 3
    @Published private(set) var session: PracticeSession
    @Published private(set) var gameOver = false
    @Published private(set) var best: Int
    @Published private(set) var nuovoRecord = false
    @Published private(set) var toast: String?
    /// Livello appena completato (l'obiettivo vira al colore success prima
    /// del cambio livello). `nil` fuori dalla celebrazione.
    @Published private(set) var livelloCompletato: Int?

    private let defaults = UserDefaults.standard
    private static let bestKey = "filo.salitaBest"
    private var semeBase: UInt64
    private var bestIniziale: Int
    private var toastTask: Task<Void, Never>?
    // La `session` è un ObservableObject annidato: inoltriamo i suoi cambi (somma,
    // filo…) così anche l'HUD che legge `vm.session` si ridisegna a ogni mossa.
    private var sessionCancellable: AnyCancellable?

    init() {
        let b = UserDefaults.standard.integer(forKey: Self.bestKey)
        best = b
        bestIniziale = b
        let seme = UInt64.random(in: 1...UInt64(UInt32.max))
        semeBase = seme
        session = PracticeSession(puzzle:
            PracticeGenerator.make(target: Self.target(perLivello: 1), seed: seme &+ 1))
        osserva(session)
    }

    private func osserva(_ s: PracticeSession) {
        sessionCancellable = s.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Target del livello: 1→10, 2→25, 3→50, 4→100, poi +100 (5→200, 6→300, …).
    static func target(perLivello n: Int) -> Int {
        switch n {
        case ..<2:  return 10
        case 2:     return 25
        case 3:     return 50
        case 4:     return 100
        default:    return 100 + (n - 4) * 100
        }
    }

    var target: Int { Self.target(perLivello: livello) }

    /// L'obiettivo mostrato è in fase di celebrazione (colore success).
    var celebra: Bool { livelloCompletato == livello }

    func gestisci(_ mossa: Mossa) {
        guard !gameOver else { return }
        switch mossa {
        case .vittoria: superaLivello()
        case .spezzato, .annodato: perdiVita()
        default: break
        }
    }

    /// "Ricomincia il filo": azzera il filo corrente, nessuna vita persa.
    func ripulisci() {
        guard !gameOver else { return }
        session.ripulisci()
    }

    /// "Ricomincia la Salita": dal livello 1 con 3 vite.
    func riprova() {
        livello = 1
        vite = 3
        gameOver = false
        nuovoRecord = false
        livelloCompletato = nil
        bestIniziale = best
        semeBase = UInt64.random(in: 1...UInt64(UInt32.max))
        nuovaSessione()
    }

    // MARK: Interno

    private func superaLivello() {
        session.blocca()
        livelloCompletato = livello
        FiloHaptics.success()
        mostraToast(String(localized: "Livello completato"))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !gameOver else { return }
            livello += 1
            if livello > best {
                best = livello
                defaults.set(best, forKey: Self.bestKey)
            }
            nuovaSessione()
        }
    }

    private func perdiVita() {
        vite -= 1
        FiloHaptics.warning()
        if vite <= 0 {
            vite = 0
            finePartita()
        } else {
            session.blocca()
            mostraToast(String(localized: "Hai perso una vita."))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !gameOver else { return }
                session.ripulisci()
                session.sblocca()
            }
        }
    }

    private func finePartita() {
        gameOver = true
        nuovoRecord = livello > bestIniziale
        toastTask?.cancel()
        toast = nil
        session.blocca()
        session.mostraSoluzione()
    }

    private func nuovaSessione() {
        session = PracticeSession(puzzle:
            PracticeGenerator.make(target: target, seed: semeBase &+ UInt64(livello)))
        osserva(session)
    }

    private func mostraToast(_ t: String) {
        toastTask?.cancel()
        toast = t
        AccessibilityNotification.Announcement(t).post()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }
}

struct SalitaView: View {
    @StateObject private var vm = SalitaViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mostraRegole = false

    /// Ritorno al menu orchestrato dal presentatore (transizione a tessere).
    /// Se assente, chiusura standard con dismiss.
    var onClose: (() -> Void)? = nil

    private func chiudi() {
        if let onClose { onClose() } else { dismiss() }
    }

    var body: some View {
        GeometryReader { geo in
            let margine = FiloMetrics.margin(forWidth: geo.size.width)
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, max(0, margine - 12))
                ZStack {
                    ScrollView {
                        VStack(spacing: FiloMetrics.sectionGap) {
                            hud
                            board
                            Button("Ricomincia il filo") {
                                FiloHaptics.light()
                                vm.ripulisci()
                            }
                            .buttonStyle(SecondaryButtonStyle(enabled: !vm.gameOver))
                            .disabled(vm.gameOver)
                        }
                        .padding(.horizontal, margine)
                        .padding(.top, FiloMetrics.relatedGap)
                        .padding(.bottom, FiloMetrics.sectionGapLarge)
                        .frame(maxWidth: 480)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)

                    if vm.gameOver {
                        gameOverOverlay
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: reduceMotion ? FiloMotion.reducedDuration : 0.25),
                           value: vm.gameOver)
            }
        }
        .background { FiloBackground() }
        .overlay(alignment: .bottom) {
            ZStack {
                if let toast = vm.toast, !vm.gameOver {
                    ToastView(testo: toast)
                }
            }
            .animation(FiloMotion.adaptive(FiloMotion.screen, reduceMotion: reduceMotion), value: vm.toast)
        }
        .sheet(isPresented: $mostraRegole) {
            RegoleSalitaView()
        }
        .onAppear { FiloHaptics.prepare() }
        .preferredColorScheme(.dark)
    }

    // MARK: Header (48 pt): chiudi · "Salita" · regole

    private var header: some View {
        ZStack {
            Text("Salita")
                .filoFont(.headerTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack {
                FiloIconButton(systemName: "xmark", label: "Chiudi") { chiudi() }
                Spacer()
                FiloIconButton(systemName: "questionmark.circle", label: "Come si gioca") {
                    mostraRegole = true
                }
            }
        }
        .frame(height: FiloMetrics.headerHeight)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    // MARK: HUD

    private var transizioneLivello: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .offset(y: 12).combined(with: .opacity),
            removal: .offset(y: -12).combined(with: .opacity))
    }

    private var hud: some View {
        VStack(spacing: FiloMetrics.relatedGap) {
            Text("Livello \(vm.livello)")
                .eyebrowStyle()
                .contentTransition(.numericText())
                .animation(FiloMotion.adaptive(FiloMotion.level, reduceMotion: reduceMotion),
                           value: vm.livello)

            // Obiettivo: vira a success (0,25 s) quando il livello è
            // completato, poi il vecchio numero sale di 12 pt e svanisce
            // mentre il nuovo entra da +12 pt (0,30 s easeInOut).
            ZStack {
                Text(verbatim: "\(vm.target)")
                    .filoFont(.target)
                    .monospacedDigit()
                    .foregroundStyle(vm.celebra ? Theme.success : Theme.gold)
                    .animation(.easeOut(duration: 0.25), value: vm.celebra)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel(Text("Obiettivo: \(vm.target)"))
                    .id(vm.livello)
                    .transition(transizioneLivello)
            }
            .animation(FiloMotion.adaptive(FiloMotion.level, reduceMotion: reduceMotion), value: vm.livello)

            sommaAttuale

            HStack(spacing: FiloMetrics.relatedGap) {
                LivesIndicator(lives: vm.vite)
                Group {
                    if vm.vite == 1 {
                        Text("Ultima vita")
                            .foregroundStyle(Theme.error)
                    } else {
                        Text("\(vm.vite) vite")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .filoFont(.caption)
                .accessibilityHidden(true)   // già detto da "Vite rimaste: n di 3"
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var sommaAttuale: some View {
        HStack(alignment: .firstTextBaseline, spacing: FiloMetrics.relatedGap) {
            Text("Somma attuale")
                .filoFont(.caption)
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: "\(vm.session.somma)")
                    .filoFont(.currentSum)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : FiloMotion.numeric, value: vm.session.somma)
                Text(verbatim: "/ \(vm.target)")
                    .filoFont(.body)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Somma attuale: \(vm.session.somma) di \(vm.target)"))
    }

    // MARK: Board (crossfade 0,22 s al cambio livello)

    private var board: some View {
        ZStack {
            PracticeBoardView(session: vm.session, onMove: vm.gestisci, outcomeHaptics: false)
                .id(vm.livello)
                .transition(.opacity)
        }
        .frame(maxWidth: BoardMetrics.maxWidth)
        .animation(.easeInOut(duration: reduceMotion ? FiloMotion.reducedDuration : 0.22), value: vm.livello)
    }

    // MARK: Fine partita

    private var gameOverOverlay: some View {
        ZStack {
            Theme.overlay
                .ignoresSafeArea(edges: .bottom)
                .accessibilityHidden(true)
            FiloCard(padding: FiloMetrics.cardPaddingLarge, floating: true, alignment: .center) {
                VStack(spacing: FiloMetrics.relatedGapLarge) {
                    VStack(spacing: FiloMetrics.relatedGap) {
                        Text("La salita finisce qui.")
                            .filoFont(.screenTitle)
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text("Hai raggiunto il livello \(vm.livello).")
                            .filoFont(.body)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    if vm.nuovoRecord {
                        Chip("Nuovo record", systemImage: "arrow.up", tint: Theme.success, filled: true)
                    } else {
                        Text("Record: livello \(vm.best)")
                            .filoFont(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    VStack(spacing: FiloMetrics.relatedGap) {
                        Button("Ricomincia la Salita") {
                            FiloHaptics.light()
                            vm.riprova()
                        }
                        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                        Button("Torna alla Home") { chiudi() }
                            .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                    }
                    .padding(.top, FiloMetrics.relatedGap)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, FiloMetrics.sectionGap)
        }
    }
}

/// Regole aperte dal "?" della Salita: stessa guida di "Come si gioca", con
/// una nota sulle vite e senza la CTA del daily (non richiede GameViewModel,
/// che la Salita non riceve nell'environment).
struct RegoleSalitaView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ComeSiGiocaContenuto(
            nota: "Nella Salita ogni livello alza la somma. Hai tre vite: ogni filo spezzato o annodato ne costa una.",
            onChiudi: { dismiss() }
        )
    }
}
