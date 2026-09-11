import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                NativeWorkspaceTabs()
                    .ignoresSafeArea()
            } else {
                WorkspaceScreenView(tab: app.selectedTab)
                    .safeAreaInset(edge: .bottom, spacing: 0) { WorkspaceTabBar() }
            }
        }
        .background(MusesBackground())
        .overlay {
            if app.isLoadingLocalState {
                ProgressView("正在读取本地商品…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MusesTheme.background)
            }
        }
        .animation(.easeOut(duration: 0.22), value: app.screen)
        .fullScreenCover(isPresented: $app.isQuickPublishPresented) {
            NavigationStack {
                WorkspaceScreenView(tab: .publish)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("关闭", systemImage: "xmark") { app.dismissQuickPublish() }
                                .accessibilityIdentifier("workspace.publish.close")
                                .disabled(app.isWorking)
                        }
                    }
                    .toolbarTitleDisplayMode(.inline)
            }
            .tint(MusesTheme.coral)
            .interactiveDismissDisabled()
            .alert(item: $app.alert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("知道了")))
            }
        }
        .alert(item: Binding(get: { app.isQuickPublishPresented ? nil : app.alert }, set: { app.alert = $0 })) { alert in
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

struct WorkspaceScreenView: View {
    @EnvironmentObject private var app: AppModel
    let tab: WorkspaceTab

    var body: some View {
        ZStack {
            if app.isQuickPublishPresented ? tab == .publish : app.selectedTab == tab {
                switch app.screen {
                case .setup: SetupView()
                case .history: tabRoot
                case .productDetail(let id): SKUDetailView(productID: id)
                case .product: ProductInputView()
                case .factConfirmation: FactConfirmationView()
                case .imageGeneration: ImageGenerationView()
                case .imageReview: ImageReviewView()
                case .videoGeneration: VideoGenerationView()
                case .videoReview: VideoReviewView()
                case .copyResult: CopyResultView()
                case .saveResult: SaveResultView()
                }
            } else {
                tabRoot
            }
        }
    }

    @ViewBuilder private var tabRoot: some View {
        switch tab {
        case .selection: ProductSelectionView()
        case .products: HistoryView()
        case .publish: QuickPublishView()
        case .followUp: SalesFollowUpView()
        case .settings: SetupView()
        }
    }
}

#if DEBUG
#Preview("App Root") {
    MusesPreview.environment(.history) { AppRootView() }
}
#endif
