import SwiftUI

@main
struct MDCSenderiOSApp: App {
    @StateObject private var model = SenderModel()

    var body: some Scene {
        WindowGroup {
            SenderView()
                .environmentObject(model)
        }
    }
}
