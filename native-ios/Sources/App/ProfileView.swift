import SwiftUI

/// PROFILO / IMPOSTAZIONI (locale, senza login). Stato dell'acquisto extra,
/// scelta del tema, accesso all'archivio, ripristino acquisti. È qui che vive
/// la monetizzazione: un unico acquisto sblocca temi + archivio (e, in futuro,
/// toglierà eventuali pubblicità).
struct ProfileView: View {
    @EnvironmentObject private var vm: GameViewModel
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var mostraArchivio = false

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    statoAccount
                    if store.isSandbox { testerSezione }
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
        .alert("FILO", isPresented: Binding(
            get: { store.messaggio != nil },
            set: { if !$0 { store.messaggio = nil } })) {
            Button("OK", role: .cancel) { store.messaggio = nil }
        } message: {
            Text(store.messaggio ?? "")
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

    // MARK: Stato account / acquisto

    private var statoAccount: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(store.isPro ? "🧵✨" : "🧵").font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isPro ? "Extra sbloccati" : "FILO free")
                        .font(.headline).foregroundStyle(Theme.text)
                    Text(store.isPro
                         ? "Grazie! Temi e archivio sono tuoi."
                         : "Un acquisto unico sblocca temi e archivio.")
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
                Spacer()
            }
            if !store.isPro {
                Button(store.prezzoExtra.map { "Sblocca extra · \($0)" } ?? "Sblocca extra") {
                    Task { await store.acquistaExtra() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(store.inCorso)
            }
            Button("Ripristina acquisti") { Task { await store.ripristina() } }
                .font(.subheadline)
                .foregroundStyle(Theme.filo)
                .frame(minHeight: 44)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border, lineWidth: 1))
    }

    // MARK: Modalità tester (solo TestFlight/sandbox)

    private var testerSezione: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $store.testerUnlock) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modalità tester").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                    Text("Sblocca tutti gli extra senza acquisto (solo in test).")
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
            }
            .tint(Theme.filo)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.filo.opacity(0.4), lineWidth: 1))
    }

    // MARK: Temi

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
        let bloccato = t.premium && !store.isPro
        let selezionato = theme.id == t
        let p = t.palette
        return Button {
            if bloccato { Task { await store.acquistaExtra() } }
            else { theme.seleziona(t, sbloccato: store.isPro) }
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
        .accessibilityLabel("\(t.nome)\(bloccato ? ", bloccato" : selezionato ? ", selezionato" : "")")
    }

    // MARK: Archivio

    private var archivioSezione: some View {
        Button { mostraArchivio = true } label: {
            HStack(spacing: 12) {
                Text("🗂️").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Archivio FILO").font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(store.isPro ? "Rigioca i puzzle passati" : "Extra — sbloccalo per rigiocare")
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Image(systemName: store.isPro ? "chevron.right" : "lock.fill")
                    .foregroundStyle(Theme.textMuted)
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
            Text("Nessun account, nessun tracciamento, gioca offline.")
                .font(.caption).foregroundStyle(Theme.textMuted)
            Link("Gioca sul web", destination: URL(string: "https://filo-game-liard.vercel.app")!)
                .font(.caption).foregroundStyle(Theme.filo)
        }
        .padding(.top, 4)
    }
}
