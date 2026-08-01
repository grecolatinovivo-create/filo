import Foundation

/// Interruttori globali del prodotto.
enum AppConfig {
    /// FASE 0 (audit): l'app è COMPLETAMENTE GRATIS. Tutti gli extra (temi,
    /// archivio) sono sbloccati per tutti, nessun acquisto. La monetizzazione
    /// (ads) arriverà in una fase futura, senza rifattorizzare la UI.
    static let everythingFree = true

    /// Login "Accedi con Apple": richiede firma di distribuzione con entitlement
    /// (certificato .p12 gestito a mano). Tenuto SPENTO finché non è pronta la
    /// firma manuale, così la CI usa la firma cloud all'export come le altre app
    /// e non ci sono error 1000 a runtime. L'app è gratis: il login è opzionale.
    static let appleSignInEnabled = false
}
