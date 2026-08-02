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
                MenuView()
                    .environmentObject(viewModel)
                    .environmentObject(theme)
                    .environmentObject(store)
                    .environmentObject(account)
                if showIntro {
                    IntroView {
                        withAnimation(.easeInOut(duration: 0.45)) { showIntro = false }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
        }
    }
}
