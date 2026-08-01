import SwiftUI

/// FILO — daily puzzle nativo SwiftUI.
/// La logica di gioco vive in FiloCore (pura, testata su Linux e in parità
/// bit-esatta col motore JS del web: vedi Tests/FiloCoreTests).
@main
struct FiloApp: App {
    @StateObject private var viewModel = GameViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(viewModel)
        }
    }
}
