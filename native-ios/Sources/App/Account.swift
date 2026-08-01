import SwiftUI
import AuthenticationServices
import UIKit

/// Accesso con Apple ID (opzionale). Implementazione con ASAuthorizationController
/// esplicito: presentiamo noi il foglio (anchor alla finestra attiva) così
/// funziona anche quando il pulsante vive dentro un foglio modale, e SURFACIAMO
/// gli eventuali errori invece di ingoiarli. Nessun backend: salviamo solo
/// l'identificativo utente (stabile per app) e il nome, in locale.
@MainActor
final class Account: NSObject, ObservableObject {
    @Published private(set) var userID: String?
    @Published private(set) var nome: String?
    @Published private(set) var inCorso = false
    @Published var errore: String?

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

    override init() {
        super.init()
        userID = UserDefaults.standard.string(forKey: kUser)
        nome = UserDefaults.standard.string(forKey: kNome)
    }

    /// Avvia l'accesso con Apple.
    func accedi() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        inCorso = true
        errore = nil
        controller.performRequests()
    }

    func esci() {
        userID = nil
        nome = nil
        UserDefaults.standard.removeObject(forKey: kUser)
        UserDefaults.standard.removeObject(forKey: kNome)
    }

    private func salva(cred: ASAuthorizationAppleIDCredential) {
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
}

extension Account: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        let cred = authorization.credential as? ASAuthorizationAppleIDCredential
        Task { @MainActor in
            self.inCorso = false
            if let cred { self.salva(cred: cred) }
            else { self.errore = "Credenziale non valida." }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        let code = (error as? ASAuthorizationError)?.code
        let msg = error.localizedDescription
        Task { @MainActor in
            self.inCorso = false
            if code == .canceled { return }          // l'utente ha annullato: nessun errore
            let n = code.map { String($0.rawValue) } ?? "?"
            self.errore = "Accesso non riuscito (codice \(n)): \(msg)"
        }
    }
}

extension Account: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? scene?.windows.first ?? ASPresentationAnchor()
        }
    }
}
