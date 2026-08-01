import SwiftUI

/// Gancio pubblicità "ads-ready": oggi NON ci sono pubblicità (interruttore
/// `AdsConfig.enabled = false`). L'architettura è predisposta per aggiungerle
/// in futuro senza rifattorizzare la UI: basterà creare un provider concreto
/// (es. AdMobProvider) e accendere l'interruttore.
///
/// NB: attivare le ads comporterà rete, prompt ATT, consenso GDPR e
/// aggiornamento della scheda "Privacy dell'app". Finché è spento, FILO resta
/// a zero rete e senza raccolta dati.
enum AdsConfig {
    /// Interruttore globale. Tenuto a false: nessuna pubblicità nel binario.
    static let enabled = false
}

/// Chi possiede l'acquisto extra non vede mai pubblicità, anche a interruttore
/// acceso in futuro.
protocol AdsProvider {
    var disponibile: Bool { get }
    func banner() -> AnyView
}

/// Implementazione neutra attuale: non mostra nulla.
struct NoAdsProvider: AdsProvider {
    var disponibile: Bool { false }
    func banner() -> AnyView { AnyView(EmptyView()) }
}

/// Slot banner da inserire nella UI. Mostra qualcosa SOLO se le ads sono
/// accese globalmente e l'utente non ha l'acquisto extra. Oggi è sempre vuoto.
struct AdSlot: View {
    let isPro: Bool
    private let provider: AdsProvider = NoAdsProvider()

    var body: some View {
        if AdsConfig.enabled, !isPro, provider.disponibile {
            provider.banner()
        } else {
            EmptyView()
        }
    }
}
