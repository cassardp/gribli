import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct GribliApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                GameView()

                if showSplash {
                    SplashView {
                        showSplash = false
                    }
                }
            }
            .fontDesign(.rounded)
        }
    }
}
