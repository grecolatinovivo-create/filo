import Foundation

/// Costruzione del testo di condivisione — IDENTICO carattere per carattere
/// al `buildShareText()` del web (README §9.1). Unica fonte del testo condiviso.
/// La riga URL finale esiste SOLO se `url` è non vuoto (stessa condizione del
/// JS: `if (CONFIG.SHARE_URL) righe.push(CONFIG.SHARE_URL)`).
public enum ShareText {
    /// URL pubblico del gioco — stesso valore di `CONFIG.SHARE_URL` nel web.
    public static let shareURL = "https://filo-game.vercel.app"

    public static func build(numero: Int, vinta: Bool, fili: [FiloConcluso],
                             T: Int, stelle: Int, sartoBattuto: Bool,
                             streak: Int, url: String? = nil) -> String {
        var righe: [String] = []
        righe.append("FILO #\(numero) 🧵" + (vinta ? "" : " ❌"))
        for f in fili {
            if f.esito == .vinto {
                let stelleStr = String(repeating: "⭐", count: stelle)
                    + (sartoBattuto ? "🥇" : "")
                righe.append("🟩🟩🟩🟩🟩 \(f.caselle)/25 " + stelleStr)
            } else {
                // p = min(somma, T)/T ; n = min(5, floor(p*5)) — stessa aritmetica
                // in doppia precisione del JS (§9.1). Spezzato ⇒ n = 5 per definizione.
                let p = Double(min(f.somma, T)) / Double(T)
                let n = min(5, Int(floor(p * 5)))
                righe.append(String(repeating: "🟦", count: n)
                    + String(repeating: "⬜", count: 5 - n)
                    + " " + (f.esito == .spezzato ? "💥" : "🪢"))
            }
        }
        if vinta && streak >= 2 {
            righe.append("🔥 \(streak) di fila")
        }
        // §9.1: la riga URL esiste SOLO se l'URL è definito e non vuoto
        if let url, !url.isEmpty {
            righe.append(url)
        }
        return righe.joined(separator: "\n")
    }
}
