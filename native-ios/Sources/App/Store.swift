import Foundation
import StoreKit

/// Gestione acquisti (StoreKit 2). Un solo prodotto non-consumabile:
/// "Sblocca extra" — rimuove ogni futura pubblicità e apre i temi e l'archivio
/// dei FILO passati. Nessun backend: il diritto è verificato dalle transazioni
/// firmate da Apple e ripristinabile con "Ripristina acquisti".
@MainActor
final class Store: ObservableObject {

    /// Identificatore del prodotto — DEVE combaciare con quello creato su
    /// App Store Connect (In-App Purchases → Non-consumabile).
    static let extraID = "com.grecolatinovivo.filo.extra"

    @Published private(set) var extra: Product?
    @Published private(set) var isPro = false
    @Published private(set) var inCorso = false
    @Published var messaggio: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        // Ascolta le transazioni in arrivo (acquisti su altri dispositivi,
        // ripristini automatici, ecc.) per l'intera vita dell'app.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.gestisci(verifica: update)
            }
        }
        Task { await bootstrap() }
    }

    /// Carica il prodotto e lo stato dei diritti all'avvio.
    func bootstrap() async {
        await caricaProdotti()
        await aggiornaDiritti()
    }

    func caricaProdotti() async {
        do {
            let prodotti = try await Product.products(for: [Self.extraID])
            extra = prodotti.first
        } catch {
            // Nessuna connessione o prodotto non ancora attivo su ASC:
            // l'app resta pienamente funzionante, solo senza acquisto.
            extra = nil
        }
    }

    /// Prezzo localizzato pronto per la UI (o nil se il prodotto non c'è).
    var prezzoExtra: String? { extra?.displayPrice }

    /// Avvia l'acquisto del pacchetto extra.
    func acquistaExtra() async {
        guard let extra else {
            messaggio = "Acquisto non disponibile al momento. Riprova più tardi."
            return
        }
        inCorso = true
        defer { inCorso = false }
        do {
            let esito = try await extra.purchase()
            switch esito {
            case .success(let verifica):
                await gestisci(verifica: verifica)
                messaggio = "Extra sbloccati. Grazie per il sostegno!"
            case .userCancelled:
                break
            case .pending:
                messaggio = "Acquisto in attesa di approvazione."
            @unknown default:
                break
            }
        } catch {
            messaggio = "Acquisto non riuscito. Riprova."
        }
    }

    /// Ripristina un acquisto già effettuato (nuovo dispositivo / reinstallo).
    func ripristina() async {
        inCorso = true
        defer { inCorso = false }
        try? await AppStore.sync()
        await aggiornaDiritti()
        messaggio = isPro ? "Acquisto ripristinato." : "Nessun acquisto da ripristinare."
    }

    /// Ricalcola i diritti dai diritti correnti firmati da Apple.
    func aggiornaDiritti() async {
        var pro = false
        for await risultato in Transaction.currentEntitlements {
            if case .verified(let t) = risultato, t.productID == Self.extraID,
               t.revocationDate == nil {
                pro = true
            }
        }
        isPro = pro
    }

    private func gestisci(verifica risultato: VerificationResult<Transaction>) async {
        guard case .verified(let t) = risultato else { return }
        if t.productID == Self.extraID, t.revocationDate == nil {
            isPro = true
        }
        await t.finish()
    }
}
