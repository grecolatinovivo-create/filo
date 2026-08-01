import SwiftUI

/// INTRO animata all'avvio (la "landing" dell'app): un filo d'oro disegna il
/// logo sulla griglia di puntini, poi compaiono la parola FILO e il claim.
/// Rispetta Riduci Movimento (mostra tutto subito, senza animazione).
/// Al termine chiama `onFinish`, che dissolve l'intro rivelando il gioco.
struct IntroView: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var trimEnd: CGFloat = 0
    @State private var endDot = false
    @State private var wordmark = false
    @State private var tagline = false

    // Stesso "viewBox" 200×150 della landing web: coerenza col brand e con l'icona.
    private let dots: [CGPoint] = {
        var a: [CGPoint] = []
        for y in [30.0, 75.0, 120.0] {
            for x in [30.0, 75.0, 120.0, 165.0] { a.append(CGPoint(x: x, y: y)) }
        }
        return a
    }()
    private let thread: [CGPoint] = [
        CGPoint(x: 30, y: 120), CGPoint(x: 30, y: 75), CGPoint(x: 120, y: 75),
        CGPoint(x: 120, y: 30), CGPoint(x: 165, y: 30)
    ]

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            VStack(spacing: 18) {
                art
                    .frame(width: 230, height: 172)
                Text("FILO")
                    .font(.system(size: 64, weight: .heavy))
                    .kerning(14)
                    .padding(.leading, 14)
                    .foregroundStyle(Theme.filoGradient)
                    .opacity(wordmark ? 1 : 0)
                    .scaleEffect(wordmark ? 1 : 0.92)
                Text("Un filo. Una somma. Ogni giorno.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .opacity(tagline ? 1 : 0)
            }
            .padding(.horizontal, 24)
        }
        .task { await run() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FILO")
    }

    private var art: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 200, geo.size.height / 150)
            let ox = (geo.size.width - 200 * s) / 2
            let oy = (geo.size.height - 150 * s) / 2
            func P(_ p: CGPoint) -> CGPoint { CGPoint(x: ox + p.x * s, y: oy + p.y * s) }
            ZStack {
                ForEach(0..<dots.count, id: \.self) { i in
                    Circle()
                        .fill(Theme.filoScuro.opacity(0.5))
                        .frame(width: 8 * s, height: 8 * s)
                        .position(P(dots[i]))
                }
                PolylineShape(points: thread.map(P))
                    .trim(from: 0, to: trimEnd)
                    .stroke(Theme.filoGradient,
                            style: StrokeStyle(lineWidth: 9 * s, lineCap: .round, lineJoin: .round))
                    .shadow(color: Theme.filo.opacity(0.6), radius: 8 * s)
                Circle()
                    .fill(Theme.filoGradient)
                    .frame(width: 15 * s, height: 15 * s)
                    .position(P(thread[thread.count - 1]))
                    .opacity(endDot ? 1 : 0)
            }
        }
    }

    private func run() async {
        if reduceMotion {
            trimEnd = 1; endDot = true; wordmark = true; tagline = true
            try? await Task.sleep(nanoseconds: 900_000_000)
            onFinish()
            return
        }
        withAnimation(.easeInOut(duration: 1.25)) { trimEnd = 1 }
        try? await Task.sleep(nanoseconds: 1_150_000_000)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { endDot = true }
        try? await Task.sleep(nanoseconds: 150_000_000)
        withAnimation(.easeOut(duration: 0.45)) { wordmark = true }
        try? await Task.sleep(nanoseconds: 350_000_000)
        withAnimation(.easeOut(duration: 0.4)) { tagline = true }
        try? await Task.sleep(nanoseconds: 950_000_000)
        onFinish()
    }
}
