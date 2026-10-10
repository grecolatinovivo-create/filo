import SwiftUI
import AuthenticationServices

/// IMPOSTAZIONI (REDESIGN_SPEC §6.10), locale. L'app è gratis: tutti gli
/// extra sono sbloccati. Qui vivono: nota "gratis" (o accesso con Apple ID,
/// se abilitato), suoni e vibrazione, archivio, info e — per l'admin/tester —
/// gli strumenti di test.
struct ProfileView: View {
    @EnvironmentObject private var vm: GameViewModel
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var account: Account
    @Environment(\.dismiss) private var dismiss

    @State private var mostraArchivio = false
    // Stesso storage letto da SoundManager ("filo.suoni"): il toggle è immediato.
    @AppStorage(SoundManager.defaultsKey) private var suoniAttivi = true
    // Stesso storage letto da FiloHaptics ("filo.haptics", default attivo).
    @AppStorage(FiloHaptics.defaultsKey) private var vibrazioneAttiva = true
    // "Tempo nella Salita" ("normale" | "esteso" | "libero"). Nessun valore
    // salvato = mai scelto: vale il default (Libero con VoiceOver attivo).
    @AppStorage(SalitaTempo.defaultsKey) private var salitaTempoSalvato: String?

    private var salitaTempo: Binding<SalitaTempo> {
        Binding(
            get: { SalitaTempo.leggi(salitaTempoSalvato) },
            set: { salitaTempoSalvato = $0.rawValue }
        )
    }

    private var mostraStrumentiAdmin: Bool { store.isSandbox || account.isAdmin }

