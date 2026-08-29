import SwiftUI

@main
struct TrueRateApp: App {
    @StateObject private var controller = SwitchController()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(controller)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: controller.isMatched ? "waveform" : "waveform.slash")
                if let rate = controller.deviceRate {
                    Text(SwitchController.shortFormat(rate: rate))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
