import SwiftUI
import FirebaseCore

@main
struct YoutubeRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppController.self) var controller

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        // Real macOS window for the control bar — guaranteed visible
        Window("YoutubeRecorder", id: "controls") {
            ControlPanelView(viewModel: controller.viewModel)
                .padding(4)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.bottom)
    }
}