    var body: some View {
        GeometryReader { geo in
            let margine = FiloMetrics.margin(forWidth: geo.size.width)
            ZStack {
                FiloBackground()
                VStack(spacing: 0) {
                    barra(margine: margine)
                    ScrollView {
                        VStack(alignment: .leading, spacing: FiloMetrics.relatedGapLarge) {
                            Text("Impostazioni")
                                .filoFont(.screenTitle)
                                .foregroundStyle(Theme.text)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.bottom, FiloMetrics.relatedGap)
                            if AppConfig.appleSignInEnabled { accessoSezione } else { gratisSezione }
                            if mostraStrumentiAdmin { testerSezione }
                            preferenzeSezione
                            archivioSezione
                            infoSezione
                                .padding(.top, FiloMetrics.relatedGap)
                        }
                        .padding(.horizontal, margine)
                        .padding(.top, 4)
                        .padding(.bottom, FiloMetrics.sectionGapLarge)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationCornerRadius(FiloMetrics.sheetCorner)
        .sheet(isPresented: $mostraArchivio) { ArchiveView() }
        .onChange(of: vibrazioneAttiva) { _, attiva in
            // conferma tattile quando la vibrazione viene riattivata
            if attiva { FiloHaptics.light() }
        }
        .alert("Accesso Apple", isPresented: Binding(
            get: { account.errore != nil },
            set: { if !$0 { account.errore = nil } })) {
            Button("OK", role: .cancel) { account.errore = nil }
        } message: {
            Text(account.errore ?? "")
        }
    }

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

    // MARK: Card "app gratis" (login Apple in pausa) — nessun pulsante di accesso

    private var gratisSezione: some View {
        FiloCard {
            HStack(spacing: 14) {
                icona("gift")
                VStack(alignment: .leading, spacing: 4) {
                    Text("FILO è gratis")
                        .filoFont(.cardTitle)
                        .foregroundStyle(Theme.text)
                    Text("Tutti gli extra sono sbloccati, nessun acquisto.")
                        .filoFont(.caption)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Accesso (Apple ID, opzionale) — app gratis

    private var accessoSezione: some View {
        FiloCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    icona(account.isAdmin ? "crown" : "person.crop.circle")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(titoloAccesso)
                            .filoFont(.cardTitle)
                            .foregroundStyle(Theme.text)
                        Text(sottotitoloAccesso)
                            .filoFont(.caption)
                            .foregroundStyle(Theme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                if account.isLoggedIn {
                    if account.isAdmin {
                        Text("Admin — tutto sbloccato")
                            .filoFont(.caption)
                            .foregroundStyle(Theme.filo)
                    }
                    // ID mostrato per poter abilitare l'admin in futuro.
                    Text("ID: \(account.userID ?? "")")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textMuted)
                        .textSelection(.enabled)
                        .lineLimit(1).truncationMode(.middle)
                    Button("Esci") { account.esci() }
                        .buttonStyle(TertiaryButtonStyle(color: Theme.filo))
                } else {
                    Button {
                        account.accedi()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                            Text("Accedi con Apple").filoFont(.button)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: FiloMetrics.secondaryHeight)
                        .background(.white, in: RoundedRectangle(cornerRadius: FiloMetrics.buttonRadius,
                                                                 style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(account.inCorso)
                    Text("Facoltativo: gioca anche senza accedere.")
                        .filoFont(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private var titoloAccesso: String {
        if let n = account.nome, !n.isEmpty { return String(localized: "Ciao, \(n)") }
        return account.isLoggedIn ? String(localized: "Accesso effettuato") : String(localized: "FILO è gratis")
    }

    private var sottotitoloAccesso: String {
        account.isLoggedIn
            ? String(localized: "Tutti gli extra sono sbloccati.")
            : String(localized: "Tutti gli extra sono sbloccati, nessun acquisto.")
    }

    // MARK: Strumenti admin/tester (funzioni invariate)

    private var testerSezione: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $store.testerUnlock) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Strumenti admin/tester")
                        .fontWeight(.semibold)
                        .filoFont(.body)
                        .foregroundStyle(Theme.text)
                    Text("Forza lo sblocco di tutto (utile per provare).")
                        .filoFont(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .tint(Theme.filo)

            HStack(spacing: 10) {
                Button {
                    vm.testerAzzera(); dismiss()
                } label: {
                    Label("Azzera filo", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                Button {
                    vm.testerNuoviNumeri(); dismiss()
                } label: {
                    Label("Nuovi numeri", systemImage: "dice")
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            }
            Text("«Nuovi numeri» carica una griglia casuale di prova (non è il FILO del giorno).")
                .filoFont(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(FiloMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: FiloMetrics.cardRadius, style: .continuous)
            shape.fill(Theme.surface)
                .overlay(shape.strokeBorder(Theme.filo.opacity(0.4), lineWidth: 1))
        }
    }

    // MARK: Suoni e vibrazione

    private var preferenzeSezione: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $suoniAttivi) {
                voce(titolo: "Suoni", sottotitolo: "Un suono discreto per ogni casella.")
            }
            .tint(Theme.filo)
            .padding(.vertical, 14)

            Rectangle()
                .fill(Theme.border.opacity(0.6))
                .frame(height: 1)
                .accessibilityHidden(true)

            Toggle(isOn: $vibrazioneAttiva) {
                voce(titolo: "Vibrazione", sottotitolo: "Feedback tattile durante il gioco.")
            }
            .tint(Theme.filo)
            .padding(.vertical, 14)

            Rectangle()
                .fill(Theme.border.opacity(0.6))
                .frame(height: 1)
                .accessibilityHidden(true)

            // Tempo nella Salita (SALITA_TIMER_SPEC §1): Normale / Esteso / Libero.
            VStack(alignment: .leading, spacing: 12) {
                voce(titolo: "Tempo nella Salita",
                     sottotitolo: "Il tempo esteso raddoppia i secondi. Libero toglie il timer, ma ogni filo spezzato o annodato costa una vita. Il record è separato.")
                    .accessibilityHidden(true)   // detto dal selettore qui sotto
                Picker("Tempo nella Salita", selection: salitaTempo) {
                    ForEach(SalitaTempo.allCases) { modo in
                        Text(modo.titolo).tag(modo)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityHint(Text("Il tempo esteso raddoppia i secondi. Libero toglie il timer, ma ogni filo spezzato o annodato costa una vita. Il record è separato."))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
        }
        .padding(.horizontal, FiloMetrics.cardPadding)
        .frame(maxWidth: .infinity)
        .background(FiloCardBackground())
    }

    private func voce(titolo: LocalizedStringKey, sottotitolo: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titolo)
                .fontWeight(.semibold)
                .filoFont(.body)
                .foregroundStyle(Theme.text)
            Text(sottotitolo)
                .filoFont(.caption)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Archivio (etichetta combinata: contiene "Archivio FILO" — UI test)

    private var archivioSezione: some View {
        Button {
            FiloHaptics.light()
            mostraArchivio = true
        } label: {
            HStack(spacing: 14) {
                icona("square.grid.2x2")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Archivio FILO")
                        .fontWeight(.semibold)
                        .filoFont(.body)
                        .foregroundStyle(Theme.text)
                    Text("Rigioca i puzzle passati")
                        .filoFont(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(FiloMetrics.cardPadding)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(FiloCardBackground())
            .contentShape(RoundedRectangle(cornerRadius: FiloMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(RigaImpostazioniStyle())
    }

    // MARK: Info

    private var infoSezione: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FILO — il puzzle quotidiano")
                .filoFont(.caption)
                .foregroundStyle(Theme.textMuted)
            Text("Nessun tracciamento, gioca offline.")
                .filoFont(.caption)
                .foregroundStyle(Theme.textTertiary)
            Link(destination: URL(string: "https://filo-game-liard.vercel.app")!) {
                HStack(spacing: 4) {
                    Text("Gioca sul web")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .filoFont(.caption)
                .foregroundStyle(Theme.filo)
                .frame(minHeight: FiloMetrics.minTouch)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Helper

    /// Icona SF Symbol della voce (decorativa), 20 pt medium in 32×32.
    private func icona(_ nome: String) -> some View {
        Image(systemName: nome)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Theme.filo)
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }
}

/// Pressione di una riga delle impostazioni: leggera attenuazione.
private struct RigaImpostazioniStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(FiloMotion.press, value: configuration.isPressed)
    }
}
