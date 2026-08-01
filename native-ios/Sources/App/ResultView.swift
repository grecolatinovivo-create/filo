import SwiftUI
import FiloCore

/// Modal RISULTATO — ordine visivo obbligatorio NEURO_SPEC §5, testi §2.
struct ResultView: View {
    @EnvironmentObject private var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stelleVisibili = 0

    private var vinta: Bool { vm.engine.stato == .vinta }
    private var L: Int { vm.puzzle.lSarto }

    private var filoVincente: (filo: FiloConcluso, indice: Int)? {
        for (i, f) in vm.engine.fili.enumerated() where f.esito == .vinto {
            return (f, i + 1)
        }
        return nil
    }

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    // 1. eyebrow
                    HStack {
                        Text(vinta ? String(localized: "FILO #\(vm.numero) · Vittoria")
                                   : String(localized: "FILO #\(vm.numero)"))
                            .captionStyle()
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.textMuted)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Chiudi")
                    }

                    // 2. PICCO: stelle animate in stagger
                    if vinta {
                        stelle
                    }

                    // 3. etichetta
                    Text(etichetta)
                        .font(.headline)
                        .foregroundStyle(vinta ? Theme.filo : Theme.text)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    // 4. riga dati + sotto-riga emotiva
                    Text(rigaDati)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Theme.text)
                    Text(sottoriga)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.center)

                    // 5. mini-griglia (mio filo dorato + Sarto tratteggiato)
                    MiniGridView()
                        .frame(width: 170, height: 170)
                        .padding(.top, 4)
                        .accessibilityHidden(true)

                    // 6. streak / milestone (mai menzionare la streak azzerata)
                    if vinta && vm.streakEffettiva >= 2 {
                        Text(testoStreak)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                    }

                    // 7. anteprima esatta del testo condiviso + caption invito
                    Text(vm.shareText)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Anteprima del risultato da condividere")
                    Text(captionInvito)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.center)

                    // 8. CTA — unico bottone pieno del modal
                    ShareLink(item: vm.shareText) {
                        Text("Condividi il risultato 🧵")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)

                    // 9. countdown al prossimo FILO (mezzanotte locale)
                    VStack(spacing: 2) {
                        Text("Il prossimo FILO si cuce tra")
                            .font(.body)
                            .foregroundStyle(Theme.text)
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(Self.countdown(da: ctx.date))
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.text)
                        }
                        .accessibilityHidden(true)
                    }
                    .padding(.top, 16)

                    // 10. link statistiche
                    Button {
                        vm.scheda = .statistiche
                    } label: {
                        Text("📊 Le tue statistiche")
                            .font(.body)
                            .foregroundStyle(Theme.filo)
                            .underline()
                            .frame(minHeight: 44)
                    }
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Stelle animate (stagger 150ms, scale 0→1)

    private var stelle: some View {
        let totale = vm.stelleOggi + (vm.sartoBattutoOggi ? 1 : 0)
        return HStack(spacing: 4) {
            ForEach(0..<totale, id: \.self) { i in
                Text(i < vm.stelleOggi ? "⭐" : "🥇")
                    .font(.largeTitle)
                    .scaleEffect(stelleVisibili > i ? 1 : 0.01)
                    .animation(reduceMotion ? nil
                               : .spring(response: 0.25, dampingFraction: 0.6)
                                   .delay(Double(i) * 0.15),
                               value: stelleVisibili)
            }
        }
        .onAppear { stelleVisibili = totale }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etichettaStelleAccessibile)
    }

    private var etichettaStelleAccessibile: String {
        let base = vm.stelleOggi == 3 ? String(localized: "Tre stelle")
                 : vm.stelleOggi == 2 ? String(localized: "Due stelle")
                 : String(localized: "Una stella")
        return vm.sartoBattutoOggi ? String(localized: "\(base), hai battuto il Sarto") : base
    }

    // MARK: Testi (NEURO_SPEC §2.1/§2.2, normativi)

    private var etichetta: String {
        guard vinta, let fv = filoVincente else { return String(localized: "Oggi il Sarto la spunta") }
        let res = Punteggio.stelle(caselle: fv.filo.caselle, lSarto: L)
        if res.gold { return String(localized: "Hai battuto il Sarto!") }
        if res.stelle == 3 { return String(localized: "Filo perfetto") }
        if res.stelle == 2 { return String(localized: "Filo elegante") }
        return String(localized: "Filo riuscito")
    }

    private var rigaDati: String {
        guard vinta, let fv = filoVincente else { return String(localized: "3 fili usati · Sarto: \(L) caselle") }
        return String(localized: "\(fv.filo.caselle) caselle · \(fv.indice)° filo · Sarto: \(L)")
    }

    private var sottoriga: String {
        guard vinta, let fv = filoVincente else {
            return String(localized: "Il suo percorso è qui sotto: studialo. Domani c'è un filo nuovo.")
        }
        let C = fv.filo.caselle
        let res = Punteggio.stelle(caselle: C, lSarto: L)
        if res.gold { return String(localized: "\(C) caselle contro le sue \(L). Oggi il maestro sei tu.") }
        if res.stelle == 3 { return String(localized: "Stessa misura del Sarto: \(C) caselle. Cucito a regola d'arte.") }
        if res.stelle == 2 {
            let d = L - C
            return String(localized: "A un soffio dal Sarto: \(d) caselle di differenza. Ci sei quasi.")
        }
        return String(localized: "Somma esatta! Il Sarto però l'ha cucita in \(L) caselle. Domani allunghi il filo?")
    }

    private var testoStreak: String {
        let sk = vm.streakEffettiva
        switch sk {
        case 2: return String(localized: "🔥 2 di fila — il filo comincia a tenere.")
        case 3: return String(localized: "🔥 3 di fila — tre nodi fanno una cucitura.")
        case 7: return String(localized: "🔥 7 di fila — una settimana senza perdere il filo.")
        case 30: return String(localized: "🔥 30 di fila — un mese cucito a mano. Chapeau.")
        default: return String(localized: "🔥 Serie: \(sk) giorni")
        }
    }

    private var captionInvito: String {
        vinta ? String(localized: "La griglia racconta tutto senza svelare niente. Falla girare.")
              : String(localized: "Anche una sconfitta è una bella storia. Sfida qualcuno a far meglio.")
    }

    // MARK: Countdown

    static func countdown(da now: Date) -> String {
        let cal = Calendar.current
        let domani = cal.date(byAdding: .day, value: 1, to: now) ?? now
        let mezzanotte = cal.startOfDay(for: domani)
        let s = max(0, Int(mezzanotte.timeIntervalSince(now)))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

/// Mini-griglia 5×5: il mio filo dorato + percorso del Sarto tratteggiato.
struct MiniGridView: View {
    @EnvironmentObject private var vm: GameViewModel

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 3
            let side = (geo.size.width - gap * 4) / 5
            ZStack(alignment: .topLeading) {
                ForEach(0..<25, id: \.self) { idx in
                    let mio = vm.engine.percorsoVincente?.contains(idx) ?? false
                    let sulSarto = vm.puzzle.percorsoSarto.contains(idx)
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(mio ? Theme.filo : Theme.surface2)
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(mio ? Theme.filoScuro : Theme.border, lineWidth: 1)
                        if sulSarto {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Theme.sarto,
                                              style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                                .padding(1)
                        }
                        Text("\(vm.puzzle.valori[idx])")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(mio ? Theme.bg : Theme.textMuted)
                    }
                    .frame(width: side, height: side)
                    .offset(x: CGFloat(idx % 5) * (side + gap),
                            y: CGFloat(idx / 5) * (side + gap))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
