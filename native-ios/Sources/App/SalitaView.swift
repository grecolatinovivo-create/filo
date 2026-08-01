import SwiftUI
import Combine
import FiloCore

/// MODALITÀ SALITA — livelli progressivi, separata dal daily.
/// Target crescenti (10, 25, 50, 100, poi +100 a livello), 3 vite. Ogni livello
/// è un puzzle di `PracticeGenerator`. Non tocca statistiche né persistenza del
/// gioco giornaliero; salva solo il record `filo.salitaBest`.
@MainActor
final class SalitaViewModel: ObservableObject {
    @Published private(set) var livello = 1
    @Published private(set) var vite = 3
    @Published private(set) var session: PracticeSession
    @Published private(set) var gameOver = false
    @Published private(set) var best: Int
    @Published private(set) var nuovoRecord = false
    @Published private(set) var toast: String?

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

    func gestisci(_ mossa: Mossa) {
        guard !gameOver else { return }
        switch mossa {
        case .vittoria: superaLivello()
        case .spezzato, .annodato: perdiVita()
        default: break
        }
    }

    func ripulisci() {
        guard !gameOver else { return }
        session.ripulisci()
    }

    func riprova() {
        livello = 1
        vite = 3
        gameOver = false
        nuovoRecord = false
        bestIniziale = best
        semeBase = UInt64.random(in: 1...UInt64(UInt32.max))
        nuovaSessione()
    }

    // MARK: Interno

    private func superaLivello() {
        session.blocca()
        mostraToast(String(localized: "Livello superato!"))
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
        if vite <= 0 {
            vite = 0
            finePartita()
        } else {
            session.blocca()
            mostraToast(String(localized: "Filo perso: una vita in meno."))
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
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }
}

struct SalitaView: View {
    @StateObject private var vm = SalitaViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bgGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 16) {
                        hud
                        PracticeBoardView(session: vm.session, onMove: vm.gestisci)
                            .id(vm.livello)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: 420)
                        Button("Ripulisci il filo") { vm.ripulisci() }
                            .buttonStyle(SecondaryButtonStyle(enabled: !vm.gameOver))
                            .disabled(vm.gameOver)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 32)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            if vm.gameOver { gameOverOverlay }
        }
        .overlay(alignment: .bottom) {
            if let toast = vm.toast, !vm.gameOver { ToastView(testo: toast) }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Chiudi")

            Spacer()
            Text("Salita")
                .font(.title2.weight(.heavy))
                .kerning(6)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .frame(maxWidth: 480)
    }

    // MARK: HUD

    private var hud: some View {
        VStack(spacing: 4) {
            Text("Livello \(vm.livello)")
                .captionStyle()
            Text("\(vm.target)")
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Theme.filoGradient)
                .accessibilityLabel("Obiettivo: \(vm.target)")

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                HStack(spacing: 4) {
                    Text("Somma").captionStyle()
                    Text("\(vm.session.somma)")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                }
                viteView
            }
            .padding(.top, 8)
        }
        .padding(.top, 8)
    }

    private var viteView: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < vm.vite ? "heart.fill" : "heart")
                    .font(.subheadline)
                    .foregroundStyle(i < vm.vite ? Theme.spezzato : Theme.textMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vite rimaste: \(vm.vite) di 3")
    }

    // MARK: Game over

    private var gameOverOverlay: some View {
        ZStack {
            Theme.overlay.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Game over")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Theme.text)
                Text("Sei arrivato al livello \(vm.livello)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.filo)
                    .multilineTextAlignment(.center)
                if vm.nuovoRecord {
                    Text("Nuovo record!")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.ok)
                } else {
                    Text("Record: livello \(vm.best)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                }
                Button("Riprova") { vm.riprova() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
                Button("Chiudi") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(28)
            .frame(maxWidth: 360)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.border, lineWidth: 1))
            .padding(24)
        }
        .transition(.opacity)
    }
}
