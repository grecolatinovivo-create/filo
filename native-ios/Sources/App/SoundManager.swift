import Foundation
import AVFoundation

/// Suoni dell'app: un "plin" per ogni casella aggiunta al filo.
/// Il tono SALE con la lunghezza del filo (scala pentatonica, plin01…plin12):
/// più cuci, più la melodia si arrampica — feedback immediato e appagante.
///
/// - Sessione audio `.ambient` + `.mixWithOthers`: non interrompe musica o
///   podcast dell'utente e rispetta l'interruttore silenzioso dell'iPhone.
/// - Player precaricati (uno per nota): latenza minima anche in drag veloce.
/// - Interruttore utente: UserDefaults "filo.suoni" (default acceso),
///   esposto nel Profilo.
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    static let defaultsKey = "filo.suoni"

    private var players: [AVAudioPlayer] = []
    private var sessionePronta = false

    var abilitati: Bool {
        get { UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.defaultsKey) }
    }

    private init() {}

    /// Plin per la casella in posizione `passo` (1 = prima casella del filo).
    /// Oltre la 12ª nota resta sull'ultima (la più acuta).
    func plin(passo: Int) {
        guard abilitati else { return }
        preparaSeServe()
        guard !players.isEmpty else { return }
        let idx = min(max(passo, 1), players.count) - 1
        let p = players[idx]
        p.currentTime = 0
        p.play()
    }

    private func preparaSeServe() {
        guard players.isEmpty else { return }
        if !sessionePronta {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            sessionePronta = true
        }
        for i in 1...12 {
            guard let url = Bundle.main.url(forResource: String(format: "plin%02d", i),
                                            withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.volume = 0.55
            player.prepareToPlay()
            players.append(player)
        }
    }
}
