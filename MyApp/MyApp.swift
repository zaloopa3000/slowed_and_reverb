import SwiftUI

@main struct MyApp: App {
    /// App flow: splash → welcome (pick a song) → player.
    enum Screen {
        case splash, welcome, player
    }

    /// One audio engine for the app's lifetime.
    @State private var engine = AudioEngine()
    @State private var screen: Screen = .splash

    var body: some Scene {
        WindowGroup {
            ZStack {
                switch screen {
                case .splash:
                    SplashView()
                        .transition(.opacity)
                case .welcome:
                    WelcomeView(engine: engine) {
                        withAnimation(.easeInOut(duration: 0.45)) { screen = .player }
                    }
                    .transition(.opacity)
                case .player:
                    PlayerView(engine: engine)
                        .transition(.opacity)
                }
            }
            .task {
                // Keep the splash visible briefly, then show the welcome screen.
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeInOut(duration: 0.5)) {
                    screen = .welcome
                }
            }
        }
    }
}
