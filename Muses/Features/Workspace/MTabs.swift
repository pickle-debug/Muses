import SwiftUI
import UIKit

/// SwiftUI pages hosted by the system tab controller so iOS owns tab scrubbing.
@available(iOS 26.0, *)
struct MTabs: UIViewControllerRepresentable {
    @EnvironmentObject private var app: AppModel

    func makeUIViewController(context: Context) -> MTabbarController {
        MTabbarController(app: app)
    }

    func updateUIViewController(_ controller: MTabbarController, context: Context) {
        controller.synchronizeSelection()
    }
}

@available(iOS 26.0, *)
final class MTabbarController: UITabBarController, UITabBarControllerDelegate {
    private let app: AppModel
    private var publishHost: UIHostingController<PublishButton>?

    init(app: AppModel) {
        self.app = app
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(app:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        mode = .tabBar
        tabBarMinimizeBehavior = .never
        delegate = self
        view.backgroundColor = UIColor(MusesTheme.background)
        tabBar.tintColor = UIColor(MusesTheme.coral)
        tabBar.unselectedItemTintColor = UIColor(MusesTheme.ink)

        viewControllers = MTab.allCases.map { tab in
            let controller: UIViewController
            if tab == .publish {
                controller = UIViewController()
                controller.tabBarItem = UITabBarItem(title: nil, image: nil, tag: 2)
                controller.tabBarItem.accessibilityIdentifier = "workspace.publish-slot"
            } else {
                controller = UIHostingController(rootView: WorkspaceScreenView(tab: tab).environmentObject(app))
                controller.tabBarItem = UITabBarItem(title: tab.rawValue, image: UIImage(systemName: tab.icon), tag: 0)
                controller.tabBarItem.accessibilityIdentifier = "workspace.tab.\(tab.rawValue)"
            }
            return controller
        }
        // UIKit keeps its own native selection gesture; the center slot is action-only.
        selectedIndex = MTab.allCases.firstIndex(of: app.selectedTab) ?? 0

        let host = UIHostingController(rootView: PublishButton(app: app))
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        NSLayoutConstraint.activate([
            host.view.widthAnchor.constraint(equalToConstant: 60),
            host.view.heightAnchor.constraint(equalToConstant: 60),
            host.view.centerXAnchor.constraint(equalTo: tabBar.centerXAnchor),
            host.view.topAnchor.constraint(equalTo: tabBar.topAnchor, constant: -10)
        ])
        publishHost = host
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let publishHost { view.bringSubviewToFront(publishHost.view) }
    }

    func synchronizeSelection() {
        guard isViewLoaded else { return }
        if let index = MTab.allCases.firstIndex(of: app.selectedTab), selectedIndex != index {
            selectedIndex = index
        }
        tabBar.isUserInteractionEnabled = !app.isWorking
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard !app.isWorking, let index = viewControllers?.firstIndex(of: viewController) else { return false }
        let tab = MTab.allCases[index]
        app.selectTab(tab)
        return tab != .publish
    }

    @objc private func keyboardWillShow() { publishHost?.view.isHidden = true }
    @objc private func keyboardWillHide() { publishHost?.view.isHidden = false }
}

@available(iOS 26.0, *)
private struct PublishButton: View {
    @ObservedObject var app: AppModel
    @State private var isPressing = false

    var body: some View {
        Button { app.selectTab(.publish) } label: {
            ZStack {
                Image(systemName: "plus")
                    .font(.system(size: 29, weight: .medium))
                    .foregroundStyle(.white).frame(width: 60, height: 60).contentShape(Circle())
                    .glassEffect(.regular.tint(MusesTheme.coral).interactive(), in: Circle())
            }
            .scaleEffect(isPressing ? 1.12 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.58), value: isPressing)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in isPressing = true }.onEnded { _ in isPressing = false })
        .accessibilityLabel(MTab.publish.rawValue)
        .accessibilityIdentifier("workspace.tab.publish")
        .accessibilityAddTraits(app.isQuickPublishPresented ? .isSelected : [])
        .disabled(app.isWorking)
        .sensoryFeedback(.selection, trigger: app.isQuickPublishPresented)
    }
}
