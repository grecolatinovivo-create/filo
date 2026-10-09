import SwiftUI

/// INTRO all'avvio (REDESIGN_SPEC §6.1): sfondo subito; il logo entra con
/// dissolvenza + salita di 6 pt (0,45 s easeOut), il claim segue con una
/// dissolvenza di 0,3 s, breve pausa (0,6 s), poi `onFinish` dissolve
/// l'intro sulla Home (0,3 s, in FiloApp). Totale ≈ 1,35 s + 0,3 s.
/// Riduci Movimento: tutto statico, 1,0 s.
struct IntroView: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var logo = false
    @State private var tagline = false

    var body: some View {
        ZStack {
            FiloBackground()
            VStack(spacing: 8) {
                Image(decorative: "LogoFilo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 176)
                    .opacity(logo ? 1 : 0)
                    .offset(y: logo || reduceMotion ? 0 : 6)
                Text("Un filo al giorno.")
                    .filoFont(.body)
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .opacity(tagline ? 1 : 0)
            }
            .padding(.horizontal, 24)
        }
        .task { await run() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("FILO"))
    }

    private func run() async {
        if reduceMotion {
            logo = true
            tagline = true
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            onFinish()
            return
        }
        withAnimation(.easeOut(duration: 0.45)) { logo = true }
        try? await Task.sleep(nanoseconds: 450_000_000)
        withAnimation(.easeOut(duration: 0.3)) { tagline = true }
        try? await Task.sleep(nanoseconds: 300_000_000)
        // pausa di lettura
        try? await Task.sleep(nanoseconds: 600_000_000)
        onFinish()
    }
}
