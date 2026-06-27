import SwiftUI

@main
struct DLNAviewerApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ServerListView()
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 640)
        #endif
    }
}
