import SwiftUI

/// FILO — daily puzzle nativo SwiftUI.
/// La logica di gioco vive in FiloCore (pura, testata su Linux e in parità
/// bit-esatta col motore JS del web: vedi Tests/FiloCoreTests).
@main
struct FiloApp: App {
    @StateObject private var viewModel = GameViewModel()
    @StateObject private var theme = ThemeManager()
    @StateObject private var store = Store()
    @StateObject private var account = Account()
    @State private var showIntro = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                // La Home anima la propria entrata quando l'intro si dissolve.
                MenuView(entrata: !showIntro)
                    .environmentObject(viewModel)
                    .environmentObject(theme)
                    .environmentObject(store)
                    .environmentObject(account)
                if showIntro {
                    IntroView {
                        // Crossfade intro → Home: 0,3 s (spec §6.1).
                        withAnimation(.easeInOut(duration: 0.3)) { showIntro = false }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .preferredColorScheme(.dark)
        }
    }
}
