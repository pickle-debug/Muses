import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch app.screen {
            case .setup: SetupView()
            case .history: HistoryView()
            case .product: ProductInputView()
            case .factConfirmation: FactConfirmationView()
            case .imageGeneration: ImageGenerationView()
            case .imageReview: ImageReviewView()
            case .videoGeneration: VideoGenerationView()
            case .videoReview: VideoReviewView()
            case .copyResult: CopyResultView()
            case .saveResult: SaveResultView()
            }
        }
        .animation(.easeOut(duration: 0.22), value: app.screen)
        .alert(item: $app.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("知道了")))
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: app.handleSceneBecameActive()
            case .inactive: app.handleSceneWillResignActive()
            case .background: app.handleSceneEnteredBackground()
            default: break
            }
        }
    }
}

#if DEBUG
#Preview("App Root") {
    MusesPreview.environment(.history) { AppRootView() }
}
#endif
