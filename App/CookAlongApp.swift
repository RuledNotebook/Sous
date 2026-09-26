import SwiftUI

@main
struct CookAlongApp: App {
    @State private var session = CookSession.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                #if DEBUG
                .modifier(DebugLaunchOptions(session: session))
                #endif
        }
    }
}
