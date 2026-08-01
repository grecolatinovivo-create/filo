import SwiftUI
import AuthenticationServices

/// Accesso con Apple ID (opzionale). L'app è giocabile senza login — l'accesso
/// serve come "sistema di accesso" per il futuro e per riconoscere l'admin.
/// Nessun backend: memorizziamo solo l'identificativo utente (stabile per app)
/// e il nome, in locale.
@MainActor
final class Account: ObservableObject {
    @Published private(set) var userID: String?
    @Published private(set) var nome: String?

    private let kUser = "filo.apple.user"
    private let kNome = "filo.apple.name"

    /// Apple ID (user identifier) con privilegi admin. Vuoto finché non si
    /// conosce: l'admin, dopo il primo accesso, vede il proprio ID nel profilo
    /// e può comunicarlo per inserirlo qui.
    static let adminIDs: Set<String> = []

    var isLoggedIn: Bool { userID != nil }
    var isAdmin: Bool {
        guard let id = userID else { return false }
        return Self.adminIDs.contains(id)
    }

    init() {
        userID = UserDefaults.standard.string(forKey: kUser)
        nome = UserDefaults.standard.string(forKey: kNome)
    }

    /// Configura la richiesta del pulsante "Accedi con Apple".
    func configura(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    /// Gestisce l'esito del pulsante SignInWithAppleButton.
    func gestisci(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let auth) = result,
              let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
        userID = cred.user
        UserDefaults.standard.set(cred.user, forKey: kUser)
        if let n = cred.fullName, let given = n.givenName {
            let full = [given, n.familyName].compactMap { $0 }.joined(separator: " ")
            if !full.isEmpty {
                nome = full
                UserDefaults.standard.set(full, forKey: kNome)
            }
        }
    }

    func esci() {
        userID = nil
        nome = nil
        UserDefaults.standard.removeObject(forKey: kUser)
        UserDefaults.standard.removeObject(forKey: kNome)
    }
}
