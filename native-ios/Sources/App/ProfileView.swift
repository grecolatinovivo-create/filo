import SwiftUI
import AuthenticationServices

/// PROFILO / IMPOSTAZIONI (locale). L'app è gratis: tutti gli extra sono
/// sbloccati. Qui vivono: accesso con Apple ID (opzionale), scelta del tema,
/// archivio, e — per l'admin/tester — gli strumenti di test.
struct ProfileView: View {
    @EnvironmentObject private var vm: GameViewModel
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var account: Account
    @Environment(\.dismiss) private var dismiss

    @State private var mostraArchivio = false

    private var mostraStrumentiAdmin: Bool { store.isSandbox || account.isAdmin }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if AppConfig.appleSignInEnabled { accessoSezione } else { gratisSezione }
                    if mostraStrumentiAdmin { testerSezione }
                    temiSezione
                    archivioSezione
                    infoSezione
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $mostraArchivio) { ArchiveView() }
        .alert("Accesso Apple", isPresented: Binding(
            get: { account.errore != nil },
            set: { if !$0 { account.errore = nil } })) {
            Button("OK", role: .cancel) { account.errore = nil }
        } message: {
            Text(account.errore ?? "")
        }
    }

    private var header: some View {
        HStack {
            Text("Profilo")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Chiudi")
        }
    }

    // MARK: Card "app gratis" (login Apple in pausa) — nessun pulsante di accesso

    private var gratisSezione: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("🧵").font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FILO è gratis")
                        .font(.headline).foregroundStyle(Theme.text)
                    Text("Tutti gli extra sono sbloccati, nessun acquisto.")
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 1))
    }

    // MARK: Accesso (Apple ID, opzionale) — app gratis

    private var accessoSezione: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(account.isAdmin ? "🧵👑" : "🧵").font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titoloAccesso)
                        .font(.headline).foregroundStyle(Theme.text)
                    Text(sottotitoloAccesso)
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
                Spacer()
            }

            if account.isLoggedIn {
                if account.isAdmin {
                    Text("Admin — tutto sbloccato")
                        .font(.caption.weight(.bold)).foregroundStyle(Theme.filo)
                }
                // ID mostrato per poter abilitare l'admin in futuro.
                Text("ID: \(account.userID ?? "")")
                    .font(.caption2.monospaced()).foregroundStyle(Theme.textMuted)
                    .textSelection(.enabled)
                    .lineLimit(1).truncationMode(.middle)
                Button("Esci") { account.esci() }
                    .font(.subheadline).foregroundStyle(Theme.filo)
                    .frame(minHeight: 44)
            } else {
                Button {
                    account.accedi()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.logo")
                        Text("Accedi con Apple").font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(account.inCorso)
                Text("Facoltativo: gioca anche senza accedere.")
                    .font(.caption2).foregroundStyle(Theme.textMuted)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 1))
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

    // MARK: Strumenti admin/tester

    private var testerSezione: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $store.testerUnlock) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Strumenti admin/tester").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                    Text("Forza lo sblocco di tutto (utile per provare).")
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
            }
            .tint(Theme.filo)

            HStack(spacing: 10) {
                Button {
                    vm.testerAzzera(); dismiss()
                } label: {
                    Label("Azzera filo", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.text)
                }
                Button {
                    vm.testerNuoviNumeri(); dismiss()
                } label: {
                    Label("Nuovi numeri", systemImage: "dice")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.text)
                }
            }
            .buttonStyle(.plain)
            Text("«Nuovi numeri» carica una griglia casuale di prova (non è il FILO del giorno).")
                .font(.caption2).foregroundStyle(Theme.textMuted)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.filo.opacity(0.4), lineWidth: 1))
    }

    // MARK: Temi (tutti sbloccati)

    private var temiSezione: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tema").captionStyle()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                ForEach(ThemeID.allCases) { t in
                    temaChip(t)
                }
            }
        }
    }

    private func temaChip(_ t: ThemeID) -> some View {
        let bloccato = t.premium && !store.featuresUnlocked
        let selezionato = theme.id == t
        let p = t.palette
        return Button {
            if bloccato { return }
            theme.seleziona(t, sbloccato: store.featuresUnlocked)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [p.bg, p.bg2],
                                             startPoint: .top, endPoint: .bottom))
                    Capsule().fill(LinearGradient(colors: [p.filoHover, p.filo],
                                                  startPoint: .leading, endPoint: .trailing))
                        .frame(width: 44, height: 10)
                    if bloccato {
                        Image(systemName: "lock.fill")
                            .font(.caption).foregroundStyle(.white.opacity(0.9))
                            .padding(6)
                            .background(.black.opacity(0.35), in: Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(6)
                    }
                }
                .frame(height: 54)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selezionato ? Theme.filo : Theme.border,
                                  lineWidth: selezionato ? 2 : 1))
                Text(t.nome)
                    .font(.caption.weight(selezionato ? .bold : .regular))
                    .foregroundStyle(selezionato ? Theme.text : Theme.textMuted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selezionato ? String(localized: "\(t.nome), selezionato") : t.nome)
    }

    // MARK: Archivio

    private var archivioSezione: some View {
        Button { mostraArchivio = true } label: {
            HStack(spacing: 12) {
                Text("🗂️").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Archivio FILO").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                    Text("Rigioca i puzzle passati").font(.caption).foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.textMuted)
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Info

    private var infoSezione: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FILO — il puzzle quotidiano")
                .font(.caption).foregroundStyle(Theme.textMuted)
            Text("Nessun tracciamento, gioca offline.")
                .font(.caption).foregroundStyle(Theme.textMuted)
            Link("Gioca sul web", destination: URL(string: "https://filo-game-liard.vercel.app")!)
                .font(.caption).foregroundStyle(Theme.filo)
        }
        .padding(.top, 4)
    }
}
