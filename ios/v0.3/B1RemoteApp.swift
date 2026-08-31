import SwiftUI

@main
struct B1RemoteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var remote = BluetoothRemoteManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(remote)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                remote.resumeAfterForeground()
            }
        }
    }
}
