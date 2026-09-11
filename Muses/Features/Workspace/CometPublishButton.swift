import SwiftUI

/// Muses 的彗星式 AI 发布按钮。默认静止，按住后启动流光动画。
struct CometPublishButton: View {
    @ObservedObject var app: AppModel
    @State private var isPressed = false
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            if isPressed {
                CometTrail(phase: phase)
                    .transition(.opacity)
            }
            Circle()
                .fill(.white.opacity(0.92))
                .overlay(Circle().fill(LinearGradient(colors: [Color.cyan.opacity(0.9), Color.blue.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                .shadow(color: .cyan.opacity(isPressed ? 0.7 : 0.3), radius: isPressed ? 20 : 10)
                .frame(width: 60, height: 60)
        }
        .frame(width: 88, height: 88)
        .contentShape(Circle())
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
            guard !app.isWorking else { return }
            if !isPressed { isPressed = true; phase = 0 }
        }.onEnded { _ in
            isPressed = false
            app.selectTab(.publish)
        })
        .accessibilityLabel(MTab.publish.rawValue)
        .accessibilityIdentifier("workspace.tab.publish.comet")
        .disabled(app.isWorking)
    }
}

private struct CometTrail: View {
    let phase: CGFloat
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(LinearGradient(colors: [.white.opacity(0.9), .cyan.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 84 + CGFloat(index * 14), height: 3 + CGFloat(index))
                        .blur(radius: CGFloat(index) * 1.4)
                        .rotationEffect(.degrees(-32))
                        .offset(x: sin(t * 2 + Double(index)) * 5, y: CGFloat(index - 2) * 6)
                }
            }
            .onAppear { _ = phase }
        }
        .allowsHitTesting(false)
    }
}
