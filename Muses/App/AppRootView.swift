import PhotosUI
import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showSmartInput = false
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isImportingPhotos = false

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                MTabs()
                    .ignoresSafeArea()
            } else {
                WorkspaceScreenView(tab: app.selectedTab)
                    .safeAreaInset(edge: .bottom, spacing: 0) { MTabBar() }
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
        .allowsHitTesting(!app.isQuickPublishPresented && !isImportingPhotos)
        .accessibilityHidden(app.isQuickPublishPresented || isImportingPhotos)
        .overlay {
            if app.isQuickPublishPresented {
                ZStack {
                    Rectangle()
                        .fill(reduceTransparency ? AnyShapeStyle(MusesTheme.surface) : AnyShapeStyle(.regularMaterial))
                        .overlay(.white.opacity(0.18))
                        .ignoresSafeArea()
                        .onTapGesture { app.dismissQuickPublish() }
                        .accessibilityHidden(true)
                    QuickPublishView(onChoosePhotos: {
                        app.dismissQuickPublish()
                        showPhotoPicker = true
                    }, onSmartRecognition: {
                        app.dismissQuickPublish()
                        showSmartInput = true
                    })
                }
                .transition(.opacity)
                .accessibilityAddTraits(.isModal)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: app.isQuickPublishPresented)
        .overlay {
            if isImportingPhotos {
                ProgressView("正在读取商品图片…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
                    .ignoresSafeArea()
                    .accessibilityAddTraits(.isModal)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems,
                      maxSelectionCount: AppModel.maximumSourcePhotoCount,
                      selectionBehavior: .ordered, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty, !isImportingPhotos else { return }
            isImportingPhotos = true
            Task {
                await app.startNewProduct(from: items)
                photoItems = []
                isImportingPhotos = false
            }
        }
        .sheet(isPresented: $showSmartInput) {
            SmartRecognitionView()
                .environmentObject(app)
                .presentationDetents([.height(340), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
                .presentationBackground(.white)
                .presentationContentInteraction(.scrolls)
                .interactiveDismissDisabled(app.isWorking)
                .alert(item: $app.alert) { alert in
                    Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("知道了")))
                }
        }
        .alert(item: Binding(get: { showSmartInput ? nil : app.alert }, set: { app.alert = $0 })) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("知道了")))
        }
    }
}

struct WorkspaceScreenView: View {
    @EnvironmentObject private var app: AppModel
    let tab: MTab

    var body: some View {
        ZStack {
            if app.selectedTab == tab {
                switch app.screen {
                case .setup: SetupView()
                case .history: tabRoot
                case .skuDetail(let id): SKUDetailView(productID: id)
                case .sku: SKUCreateView()
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
        case .publish: Color.clear
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
